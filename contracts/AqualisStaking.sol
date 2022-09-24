// !!! Contract in development, do not use in production !!!
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Token.sol";
import "./IERC900.sol";

/**
 * @title ERC900 Simple Staking Interface basic implementation
 * @dev See https://github.com/ethereum/EIPs/blob/master/EIPS/eip-900.md
 */
contract AqualisStaking is ReentrancyGuard, IERC900 {
    uint256 public constant REWARDS_PER_WEEK = 2;
    uint256 public constant PENALTY_PER_WEEK = 3; // 0.3% It will be necessary to divide percent powered by 10
    uint256 public constant COUMPOUND_FREQ = 1 weeks;
    uint256 public constant MINIMUM_WEEK_NUM = 5;
    uint256 public constant MINIMUM_STAKE = 5 weeks;
    uint256 public constant MAXIMUM_WEEK_NUM = 104;
    uint256 public constant MAXIMUM_STAKE = 104 weeks;

    address public treasuryAddress;
    address public rewardsPoolAddress;

    // Struct for personal stakes
    // amount - the amount of tokens in the stake
    // aqualisPower - AP
    // timeOfLastUpdate - when the stake was made/changed_ (in seconds since Unix epoch)
    // timeLock - when the stake finish (in seconds since Unix epoch)
    struct StakeInfo {
        uint256 amount;
        uint256 aqualisPower;
        uint256 timeOfLastUpdate; // @TODO optimize
        uint256 timeLock; // optimize
    }
    mapping(address => StakeInfo) private stakers;
    Token private immutable aqualisToken;

    event StakingExtended(address indexed user, uint256 newTimeLock);

    /**
     * @dev Constructor function
     * @param _aqualisToken ERC20 The address of the token contract used for staking
     */
    constructor(
        address _aqualisToken,
        address _rewardsPoolAddress,
        address _treasuryAddress
    ) {
        aqualisToken = Token(_aqualisToken);
        rewardsPoolAddress = _rewardsPoolAddress;
        treasuryAddress = _treasuryAddress;
    }

    /**
     * @dev Helper function to create stakes for a given address
     * @param _staker address The address the stake is being created for
     * @param _amount uint256 The number of tokens being staked
     * @param _data bytes optional data to include in the Stake event. Number of staking weeks
     */
    function createStake(
        address _staker,
        uint256 _amount,
        bytes memory _data
    ) internal {
        require(_amount > 0, "Amount smaller than minimimum deposit");
        if (stakers[_staker].amount != 0) {
            uint256 weeksNum = dataToWeeksNum(_data);
            require(
                weeksNum >= MINIMUM_WEEK_NUM,
                "MInsufficient staking interval"
            );
            require(weeksNum <= MAXIMUM_WEEK_NUM, "Maximum interval exceeded");
            // @TODO optimize. create structure in memory and write to storage in one run
            stakers[_staker].amount = _amount;
            stakers[_staker].timeOfLastUpdate = block.timestamp;
            stakers[_staker].timeLock = block.timestamp + (weeksNum * 1 weeks);
        } else {
            // If there has already been staking and the user adds another amount of tokens,
            // then his AP will be calculated on the current date from the old amount, and the new amount (old + added) will be calculated from the current date.
            // The timelock cannot be changed. There is a separate function to increase it - extendStaking()
            stakers[_staker].aqualisPower += _calculateRewards(_staker);
            stakers[_staker].amount += _amount; //Important, the amount should change after the reward calculations
            stakers[_staker].timeOfLastUpdate = block.timestamp; //Important, the timeOfLastUpdate should change after the reward calculations
        }

        aqualisToken.transferFrom(_staker, address(this), _amount);
        emit Staked(_staker, _amount, totalStakedFor(_staker), _data);
    }

    /**
     * @notice Stakes a certain amount of tokens, this MUST transfer the given amount from the user
     * @notice MUST trigger Staked event
     * @param _amount uint256 the amount of tokens to stake
     * @param _data bytes optional data to include in the Stake event. Number of staking weeks
     */
    function stake(uint256 _amount, bytes calldata _data) external {
        createStake(msg.sender, _amount, _data);
    }

    /**
     * @notice Stakes a certain amount of tokens, this MUST transfer the given amount from the caller
     * @notice MUST trigger Staked event
     * @param _user address the address the tokens are staked for
     * @param _amount uint256 the amount of tokens to stake
     * @param _data bytes optional data to include in the Stake event. Number of staking weeks
     */
    // @TODO wouldn't this feature be a problem, because someone can stake for another?
    function stakeFor(
        address _user,
        uint256 _amount,
        bytes calldata _data
    ) external {
        createStake(_user, _amount, _data);
    }

    /**
     * @notice Extend the staking period. The user may also add additional weeks onto their current stake to increase rewards, by minimum intervals of 1 week.
     * @param _weeksNum number of weeks to extend
     */
    function extendStaking(uint256 _weeksNum) external {
        require(_weeksNum > 0, "Minimum extended period 1 week");
        require(_weeksNum < MAXIMUM_WEEK_NUM, "Maximum interval exceeded");
        // @TODO A complex check can be made to ensure that the added number of weeks does not exceed the maximum (104),
        // otherwise the AP will not be added, and the staking lock will remain.
        // But it will consume more gas
        stakers[msg.sender].timeLock += _weeksNum * 1 weeks;
        emit StakingExtended(msg.sender, stakers[msg.sender].timeLock);
    }

    /**
     * @notice Unstakes a certain amount of tokens, this SHOULD return the given amount of tokens to the user, if unstaking is currently not possible the function MUST revert
     * @notice MUST trigger Unstaked event
     * @param _amount uint256 the amount of tokens to unstake
     * @param _data bytes optional data to include in the Unstake event
     */
    function unstake(uint256 _amount, bytes calldata _data)
        external
        nonReentrant
    {
        address staker = msg.sender;
        require(
            stakers[staker].amount >= _amount,
            "Can't withdraw more than you have"
        );
        require(
            stakers[staker].timeLock > block.timestamp,
            "Staking period has not expired"
        );
        stakers[staker].aqualisPower = _calculateRewards(staker);
        stakers[staker].amount -= _amount; //Important, the amount should change after the reward calculations
        stakers[staker].timeOfLastUpdate = block.timestamp; //Important, the timeOfLastUpdate should change after the reward calculations

        aqualisToken.transfer(staker, _amount);
        emit Unstaked(staker, _amount, totalStakedFor(staker), _data);
    }

    /**
     * @notice UnstakesAll amount of tokens, this SHOULD return the given amount of tokens to the user, if unstaking is currently not possible the function MUST revert
     * @notice MUST trigger Unstaked event
     * @dev Unstaking tokens is an atomic operation—either all of the tokens in a stake, or none of the tokens.
     */
    function unstakeAll() external nonReentrant {
        address staker = msg.sender;
        uint256 amount = stakers[staker].amount;
        require(amount > 0, "You have no deposit");
        require(
            stakers[staker].timeLock > block.timestamp,
            "Staking period has not expired"
        );
        stakers[staker].amount = 0;
        stakers[staker].timeOfLastUpdate = 0;
        stakers[staker].timeLock = 0;
        // stakers[staker].aqualisPower = 0; // I don't think it needs to be reset.
        aqualisToken.transfer(staker, amount);
        emit Unstaked(staker, amount, totalStakedFor(staker), "");
    }

    // @TODO prohibit unstaking before the period
    // Early Unstaking Fee
    // Staked AQL may be unstaked earlier for a fee of 1% plus 0.3% per week remaining (rounded up), for example:
    // Less than 1 week remaining 1% + 0.3%  = 1.3%
    // Between 10 to 11 weeks remaining = 1% + 3.3% = 4.3%
    // Between 104 to 105 weeks remaining = 1% + 31.5% = 32.5%
    // This fee will be distributed in the following way:
    // 50% will be burned
    // 40% will be distributed to the AP Rewards Pool
    // 10% will be distributed to the Treasury
    function unstakeWithPenalty(uint256 _amount) external nonReentrant {
        address staker = msg.sender;
        uint256 weeksNum = unstakeTimer(staker) / 1 weeks;
        uint256 penaltyPercent = weeksNum * PENALTY_PER_WEEK + 10; // +10 (1%) because PENALTY_PER_WEEK multiply by 10
        uint256 penalty = (_amount * penaltyPercent) / 1000;
        uint256 returnAmount = _amount - penalty;

        stakers[staker].aqualisPower = _calculateRewards(staker); // Leave the full calculation of the AP or need to take the fine?
        stakers[staker].amount -= _amount;
        stakers[staker].timeOfLastUpdate = block.timestamp;

        aqualisToken.transfer(staker, returnAmount);
        // 50% will be burned
        uint256 toBurn = penalty / 2;
        aqualisToken.burn(staker, toBurn);
        // 10% will be distributed to the Treasury
        uint256 toTreasury = penalty / 10;
        aqualisToken.transfer(treasuryAddress, toTreasury);
        // 40% will be distributed to the AP Rewards Pool
        aqualisToken.transfer(
            rewardsPoolAddress,
            penalty - toBurn - toTreasury
        );

        emit Unstaked(staker, returnAmount, totalStakedFor(staker), "");
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
    function totalStaked() public view returns (uint256) {
        return aqualisToken.balanceOf(address(this));
    }

    /**
     * @notice Address of the token being used by the staking interface
     * @return address The address of the ERC20 token used for staking
     */
    function token() public view returns (address) {
        return address(aqualisToken);
    }

    /**
     * @notice MUST return true if the optional history functions are implemented, otherwise false
     * @dev Since we don't implement the optional interface, this always returns false
     * @return bool Whether or not the optional history functions are implemented
     */
    function supportsHistory() public pure returns (bool) {
        return false;
    }

    function calculateAqualisPower(address _staker)
        external
        view
        returns (uint256)
    {
        return stakers[_staker].aqualisPower + _calculateRewards(_staker);
    }

    // For Snapshot
    function calculateReward(address _staker) external view returns (uint256) {
        return stakers[_staker].aqualisPower + _calculateRewards(_staker);
    }

    function getDepositInfo(address _staker)
        public
        view
        returns (uint256 _stake, uint256 _rewards)
    {
        _stake = stakers[_staker].amount;
        _rewards = stakers[_staker].aqualisPower + _calculateRewards(_staker);
    }

    function getStakeInfo(address _staker)
        public
        view
        returns (StakeInfo memory)
    {
        return stakers[_staker];
    }

    // Utility function that returns the timer for unstake
    function unstakeTimer(address _staker)
        public
        view
        returns (uint256 _timer)
    {
        if (stakers[_staker].timeLock <= block.timestamp) {
            _timer = 0;
        } else {
            _timer = stakers[_staker].timeLock - block.timestamp;
        }
    }

    function dataToWeeksNum(bytes memory data) private pure returns (uint256) {
        uint256 x;
        assembly {
            x := mload(add(data, add(0x20, 0)))
        }
        return x;
    }

    // https://github.com/GNSPS/solidity-bytes-utils/blob/6458fb2780a3092bc756e737f246be1de6d3d362/contracts/BytesLib.sol#L374-L383
    function toUint256(bytes memory _data, uint256 _start)
        internal
        pure
        returns (uint256)
    {
        require(_data.length >= _start + 32, "slicing out of range");
        uint256 x;
        assembly {
            x := mload(add(_data, add(0x20, _start)))
        }
        return x;
    }

    function slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _length
    ) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");
        bytes memory tempBytes;
        assembly {
            switch iszero(_length)
            case 0 {
                tempBytes := mload(0x40)
                let lengthmod := and(_length, 31)
                let mc := add(
                    add(tempBytes, lengthmod),
                    mul(0x20, iszero(lengthmod))
                )
                let end := add(mc, _length)
                for {
                    let cc := add(
                        add(
                            add(_bytes, lengthmod),
                            mul(0x20, iszero(lengthmod))
                        ),
                        _start
                    )
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }
                mstore(tempBytes, _length)
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            default {
                tempBytes := mload(0x40)
                mstore(tempBytes, 0)
                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    // rewards must be calculated incrementaly (compounding)
    // Tokens may be staked for anywhere between 5 to 105 weeks. Each additional week staked gives the user an additional 2% AP (compounding). For example:
    // 100 AQ staked for 5 weeks = 110.41 AP (10.41% bonus)
    // 100 AQ staked for 52 weeks = 280.03 AP (180.03% bonus)
    // 100 AQ staked for 104 weeks = 784.18 AP (684.18% bonus)
    // Based on the figures above, the rewards get exponentially better based on the time staked
    function _calculateRewards(address _staker)
        internal
        view
        returns (uint256 rewards)
    {
        uint256 weeksNum = (block.timestamp -
            stakers[_staker].timeOfLastUpdate) / COUMPOUND_FREQ;
        weeksNum = min(weeksNum, MAXIMUM_WEEK_NUM);
        uint256 baseAmount = stakers[_staker].amount +
            stakers[_staker].aqualisPower;
        uint256 feePerNextWeek;
        for (uint256 i = 0; i <= weeksNum; i++) {
            feePerNextWeek = ((baseAmount + rewards) * REWARDS_PER_WEEK) / 100;
            rewards += feePerNextWeek;
        }
    }
}

// 1. You want to split each user's stake into parts, for example, Alan stakes 1000 tokens for 10 weeks, after 2 weeks he wants to stake another 500 tokens for 10 weeks.
//    need to create an array of staking, each will behave separately. And each will need to be separately unstake, renew, and withdraw.
//    And also somewhere to keep a list of all the current stakes of the user (it is problematic to do this in the blockchain, because of the gas)
//    Or will be only one staking for the user, and if he adds, subtracts, extends something, then he does it all with one stake?
//    Then, when adding a stake, what to do with the previous timelock?
// 2. Reward to consider whole weeks? For example, 5 weeks and 5 days have passed. Will the reward be calculated as a whole 5 weeks or 5 weeks + a fraction of the week (5 days)?
// 3. Interaction with the contract only through the frontend or through the block explorer too?
// 4. Reward percentage, number of weeks, etc. can make variables instead of constants?
// 5. "Fixed or Variable Duration ??? // Users may stake tokens for a locked duration (timer will not count down) or a variable duration.
//    Users can toggle between fixed and variable staking on the smart contract." - I dont understand this part
// 6. AP reset after unstake? If reset it, then many unclear situations will arise, for example, if not all amount is unstaken, 1 wei or several are left. The amount will not be reset
//    and then it is not clear how to reset the AP.
// 7. "50% will be burned
//    40% will be distributed to the AP Rewards Pool
//    10% will be distributed to the Treasury"
//    I need Treasure and Pool addresses. Just transfer the token to these addresses? Or is it complicated with Pool?
// 8. Does the owner's contract need to be done? For example, to set different parameters and addresses (register, reward pool, etc.). Will this create distrust in the community?
//    Assuming the owner can change the staking rules at any time
