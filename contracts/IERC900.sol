// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

/**
 * @title ERC900 Simple Staking Interface
 * @dev See https://github.com/ethereum/EIPs/blob/master/EIPS/eip-900.md
 */
interface IERC900 {
    event Staked(
        address indexed user,
        uint256 amount,
        uint256 total,
        bytes data
    );
    event Unstaked(
        address indexed user,
        uint256 amount,
        uint256 total,
        bytes data
    );

    function stake(uint256 amount, bytes memory data) external;

    function stakeFor(
        address user,
        uint256 amount,
        bytes memory data
    ) external;

    function unstake(uint256 amount, bytes memory data) external;

    function totalStakedFor(address addr) external view returns (uint256);

    function totalStaked() external view returns (uint256);

    function token() external view returns (address);

    function supportsHistory() external pure returns (bool);
}
