// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6; // Solidity version 0.7.6 is used due to compatibility requirements //had to
pragma abicoder v2; //Enables ABI coder v2 for structs in function parameters (had to)

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

// LiquidityPositionManager allows users to create Uniswap V3 positions with a specified width.
contract LiquidityPositionManager is ReentrancyGuard {
    INonfungiblePositionManager public immutable positionManager;
    int24 public constant MAX_ALLOWED_TICK_DEVIATION = 200; // Prevents liquidity provision in extreme market conditions

    // Events for external tracking of liquidity operations
    event LiquidityPositionCreated(
        address indexed user,
        uint256 indexed positionId,
        uint128 liquidityAmount,
        uint256 actualAmount0,
        uint256 actualAmount1,
        int24 lowerTick,
        int24 upperTick
    );

    event ExcessTokensReturned(address indexed user, address token, uint256 amount);  // Emitted when excess tokens are refunded
    event LiquidityComputationFailed(address indexed user, string reason); // Emitted when liquidity calculation fails

    struct PositionMetadata {
        address token0;
        address token1;
        uint24 fee;
        uint160 lowerSqrtPriceX96;
        uint160 upperSqrtPriceX96;
        int24 lowerTick;
        int24 upperTick;
    }

    constructor(address _positionManager) {
        positionManager = INonfungiblePositionManager(_positionManager);
    }

    /**
    * @dev Creates a liquidity position on Uniswap V3
    * @param pool The Uniswap V3 pool address
    * @param desiredAmount0 The amount of token0 to add
    * @param desiredAmount1 The amount of token1 to add
    * @param positionWidth The width of the liquidity position (defined as per formula)
    * @param slippageTolerance Allowed slippage tolerance percentage
    */
    function createLiquidityPosition(
        address pool,
        uint256 desiredAmount0,
        uint256 desiredAmount1,
        uint256 positionWidth,
        uint256 slippageTolerance
    ) external nonReentrant returns (
        uint256 positionId,
        uint128 liquidityAmount,
        uint256 actualAmount0,
        uint256 actualAmount1
    ) {
        require(positionWidth > 0 && positionWidth < 10000, "Invalid position width");
        require(desiredAmount0 > 0 && desiredAmount1 > 0, "Invalid token amounts");

        PositionMetadata memory data = preparePosition(pool, positionWidth);

        _handleTokenTransfers(data.token0, data.token1, desiredAmount0, desiredAmount1);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: data.token0,
            token1: data.token1,
            fee: data.fee,
            tickLower: data.lowerTick,
            tickUpper: data.upperTick,
            amount0Desired: desiredAmount0,
            amount1Desired: desiredAmount1,
            amount0Min: (desiredAmount0 * (10000 - slippageTolerance)) / 10000,
            amount1Min: (desiredAmount1 * (10000 - slippageTolerance)) / 10000,
            recipient: msg.sender,
            deadline: block.timestamp + 1800
        });

        (positionId, liquidityAmount, actualAmount0, actualAmount1) = positionManager.mint(params);
        require(liquidityAmount > 0, "Insufficient liquidity");

        emit LiquidityPositionCreated(msg.sender, positionId, liquidityAmount, actualAmount0, actualAmount1, data.lowerTick, data.upperTick);

        _refundTokens(data.token0, desiredAmount0, actualAmount0);
        _refundTokens(data.token1, desiredAmount1, actualAmount1);
    }

    /**
     * @dev Computes the tick and price range for liquidity provision.
     * @param pool Address of the Uniswap V3 pool
     * @param positionWidth The width of the liquidity position
     */
    function preparePosition(address pool, uint256 positionWidth) internal view returns (PositionMetadata memory data) {
        IUniswapV3Pool v3Pool = IUniswapV3Pool(pool);

        data.token0 = v3Pool.token0();
        data.token1 = v3Pool.token1();
        data.fee = v3Pool.fee();

        (uint160 currentSqrtPriceX96, int24 currentTick, , , , , ) = v3Pool.slot0();
        require(currentTick >= -MAX_ALLOWED_TICK_DEVIATION && currentTick <= MAX_ALLOWED_TICK_DEVIATION, "Tick deviation is too high");

        (data.lowerSqrtPriceX96, data.upperSqrtPriceX96) = _determinePriceRange(currentSqrtPriceX96, positionWidth);
        data.lowerTick = TickMath.getTickAtSqrtRatio(data.lowerSqrtPriceX96);
        data.upperTick = TickMath.getTickAtSqrtRatio(data.upperSqrtPriceX96);

        int24 tickSpacing = v3Pool.tickSpacing();
        data.lowerTick = _adjustTickToSpacing(data.lowerTick, tickSpacing);
        data.upperTick = _adjustTickToSpacing(data.upperTick, tickSpacing);

        require(data.lowerTick < data.upperTick, "Invalid tick range");
    }

    /**
     * @dev Computes the lower and upper sqrt price boundaries based on the given position width.
     */
    function _determinePriceRange(uint160 currentSqrtPriceX96, uint256 positionWidth) internal pure returns (uint160 lowerSqrtPriceX96, uint160 upperSqrtPriceX96) {
        require(positionWidth > 0, "Invalid position width");

        uint256 currentPrice = uint256(currentSqrtPriceX96) * uint256(currentSqrtPriceX96) >> (96 * 2);

        uint256 lowerPrice = (currentPrice * (10000 - positionWidth)) / 10000;
        uint256 upperPrice = (currentPrice * (10000 + positionWidth)) / 10000;

        lowerSqrtPriceX96 = TickMath.getSqrtRatioAtTick(TickMath.getTickAtSqrtRatio(uint160(lowerPrice)));
        upperSqrtPriceX96 = TickMath.getSqrtRatioAtTick(TickMath.getTickAtSqrtRatio(uint160(upperPrice)));

        require(lowerSqrtPriceX96 < upperSqrtPriceX96, "Invalid price range");
    }

    /**
    * @dev Handles token transfers before liquidity minting
    */
    function _handleTokenTransfers(address token0, address token1, uint256 amount0, uint256 amount1) internal {
        IERC20(token0).transferFrom(msg.sender, address(this), amount0);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1);
        IERC20(token0).approve(address(positionManager), amount0);
        IERC20(token1).approve(address(positionManager), amount1);
    }

    /**
     * @dev Refunds excess tokens to the user if more tokens were transferred than needed.
     */
    function _refundTokens(address token, uint256 desiredAmount, uint256 actualAmount) internal {
        if (actualAmount < desiredAmount) {
            uint256 refundAmount = desiredAmount - actualAmount;
            IERC20(token).transfer(msg.sender, refundAmount);
            emit ExcessTokensReturned(msg.sender, token, refundAmount);
        }
    }

    /**
     * @dev Adjusts the given tick value to be a multiple of the pool's tick spacing.
     * Ensures that the ticks align with the Uniswap V3 pool tick spacing requirement.
     */
    function _adjustTickToSpacing(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 adjustedTick = tick / spacing;
        if (tick < 0 && (tick % spacing != 0)) {
            adjustedTick--;
        }
        return adjustedTick * spacing;
    }
}
