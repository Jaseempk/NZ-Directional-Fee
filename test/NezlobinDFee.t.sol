//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {MockERC20} from "@uniswap/v4-core/lib/forge-gas-snapshot/lib/forge-std/src/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {console} from "forge-std/console.sol";

import {NezlobinDirectionalFee} from "../src/NezlobinDirectionalFee.sol";

contract NezlobinDFeeTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    NezlobinDirectionalFee feeHook;
    Currency token0;
    Currency token1;
    uint24 fee = 3000;
    int24 tickLower = -60;
    int24 tickUpper = 60;
    address streamUpkeep = 0x5083b3A4739cE599809988C911aF618eCd08bfFA;
    int256 liquidityDelta = 100 ether;
    int256 amountSpcfd = 2.5 ether;
    address someAddress = makeAddr("someAddress");

    function setUp() public {
        deployFreshManagerAndRouters();
        (token0, token1) = deployMintAndApprove2Currencies();
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );
        address nezlobinHookAddress = address(flags);

        deployCodeTo(
            "NezlobinDirectionalFee.sol:NezlobinDirectionalFee",
            abi.encode(manager),
            nezlobinHookAddress
        );
        feeHook = NezlobinDirectionalFee(nezlobinHookAddress);

        MockERC20(Currency.unwrap(token0)).approve(
            address(feeHook),
            type(uint256).max
        );
        MockERC20(Currency.unwrap(token1)).approve(
            address(feeHook),
            type(uint256).max
        );

        (key, ) = initPool(
            token0,
            token1,
            feeHook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_baseFeeFluctuations_basedOnGasPrice() public {
        PoolSwapTest.TestSettings memory test = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        uint24 lpFeeBeforeSwap = feeHook.getLpFee();
        console.log("lpFeeBefore:", lpFeeBeforeSwap);

        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -amountSpcfd,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            test,
            ZERO_BYTES
        );
        console.log("sqrtLmt:", TickMath.MIN_SQRT_PRICE);
        uint24 lpFeeAfterSwap1 = feeHook.getLpFee();
        console.log("lpFeeAfterSwap1:", lpFeeAfterSwap1);

        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -amountSpcfd,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            test,
            ZERO_BYTES
        );
        console.log("sqrtLmt2:", TickMath.MIN_SQRT_PRICE + 2);
        uint24 lpFeeAfterSwap2 = feeHook.getLpFee();
        console.log("lpFeeAfterSwap2:", lpFeeAfterSwap2);
    }

    function test_accessControlFailures() public {
        uint256 newAlpha = 3e16;
        int256 newBuyThreshold = 3;
        int256 sellThreshold = -3;
        vm.startPrank(someAddress);

        vm.expectRevert(NezlobinDirectionalFee.NZD__OnlyOwnerAccess.selector);
        feeHook.updateAlpha(newAlpha);

        vm.expectRevert(NezlobinDirectionalFee.NZD__OnlyOwnerAccess.selector);
        feeHook.updateBuyThreshold(newBuyThreshold);

        vm.expectRevert(NezlobinDirectionalFee.NZD__OnlyOwnerAccess.selector);
        feeHook.updateSellThreshold(sellThreshold);

        vm.stopPrank();
    }
}
