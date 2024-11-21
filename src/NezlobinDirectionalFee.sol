// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "lib/v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "lib/v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "lib/v4-periphery/lib/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolIdLibrary, PoolId} from "lib/v4-periphery/lib/v4-core/src/types/PoolId.sol";
import {PoolKey} from "lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "lib/v4-periphery/lib/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import {StateLibrary} from "lib/v4-periphery/lib/v4-core/src/libraries/StateLibrary.sol";
import {BalanceDelta} from "lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title Nezlobin Directional Fee Hook
/// @notice A Uniswap V4 hook that implements dynamic fee adjustment based on price impact
/// @dev This contract adjusts LP fees based on recent price movements to optimize liquidity & IL for LPs
contract NezlobinDirectionalFee is BaseHook {
    // Custom errors
    error NZD__MustBeDynamicFee();
    error NZD__FeeFactorIsTooBig();
    error NZD__OnlyOwnerAccess();

    // Library usage
    using CurrencyLibrary for Currency;
    using LPFeeLibrary for uint24;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    // External contract interface
    AggregatorV3Interface v3Interface;

    // State variables
    PoolId public poolId;
    uint24 public initialLpFee = 1e3;
    uint256 public cDelta;
    int256 public ethPriceT;
    int256 public ethPriceT1;
    int256 priceImpactPercent;

    // Configurable parameters
    uint256 public alpha = 2e16; // Represents 0.02
    int256 public buyThreshold = 2e4;
    int256 public sellThreshold = -2e4;

    // Constants
    uint256 public constant ALPHA_PRECISION = 1e18;
    uint256 public constant CDELTA_PRECISION = 1e24;
    int256 public constant PRICE_IMPACT_PRECISION = 1e4;

    // Immutable variables
    address public immutable i_owner;

    // Mappings
    mapping(PoolId => uint256) public poolIdToBlock;

    /// @notice Restricts function access to the contract owner
    modifier onlyOwner() {
        if (msg.sender != i_owner) revert NZD__OnlyOwnerAccess();
        _;
    }

    /// @notice Initializes the contract with the Uniswap V4 PoolManager
    /// @param _manager The address of the Uniswap V4 PoolManager
    constructor(
        IPoolManager _manager,
        address priceFeedAddress
    ) BaseHook(_manager) {
        i_owner = msg.sender;
        v3Interface = AggregatorV3Interface(priceFeedAddress);
    }

    /// @notice Defines the permissions for this hook in the Uniswap V4 ecosystem
    /// @return Hooks.Permissions The set of permissions required by this hook
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /// @notice Initializes the hook for a new pool
    /// @dev Sets up initial price and ensures the pool uses dynamic fees
    /// @param key The PoolKey for the new pool
    function beforeInitialize(
        address,
        PoolKey calldata key,
        uint160,
        bytes calldata
    ) external override returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert NZD__MustBeDynamicFee();
        poolIdToBlock[key.toId()] = block.number;
        return this.beforeInitialize.selector;
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24,
        bytes calldata
    ) external override returns (bytes4) {
        poolManager.updateDynamicLPFee(key, initialLpFee);
        return (this.afterInitialize.selector);
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        (uint256 currentSqrtPrice, , , ) = poolManager.getSlot0(key.toId());

        ethPriceT = int(currentSqrtPrice);

        return (this.afterAddLiquidity.selector, delta);
    }

    /// @notice Executes before a swap operation
    /// @dev Calculates price impact and adjusts fees accordingly
    /// @param key The PoolKey for the swap
    /// @param params The swap parameters
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        poolId = key.toId();
        if (poolIdToBlock[key.toId()] < block.number) {
            poolIdToBlock[key.toId()] = block.number;

            // Update price and calculate price impact
            (uint256 sqrtPriceAtT1, , , ) = poolManager.getSlot0(key.toId());

            ethPriceT1 = int256(sqrtPriceAtT1);

            priceImpactPercent =
                ((ethPriceT1 - ethPriceT) * PRICE_IMPACT_PRECISION) /
                ethPriceT;

            // Calculate cDelta
            cDelta = priceImpactPercent < 0
                ? calculateCDelta(key, uint256(-priceImpactPercent))
                : calculateCDelta(key, uint256(priceImpactPercent));

            ethPriceT = ethPriceT1;
        }

        // Adjust fees based on price impact
        if (priceImpactPercent > 0 && priceImpactPercent >= buyThreshold) {
            adjustFees(key, params, true);
        } else if (
            priceImpactPercent < 0 && priceImpactPercent <= sellThreshold
        ) {
            adjustFees(key, params, false);
        } else {
            return (
                this.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, int128) {
        return (this.afterSwap.selector, 0);
    }

    /// @notice Updates the buy threshold
    /// @param newBuyThreshold The new buy threshold value
    function updateBuyThreshold(int256 newBuyThreshold) public onlyOwner {
        buyThreshold = newBuyThreshold;
    }

    /// @notice Updates the sell threshold
    /// @param newSellThreshold The new sell threshold value
    function updateSellThreshold(int256 newSellThreshold) public onlyOwner {
        sellThreshold = newSellThreshold;
    }

    /// @notice Updates the alpha value
    /// @param newAlpha The new alpha value
    function updateAlpha(uint256 newAlpha) public onlyOwner {
        alpha = newAlpha;
    }

    /// @notice Calculates the 'c' factor for fee adjustment
    /// @dev Uses fixed-point arithmetic to handle decimal values
    /// @param key The PoolKey for the calculation
    /// @param priceImpact The calculated price impact
    /// @return cdelta The calculated 'cDelta' factor
    function calculateCDelta(
        PoolKey calldata key,
        uint256 priceImpact
    ) internal view returns (uint256 cdelta) {
        uint128 liquidity = poolManager.getLiquidity(key.toId());
        (, , , uint24 currentLpFee) = poolManager.getSlot0(key.toId());

        uint256 numerator = alpha * priceImpact * CDELTA_PRECISION;
        uint256 denominator = liquidity * ALPHA_PRECISION;

        // Calculate initial c
        uint256 c = numerator / denominator;

        // Calculate maximum allowable c based on currentLpFee constraint
        // Subtract 1 to ensure currentLpFee - cdelta > 0
        uint256 maxC = (currentLpFee - 1) / priceImpact;

        // Use the minimum of calculated c and maxC
        c = c > maxC ? maxC : c;

        cdelta = c * priceImpact;
    }

    function getTickLiquidity(
        PoolKey calldata key
    ) public view returns (uint128 liquidity) {
        liquidity = poolManager.getLiquidity(key.toId());
    }

    /// @notice Retrieves the current LP fee for the pool
    /// @return The current LP fee
    function getLpFee() public view returns (uint24) {
        (, , , uint24 lpFee) = poolManager.getSlot0(poolId);
        return lpFee;
    }

    /// @notice Adjusts the LP fees based on price impact
    /// @dev This is an internal function called by beforeSwap
    /// @param key The PoolKey for the adjustment
    /// @param params The swap parameters
    /// @param isToken0PricePumping Whether the adjustment is for a buy or sell
    function adjustFees(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bool isToken0PricePumping
    ) internal {
        (, , , uint24 currentLpFee) = poolManager.getSlot0(key.toId());

        uint24 newFee;
        if (isToken0PricePumping) {
            newFee = params.zeroForOne
                ? currentLpFee - uint24(cDelta)
                : currentLpFee + uint24(cDelta);
        } else {
            newFee = params.zeroForOne
                ? currentLpFee + uint24(cDelta)
                : currentLpFee - uint24(cDelta);
        }

        poolManager.updateDynamicLPFee(key, newFee);
    }
}
