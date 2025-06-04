import { ethers, upgrades } from "hardhat";

// deploy test womrhole on amoy
async function main() {
    const contractAddress = "0x76eF1d38B1120Bb9f3C967B8Aa119506b1645Be5";
    const contract = await ethers.getContractAt("USDVContractV2", contractAddress);

    try {
        const amount = ethers.parseUnits("1", 6);
        const tx = await contract.mintToken(amount);
        await tx.wait();
        console.log("Transaction complete ", tx);
    } catch (err) {
        console.log('err: ', err);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
