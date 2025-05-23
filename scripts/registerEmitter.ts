import { ethers } from "hardhat";
import * as dotenv from "dotenv";
import { CHAIN_ID_SOLANA } from "@certusone/wormhole-sdk";
import { tryNativeToHexString } from "@certusone/wormhole-sdk";
import ABI from "../artifacts/contracts/usdvContract_withoutNatSpec.sol/USDVContract.json";
dotenv.config();

const contractAddress = "0x1EC558Fd542d354B7818A8A8F8124b6e39F015B9";
const solana_address = process.env.SOLANA_ADDRESS || "";

const main = async () => {
    const [signer] = await ethers.getSigners();
    const contract = new ethers.Contract(contractAddress, ABI.abi, signer);

    // Convert Solana emitter address to bytes32
    const targetContractAddressHex = "0x" + tryNativeToHexString(solana_address, CHAIN_ID_SOLANA);

    const tx = await contract.registerEmitter(CHAIN_ID_SOLANA, targetContractAddressHex);
    console.log("Transaction sent:", tx.hash);
    await tx.wait();
    console.log("Transaction confirmed.");
}

main()