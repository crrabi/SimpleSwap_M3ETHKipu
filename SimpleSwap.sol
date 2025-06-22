// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// =================================================================
//                           IMPORTS
// =================================================================

// import the ERC20 standard implementation from OpenZeppelin.
// SimpleSwap contract will BE an ERC20 token itself, representing liquidity pool shares.
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC20/ERC20.sol";
// import the IERC20 interface to interact with other tokens.
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC20/IERC20.sol";
// For the square root calculation needed when minting initial liquidity.
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/utils/math/Math.sol";


/**
 * @title SimpleSwap
 * @author crrabi+AIGoogleStudio
 * @notice A simple Automated Market Maker (AMM) for swapping ERC20 tokens.
 * This contract adheres to the requirements of the provided SwapVerifier.
 * It also acts as an ERC20 token for liquidity provider (LP) shares.
 */
contract SimpleSwap is ERC20 {

    // =================================================================
    //                           STATE VARIABLES
    // =================================================================

    /**
     * @notice Stores the reserves for each token pair.
     * The structure is a nested mapping: mapping(address => mapping(address => uint256))
     * To avoid ambiguity and duplication, enforce an order (token0 address < token1 address).
     */
    mapping(address => mapping(address => uint256)) private _reserves;

    // A small amount of liquidity is locked forever to increase the cost of initial pool manipulation.
    uint256 public constant MINIMUM_LIQUIDITY = 1000;


    // =================================================================
    //                             CONSTRUCTOR
    // =================================================================

    /**
     * @notice Initializes the contract, setting the name and symbol for the LP token.
     * The ERC20 constructor takes the token name and symbol as arguments.
     */
    constructor() ERC20("SimpleSwap LP Token", "SSLP") {}


    // =================================================================
    //                       PRIVATE/INTERNAL HELPERS
    // =================================================================

    /**
     * @notice Sorts token addresses to ensure a unique pair identifier.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return token0 The token with the lower address.
     * @return token1 The token with the higher address.
     */
    function _sortTokens(address tokenA, address tokenB) private pure returns (address token0, address token1) {
        require(tokenA != tokenB, "SimpleSwap: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }
    
    /**
     * @notice A private function to safely update the reserves.
     * @param token0 The address of the first token (sorted).
     * @param token1 The address of the second token (sorted).
     * @param reserve0 The new reserve amount for token0.
     * @param reserve1 The new reserve amount for token1.
     */
    function _updateReserves(address token0, address token1, uint256 reserve0, uint256 reserve1) private {
        _reserves[token0][token1] = reserve0;
        _reserves[token1][token0] = reserve1;
    }


    // =================================================================
    //                           VIEW/PURE FUNCTIONS
    // =================================================================
    
    /**
     * @notice Gets the reserves for a given pair.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return reserveA The reserve corresponding to tokenA.
     * @return reserveB The reserve corresponding to tokenB.
     */
    function getReserves(address tokenA, address tokenB) public view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = _sortTokens(tokenA, tokenB);
        if (tokenA == token0) {
        reserveA = _reserves[tokenA][tokenB];
        reserveB = _reserves[tokenB][tokenA];
        } else {
        reserveA = _reserves[tokenB][tokenA];
        reserveB = _reserves[tokenA][tokenB];
        }
    }

    /**
     * @notice Given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset.
     */
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");

        // Uniswap V2 formula with 0.3% fee
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /**
     * @notice Returns the price of tokenA in terms of tokenB, scaled by 1e18.
     */
    function getPrice(address tokenA, address tokenB) public view returns (uint256 price) {
        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB);
        require(reserveA > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_A");
        price = (reserveB * 1e18) / reserveA;
    }


    // =================================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =================================================================

    /**
     * @notice Adds liquidity to an ERC-20 to ERC-20 pair.
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(deadline >= block.timestamp, "SimpleSwap: EXPIRED");

        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB);

        // Scope for amount calculation to free up stack space
        {
        if (reserveA == 0 && reserveB == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
            } else {
                uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
                if (amountBOptimal <= amountBDesired) {
                    require(amountBOptimal >= amountBMin, "SimpleSwap: INSUFFICIENT_B_AMOUNT");
                    amountA = amountADesired;
                    amountB = amountBOptimal;
                    } else {
                    uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
                    require(amountAOptimal <= amountADesired && amountAOptimal >= amountAMin, "SimpleSwap: INSUFFICIENT_A_AMOUNT");
                    amountA = amountAOptimal;
                    amountB = amountBDesired;
                    }
                }
        }

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        // Scope for liquidity calculation
        {
        uint256 totalLPSupply = totalSupply();
        if (totalLPSupply == 0) {
            // Calculate the initial liquidity.
            liquidity = Math.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            } else {
                liquidity = Math.min((amountA * totalLPSupply) / reserveA, (amountB * totalLPSupply) / reserveB);
                }
        }
    
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_MINTED");
    
        // Mint the calculated liquidity to the recipient.
        _mint(to, liquidity);

        // Update reserves after minting.
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        _updateReserves(token0, token1, reserveA + amountA, reserveB + amountB);
    }

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        require(deadline >= block.timestamp, "SimpleSwap: EXPIRED");
        require(path.length == 2, "SimpleSwap: INVALID_PATH");

        address tokenIn = path[0];
        address tokenOut = path[1];
    
        uint256 amountOut;
        // Scope for reserves and amountOut calculation
        {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(tokenIn, tokenOut);
            amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
            require(amountOut >= amountOutMin, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");
        }

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    
        // Scope for reserve update
        {
            (uint256 reserveInAfter, uint256 reserveOutAfter) = getReserves(tokenIn, tokenOut);
            (address token0, address token1) = _sortTokens(tokenIn, tokenOut);
            if (tokenIn == token0) {
                _updateReserves(token0, token1, reserveInAfter + amountIn, reserveOutAfter - amountOut);
                } else {
                _updateReserves(token0, token1, reserveOutAfter - amountOut, reserveInAfter + amountIn);
                }
        }

        IERC20(tokenOut).transfer(to, amountOut);
    }

    /**
     * @notice Removes liquidity from a pair, burning LP tokens in the process.
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        require(deadline >= block.timestamp, "SimpleSwap: EXPIRED");

        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB);
    
        // We need the total supply BEFORE burning the tokens.
        uint256 totalLPSupply = totalSupply();

        // Calculate the amount of underlying tokens to return.
        amountA = (liquidity * reserveA) / totalLPSupply;
        amountB = (liquidity * reserveB) / totalLPSupply;

        require(amountA >= amountAMin, "SimpleSwap: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "SimpleSwap: INSUFFICIENT_B_AMOUNT");
    
        // Burn the LP tokens directly from the message sender's balance.
        // This is the correct way and does not require a prior approval/transferFrom.
        _burn(msg.sender, liquidity);

        // Update the reserves.
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        _updateReserves(token0, token1, reserveA - amountA, reserveB - amountB);

        // Send the underlying tokens to the recipient.
        IERC20(tokenA).transfer(to, amountA);
        IERC20(tokenB).transfer(to, amountB);
    }
}