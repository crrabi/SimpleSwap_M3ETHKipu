// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import the IERC20 interface to interact with other tokens.
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC20/IERC20.sol";

/**
 * @title SimpleSwap
 * @author crrabi + AI Development Assistant
 * @notice A simple Automated Market Maker (AMM) contract for swapping ERC20 tokens, providing liquidity, and querying prices.
 */
contract SimpleSwap {
    // --- State ---
    // @dev Mapping from a pair's unique ID to the total supply of its Liquidity Pool (LP) tokens.
    mapping(bytes32 => uint256) public totalSupply;
    // @dev Mapping from a pair's unique ID to a user's address to their balance of LP tokens.
    mapping(bytes32 => mapping(address => uint256)) public balanceOf;
    // @dev Stores the reserve of the first token (sorted by address) for each pair. Packed into a single slot with _reserve1 for gas efficiency.
    mapping(bytes32 => uint112) private _reserve0;
    // @dev Stores the reserve of the second token (sorted by address) for each pair. Packed into a single slot with _reserve0 for gas efficiency.
    mapping(bytes32 => uint112) private _reserve1;

    // --- Modifier ---
    /**
     * @dev Ensures that the transaction is executed before the specified deadline.
     * @param deadline The timestamp after which the transaction should be reverted.
     */
    modifier checkDeadline(uint deadline) {
        require(deadline >= block.timestamp, "EXPIRED");
        _;
    }

    // --- Internal Helpers ---
    /**
     * @dev Sorts two token addresses to ensure a deterministic order for pair identification.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return token0 The token with the lexicographically smaller address.
     * @return token1 The token with the lexicographically larger address.
     */
    function _sortTokens(address tokenA, address tokenB) private pure returns (address token0, address token1) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
    }
    /**
     * @dev Calculates a unique and deterministic pair identifier from two token addresses.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return pairId The unique bytes32 identifier for the token pair.
     */
    function _getPairId(address tokenA, address tokenB) private pure returns (bytes32 pairId) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pairId = keccak256(abi.encodePacked(token0, token1));
    }
    /**
     * @dev Updates the reserve balances for a given pair by reading the contract's current token balances.
     * This is safer than manual tracking as it reflects the true state.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @param pairId The unique identifier of the pair being updated.
     */
    function _update(address tokenA, address tokenB, bytes32 pairId) private {
        // Sort tokens to fetch balances in the canonical order (_reserve0, _reserve1).
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        //checks that `balance0` and `balance1` do not exceed the maximum value storable by a `uint112` (2^112 - 1).
        // If either balance exceeds this limit, the transaction will revert with the message "OVERFLOW".
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "OVERFLOW");
        _reserve0[pairId] = uint112(balance0);
        _reserve1[pairId] = uint112(balance1);
    }
    /**
    *@dev Increases the total supply of LP tokens for the given `pairId`
    *and assigns the `liquidity` amount to the `to` address.
    *@param to The address to which the new liquidity tokens will be minted.
    *@param liquidity The amount of liquidity tokens to mint.
    *@param pairId The unique ID of the liquidity pair these tokens belong to.
    */
    function _mint(address to, uint256 liquidity, bytes32 pairId) private {
        totalSupply[pairId] += liquidity;
        balanceOf[pairId][to] += liquidity;
    }
    /** 
    *@dev Decreases the `liquidity` amount from the `from` address's balance
    *and subsequently reduces the total supply of LP tokens for the given `pairId`.
    *@param from The address from which the liquidity tokens will be burned.
    *@param liquidity The amount of liquidity tokens to burn.
    *@param pairId The unique ID of the liquidity pair these tokens belong to.
    */
    function _burn(address from, uint256 liquidity, bytes32 pairId) private {
        balanceOf[pairId][from] -= liquidity;
        totalSupply[pairId] -= liquidity;
    }
    
    /**
     * @dev Calculates the square root of a number using the Babylonian method.
     * This is the exact, battle-tested implementation from Uniswap V2.
     * @param y The number to calculate the square root of.
     * @return z The integer square root of y.
     */
    function _sqrt(uint y) private pure returns (uint z) {
        if (y == 0) return 0;
        uint x = y / 2 + 1; // start with a reasonable guess
        unchecked {
            while (true) {
                uint x2 = (x + y / x) / 2;
                if (x2 == x) {
                    return x;
                }
                x = x2;
            }
        }
    }
    
    // --- Public Functions ---
    /**
     * @notice Retrieves the current liquidity reserves for a given token pair.
     * @dev The order of the returned reserves matches the order of the token addresses provided as input.
     * @param tokenA The address of the first token in the pair.
     * @param tokenB The address of the second token in the pair.
     * @return reserveA The total amount of tokenA held in the pool's reserves.
     * @return reserveB The total amount of tokenB held in the pool's reserves.
     */
    function getReserves(address tokenA, address tokenB) public view returns (uint256 reserveA, uint256 reserveB) {
        // Internally, reserves are stored based on sorted token addresses (token0, token1).
        (address token0, ) = _sortTokens(tokenA, tokenB);
        bytes32 pairId = _getPairId(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1) = (_reserve0[pairId], _reserve1[pairId]);
        // Re-order the reserves to match the user's input order for a consistent and predictable return value.
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }
    /**
     * @notice Adds liquidity to an ERC20-ERC20 token pair pool.
     * @dev If the pool is new, the deposited amounts set the initial price. Otherwise, tokens must be deposited
     * at the current pool ratio. The function uses local scopes `{...}` to prevent "Stack Too Deep" errors.
     * @param tokenA Address of one of the tokens in the pair.
     * @param tokenB Address of the other token in the pair.
     * @param amountADesired The amount of tokenA the user wants to deposit.
     * @param amountBDesired The amount of tokenB the user wants to deposit.
     * @param amountAMin The minimum amount of tokenA to deposit (for slippage protection).
     * @param amountBMin The minimum amount of tokenB to deposit (for slippage protection).
     * @param to The address that will receive the Liquidity Pool (LP) tokens.
     * @param deadline The timestamp by which this transaction must be executed.
     * @return amountA The actual amount of tokenA deposited.
     * @return amountB The actual amount of tokenB deposited.
     * @return liquidity The amount of LP tokens minted to the user.
     */
    function addLiquidity(
        address tokenA, address tokenB, uint amountADesired, uint amountBDesired,
        uint amountAMin, uint amountBMin, address to, uint deadline
    ) external checkDeadline(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        // --- Calculation Scope to manage stack ---
        {
            (uint reserveA, uint reserveB) = getReserves(tokenA, tokenB);
            if (reserveA == 0 && reserveB == 0) {
                // If the pool is empty, the first liquidity provider sets the initial price.
                (amountA, amountB) = (amountADesired, amountBDesired);
            } else {
                 // For existing pools, calculate the optimal deposit amounts to maintain the price ratio.
                uint amountBOptimal = (amountADesired * reserveB) / reserveA;
                if (amountBOptimal <= amountBDesired) {
                    // If the optimal B amount is within the user's desired limit, use it.
                    require(amountBOptimal >= amountBMin, "INSUFFICIENT_B_AMOUNT");
                    (amountA, amountB) = (amountADesired, amountBOptimal);
                } else {
                    // Otherwise, calculate the optimal A amount based on the desired B amount.
                    uint amountAOptimal = (amountBDesired * reserveA) / reserveB;
                    require(amountAOptimal >= amountAMin, "INSUFFICIENT_A_AMOUNT");
                    (amountA, amountB) = (amountAOptimal, amountBDesired);
                }
            }
        } // --- End of scope. `reserveA`, `reserveB`, `amountBOptimal`, etc. are now cleared from the stack. ---
        // After calculations are complete, transfer the exact amounts from the user to this contract.
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        
        bytes32 pairId = _getPairId(tokenA, tokenB);
        // --- Minting Scope: another local scope for stack management. ---
        {
            (uint reserveA, uint reserveB) = getReserves(tokenA, tokenB);
            uint _totalSupply = totalSupply[pairId];
            if (_totalSupply == 0) {
                // For the very first liquidity provider, LP tokens are calculated as the geometric mean.
                liquidity = _sqrt(amountA * amountB);
            } else {
                // For subsequent providers, liquidity is minted proportionally to the existing total supply.
                // calculate based on both tokens and take the minimum to be fair to the user.
                uint liquidityA = (amountA * _totalSupply) / reserveA;
                uint liquidityB = (amountB * _totalSupply) / reserveB;
                liquidity = liquidityA < liquidityB ? liquidityA : liquidityB;
            }
        }
        
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        // Mint the new LP tokens to the recipient.
        _mint(to, liquidity, pairId);
         // Update the contract's stored reserves to reflect the new state.
        _update(tokenA, tokenB, pairId);
    }
    /**
     * @notice Removes liquidity from a pool by burning LP tokens.
     * @dev The user receives underlying tokens proportional to their share of the pool.
     * @param tokenA Address of one of the tokens in the pair.
     * @param tokenB Address of the other token in the pair.
     * @param liquidity The amount of LP tokens to burn.
     * @param amountAMin The minimum amount of tokenA to receive (slippage protection).
     * @param amountBMin The minimum amount of tokenB to receive (slippage protection).
     * @param to The address that will receive the withdrawn tokens.
     * @param deadline The timestamp by which this transaction must be executed.
     * @return amountA The actual amount of tokenA withdrawn.
     * @return amountB The actual amount of tokenB withdrawn.
     */
    function removeLiquidity(
        address tokenA, address tokenB, uint256 liquidity, uint256 amountAMin,
        uint256 amountBMin, address to, uint256 deadline
    ) external checkDeadline(deadline) returns (uint256 amountA, uint256 amountB) {
        bytes32 pairId = _getPairId(tokenA, tokenB);
        // Ensure the user has enough LP tokens to burn.
        require(balanceOf[pairId][msg.sender] >= liquidity, "INSUFFICIENT_LIQUIDITY");
        // --- Calculation Scope to manage stack ---
        {
            (uint reserveA, uint reserveB) = getReserves(tokenA, tokenB);
            uint256 poolTotalSupply = totalSupply[pairId];
            // The amount of each token returned is proportional to the user's share of the pool.
            amountA = (liquidity * reserveA) / poolTotalSupply;
            amountB = (liquidity * reserveB) / poolTotalSupply;
        }   // `reserveA`, `reserveB`, and `poolTotalSupply` are cleared from the stack here.

        // Check for slippage: ensure the user receives at least the minimum amounts they specified.
        require(amountA >= amountAMin, "INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "INSUFFICIENT_B_AMOUNT");

        // Burn the user's LP tokens.
        _burn(msg.sender, liquidity, pairId);
        // Send them the corresponding underlying tokens.
        IERC20(tokenA).transfer(to, amountA);
        IERC20(tokenB).transfer(to, amountB);
        // Update the reserves to reflect the withdrawal.
        _update(tokenA, tokenB, pairId);
    }
    /**
     * @notice Swaps an exact amount of an input token for as much as possible of an output token.
     * @dev This implementation only supports direct swaps (a path of two tokens).
     * @param amountIn The exact amount of input tokens to be swapped.
     * @param amountOutMin The minimum amount of output tokens the user will accept (slippage protection).
     * @param path An array of token addresses. Must be [inputToken, outputToken].
     * @param to The address that will receive the output tokens.
     * @param deadline The timestamp by which this transaction must be executed.
     */
    function swapExactTokensForTokens(
        uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline
    ) external checkDeadline(deadline) {
        // This simple implementation only allows direct A-to-B swaps.
        require(path.length == 2, "INVALID_PATH");

        uint amountOut;
        // --- Calculation scope for stack management ---
        {
            (uint reserveIn, uint reserveOut) = getReserves(path[0], path[1]);
            // Calculate the output amount using the standard constant product formula.
            amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
        }
        
        // Slippage check: ensure the output amount is not less than the minimum acceptable amount.
        require(amountOut >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        
        // Perform the token swap.
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[1]).transfer(to, amountOut);
        
        // Get the pair ID and update the reserves after the swap is complete.
        bytes32 pairId = _getPairId(path[0], path[1]);
        _update(path[0], path[1], pairId);
    }
     /**
     * @notice Returns the spot price of tokenA in terms of tokenB, based on the reserve ratio.
     * @param tokenA The address of the base token.
     * @param tokenB The address of the quote token.
     * @return price The amount of tokenB required to buy one unit of tokenA (scaled by 1e18 for precision).
     */
    function getPrice(address tokenA, address tokenB) external view returns (uint256 price) {
        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB);
        // The pool must have liquidity for both tokens to have a valid price.
        require(reserveA > 0 && reserveB > 0, "INSUFFICIENT_LIQUIDITY");
        // Price is simply the ratio of reserves, scaled up by 1e18 to handle decimals.
        return (reserveB * 1e18) / reserveA;
    }
    /**
     * @notice Calculates how many output tokens will be received for a given input amount.
     * @dev This is a pure function for off-chain or on-chain quoting. It does not perform a swap.
     * @param amountIn The amount of the input token.
     * @param reserveIn The liquidity reserve of the input token.
     * @param reserveOut The liquidity reserve of the output token.
     * @return amountOut The calculated amount of the output token to be received.
     */
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256 amountOut) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        // Returns the calculated output based on the constant product formula.
        return (amountIn * reserveOut) / (reserveIn + amountIn);
    }
}
