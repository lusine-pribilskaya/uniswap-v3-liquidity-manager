# LiquidityPositionManager

## Overview
The **LiquidityPositionManager** is a Solidity smart contract that allows users to create liquidity positions on **Uniswap V3** with a specified position width. The contract ensures the proper allocation of liquidity across a **price range** determined by the user-defined width.

## Key Features
- **Liquidity Provision**: Adds liquidity to a Uniswap V3 pool with a defined price range.
- **Tick Adjustments**: Ensures tick values are properly spaced according to Uniswap's tick rules.
- **On-Chain Price Calculation**: Computes the **lower** and **upper** bounds of the position **fully on-chain**.
- **Reentrancy Protection**: Uses **ReentrancyGuard** from OpenZeppelin to secure token transfers.
- **Event Logging**: Emits detailed events for external tracking.

## Smart Contract Details
### **1. Core Functionality**
#### **createLiquidityPosition()**
This function:
- Accepts Uniswap V3 pool address, token amounts, position width, and slippage tolerance.
- Adjusts price bounds based on the given width.
- Transfers and approves tokens before minting a Uniswap V3 position.
- Handles excess token refunds and emits relevant events.

#### **preparePosition()**
- Fetches the current Uniswap V3 price and computes valid **tick boundaries**.
- Adjusts the **tick spacing** to match the pool's tick spacing requirement.

#### **_determinePriceRange()**
- Computes the **lower and upper price bounds** based on the current pool price.
- Uses **Uniswap's TickMath** to convert prices into **sqrtPriceX96** format.

### **2. Token Management**
#### **_handleTokenTransfers()**
- Transfers and approves token0/token1 before adding liquidity.

#### **_refundTokens()**
- Refunds excess tokens if the exact required amount was not used.

### **3. Tick & Price Adjustments**
#### **_adjustTickToSpacing()**
- Ensures that tick values align with Uniswap's required tick spacing.

## Events
- **LiquidityPositionCreated** → Emitted when a new liquidity position is successfully created.
- **ExcessTokensReturned** → Emitted when unused tokens are refunded.
- **LiquidityComputationFailed** → Emitted if an error occurs during liquidity calculations.

## Deployment & Testing
### Prerequisites
- **Node.js** (>=16.x)
- **Hardhat** framework
- **Solidity 0.7.6**
- **Uniswap V3 Core & Periphery Contracts**

### Installation
```sh
npm install
```

### Compilation
```sh
npx hardhat compile
```

### Running Tests
```sh
npx hardhat test
```

## Usage
### Deploying the Contract
1. Configure the **Hardhat network** settings.
2. Deploy the contract using:
   ```sh
   npx hardhat run scripts/deploy.js --network sepolia
   ```

### Creating a Liquidity Position
Call the **createLiquidityPosition** function with:
```solidity
liquidityManager.createLiquidityPosition(
    poolAddress,
    amountToken0,
    amountToken1,
    positionWidth,
    slippageTolerance
);
```

## Security Considerations
- **ReentrancyGuard** is implemented to prevent reentrancy attacks.
- **Tick spacing and price range validation** ensure safe interactions with Uniswap V3.
- **Excess token refunds** prevent locked funds in the contract.

## License
This project is licensed under the **MIT License**.

