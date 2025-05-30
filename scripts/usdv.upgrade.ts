import { ethers, upgrades } from "hardhat";

async function main() {
    const proxyAddress = "0x929480f628E5dD84d9b935c5C8c79CeBf93691b7";

    const ContractV2 = await ethers.getContractFactory("USDVContractV2");
    const upgraded = await upgrades.upgradeProxy(proxyAddress, ContractV2);
    console.log("Upgraded to ContractV2 at:", await upgraded.getAddress());

    // Initialize new state variable
    const tx = await upgraded.initializeV2();
    await tx.wait();
    console.log("Initialized in V2");
}

main();
