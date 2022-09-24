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
    aqualisStaking = await AqualisStaking.deploy(aqualisToken.address, process.env.RWRDS_POOL_ADDRESS, process.env.TREASURY_ADDRESS);  
  }

  describe("Deployment and fill the balances", function () {

    it("Should set the right Token", async function () {
      await loadFixture(deploy);
      expect(await aqualisStaking.token()).to.equal(aqualisToken.address);
    });

    it("Should set the right owner for Token", async function () {
      expect(await aqualisToken.owner()).to.equal(account0.address);
    });

    it("Should get the right balances", async function () {
      const amount = hre.ethers.utils.parseEther("1");
      await aqualisToken.transfer(account1.address, amount);
      await aqualisToken.transfer(account2.address, amount);
      expect(await aqualisToken.balanceOf(account1.address)).to.equal(amount);
      expect(await aqualisToken.balanceOf(account2.address)).to.equal(amount);
    });

    it("Should fail", async function () {
      await expect(aqualisStaking.stake(0, 0)).to.be.revertedWith("Amount smaller than minimimum deposit");
    });

  });

  describe("Staking 1", function () {

    it("Approve Tokens for Staking SC", async function () {
      const amount = hre.ethers.utils.parseEther("1000");
      await aqualisToken.approve(aqualisStaking.address, amount); 
      await aqualisToken.connect(account1).approve(aqualisStaking.address, amount); 
      await aqualisToken.connect(account2).approve(aqualisStaking.address, amount); 

      expect(await aqualisToken.allowance(account0.address, aqualisStaking.address)).to.equal(amount);
      expect(await aqualisToken.allowance(account1.address, aqualisStaking.address)).to.equal(amount);
      expect(await aqualisToken.allowance(account2.address, aqualisStaking.address)).to.equal(amount);
    });

    it("Stake for 3 accounts", async function () {
      const amount0 = hre.ethers.utils.parseEther("0");
      const amount05 = hre.ethers.utils.parseEther("0.5");
      const amount15 = hre.ethers.utils.parseEther("1.5");
      await aqualisStaking.stake(amount05, 0); // account0
      await aqualisStaking.stakeFor(account1.address, amount05, 0); // account1
      await aqualisStaking.stakeFor(account2.address, amount05, 0); // account2

      expect(await aqualisStaking.totalStakedFor(account0.address)).to.equal(amount05);
      expect(await aqualisStaking.totalStakedFor(account1.address)).to.equal(amount05);
      expect(await aqualisStaking.totalStakedFor(account2.address)).to.equal(amount05);
      expect(await aqualisStaking.totalStaked()).to.equal(amount15);

      // const [stakeAmount, reward] = await aqualisStaking.getDepositInfo(account0.address);
      // console.log('Stake amount: ', stakeAmount, '. Reward: ', reward);
      // expect(await aqualisStaking.getDepositInfo(account0.address)).to.equal([amount05, amount0]);
      const rewardTimer = await aqualisStaking.unstakeTimer(account0.address);
      const COUMPOUND_FREQ = await aqualisStaking.COUMPOUND_FREQ();
      console.log('Reward timer: ', rewardTimer);
      console.log('COUMPOUND_FREQ: ', COUMPOUND_FREQ);
    });

    it("Check rewards after 1 week", async function () {
      const [stakeAmount, reward] = await aqualisStaking.getDepositInfo(account0.address);
      console.log('Stake amount: ', stakeAmount, '. Reward: ', reward);
      const rewardTimer = await aqualisStaking.unstakeTimer(account0.address);
      console.log('Reward timer: ', rewardTimer);
    });

  });

  // describe("Withdrawals", function () {
  //   describe("Validations", function () {
  //     it("Should revert with the right error if called too soon", async function () {
  //       const { lock } = await loadFixture(deployOneYearLockFixture);

  //       await expect(lock.withdraw()).to.be.revertedWith(
  //         "You can't withdraw yet"
  //       );
  //     });

  //     it("Should revert with the right error if called from another account", async function () {
  //       const { lock, unlockTime, otherAccount } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       // We can increase the time in Hardhat Network
  //       await time.increaseTo(unlockTime);

  //       // We use lock.connect() to send a transaction from another account
  //       await expect(lock.connect(otherAccount).withdraw()).to.be.revertedWith(
  //         "You aren't the owner"
  //       );
  //     });

  //     it("Shouldn't fail if the unlockTime has arrived and the owner calls it", async function () {
  //       const { lock, unlockTime } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       // Transactions are sent using the first signer by default
  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw()).not.to.be.reverted;
  //     });
  //   });

  //   describe("Events", function () {
  //     it("Should emit an event on withdrawals", async function () {
  //       const { lock, unlockTime, lockedAmount } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw())
  //         .to.emit(lock, "Withdrawal")
  //         .withArgs(lockedAmount, anyValue); // We accept any value as `when` arg
  //     });
  //   });

  //   describe("Transfers", function () {
  //     it("Should transfer the funds to the owner", async function () {
  //       const { lock, unlockTime, lockedAmount, owner } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw()).to.changeEtherBalances(
  //         [owner, lock],
  //         [lockedAmount, -lockedAmount]
  //       );
  //     });
  //   });
  // });
});
