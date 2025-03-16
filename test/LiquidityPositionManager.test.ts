import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { LiquidityPositionManager, MockToken, MockUniswapV3Pool, MockNonfungiblePositionManager } from "../typechain";

describe("LiquidityPositionManager", function () {
    let liquidityManager: LiquidityPositionManager;
    let positionManager: MockNonfungiblePositionManager;
    let mockPool: MockUniswapV3Pool;
    let token0: MockToken;
    let token1: MockToken;
    let owner: SignerWithAddress, user: SignerWithAddress;

    beforeEach(async function () {
        [owner, user] = await ethers.getSigners();

        // Deploy mock token contracts
        const MockToken = await ethers.getContractFactory("MockToken");
        token0 = (await MockToken.deploy("Token0", "TK0")) as MockToken;
        token1 = (await MockToken.deploy("Token1", "TK1")) as MockToken;

        // Deploy a mock Uniswap V3 pool
        const MockPool = await ethers.getContractFactory("MockUniswapV3Pool");
        mockPool = (await MockPool.deploy(token0.address, token1.address, 3000)) as MockUniswapV3Pool;
        
        // Deploy a mock Uniswap V3 position manager
        const MockPositionManager = await ethers.getContractFactory("MockNonfungiblePositionManager");
        positionManager = (await MockPositionManager.deploy()) as MockNonfungiblePositionManager;

        // Deploy the liquidity manager contract
        const LiquidityPositionManager = await ethers.getContractFactory("LiquidityPositionManager");
        liquidityManager = (await LiquidityPositionManager.deploy(positionManager.address)) as LiquidityPositionManager;
    });

    describe("Contract Deployment", function () {
        it("Should correctly set the position manager address", async function () {
            expect(await liquidityManager.positionManager()).to.equal(positionManager.address);
        });
    });

    describe("Liquidity Management Functions", function () {
        it("Should revert if token amounts are zero", async function () {
            await expect(
                liquidityManager.createLiquidityPosition(mockPool.address, 0, 0, 500, 1)
            ).to.be.revertedWith("Invalid token amounts");
        });

        it("Should revert if the width parameter is invalid", async function () {
            await expect(
                liquidityManager.createLiquidityPosition(mockPool.address, 1000, 1000, 0, 1)
            ).to.be.revertedWith("Invalid position width");
        });

        it("Should successfully approve and transfer tokens before adding liquidity", async function () {
            // Mint tokens for the owner
            await token0.mint(owner.address, ethers.utils.parseEther("100"));
            await token1.mint(owner.address, ethers.utils.parseEther("100"));

            // Approve the liquidity manager contract to spend tokens
            await token0.approve(liquidityManager.address, ethers.utils.parseEther("100"));
            await token1.approve(liquidityManager.address, ethers.utils.parseEther("100"));

            // Attempt to create a liquidity position and check for the emitted event
            await expect(
                liquidityManager.createLiquidityPosition(mockPool.address, ethers.utils.parseEther("10"), ethers.utils.parseEther("10"), 500, 1)
            ).to.emit(liquidityManager, "LiquidityPositionCreated");
        });
    });

    describe("Edge Case Handling", function () {
        it("Should correctly adjust tick values to be valid within Uniswap's tick spacing", async function () {
            const tickSpacing: number = 10;
            const rawTick: number = 27;
            const expectedTick: number = Math.floor(rawTick / tickSpacing) * tickSpacing;

            expect(await liquidityManager._adjustTickToSpacing(rawTick, tickSpacing)).to.equal(expectedTick);
        });
    });
});
