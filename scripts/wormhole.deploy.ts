import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

// deploy test womrhole on amoy
async function main() {
    const wormholeAddress = "0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35";
    const chainId = 5;
    const wormholeFinality = 1;

    const Wormhole = await ethers.getContractFactory("Wormhole");
    const wormhole = await Wormhole.deploy(wormholeAddress, chainId, wormholeFinality);

    console.log('deployed wormhole = ', wormhole);
    console.log("Wormhole deployed to:", wormhole.address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
