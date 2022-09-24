const hre = require("hardhat");
require('dotenv').config();

async function main() {

  const AqualisToken = await hre.ethers.getContractFactory("Token");
  const aqualisToken = await AqualisToken.deploy('Aqualis Token', 'AQT');
  const AqualisStaking = await hre.ethers.getContractFactory("AqualisStaking");
  const aqualisStaking = await AqualisStaking.deploy(aqualisToken.address, process.env.RWRDS_POOL_ADDRESS, process.env.TREASURY_ADDRESS);

  await aqualisStaking.deployed();

  console.log(
    `Aqualis Staking deployed to ${aqualisStaking.address}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
