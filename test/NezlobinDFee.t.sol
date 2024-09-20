//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {console} from "forge-std/console.sol";
import {LiquidityAmounts} from "lib/v4-periphery/lib/v4-core/test/utils/LiquidityAmounts.sol";

import {NezlobinDirectionalFee} from "../src/NezlobinDirectionalFee.sol";

contract NezlobinDFeeTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    NezlobinDirectionalFee feeHook;
    Currency token0;
    Currency token1;
    MockERC20 token;
    uint24 fee = 3000;
    int24 tickLower = -60;
    int24 tickUpper = 60;
    uint8 decimals = 6;
    address streamUpkeep = 0x5083b3A4739cE599809988C911aF618eCd08bfFA;
    uint256 token0ToSpend = 100 ether;
    int256 amountSpcfd = 2.5 ether;
    address someAddress = makeAddr("someAddress");

    function setUp() public {
        token0 = Currency.wrap(address(0));

        deployFreshManagerAndRouters();
        // (token0, token1) = deployMintAndApprove2Currencies();

        token = new MockERC20("Test USDC", "USDC", decimals);
        token1 = Currency.wrap(address(token));

        MockERC20(Currency.unwrap(token1)).mint(address(this), 100 ether);

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.AFTER_INITIALIZE_FLAG |
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
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

        MockERC20(Currency.unwrap(token1)).approve(
            address(feeHook),
            type(uint256).max
        );
        MockERC20(Currency.unwrap(token1)).approve(
            address(modifyLiquidityRouter),
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

        uint160 sqrtPriceAtLowerTick = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceAtUpperTick = TickMath.getSqrtPriceAtTick(tickUpper);

        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            sqrtPriceAtLowerTick,
            sqrtPriceAtUpperTick,
            token0ToSpend
        );

        vm.deal(address(this), 200 ether);

        modifyLiquidityRouter.modifyLiquidity{value: token0ToSpend}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int128(liquidityDelta),
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

        swapRouter.swap{value: 2.5 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -amountSpcfd,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            test,
            ZERO_BYTES
        );

        int256 newAmtSpcfd = 10 ether;

        swapRouter.swap{value: uint256(newAmtSpcfd)}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -newAmtSpcfd,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            test,
            ZERO_BYTES
        );

        console.log("-------------------New-Block--------------------");

        uint256 currentBlock = block.number;
        vm.roll(currentBlock + 1);

        swapRouter.swap{value: uint256(amountSpcfd)}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -amountSpcfd,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            test,
            ZERO_BYTES
        );

        console.log("------------------------------------------------");
        swapRouter.swap{value: uint256(amountSpcfd)}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -amountSpcfd,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            test,
            ZERO_BYTES
        );

        console.log("------------------------------------------------");
        swapRouter.swap{value: uint256(amountSpcfd)}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -amountSpcfd,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            test,
            ZERO_BYTES
        );

        console.log("-------------------New-Block--------------------");
        uint256 newBlock = block.number;
        vm.roll(newBlock + 1);

        swapRouter.swap{value: uint256(amountSpcfd)}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -amountSpcfd,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            test,
            ZERO_BYTES
        );

        console.log("------------------------------------------------");
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
