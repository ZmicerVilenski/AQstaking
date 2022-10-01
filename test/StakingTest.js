const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
require('dotenv').config();

describe("Staking", function () {

  let token, staking, account0, account1, account2;

  async function deploy() {
    [account0, account1, account2] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("Token");
    token = await Token.deploy('Token', 'AQT');
    const Staking = await ethers.getContractFactory("Staking");
    staking = await Staking.deploy(token.address);  
  }

  describe("Deployment, fill the balances, check setters and getters", function () {

    it("Set parameters", async function () {

      await loadFixture(deploy);
      await staking.setTreasuryAddress(process.env.TREASURY_ADDRESS);
      await staking.setRewardsPoolAddress(process.env.RWRDS_POOL_ADDRESS);

      expect(await staking.treasuryAddress()).to.equal(process.env.TREASURY_ADDRESS);
      expect(await staking.rewardsPoolAddress()).to.equal(process.env.RWRDS_POOL_ADDRESS);

    });

    it("Setters & getters", async function () {

      await staking.setRewardsPerCompPeriod(22);
      expect(await staking.rewardsPerWeek()).to.equal(22);
      await staking.setPenaltyPerCompPeriod(4);
      expect(await staking.penaltyPerWeek()).to.equal(4);
      await staking.setMinimumWeeksNum(6);
      expect(await staking.minimumWeeksNum()).to.equal(6);
      await staking.setMaximumWeeksNum(200);
      expect(await staking.maximumWeeksNum()).to.equal(200);
      const depInfo = await staking.getDepositInfo(account0.address);
      console.log(depInfo);
      const stakeInfo = await staking.getStakeInfo(account0.address);
      console.log(stakeInfo);

      // Return all parameters to default
      await staking.setRewardsPerCompPeriod(20);
      await staking.setPenaltyPerCompPeriod(3);
      await staking.setMinimumWeeksNum(5);
      await staking.setMaximumWeeksNum(104);

    });

    it("Should set the right Token", async function () {
      expect(await staking.tokenAddress()).to.equal(token.address);
    });

    it("Should set the right owner for Token & Staking", async function () {
      expect(await token.owner()).to.equal(account0.address);
      expect(await staking.owner()).to.equal(account0.address);
    });

    it("Should get the right balances", async function () {

      const amount = hre.ethers.utils.parseEther("1000000000");
      await token.transfer(account1.address, amount);
      await token.transfer(account2.address, amount);
      expect(await token.balanceOf(account1.address)).to.equal(amount);
      expect(await token.balanceOf(account2.address)).to.equal(amount);

    });

    it("Should fail", async function () {
      await expect(staking.stake(0, 0)).to.be.revertedWith("Amount smaller than minimimum deposit");
    });

  });

  describe("Stake", function () {

    it("Approve Tokens for Staking SC", async function () {

      const amount = hre.ethers.utils.parseEther("1000000000");
      await token.approve(staking.address, amount); 
      await token.connect(account1).approve(staking.address, amount); 
      await token.connect(account2).approve(staking.address, amount);  

      expect(await token.allowance(account0.address, staking.address)).to.equal(amount);
      expect(await token.allowance(account1.address, staking.address)).to.equal(amount);
      expect(await token.allowance(account2.address, staking.address)).to.equal(amount);

    });

    it("Stake for 3 accounts", async function () {

      const amount100 = hre.ethers.utils.parseEther("100");
      const amount200 = hre.ethers.utils.parseEther("200");
      const amount300 = hre.ethers.utils.parseEther("300");

      await staking.stake(amount100, 10); // account0
      await staking.stakeFor(account1.address, amount100, 10); // account1
      await staking.connect(account2).stake(amount100, 10); // account2

      expect(await staking.totalStakedFor(account0.address)).to.equal(amount100);
      expect(await staking.totalStakedFor(account1.address)).to.equal(amount100);
      expect(await staking.totalStakedFor(account2.address)).to.equal(amount100);
      expect(await staking.totalStaked()).to.equal(amount300);

      await expect(staking.stake(amount100, 104)).to.emit(staking, "Staked").withArgs(account0.address, amount100, amount200, anyValue);
      await expect(staking.connect(account1).stake(amount100, 105)).to.emit(staking, "Staked").withArgs(account1.address, amount100, amount200, anyValue);
      await expect(staking.connect(account2).stake(amount100, 105)).to.emit(staking, "Staked").withArgs(account2.address, amount100, amount200, anyValue);

    });

    it("Change auto extending", async function () {

      expect(await staking.isStakeAutoExtending(account0.address)).to.equal(false);
      await staking.activateAutoExtending(); // for account 0
      expect(await staking.isStakeAutoExtending(account0.address)).to.equal(true);
      expect(await staking.isStakeAutoExtending(account1.address)).to.equal(true);
      await staking.connect(account1).disableAutoExtending(); // for account 1
      expect(await staking.isStakeAutoExtending(account1.address)).to.equal(false);

    });

    it("Extend timeLock and increase stake amount", async function () {

      let stakeInfo = await staking.getStakeInfo(account0.address);
      console.log('Account: ', account0.address, ' timeLock before extending: ', stakeInfo.timeLock);
      await staking.extendStaking(5); // Extend for 5 weeks
      stakeInfo = await staking.getStakeInfo(account0.address);
      console.log('Account: ', account0.address, ' timeLock after extending: ', stakeInfo.timeLock);

      const incAmount = hre.ethers.utils.parseEther("1");
      console.log('Account: ', account0.address, ' amount before extending: ', stakeInfo.amount);
      await staking.increaseStakingAmount(incAmount); // Increase for 1 token
      stakeInfo = await staking.getStakeInfo(account0.address);
      console.log('Account: ', account0.address, ' amount after extending: ', stakeInfo.amount);

    });

    it("Check staking amount, reward and timer", async function () {

      let stakeAmount, reward, weeksForUnstake;
      let now = await time.latest();
      weeksForUnstake = await staking.weeksForUnstake(account0.address);
      [stakeAmount, ] = await staking.getDepositInfo(account0.address);
      console.log('Stake amount: ', BigInt(stakeAmount));
      const n = Number(BigInt(weeksForUnstake));
      for (let i=1; i <= n; i++) {
        [,reward] = await staking.getDepositInfo(account0.address);
        weeksForUnstake = await staking.weeksForUnstake(account0.address);
        await time.increaseTo(now + i * 604800);
        console.log(i, '. AP: ', BigInt(reward), '. Weeks for unstake: ', BigInt(weeksForUnstake));
      }

    });

  });

  describe("Unstake", async function () {

    it("Unstake should fail, because timeLock perion not finished", async function () {
      let now = await time.latest();
      await time.increaseTo(now+10);
      await expect(staking.unstake(1000000000)).to.be.revertedWith("Staking period has not expired");
    });

    it("Unstake should fail, because amount larger than staker has", async function () {
      const amount300 = hre.ethers.utils.parseEther("300");
      await expect(staking.unstake(amount300)).to.be.revertedWith("Can't withdraw more than you have");
    });

    it("Unstake with penalty", async function () {

      let weeksForUnstake = await staking.weeksForUnstake(account0.address);
      let stakeInfo = await staking.getStakeInfo(account0.address);
      const amount100 = hre.ethers.utils.parseEther("100");

      let totalSupply = await token.totalSupply();
      let ownerBallance = await token.balanceOf(account0.address);
      let stakingBallance = await token.balanceOf(staking.address);
      let treasuryBallance = await token.balanceOf(process.env.TREASURY_ADDRESS);
      let rwrdsPoolBallance = await token.balanceOf(process.env.RWRDS_POOL_ADDRESS);
      console.log('Account: ', account0.address, ' amount: ', BigInt(stakeInfo.amount), ' timeLock: ', BigInt(stakeInfo.timeLock));
      console.log('Weeks for unstake: ', BigInt(weeksForUnstake));
      console.log('Before unastake with penalty: totalSupply: ', BigInt(totalSupply), '. ownerBallance', BigInt(ownerBallance), '. stakingBallance', BigInt(stakingBallance), '. treasuryBallance', BigInt(treasuryBallance), '. rwrdsPoolBallance', BigInt(rwrdsPoolBallance));

      await staking.unstakeWithPenalty(amount100);
      
      totalSupply = await token.totalSupply();
      ownerBallance = await token.balanceOf(account0.address);
      stakingBallance = await token.balanceOf(staking.address);
      treasuryBallance = await token.balanceOf(process.env.TREASURY_ADDRESS);
      rwrdsPoolBallance = await token.balanceOf(process.env.RWRDS_POOL_ADDRESS);
      console.log('After unastake with penalty:  totalSupply: ', BigInt(totalSupply), '. ownerBallance', BigInt(ownerBallance), '. stakingBallance', BigInt(stakingBallance), '. treasuryBallance', BigInt(treasuryBallance), '. rwrdsPoolBallance', BigInt(rwrdsPoolBallance));
      console.log(' - ownerBallance must increase for amount (100 Tokens) - penalty (depends on staking period)');
      console.log(' - totalSupply must decrease for burned amount = 50% of penalty');
      console.log(' - stakingBallance must decrease for unstaking amount (100 Tokens)');
      console.log(' - treasuryBallance must increase for 10% from penalty');
      console.log(' - rwrdsPoolBallance must increase for 40% from penalty');

    });

  });
    
});
