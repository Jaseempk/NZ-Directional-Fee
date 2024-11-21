// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Constants} from "lib/v4-periphery/lib/v4-core/test/utils/Constants.sol";

contract V4PreDeployed is Script {
    PoolManager manager =
        PoolManager(0x7Da1D65F8B249183667cdE74C5CBD46dD38AA829);
    PoolSwapTest swapRouter =
        PoolSwapTest(0x96E3495b712c6589f1D2c50635FDE68CF17AC83c);
    PoolModifyLiquidityTest modifyLiquidityRouter =
        PoolModifyLiquidityTest(0xC94a4C0a89937E278a0d427bb393134E68d5ec09);

    Currency token0;
    Currency token1;

    address token0Address = address(0);
    address token1Address = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    PoolKey key;

    function setUp() public {
        vm.startBroadcast();

        if (address(token0Address) > address(token1Address)) {
            (token0, token1) = (
                Currency.wrap(
                    address(0x036CbD53842c5426634e7929541eC2318f3dCF7e)
                ),
                Currency.wrap(
                    address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
                )
            );
        } else {
            (token0, token1) = (
                Currency.wrap(
                    address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
                ),
                Currency.wrap(
                    address(0x036CbD53842c5426634e7929541eC2318f3dCF7e)
                )
            );
        }

        key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 120,
            hooks: IHooks(0xECb8F35dD96116C9fE6b71A9e7E64CD49b38b4C0)
        });

        // the second argument here is SQRT_PRICE_1_1
        manager.initialize(
            key,
            79228162514264337593543950336,
            Constants.ZERO_BYTES
        );
    }

    function run() public {}
}
