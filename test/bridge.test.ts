import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { chainToChainId } from "@wormhole-foundation/sdk/dist/cjs";

describe("Wormhole bridge", async function () {
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.
    async function deployWormholeContract() {
        const CORE_CONTRACT = "0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35";
        const CHAIN_ID = chainToChainId("Polygon");

        // const [owner, otherAccount] = await ethers.getSigners();
        const wormhole = await ethers.getContractFactory("Wormhole");
        const wormholeContract = await wormhole.deploy(CORE_CONTRACT, CHAIN_ID, 1);

        return wormholeContract;
    }

    it("Post message", async function () {
        // const wormholeContract = await loadFixture(deployWormholeContract);
        // const tx = await wormholeContract.sendMessage("Hello Wormhole Bridge!");
        // const receipt = await tx.wait();
        // expect(receipt).is.not.null;
    });

    it("Receive message", async function () {
        // const wormholeContract = await loadFixture(deployWormholeContract);
    })
})