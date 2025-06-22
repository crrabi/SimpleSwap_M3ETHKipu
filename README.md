# SimpleSwap: A Uniswap V2-style Automated Market Maker (AMM)

## 📖 Overview

**SimpleSwap** is a smart contract written in Solidity that implements a simple Automated Market Maker (AMM) protocol, similar in principle to Uniswap V2. It allows users to perform three core decentralized finance (DeFi) operations on any pair of ERC20 tokens:

1.  **Provide Liquidity:** Users can deposit a pair of tokens to become Liquidity Providers (LPs) and earn fees.
2.  **Swap Tokens:** Users can trade one ERC20 token for another.
3.  **Remove Liquidity:** LPs can withdraw their share of the token reserves, including any accrued fees.

This project was developed to meet the strict specifications of a `SwapVerifier` contract, which exercises all functions to ensure correctness, security, and adherence to established AMM formulas.

## ✨ Features

The `SimpleSwap` contract exposes a public API with five main functions:

-   `addLiquidity`: Adds liquidity to a token pair pool. In return, the provider receives LP (Liquidity Provider) tokens representing their share.
-   `removeLiquidity`: Burns LP tokens and allows the provider to withdraw their proportional share of the underlying tokens.
-   `swapExactTokensForTokens`: Swaps an exact amount of an input token for a calculated amount of an output token, including a 0.3% fee for liquidity providers.
-   `getAmountOut`: A view function that calculates the amount of output tokens one would receive in a swap, based on the Uniswap V2 formula.
-   `getPrice`: A view function that returns the price of a token in terms of the other, scaled to 18 decimals.

The contract itself is an ERC20 token, representing the LP shares for all liquidity pools managed by it.

## 🛠️ Technologies & Tools

-   **Language:** [Solidity (`^0.8.20`)](https://soliditylang.org/)
-   **Standards:** [ERC20](https://eips.ethereum.org/EIPS/eip-20)
-   **Libraries:** [OpenZeppelin Contracts](https://www.openzeppelin.com/contracts) (for secure ERC20 implementation and Math utilities).
-   **Development Environment:** [Remix IDE](https://remix.ethereum.org/)
-   **AI Development Assistant:** [Google's Large Language Model](https://ai.google/) (for pair programming, debugging, and documentation).

## 🚀 Development Journey & Challenges

The development process was an iterative cycle of coding, testing, and debugging against a pre-existing `SwapVerifier` contract. This approach revealed several common but critical challenges in smart contract development, which were instrumental to the project's learning curve.

#### 1. Battling the EVM: `Stack too deep`
-   **Problem:** The initial implementation of `swapExactTokensForTokens` and `addLiquidity` resulted in a `Stack too deep` compiler error. This is a limitation of the Ethereum Virtual Machine (EVM), which has a maximum stack depth of 1024.
-   **Solution:** The issue was resolved through a two-pronged approach:
    1.  **Code Refactoring:** Functions were refactored to reduce the number of local variables, using scoped blocks (`{...}`) to ensure variables were discarded from the stack as soon as they were no longer needed.
    2.  **Compiler Configuration:** The modern **`viaIR` compilation pipeline** was enabled in the Solidity compiler settings, along with the optimizer. This new pipeline performs more advanced code optimization, which was key to resolving the stack issue.

#### 2. Adhering to Modern Standards: `ERC20InvalidReceiver`
-   **Problem:** The first attempt to add liquidity failed with an `ERC20InvalidReceiver` error. The goal was to lock the `MINIMUM_LIQUIDITY` by minting it to the `address(0)`, a technique used in Uniswap V2.
-   **Solution:** Modern OpenZeppelin ERC20 implementations explicitly forbid minting to the zero address as a safety measure. The code was corrected by removing the `_mint(address(0), ...)` call. The minimum liquidity is now effectively locked by simply not minting it to any user, while still accounting for it in the initial liquidity calculation.

#### 3. Managing Permissions: `ERC20InsufficientAllowance`
-   **Problem:** The `removeLiquidity` function failed because it attempted to use `transferFrom` to pull LP tokens from the user to the contract before burning them, but the user (the `SwapVerifier`) had not approved this transfer.
-   **Solution:** The logic was corrected to use `_burn(msg.sender, liquidity)` directly. This function burns tokens from the caller's balance without requiring a separate `approve` step, which is the standard and more gas-efficient pattern for this operation.

#### 4. The Final Boss: `ERC20InsufficientBalance`
-   **Problem:** The final and most subtle bug was an `ERC20InsufficientBalance` error during a swap, indicating that the contract's internal accounting of reserves had desynchronized from its actual token balance.
-   **Solution:** Investigation revealed that our `getAmountOut` formula was a simple constant product formula (`x * y = k`). The `SwapVerifier`, however, expected the **Uniswap V2 formula**, which includes a **0.3% fee** for liquidity providers. By implementing the correct fee-based formula (`amountOut = (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee)`), the contract's calculations perfectly aligned with the verifier's expectations, and all tests passed successfully.

## ✅ How to Test

This contract is designed to be verified by the provided `SwapVerifier.sol`. To run the tests in a development environment like Remix:

1.  **Deploy Contracts:**
    -   Deploy two instances of a test ERC20 token (e.g., `TestToken.sol`).
    -   Deploy the `SimpleSwap.sol` contract.
    -   Deploy the `SwapVerifier.sol` contract.

2.  **Fund the Verifier:**
    -   Mint a substantial amount of both test tokens and send them directly to the deployed `SwapVerifier` contract's address.

3.  **Run Verification:**
    -   Call the `verify()` function on the deployed `SwapVerifier`.
    -   Provide the addresses of `SimpleSwap`, `TestToken A`, and `TestToken B`, along with initial liquidity amounts and a swap amount.
    -   A successful transaction indicates that `SimpleSwap` has passed all verification checks.
