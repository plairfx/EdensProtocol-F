// SPDX-License-Identifier: MIT

import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata, IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IEdenPL} from "./Interfaces/IEdenPL.sol";

pragma solidity ^0.8.23;

contract EdenVault is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address immutable asset;
    address immutable pool;
    uint256 totalAssetsDeposited;
    uint256 totalFeesGenerated;

    // Events
    event Withdrawn(uint256 amount);
    event Deposited(uint256 amount);

    // Errors
    error AmountIsNotEqualDepositedETH();
    error SharesOrAssetsLessThanExpected();

    modifier onlyPool() {
        require(msg.sender == pool);
        _;
    }

    constructor(address depositAsset, address _pool) ERC20("LP-Token", "LP") {
        asset = depositAsset;
        pool = _pool;
    }

    receive() external payable {
        if (msg.sender == pool) {} else if (asset == address(0x0)) {
            getAccumulatedFees();
            deposit(msg.value, ((msg.value / 100 ether) * 95 ether));
        } else {
            revert("Asset Not Eth");
        }
    }

    function useLiq(uint256 amount) external onlyPool {
        if (asset != address(0x0)) {
            IERC20(asset).safeTransfer(pool, amount);
        } else {
            (bool success,) = pool.call{value: amount}("");
            require(success);
        }
    }

    /**
     * @notice deposits token in return for shares token.
     * @dev Deposits the token in the vault for shares,
     * before every deposit `getAccumulatedFees()` gets called if  pool has rewards it will add the token to the vault.
     * to ensure the profits stays with right users.
     * @param amount The amount to deposit
     * @param minAmount the min amount of shares the user wants to receive
     * @return shares
     */
    function deposit(uint256 amount, uint256 minAmount) public payable nonReentrant returns (uint256 shares) {
        getAccumulatedFees();
        if (asset == address(0x0)) {
            require(msg.value == amount, AmountIsNotEqualDepositedETH());
        } else {
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }
        shares = _deposit(amount, minAmount);
        totalAssetsDeposited += amount;
        emit Deposited(amount);
    }

    /**
     * @notice withdraw the asset in exchange for shares.
     * @dev withdraws the token in the vault for the asset
     * before every withdraw `getAccumulatedFees()` gets called if  pool has rewards it will add the token to the vault.
     * to ensure the profits stays with right users.
     * @param amount The amount the user wants to withdraw.
     * @param minAmount the min amount of tokens to receive
     * @return assets
     */
    function withdraw(uint256 amount, uint256 minAmount) public nonReentrant returns (uint256 assets) {
        getAccumulatedFees();
        assets = _withdraw(amount, minAmount);
        totalAssetsDeposited -= amount;
        emit Withdrawn(amount);
    }

    function _deposit(uint256 amount, uint256 minAmount) internal returns (uint256 shares) {
        shares = convertToShares(amount);
        require(shares >= minAmount, SharesOrAssetsLessThanExpected());
        _mint(msg.sender, shares);
    }

    function _withdraw(uint256 shares, uint256 minAmount) internal returns (uint256 assets) {
        uint256 amountToReceive = convertToAssets(shares);

        require(amountToReceive >= minAmount, SharesOrAssetsLessThanExpected());

        if (asset != (address(0x0))) {
            _burn(msg.sender, shares);
            IERC20(asset).safeTransfer(msg.sender, amountToReceive);
            assets = amountToReceive;
        } else {
            _burn(msg.sender, shares);
            (bool success,) = msg.sender.call{value: amountToReceive}("");
            require(success);
            assets = amountToReceive;
        }
    }

    /**
     * @notice gets called to receive the fees  from the set Pool if there any.
     * @dev  checks to see if the fees are higher than 0, if so the vault will call `getFeesAccumulated`
     * to receive the fees, this happens so the user depositing/withdrawnig will always get the full amount + fees the vault has earned.
     */
    function getAccumulatedFees() internal returns (uint256 fees) {
        uint256 fees = IEdenPL(pool).getFeesAccumulated();
        if (fees > 0) {
            IEdenPL(pool).depositFees();
            totalAssetsDeposited += fees;
        }
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256 assets) {
        assets = (shares * totalAssetsDeposited) / totalSupply();
    }

    function _convertToShares(uint256 assets) internal view returns (uint256 shares) {
        if (totalSupply() == 0) {
            shares = assets;
        } else {
            shares = (assets * totalSupply()) / totalAssetsDeposited;
        }
    }

    function getAsset() public view returns (address) {
        return asset;
    }

    function decimals() public view override returns (uint8) {
        if (asset != (address(0x0))) {
            return IERC20Metadata(asset).decimals();
        } else {
            return 18;
        }
    }

    function totalAssets() public view returns (uint256) {
        return totalAssetsDeposited;
    }

    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = _convertToShares(assets);
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = _convertToAssets(shares);
    }
}
