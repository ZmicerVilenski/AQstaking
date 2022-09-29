const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
require('dotenv').config();

describe("Aqualis Staking", function () {

  let aqualisToken, aqualisStaking, account0, account1, account2;

  async function deploy() {
    [account0, account1, account2] = await ethers.getSigners();
    const AqualisToken = await ethers.getContractFactory("Token");
    aqualisToken = await AqualisToken.deploy('Aqualis Token', 'AQT');
    const AqualisStaking = await ethers.getContractFactory("AqualisStaking");
    aqualisStaking = await AqualisStaking.deploy(aqualisToken.address);  
  }

  describe("Deployment, fill the balances, check setters and getters", function () {

    it("Set parameters", async function () {

      await loadFixture(deploy);
      await aqualisStaking.setTreasuryAddress(process.env.TREASURY_ADDRESS);
      await aqualisStaking.setRewardsPoolAddress(process.env.RWRDS_POOL_ADDRESS);

      expect(await aqualisStaking.treasuryAddress()).to.equal(process.env.TREASURY_ADDRESS);
      expect(await aqualisStaking.rewardsPoolAddress()).to.equal(process.env.RWRDS_POOL_ADDRESS);

    });

    it("Setters & getters", async function () {

      await aqualisStaking.setRewardsPerCompPeriod(22);
      expect(await aqualisStaking.rewardsPerWeek()).to.equal(22);
      await aqualisStaking.setPenaltyPerCompPeriod(4);
      expect(await aqualisStaking.penaltyPerWeek()).to.equal(4);
      await aqualisStaking.setMinimumWeeksNum(6);
      expect(await aqualisStaking.minimumWeeksNum()).to.equal(6);
      await aqualisStaking.setMaximumWeeksNum(200);
      expect(await aqualisStaking.maximumWeeksNum()).to.equal(200);
      const depInfo = await aqualisStaking.getDepositInfo(account0.address);
      console.log(depInfo);
      const stakeInfo = await aqualisStaking.getStakeInfo(account0.address);
      console.log(stakeInfo);

      // Return all parameters to default
      await aqualisStaking.setRewardsPerCompPeriod(20);
      await aqualisStaking.setPenaltyPerCompPeriod(3);
      await aqualisStaking.setMinimumWeeksNum(5);
      await aqualisStaking.setMaximumWeeksNum(104);

    });

    it("Should set the right Token", async function () {
      expect(await aqualisStaking.token()).to.equal(aqualisToken.address);
    });

    it("Should set the right owner for Token & Staking", async function () {
      expect(await aqualisToken.owner()).to.equal(account0.address);
      expect(await aqualisStaking.owner()).to.equal(account0.address);
    });

    it("Should get the right balances", async function () {

      const amount = hre.ethers.utils.parseEther("1000000000");
      await aqualisToken.transfer(account1.address, amount);
      await aqualisToken.transfer(account2.address, amount);
      expect(await aqualisToken.balanceOf(account1.address)).to.equal(amount);
      expect(await aqualisToken.balanceOf(account2.address)).to.equal(amount);

    });

    it("Should fail", async function () {
      await expect(aqualisStaking.stake(0, 0)).to.be.revertedWith("Amount smaller than minimimum deposit");
    });

  });

  describe("Stake", function () {

    it("Approve Tokens for Staking SC", async function () {

      const amount = hre.ethers.utils.parseEther("1000000000");
      await aqualisToken.approve(aqualisStaking.address, amount); 
      await aqualisToken.connect(account1).approve(aqualisStaking.address, amount); 
      await aqualisToken.connect(account2).approve(aqualisStaking.address, amount);  

      expect(await aqualisToken.allowance(account0.address, aqualisStaking.address)).to.equal(amount);
      expect(await aqualisToken.allowance(account1.address, aqualisStaking.address)).to.equal(amount);
      expect(await aqualisToken.allowance(account2.address, aqualisStaking.address)).to.equal(amount);

    });

    it("Stake for 3 accounts", async function () {

      const amount100 = hre.ethers.utils.parseEther("100");
      const amount200 = hre.ethers.utils.parseEther("200");
      const amount300 = hre.ethers.utils.parseEther("300");

      await aqualisStaking.stake(amount100, 10); // account0
      await aqualisStaking.stakeFor(account1.address, amount100, 10); // account1
      await aqualisStaking.connect(account2).stake(amount100, 10); // account2

      expect(await aqualisStaking.totalStakedFor(account0.address)).to.equal(amount100);
      expect(await aqualisStaking.totalStakedFor(account1.address)).to.equal(amount100);
      expect(await aqualisStaking.totalStakedFor(account2.address)).to.equal(amount100);
      expect(await aqualisStaking.totalStaked()).to.equal(amount300);

      await expect(aqualisStaking.stake(amount100, 104)).to.emit(aqualisStaking, "Staked").withArgs(account0.address, amount100, amount200, anyValue);
      await expect(aqualisStaking.connect(account1).stake(amount100, 105)).to.emit(aqualisStaking, "Staked").withArgs(account1.address, amount100, amount200, anyValue);
      await expect(aqualisStaking.connect(account2).stake(amount100, 105)).to.emit(aqualisStaking, "Staked").withArgs(account2.address, amount100, amount200, anyValue);

    });

    it("Change auto extending", async function () {

      expect(await aqualisStaking.isStakeAutoExtending(account0.address)).to.equal(false);
      await aqualisStaking.activateAutoExtending(); // for account 0
      expect(await aqualisStaking.isStakeAutoExtending(account0.address)).to.equal(true);
      expect(await aqualisStaking.isStakeAutoExtending(account1.address)).to.equal(true);
      await aqualisStaking.connect(account1).disableAutoExtending(); // for account 1
      expect(await aqualisStaking.isStakeAutoExtending(account1.address)).to.equal(false);

    });

    it("Extend timeLock and increase stake amount", async function () {

      let stakeInfo = await aqualisStaking.getStakeInfo(account0.address);
      console.log('Account: ', account0.address, ' timeLock before extending: ', stakeInfo.timeLock);
      await aqualisStaking.extendStaking(5); // Extend for 5 weeks
      stakeInfo = await aqualisStaking.getStakeInfo(account0.address);
      console.log('Account: ', account0.address, ' timeLock after extending: ', stakeInfo.timeLock);

      const incAmount = hre.ethers.utils.parseEther("1");
      console.log('Account: ', account0.address, ' amount before extending: ', stakeInfo.amount);
      await aqualisStaking.increaseStakingAmount(incAmount); // Increase for 1 token
      stakeInfo = await aqualisStaking.getStakeInfo(account0.address);
      console.log('Account: ', account0.address, ' amount after extending: ', stakeInfo.amount);

    });

    it("Check staking amount, reward and timer", async function () {

      let stakeAmount, reward, weeksForUnstake;
      let now = await time.latest();
      weeksForUnstake = await aqualisStaking.weeksForUnstake(account0.address);
      [stakeAmount, ] = await aqualisStaking.getDepositInfo(account0.address);
      console.log('Stake amount: ', BigInt(stakeAmount));
      const n = Number(BigInt(weeksForUnstake));
      for (let i=1; i <= n; i++) {
        [,reward] = await aqualisStaking.getDepositInfo(account0.address);
        weeksForUnstake = await aqualisStaking.weeksForUnstake(account0.address);
        await time.increaseTo(now + i * 604800);
        console.log(i, '. AP: ', BigInt(reward), '. Weeks for unstake: ', BigInt(weeksForUnstake));
      }

    });

  });

  describe("Unstake", async function () {

    it("Unstake should fail, because timeLock perion not finished", async function () {
      let now = await time.latest();
      await time.increaseTo(now+10);
      await expect(aqualisStaking.unstake(1000000000)).to.be.revertedWith("Staking period has not expired");
    });

    it("Unstake should fail, because amount larger than staker has", async function () {
      const amount300 = hre.ethers.utils.parseEther("300");
      await expect(aqualisStaking.unstake(amount300)).to.be.revertedWith("Can't withdraw more than you have");
    });

    it("Unstake with penalty", async function () {

      let weeksForUnstake = await aqualisStaking.weeksForUnstake(account0.address);
      let stakeInfo = await aqualisStaking.getStakeInfo(account0.address);
      const amount100 = hre.ethers.utils.parseEther("100");

      let totalSupply = await aqualisToken.totalSupply();
      let ownerBallance = await aqualisToken.balanceOf(account0.address);
      let stakingBallance = await aqualisToken.balanceOf(aqualisStaking.address);
      let treasuryBallance = await aqualisToken.balanceOf(process.env.TREASURY_ADDRESS);
      let rwrdsPoolBallance = await aqualisToken.balanceOf(process.env.RWRDS_POOL_ADDRESS);
      console.log('Account: ', account0.address, ' amount: ', BigInt(stakeInfo.amount), ' timeLock: ', BigInt(stakeInfo.timeLock));
      console.log('Weeks for unstake: ', BigInt(weeksForUnstake));
      console.log('Before unastake with penalty: totalSupply: ', BigInt(totalSupply), '. ownerBallance', BigInt(ownerBallance), '. stakingBallance', BigInt(stakingBallance), '. treasuryBallance', BigInt(treasuryBallance), '. rwrdsPoolBallance', BigInt(rwrdsPoolBallance));

      await aqualisStaking.unstakeWithPenalty(amount100);
      
      totalSupply = await aqualisToken.totalSupply();
      ownerBallance = await aqualisToken.balanceOf(account0.address);
      stakingBallance = await aqualisToken.balanceOf(aqualisStaking.address);
      treasuryBallance = await aqualisToken.balanceOf(process.env.TREASURY_ADDRESS);
      rwrdsPoolBallance = await aqualisToken.balanceOf(process.env.RWRDS_POOL_ADDRESS);
      console.log('After unastake with penalty:  totalSupply: ', BigInt(totalSupply), '. ownerBallance', BigInt(ownerBallance), '. stakingBallance', BigInt(stakingBallance), '. treasuryBallance', BigInt(treasuryBallance), '. rwrdsPoolBallance', BigInt(rwrdsPoolBallance));
      console.log(' - ownerBallance must increase for amount (100 Tokens) - penalty (depends on staking period)');
      console.log(' - totalSupply must decrease for burned amount = 50% of penalty');
      console.log(' - stakingBallance must decrease for unstaking amount (100 Tokens)');
      console.log(' - treasuryBallance must increase for 10% from penalty');
      console.log(' - rwrdsPoolBallance must increase for 40% from penalty');

    });

  });
    
});
