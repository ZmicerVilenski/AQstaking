// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Token.sol";
import "./ABDKMath64x64.sol";

/**
 * @title Staking contract
 */
contract Staking is Ownable, ReentrancyGuard {
    uint256 public rewardsPerWeek; // 20 - 2% by default
    uint256 public penaltyPerWeek; // 3 by default that means 0.3% It will be necessary to divide percent powered by 10
    uint256 public minimumWeeksNum; // 5 by default
    uint256 public maximumWeeksNum; // 104 by default
    address public treasuryAddress;
    address public rewardsPoolAddress;

    // Struct for personal stakes
    // amount - the amount of tokens in the stake
    // timeLock - when the stake finish (in seconds since Unix epoch)
    // autoExtended - flag of automaticaly extended staking period for maximum avalible (maximumWeeksNum)
    struct StakeInfo {
        uint256 amount;
        uint256 timeLock;
        bool autoExtended;
    }
    mapping(address => StakeInfo) private stakers;
    Token private immutable token;

    event Staked(
        address indexed staker,
        uint256 amount,
        uint256 total,
        uint256 timeLock
    );
    event Unstaked(
        address indexed staker,
        uint256 amount,
        uint256 total,
        uint256 weeksNum
    );
    event StakingChended(
        address indexed staker,
        uint256 newAmount,
        uint256 newTimeLock,
        bool autoExtended
    );

    /**
     * @dev Constructor function
     * @param _token ERC20 The address of the token contract used for staking
     */
    constructor(address _token) {
        token = Token(_token);
        // set default values:
        rewardsPerWeek = 20;
        penaltyPerWeek = 3;
        minimumWeeksNum = 5;
        maximumWeeksNum = 104;
    }

    /**
     * @dev Set Treasury address.
     * @param _treasuryAddress Treasury address
     */
    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        treasuryAddress = _treasuryAddress;
    }

    /**
     * @dev Set Rewards pool address.
     * @param _rewardsPoolAddress Rewards pool address
     */
    function setRewardsPoolAddress(address _rewardsPoolAddress)
        external
        onlyOwner
    {
        rewardsPoolAddress = _rewardsPoolAddress;
    }

    /**
     * @dev Set Rewards per compound period
     * @param _rewardsPerWeek Rewards per compound period,
     * by default = 20 or 2% (multiplied by 10 to allow to enter a fractional number)
     * in Smart contract used only integer numbers, no float
     */
    function setRewardsPerCompPeriod(uint256 _rewardsPerWeek)
        external
        onlyOwner
    {
        rewardsPerWeek = _rewardsPerWeek;
    }

    /**
     * @dev Set Rewards per compound period
     * @param _penaltyPerWeek Penalty per compound period if stake withdraw befor time lock (staking period),
     * by default = 3 or 0.3% (multiplied by 10 to allow to enter a fractional number)
     * in Smart contract used only integer numbers, no float
     */
    function setPenaltyPerCompPeriod(uint256 _penaltyPerWeek)
        external
        onlyOwner
    {
        penaltyPerWeek = _penaltyPerWeek;
    }

    /**
     * @dev Set minimum number of weeks for staking.
     * @param _minimumWeeksNum Number of weeks
     */
    function setMinimumWeeksNum(uint256 _minimumWeeksNum) external onlyOwner {
        minimumWeeksNum = _minimumWeeksNum;
    }

    /**
     * @dev Set maximum number of weeks for staking.
     * @param _maximumWeeksNum Number of weeks
     */
    function setMaximumWeeksNum(uint256 _maximumWeeksNum) external onlyOwner {
        maximumWeeksNum = _maximumWeeksNum;
    }

    /**
     * @notice Return deposit info (value array [stakeAmount, rewardPower])
     * @param _staker Staker address
     */
    function getDepositInfo(address _staker)
        external
        view
        returns (uint256 stakeAmount, uint256 rewardPower)
    {
        stakeAmount = stakers[_staker].amount;
        rewardPower = _calculateRewards(_staker);
    }

    /**
     * @notice Return Stake info in structure {amount, timeLock}
     * @param _staker Staker address
     */
    function getStakeInfo(address _staker)
        external
        view
        returns (StakeInfo memory)
    {
        return stakers[_staker];
    }

    /**
     * @notice Stakes a certain amount of tokens, this MUST transfer the given amount from the staker
     * @notice MUST trigger Staked event
     * @param _amount uint256 the amount of tokens to stake
     * @param _weeksNum number of staking weeks
     */
    function stake(uint256 _amount, uint256 _weeksNum) external {
        _createStake(msg.sender, _amount, _weeksNum);
    }

    /**
     * @notice Stakes a certain amount of tokens, this MUST transfer the given amount from the caller
     * @notice MUST trigger Staked event
     * @param _staker address of the  staker
     * @param _amount uint256 the amount of tokens to stake
     * @param _weeksNum number of staking weeks
     */
    function stakeFor(
        address _staker,
        uint256 _amount,
        uint256 _weeksNum
    ) external onlyOwner {
        _createStake(_staker, _amount, _weeksNum);
    }

    /**
     * @dev function to create stakes for a given address
     * @param _staker address of the  staker
     * @param _amount number of tokens being staked
     * @param _weeksNum number of staking weeks
     */
    function _createStake(
        address _staker,
        uint256 _amount,
        uint256 _weeksNum
    ) internal {
        require(_amount > 0, "Amount smaller than minimimum deposit");
        require(_weeksNum >= minimumWeeksNum, "Insufficient staking interval");
        // if user stake at least one week more than the maximum, then the stake will go into a state of automatic renewal
        // the number of weeks before the unstake will always be equal to the maximum
        if (_weeksNum > maximumWeeksNum) {
            stakers[_staker].autoExtended = true;
        }
        stakers[_staker].amount += _amount;
        stakers[_staker].timeLock = block.timestamp + (_weeksNum * 1 weeks);

        token.transferFrom(_staker, address(this), _amount);
        emit Staked(
            _staker,
            _amount,
            totalStakedFor(_staker),
            stakers[_staker].timeLock
        );
    }

    /**
     * @notice activate auto renewal of staking
     */
    function activateAutoExtending() external {
        stakers[msg.sender].autoExtended = true;
        emit StakingChended(
            msg.sender,
            stakers[msg.sender].amount,
            stakers[msg.sender].timeLock,
            stakers[msg.sender].autoExtended
        );
    }

    /**
     * @notice return flag of auto extenging for staker's stake
     * @param _staker address of the  staker
     */
    function isStakeAutoExtending(address _staker)
        external
        view
        returns (bool)
    {
        return stakers[_staker].autoExtended;
    }

    /**
     * @notice disable auto renewal of staking
     */
    function disableAutoExtending() external {
        stakers[msg.sender].autoExtended = false;
        stakers[msg.sender].timeLock =
            block.timestamp +
            (maximumWeeksNum * 1 weeks);
        emit StakingChended(
            msg.sender,
            stakers[msg.sender].amount,
            stakers[msg.sender].timeLock,
            stakers[msg.sender].autoExtended
        );
    }

    /**
     * @notice Extend the staking period. The staker may also add additional weeks onto their current stake to increase rewards, by minimum intervals of 1 week.
     * @param _weeksNum number of weeks to extend
     */
    function extendStaking(uint256 _weeksNum) external {
        require(_weeksNum > 0, "Number of weeks must be > 0");
        // if user stake at least one week more than the maximum, then the stake will go into a state of automatic renewal
        // the number of weeks before the unstake will always be equal to the maximum
        uint256 weeksLeft;
        if (block.timestamp < stakers[msg.sender].timeLock) {
            weeksLeft =
                (stakers[msg.sender].timeLock - block.timestamp) /
                1 weeks;
        }
        if (weeksLeft + _weeksNum > maximumWeeksNum) {
            stakers[msg.sender].autoExtended = true;
        }
        stakers[msg.sender].timeLock += _weeksNum * 1 weeks;
        emit StakingChended(
            msg.sender,
            stakers[msg.sender].amount,
            stakers[msg.sender].timeLock,
            stakers[msg.sender].autoExtended
        );
    }

    /**
     * @notice Increase staking amount.
     * @param _amount amount by which to increase staking
     */
    function increaseStakingAmount(uint256 _amount) external {
        require(_amount > 0, "Amount must be > 0");
        stakers[msg.sender].amount += _amount;
        emit StakingChended(
            msg.sender,
            stakers[msg.sender].amount,
            stakers[msg.sender].timeLock,
            stakers[msg.sender].autoExtended
        );
    }

    /**
     * @notice Unstakes a certain amount of tokens, this SHOULD return the given amount of tokens to the staker, if unstaking is currently not possible the function MUST revert
     * @notice MUST trigger Unstaked event
     * @param _amount uint256 the amount of tokens to unstake
     */
    function unstake(uint256 _amount) external nonReentrant {
        address staker = msg.sender;
        require(
            stakers[staker].amount >= _amount,
            "Can't withdraw more than you have"
        );
        require(
            stakers[staker].timeLock <= block.timestamp,
            "Staking period has not expired"
        );
        stakers[staker].amount -= _amount;

        token.transfer(staker, _amount);
        emit Unstaked(
            staker,
            _amount,
            totalStakedFor(staker),
            stakers[msg.sender].timeLock
        );
    }

    /**
     * @notice UnstakesAll amount of tokens, this SHOULD return the given amount of tokens to the staker, if unstaking is currently not possible the function MUST revert
     * @notice MUST trigger Unstaked event
     * @dev Unstaking tokens is an atomic operation—either all of the tokens in a stake, or none of the tokens.
     */
    function unstakeAll() external nonReentrant {
        address staker = msg.sender;
        uint256 amount = stakers[staker].amount;
        require(amount > 0, "You have no deposit");
        require(
            stakers[staker].timeLock <= block.timestamp,
            "Staking period has not expired"
        );
        stakers[staker].amount = 0;
        stakers[staker].timeLock = 0;

        token.transfer(staker, amount);
        emit Unstaked(staker, amount, totalStakedFor(staker), 0);
    }

    /**
     * @notice Unstakes a certain amount of tokens, before staking period finished, while taking a fine
     * @notice Early Unstaking Fee
     * Staked AQL may be unstaked earlier for a fee of 1% plus 0.3% per week remaining (rounded up), for example:
     * Less than 1 week remaining 1% + 0.3%  = 1.3%
     * Between 10 to 11 weeks remaining = 1% + 3.3% = 4.3%
     * Between 104 to 105 weeks remaining = 1% + 31.5% = 32.5%
     * @notice MUST trigger Unstaked event
     * @param _amount uint256 the amount of tokens to unstake
     */
    function unstakeWithPenalty(uint256 _amount) external nonReentrant {
        address staker = msg.sender;
        uint256 weeksNum = weeksForUnstake(staker);
        uint256 penaltyPercent = weeksNum * penaltyPerWeek + 10; // +10 (1%) because penaltyPerWeek multiply by 10
        uint256 penalty = (_amount * penaltyPercent) / 1000;
        uint256 returnAmount = _amount - penalty;

        stakers[staker].amount -= _amount;

        token.transfer(staker, returnAmount);
        // 50% will be burned
        uint256 toBurn = penalty / 2;
        //token.burn(address(this), toBurn);
        token.transfer(
            address(0x000000000000000000000000000000000000dEaD),
            toBurn
        ); // To burn contract send tokens to DEAD address
        // 10% will be distributed to the Treasury
        uint256 toTreasury = penalty / 10;
        token.transfer(treasuryAddress, toTreasury);
        // 40% will be distributed to the AP Rewards Pool
        token.transfer(rewardsPoolAddress, penalty - toBurn - toTreasury);

        emit Unstaked(
            staker,
            returnAmount,
            totalStakedFor(staker),
            stakers[staker].timeLock
        );
    }

    /**
     * @notice Returns the current total of tokens staked for an address
     * @param _address address The address to query
     * @return uint256 The number of tokens staked for the given address
     */
    function totalStakedFor(address _address) public view returns (uint256) {
        return stakers[_address].amount;
    }

    /**
     * @notice Returns the current total of tokens staked
     * @return uint256 The number of tokens staked in the contract
     */
    function totalStaked() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Address of the token being used by the staking interface
     * @return address The address of the ERC20 token used for staking
     */
    function tokenAddress() external view returns (address) {
        return address(token);
    }

    /**
     * @notice returns reward in AP
     * @param _staker staker address
     * @return rewards in Reward Power
     */
    function calculateRewardPower(address _staker)
        external
        view
        returns (uint256)
    {
        return _calculateRewards(_staker);
    }

    /**
     * @notice Function for Snapshot
     * @param _staker staker address
     * @return rewards in Reward Power
     */
    function calculateReward(address _staker) external view returns (uint256) {
        return _calculateRewards(_staker);
    }

    /**
     * @notice Returns the timer for unstake in seconds
     * @param _staker staker address
     * @return _timer remaining seconds to unstake
     */
    function unstakeTimer(address _staker)
        public
        view
        returns (uint256 _timer)
    {
        if (stakers[_staker].autoExtended) {
            return maximumWeeksNum * 1 weeks;
        }

        if (stakers[_staker].timeLock <= block.timestamp) {
            return 0;
        } else {
            return stakers[_staker].timeLock - block.timestamp;
        }
    }

    /**
     * @notice Returns the timer for unstake in weeks
     * @param _staker staker address
     * @return remaining weeks to unstake
     */
    function weeksForUnstake(address _staker) public view returns (uint256) {
        return unstakeTimer(_staker) / 1 weeks + 1;
    }

    /**
     * @notice Utility function, returns the minimum of two values
     * @param a value 1
     * @param b value 2
     * @return minimum value
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    /**
     * @dev rewards calculated incrementaly (compounding)
     * Tokens may be staked for anywhere between 5 to 104 weeks. Each additional week staked gives the staker an additional 2% AP (compounding).
     * Based on the figures above, the rewards get exponentially better based on the time staked
     * @param _staker staker address
     * @return rewards in Reward Power
     */
    function _calculateRewards(address _staker)
        internal
        view
        returns (uint256 rewards)
    {
        uint256 weeksNum;
        if (stakers[_staker].autoExtended) {
            weeksNum = maximumWeeksNum;
        } else {
            weeksNum = weeksForUnstake(_staker);
            weeksNum = _min(weeksNum, maximumWeeksNum);
        }
        uint256 baseAmount = stakers[_staker].amount;
        // percent fraction = 3 because percentages are set * 10 for the ability to set fractions
        // to get the percentage need to divide not by 100 but by 1000 (3 zeros)
        rewards = _compound(baseAmount, rewardsPerWeek, weeksNum, 3);
    }

    /**
     * @dev Utility function, calculate reward exponential "A_0*(1+r)^n". Use ABDKMath64x64 library
     * @param _base base amount
     * @param _ratio reward percent
     * @param _n power
     * @param _percentFraction percent fraction
     * @return reward exponential "A_0*(1+r)^n"
     */
    function _compound(
        uint256 _base,
        uint256 _ratio,
        uint256 _n,
        uint256 _percentFraction
    ) internal pure returns (uint256) {
        return
            ABDKMath64x64.mulu(
                ABDKMath64x64.pow(
                    ABDKMath64x64.add(
                        ABDKMath64x64.fromUInt(1),
                        ABDKMath64x64.divu(_ratio, 10**_percentFraction)
                    ), //(1+r), where r is allowed to be one hundredth of a percent, ie 5/100/100
                    _n
                ), //(1+r)^n
                _base
            ); //A_0 * (1+r)^n
    }
}
