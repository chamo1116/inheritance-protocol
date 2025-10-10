# Inheritance Protocol - Digital Will Smart Contract

## The Problem

When someone passes away, accessing their digital assets (cryptocurrency, NFTs) can be a nightmare for heirs. Private keys are lost, and the legal process to gain access is slow, expensive, and often unaware of these assets. Traditional estate planning doesn't account for blockchain-based wealth.

## The Solution

The **Inheritance Protocol** provides a trustless, automated solution for transferring digital assets to designated beneficiaries after a period of inactivity. Using smart contracts, your crypto assets can be seamlessly passed on to your heirs without lawyers, probate courts, or lost keys.

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)

---

## Overview

The Inheritance Protocol implements a "dead man's switch" mechanism through the **DigitalWill** smart contract. Asset owners (Grantors) can deposit various digital assets, designate beneficiaries, and set up an automated transfer system that activates only if they fail to check in regularly.

### Why Blockchain for Digital Inheritance?

**Trustless Automation**

- No lawyers, executors, or third parties required
- Smart contracts execute exactly as programmed
- Eliminates human error and manipulation

**Multi-Asset Support**

- ETH (native cryptocurrency)
- ERC-20 tokens (USDC, DAI, etc.)
- NFTs (ERC-721 and ERC-1155)
- All in one unified contract

**Privacy & Control**

- Your beneficiaries remain private until execution
- You maintain full control while active
- No public probate process

**Instant Execution**

- Assets transfer immediately when conditions are met
- No waiting periods or lengthy legal processes
- Global accessibility 24/7

---

## How It Works

### 1. **Setup**

A user (the "Grantor") deploys the **DigitalWill** smart contract to the blockchain. This contract becomes their personal digital will.

### 2. **Designate Assets & Heirs**

The Grantor:

- Deposits specific assets into the contract:
  - **ETH** (Ether)
  - **ERC-20 tokens** (stablecoins, governance tokens, etc.)
  - **NFTs** (ERC-721 collectibles, domain names, etc.)
- Specifies beneficiary wallet addresses for each asset
- Sets allocation percentages or specific amounts per beneficiary

### 3. **Set the "Heartbeat"**

The Grantor sets a time limit (e.g., **90 days**). This is the "heartbeat" period:

- The Grantor must call the `checkIn()` function within each 90-day period
- Each successful check-in resets the countdown
- This proves the Grantor is still active and in control

### 4. **Automatic Execution**

If the Grantor fails to check in after the time limit expires:

- The contract becomes **"claimable"**
- Any designated beneficiary can trigger a claim function
- Assets are **instantly and automatically** transferred to their allocated beneficiaries
- No further action required from any third party
