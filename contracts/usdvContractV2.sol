// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./bridge/modules/wormhole/IWormhole.sol";
import "./bridge/modules/utils/BytesLib.sol";
import "./bridge/WormholeGetters.sol";
import "./bridge/WormholeMessages.sol";
import "./usdvContract_withoutNatSpec.sol";

contract USDVContractV2 is USDVContract, WormholeGetters, WormholeMessages {
    ///@custom:oz-upgrades-validate-as-initializer
    function initializeV2() public reinitializer(2) {
        __USDVContract_init();

        setWormhole(address(0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35));
        setChainId(10007);
        setWormholeFinality(1);
    }

    // bridge
    function registerEmitter(
        uint16 emitterChainId,
        bytes32 emitterAddress
    ) public onlyOwner {
        // sanity check the emitterChainId and emitterAddress input values
        require(
            emitterChainId != 0 && emitterChainId != chainId(),
            "emitterChainId cannot equal 0 or this chainId"
        );
        require(
            emitterAddress != bytes32(0),
            "emitterAddress cannot equal bytes32(0)"
        );

        // update the registeredEmitters state variable
        setEmitter(emitterChainId, emitterAddress);
    }

    function verifyEmitter(
        IWormhole.VM memory vm
    ) internal view returns (bool) {
        // Verify that the sender of the Wormhole message is a trusted
        // Wormhole contract.
        return getRegisteredEmitter(vm.emitterChainId) == vm.emitterAddress;
    }

    function sendMessage(
        string memory wormholeMessage
    ) public payable returns (uint64 messageSequence) {
        // enforce a max size for the arbitrary message
        require(
            abi.encodePacked(wormholeMessage).length < type(uint16).max,
            "message too large"
        );

        // cache Wormhole instance and fees to save on gas
        IWormhole wormhole = wormhole();
        uint256 wormholeFee = wormhole.messageFee();

        // Confirm that the caller has sent enough value to pay for the Wormhole
        // message fee.
        require(msg.value == wormholeFee, "insufficient value");

        // create the WormholeMessage struct
        WormholeMessage memory parsedMessage = WormholeMessage({
            payloadID: uint8(1),
            message: wormholeMessage
        });

        // encode the WormholeMessage struct into bytes
        bytes memory encodedMessage = encodeMessage(parsedMessage);

        // Send the Wormhole message by calling publishMessage on the
        // Wormhole core contract and paying the Wormhole protocol fee.
        messageSequence = wormhole.publishMessage{value: wormholeFee}(
            0, // batchID
            encodedMessage,
            wormholeFinality()
        );
    }

    function receiveMessage(bytes memory encodedMessage, bytes32 vaaHash) public {
        // call the Wormhole core contract to parse and verify the encodedMessage
        (
            IWormhole.VM memory wormholeMessage,
            bool valid,
            string memory reason
        ) = wormhole().parseAndVerifyVM(encodedMessage);

        // confirm that the Wormhole core contract verified the message
        require(valid, reason);

        // verify that this message was emitted by a registered emitter
        require(verifyEmitter(wormholeMessage), "unknown emitter");

        // decode the message payload into the WormholeMessage struct
        WormholeMessage memory parsedMessage = decodeMessage(
            wormholeMessage.payload
        );

        /**
         * Check to see if this message has been consumed already. If not,
         * save the parsed message in the receivedMessages mapping.
         *
         * This check can protect against replay attacks in xDapps where messages are
         * only meant to be consumed once.
         */
        require(
            !isMessageConsumed(vaaHash),
            "message already consumed"
        );
        consumeMessage(vaaHash, parsedMessage.message);
    }
}
