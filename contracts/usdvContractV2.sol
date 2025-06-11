// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./bridge/modules/wormhole/IWormhole.sol";
import "./bridge/modules/utils/BytesLib.sol";
import "./bridge/WormholeGetters.sol";
import "./bridge/WormholeMessages.sol";
import "./usdvContract_withoutNatSpec.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract USDVContractV2 is USDVContract, WormholeGetters, WormholeMessages {
    event BurntForWUSDV(address user, uint256 amount, uint64 messageSequence);

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

    function burnForWUSDV(
        uint256 _amount
    )
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint64 messageSequence)
    {
        require(_amount > 0);
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");

        // Burn the tokens
        _burn(msg.sender, _amount);

        // Format the message, e.g., "locked 250"
        string memory wormholeMessage = string(
            abi.encodePacked(Strings.toString(_amount))
        );

        // Wormhole instance and fee
        IWormhole wormholeInstance = wormhole();
        uint256 wormholeFee = wormholeInstance.messageFee();

        require(msg.value == wormholeFee, "Incorrect Wormhole fee");

        WormholeMessage memory parsedMessage = WormholeMessage({
            payloadID: uint8(1),
            message: wormholeMessage
        });

        bytes memory encodedMessage = encodeMessage(parsedMessage);

        // Publish the message
        messageSequence = wormholeInstance.publishMessage{value: wormholeFee}(
            0, // batchID
            encodedMessage,
            wormholeFinality()
        );

        emit BurntForWUSDV(msg.sender, _amount, messageSequence);
    }

    function receiveAndRedeem(
        bytes memory encodedMessage
    ) external nonReentrant whenNotPaused {
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
            !isMessageConsumed(wormholeMessage.hash),
            "message already consumed"
        );
        consumeMessage(wormholeMessage.hash, parsedMessage.message);

        uint256 amountToMintAndBurn = stringToUint(parsedMessage.message);

        if (!isPublicRedeemOpen) {
            require(msg.sender == owner(), "Not Authorized");
        }

        _mint(msg.sender, amountToMintAndBurn);

        uint256 tokenAmountToTransfer = (amountToMintAndBurn * tokenPrice) / 10 ** 6;

        if (currencyToken.balanceOf(address(this)) >= tokenAmountToTransfer) {
            require(
                currencyToken.transfer(msg.sender, tokenAmountToTransfer),
                "Transfer failed"
            );

            _burn(msg.sender, amountToMintAndBurn);

            emit redeemTokenEvent(
                msg.sender,
                amountToMintAndBurn,
                tokenAmountToTransfer,
                tokenPrice,
                block.timestamp
            );
        } else {
            emit InsufficientFundEvent(
                msg.sender,
                amountToMintAndBurn,
                tokenAmountToTransfer,
                tokenPrice,
                block.timestamp,
                currencyToken.balanceOf(address(this))
            );
            revert("Not Enough Balance on Contract");
        }
    }

    function stringToUint(string memory _str) internal pure returns (uint256) {
        bytes memory temp = bytes(_str);
        uint256 result = 0;
        for (uint256 i = 0; i < temp.length; i++) {
            require(
                temp[i] >= 0x30 && temp[i] <= 0x39,
                "Invalid character in string"
            ); // '0' to '9'
            result = result * 10 + (uint8(temp[i]) - 48);
        }
        return result;
    }

    // function sendMessage(
    //     string memory wormholeMessage
    // ) public payable returns (uint64 messageSequence) {
    //     // enforce a max size for the arbitrary message
    //     require(
    //         abi.encodePacked(wormholeMessage).length < type(uint16).max,
    //         "message too large"
    //     );

    //     // cache Wormhole instance and fees to save on gas
    //     IWormhole wormhole = wormhole();
    //     uint256 wormholeFee = wormhole.messageFee();

    //     // Confirm that the caller has sent enough value to pay for the Wormhole
    //     // message fee.
    //     require(msg.value == wormholeFee, "insufficient value");

    //     // create the WormholeMessage struct
    //     WormholeMessage memory parsedMessage = WormholeMessage({
    //         payloadID: uint8(1),
    //         message: wormholeMessage
    //     });

    //     // encode the WormholeMessage struct into bytes
    //     bytes memory encodedMessage = encodeMessage(parsedMessage);

    //     // Send the Wormhole message by calling publishMessage on the
    //     // Wormhole core contract and paying the Wormhole protocol fee.
    //     messageSequence = wormhole.publishMessage{value: wormholeFee}(
    //         0, // batchID
    //         encodedMessage,
    //         wormholeFinality()
    //     );
    // }

    // function receiveMessage(bytes memory encodedMessage) public {
    //     // call the Wormhole core contract to parse and verify the encodedMessage
    //     (
    //         IWormhole.VM memory wormholeMessage,
    //         bool valid,
    //         string memory reason
    //     ) = wormhole().parseAndVerifyVM(encodedMessage);

    //     // confirm that the Wormhole core contract verified the message
    //     require(valid, reason);

    //     // verify that this message was emitted by a registered emitter
    //     require(verifyEmitter(wormholeMessage), "unknown emitter");

    //     // decode the message payload into the WormholeMessage struct
    //     WormholeMessage memory parsedMessage = decodeMessage(
    //         wormholeMessage.payload
    //     );

    //     /**
    //      * Check to see if this message has been consumed already. If not,
    //      * save the parsed message in the receivedMessages mapping.
    //      *
    //      * This check can protect against replay attacks in xDapps where messages are
    //      * only meant to be consumed once.
    //      */
    //     require(
    //         !isMessageConsumed(wormholeMessage.hash),
    //         "message already consumed"
    //     );
    //     consumeMessage(wormholeMessage.hash, parsedMessage.message);
    // }
}
