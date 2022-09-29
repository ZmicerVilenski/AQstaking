const hre = require("hardhat");
require('dotenv').config();

async function main() {

  // For deploy in mainnet delete deployment of Token and use AQUALIS_TOKEN_ADDRESS
  const AqualisToken = await hre.ethers.getContractFactory("Token");
  const aqualisToken = await AqualisToken.deploy('Aqualis Token', 'AQT');
  console.log(
    `Aqualis Token deployed to ${aqualisToken.address}`
  );
  //
  
  const AqualisStaking = await hre.ethers.getContractFactory("AqualisStaking");
  const aqualisStaking = await AqualisStaking.deploy(aqualisToken.address); // For deploy in mainnet comment this line and uncomment next
  // const aqualisStaking = await AqualisStaking.deploy(process.env.AQUALIS_TOKEN_ADDRESS);

  await aqualisStaking.setTreasuryAddress(process.env.TREASURY_ADDRESS);
  await aqualisStaking.setRewardsPoolAddress(process.env.RWRDS_POOL_ADDRESS);

  await aqualisStaking.deployed();

  console.log(
    `Aqualis Staking deployed to ${aqualisStaking.address}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
