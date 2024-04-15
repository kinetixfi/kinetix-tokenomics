// SPDX-License-Identifier: BSD-3-Clause

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IVester.sol";
import "./interfaces/IBurnable.sol";
import "../utils/Governable.sol";

/**
 * @title  Vester
 * @notice Implementation of vesting.
 */
contract Vester is IVester, IERC20, ReentrancyGuard, Governable {

    using SafeERC20 for IERC20;

    string public  name;
    string public symbol;
    uint8 public decimals = 18;

    uint256 public immutable vestingDuration;  // in seconds
    uint256 public immutable directRefundRate; // bps 100

    address public immutable depositToken;  // must be burnable
    address public immutable claimableToken;

    uint256 public override totalSupply;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public override cumulativeClaimAmounts;
    mapping(address => uint256) public override claimedAmounts;
    mapping(address => uint256) public lastVestingTimes;

    event Claim(address indexed receiver, uint256 amount);
    event Deposit(address indexed account, uint256 depositAmount , uint256 directRefundAmount);
    event WithdrawToken(address indexed account, address indexed token, uint256 withdrawAmount);
    event UpdateVesting(address indexed account,uint256 lastVestingTime,uint256 burnAmount);

    /// @notice constructor
    /// @dev Initializes token addresses and vesting parameters
    /// @param _name vesting token name
    /// @param _name vesting token symbol
    /// @param _vestingDuration vesting duration in seconds
    /// @param _directRefundRate direct refund rate, if defined, some part of deposit amount, directly transfer
    /// @param _depositToken deposit token address
    /// @param _claimableToken claimable token address
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _vestingDuration,
        uint256 _directRefundRate,
        address _depositToken,
        address _claimableToken
    )  {
        require(_directRefundRate < 100, "invalid direct refund rate");
        require(_depositToken != address(0), "invalid deposit token");
        require(_claimableToken != address(0), "invalid claimable token");
        require(_depositToken != _claimableToken, "invalid tokens");
        name = _name;
        symbol = _symbol;
        

        vestingDuration = _vestingDuration;
        directRefundRate = _directRefundRate;
        depositToken = _depositToken;
        claimableToken = _claimableToken;
    }

    /// @notice send claimable amount to msg.sender
    function claim() external nonReentrant returns (uint256) {
        return _claim(msg.sender, msg.sender);
    }

    /// @notice send claimable amount to _receiver
    /// @param _receiver receiver address
    function claimTo(address _receiver) external nonReentrant returns (uint256) {
        require(_receiver != address(0), "zero address");
        return _claim(msg.sender, _receiver);
    }

    /// @dev to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov nonReentrant{
        if (_token == depositToken) {
            uint256 depositBalance = IERC20(depositToken).balanceOf(address(this));
            require(totalSupply + _amount <= depositBalance , "Not allowed to withdraw users' funds");
        }
        if (_token == claimableToken) {
            uint256 claimBalance = IERC20(claimableToken).balanceOf(address(this));
            require(totalSupply + _amount <= claimBalance , "Not allowed to withdraw users' funds");
        }

        IERC20(_token).safeTransfer(_account, _amount);
        emit WithdrawToken(_account, _token ,_amount);
    }

    /// @notice calculate claimable amount for `_account`
    function claimable(address _account) public view override returns (uint256) {
        uint256 amount = cumulativeClaimAmounts[_account] - claimedAmounts[_account];
        uint256 nextClaimable = _getNextClaimableAmount(_account);
        return amount + nextClaimable;
    }

    /// @notice vesting token balance of `_account`
    function balanceOf(address _account) external view override returns (uint256) {
        return balances[_account];
    }

    /// @dev empty implementation, tokens are non-transferrable
    function transfer(
        address, /* recipient */
        uint256 /* amount */
    ) public pure override returns (bool) {
        revert("non-transferrable");
    }

    /// @dev empty implementation, tokens are non-transferrable
    function allowance(
        address, /* owner */
        address /* spender */
    ) public view virtual override returns (uint256) {
        return 0;
    }

    /// @dev empty implementation, tokens are non-transferrable
    function approve(
        address, /* spender */
        uint256 /* amount */
    ) public pure virtual override returns (bool) {
        revert("non-transferrable");
    }

    /// @dev empty implementation, tokens are non-transferrable
    function transferFrom(
        address, /* sender */
        address, /* recipient */
        uint256 /* amount */
    ) public pure virtual override returns (bool) {
        revert("non-transferrable");
    }

    /// @notice total vested amount of `_account`
    function getVestedAmount(address _account) public view override returns (uint256) {
        return balances[_account] + cumulativeClaimAmounts[_account];
    }

    /// @dev vesting token mint function
    function _mint(address _account, uint256 _amount) private {
        require(_account != address(0), "mint to the zero address");

        totalSupply = totalSupply + _amount;
        balances[_account] = balances[_account] + _amount;

        emit Transfer(address(0), _account, _amount);
    }

    /// @dev vesting token burn function
    function _burn(address _account, uint256 _amount) private {
        require(_account != address(0), "burn from the zero address");
        require(balances[_account] >= _amount , "burn amount exceeds balance");
        balances[_account] = balances[_account] - _amount;
        totalSupply = totalSupply - _amount;

        emit Transfer(_account, address(0), _amount);
    }

    /// @notice deposit for vesting 
    /// @param _amount amount of deposit token
    function deposit(uint256 _amount) external nonReentrant{         
        require(_amount > 0, "invalid _amount");
        uint256 claimBalance = IERC20(claimableToken).balanceOf(address(this));
        require(claimBalance >= totalSupply + _amount, "Not enough claimable token");
        address account = msg.sender;

        _updateVesting(account);

        IERC20(depositToken).safeTransferFrom(account, address(this), _amount);

        uint256 directRefundAmount;

        if (directRefundRate > 0){
            directRefundAmount = (_amount * directRefundRate) / 100;
        }

        uint256 depositAmount = _amount - directRefundAmount;

        _mint(account, depositAmount);

        if(directRefundAmount > 0){
            IBurnable(depositToken).burn(directRefundAmount);
            IERC20(claimableToken).safeTransfer(account, directRefundAmount);
        }

        emit Deposit(account, depositAmount, directRefundAmount);
    }

    /// @notice update vesting status for `_account`
    /// @dev update lastVestingTimes for `_account` and if claimable amount exists, 
    /// @dev burn  and transfer to cumulativeClaimAmounts 
    /// @param _account amount of deposit token
    function _updateVesting(address _account) private {
        uint256 amount = _getNextClaimableAmount(_account);
        lastVestingTimes[_account] = block.timestamp;

        if (amount > 0) {
            // transfer claimableAmount from balances to cumulativeClaimAmounts
            _burn(_account, amount);
            cumulativeClaimAmounts[_account] = cumulativeClaimAmounts[_account] + amount;

            IBurnable(depositToken).burn(amount);
        }

        emit UpdateVesting(_account, block.timestamp, amount);
    }

    /// @dev calculate next claimable amounts  for `_account` 
    function _getNextClaimableAmount(address _account) private view returns (uint256) {
        uint256 timeDiff = block.timestamp - lastVestingTimes[_account];
        if (timeDiff == 0) {
            return 0;
        }

        uint256 balance = balances[_account];
        if (balance == 0 ) {
            return 0;
        }

        uint256 vestedAmount = getVestedAmount(_account);
        uint256 claimableAmount =(vestedAmount * timeDiff) / vestingDuration;

        if (claimableAmount < balance) {
            return claimableAmount;
        }

        return balance;
    }

    /// @dev internal function of claim
    function _claim(address _account, address _receiver) private returns (uint256) {
        _updateVesting(_account);
        uint256 amount = claimable(_account);
        if(amount > 0){
            claimedAmounts[_account] = claimedAmounts[_account] + amount;
            IERC20(claimableToken).safeTransfer(_receiver, amount);
        }
        emit Claim(_account, amount);
        return amount;
    }
}
