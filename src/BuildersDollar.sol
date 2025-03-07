// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// BuildersDollar - An ERC20 stablecoin fully collateralized by DAI
// which earns yield in Aave for the BuildersDollarchain Ecosystem
// implemented by: kassandra.eth

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IRewardsController} from "./interfaces/IRewardsController.sol";

contract BuildersDollar is ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    IERC20 public immutable aToken;
    IPool public immutable pool;
    IRewardsController public immutable rewards;

    address public yieldClaimer;

    event Minted(address receiver, uint256 amount);
    event Burned(address receiver, uint256 amount);

    event YieldClaimerSet(address yieldClaimer);

    event ClaimedYield(uint256 amount);
    event ClaimedRewards(address[] rewardsList, uint256[] claimedAmounts);

    error OnlyClaimers();
    error ClaimZero();
    error YieldInsufficient();

    error ClaimRewardsFailedLowLevel();
    error ClaimRewardsFailed();

    constructor(address _token, address _aToken, address _pool, address _rewards) {
        token = IERC20(_token);
        aToken = IERC20(_aToken);
        pool = IPool(_pool);
        rewards = IRewardsController(_rewards);
    }

    function initialize(string memory name, string memory symbol) external initializer {
        __ERC20_init(name, symbol);
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
    }

    function setYieldClaimer(address _yieldClaimer) external onlyOwner {
        yieldClaimer = _yieldClaimer;
        emit YieldClaimerSet(_yieldClaimer);
    }

    modifier onlyYieldClaimer() {
        _checkYieldClaimer();
        _;
    }

    function _checkYieldClaimer() internal view virtual {
        if (yieldClaimer != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }

    function mint(uint256 amount, address receiver) external {
        require(amount > 0, "BuildersDollar: mint 0");
        IERC20 _token = token;
        IPool _pool = pool;
        _token.safeTransferFrom(msg.sender, address(this), amount);
        _token.safeIncreaseAllowance(address(_pool), amount);
        _pool.supply(address(_token), amount, address(this), 0);
        _mint(receiver, amount);
        emit Minted(receiver, amount);
    }

    function burn(uint256 amount, address receiver) external nonReentrant {
        require(amount > 0, "BuildersDollar: burn 0");
        _burn(msg.sender, amount);
        IPool _pool = pool;
        aToken.safeIncreaseAllowance(address(_pool), amount);
        _pool.withdraw(address(token), amount, receiver);
        emit Burned(receiver, amount);
    }

    function claimYield(uint256 amount) external onlyYieldClaimer {
        if (amount == 0) revert ClaimZero();
        uint256 yield = _yieldAccrued();
        if (yield < amount) revert YieldInsufficient();
        pool.withdraw(address(token), amount, owner());
        emit ClaimedYield(amount);

        try this.claimRewards() {}
        catch Error(string memory) {
            revert ClaimRewardsFailed();
        } catch (bytes memory) {
            revert ClaimRewardsFailedLowLevel();
        }
    }

    function claimRewards() external nonReentrant {
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        (address[] memory rewardsList, uint256[] memory claimedAmounts) = rewards.claimAllRewards(assets, owner());

        emit ClaimedRewards(rewardsList, claimedAmounts);
    }

    function rescueToken(address tok, uint256 amount) external onlyOwner {
        require(tok != address(aToken), "BuildersDollar: cannot withdraw collateral");
        IERC20(tok).safeTransfer(owner(), amount);
    }

    function yieldAccrued() external view returns (uint256) {
        return _yieldAccrued();
    }

    function rewardsAccrued() external view returns (address[] memory rewardsList, uint256[] memory unclaimedAmounts) {
        address[] memory assets;
        assets[0] = address(aToken);
        return rewards.getAllUserRewards(assets, address(this));
    }

    function _yieldAccrued() internal view returns (uint256) {
        return aToken.balanceOf(address(this)) - totalSupply();
    }
}
