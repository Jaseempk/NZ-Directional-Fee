# Nezlobin Directional Fee Hook

This repository contains a Uniswap V4 Hook contract implementing a dynamic fee mechanism based on price impact. The hook adjusts swap fees in response to market conditions, aiming to optimize liquidity provision and trading efficiency.

## Overview

The `NezlobinDirectionalFee` contract is a custom hook for Uniswap V4 that implements a directional fee strategy. It adjusts the LP fee based on the price impact of recent trades, potentially reducing fees for trades that improve market stability and increasing fees for trades that might increase volatility.

## Features

- Dynamic fee adjustment based on price impact
- Integration with Uniswap V4's hook system
- Adjustable thresholds for fee adjustments
- Owner-controlled parameter updates
- Efficient use of Uniswap V4's singleton contract architecture

## Contract Details

- **Contract Name:** `NezlobinDirectionalFee`
- **Extends:** `BaseHook`

### Key Components

1. **Price Impact Calculation:** The contract calculates the price impact percentage between blocks.
2. **Fee Adjustment:** Based on the price impact, the contract adjusts the LP fee for buys and sells.
3. **Thresholds:** Configurable thresholds (`buyThreshold` and `sellThreshold`) determine when fee adjustments are triggered.
4. **Owner Controls:** The contract includes functions for the owner to update key parameters.

## Usage

To deploy and use this hook:

1. Deploy the `NezlobinDirectionalFee` contract, passing the Uniswap V4 PoolManager address as a constructor argument.
2. When creating a new pool or modifying an existing one in Uniswap V4, specify this contract's address as the hook for the pool.

## Configuration

Key parameters that can be adjusted by the owner:

- `ALPHA`: Coefficient for fee calculation (default: 200000000000000000, representing 0.2)
  - Note: ALPHA is represented using fixed-point arithmetic with 18 decimal places
- `buyThreshold`: Threshold for buy-side fee adjustments (default: 2)
- `sellThreshold`: Threshold for sell-side fee adjustments (default: -2)

To update these parameters:

```solidity
function updateBuyThreshold(int256 newBuyThreshold) public onlyOwner
function updateSellThreshold(int256 newSellThreshold) public onlyOwner
function updateAlpha(uint256 newAlpha) public onlyOwner

```

## Owner Functions

The contract includes the following owner-only functions:

- `updateAlpha`:Updates the alpha value
- `updateBuyThreshold`: Updates the buy threshold
- `updateSellThreshold`: Updates the sell threshold

Only the address set as `i_owner` during contract deployment can call these functions.
