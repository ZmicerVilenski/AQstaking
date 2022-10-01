const hre = require("hardhat");
require('dotenv').config();

async function main() {

  // For deploy in mainnet delete deployment of Token and use TOKEN_ADDRESS
  const Token = await hre.ethers.getContractFactory("Token");
  const token = await AqualisToken.deploy('Aqualis Token', 'AQT');
  console.log(
    `Aqualis Token deployed to ${aqualisToken.address}`
  );
  //
  
  const Staking = await hre.ethers.getContractFactory("Staking");
  const staking = await Staking.deploy(token.address); // For deploy in mainnet comment this line and uncomment next
  // const staking = await Staking.deploy(process.env.TOKEN_ADDRESS);

  await staking.setTreasuryAddress(process.env.TREASURY_ADDRESS);
  await staking.setRewardsPoolAddress(process.env.RWRDS_POOL_ADDRESS);

  await staking.deployed();

  console.log(
    `Staking deployed to ${staking.address}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
