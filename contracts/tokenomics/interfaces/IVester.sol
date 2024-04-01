// SPDX-License-Identifier: BSD-3-Clause

pragma solidity 0.8.13;

interface IVester {
    function claimable(address _account) external view returns (uint256);
    function cumulativeClaimAmounts(address _account) external view returns (uint256);
    function claimedAmounts(address _account) external view returns (uint256);
    function getVestedAmount(address _account) external view returns (uint256);
}
