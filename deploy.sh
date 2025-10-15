#!/bin/bash

# Deployment script for DigitalWillFactory
# Usage: ./deploy.sh [network]
# Networks: sepolia, base-sepolia, optimism-sepolia, arbitrum-sepolia

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please create a .env file based on .env.example"
    exit 1
fi

# Load environment variables
source .env

# Check if private key is set
if [ -z "$PRIVATE_KEY" ] || [ "$PRIVATE_KEY" = "your_private_key_here" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set in .env file${NC}"
    exit 1
fi

# Get network from argument or default to sepolia
NETWORK=${1:-sepolia}

echo -e "${GREEN}Deploying DigitalWillFactory to $NETWORK...${NC}\n"

case $NETWORK in
    sepolia)
        if [ -z "$SEPOLIA_RPC_URL" ]; then
            echo -e "${RED}Error: SEPOLIA_RPC_URL not set in .env${NC}"
            exit 1
        fi
        forge script script/Deploy.s.sol:DeployScript \
            --rpc-url $SEPOLIA_RPC_URL \
            --broadcast \
            --verify \
            --etherscan-api-key $ETHERSCAN_API_KEY \
            -vvvv
        ;;
    
    base-sepolia)
        if [ -z "$BASE_SEPOLIA_RPC_URL" ]; then
            echo -e "${YELLOW}Warning: BASE_SEPOLIA_RPC_URL not set, using default${NC}"
            BASE_SEPOLIA_RPC_URL="https://sepolia.base.org"
        fi
        forge script script/Deploy.s.sol:DeployScript \
            --rpc-url $BASE_SEPOLIA_RPC_URL \
            --broadcast \
            --verify \
            --verifier-url https://api-sepolia.basescan.org/api \
            --etherscan-api-key $ETHERSCAN_API_KEY \
            -vvvv
        ;;
    
    optimism-sepolia)
        if [ -z "$OPTIMISM_SEPOLIA_RPC_URL" ]; then
            echo -e "${YELLOW}Warning: OPTIMISM_SEPOLIA_RPC_URL not set, using default${NC}"
            OPTIMISM_SEPOLIA_RPC_URL="https://sepolia.optimism.io"
        fi
        forge script script/Deploy.s.sol:DeployScript \
            --rpc-url $OPTIMISM_SEPOLIA_RPC_URL \
            --broadcast \
            -vvvv
        ;;
    
    arbitrum-sepolia)
        if [ -z "$ARBITRUM_SEPOLIA_RPC_URL" ]; then
            echo -e "${YELLOW}Warning: ARBITRUM_SEPOLIA_RPC_URL not set, using default${NC}"
            ARBITRUM_SEPOLIA_RPC_URL="https://sepolia.arbitrum.io/rpc"
        fi
        forge script script/Deploy.s.sol:DeployScript \
            --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
            --broadcast \
            -vvvv
        ;;
    
    *)
        echo -e "${RED}Error: Unknown network '$NETWORK'${NC}"
        echo "Available networks: sepolia, base-sepolia, optimism-sepolia, arbitrum-sepolia"
        exit 1
        ;;
esac

echo -e "\n${GREEN}Deployment complete!${NC}"
echo -e "${YELLOW}Don't forget to update the contract address in hera-ui/src/lib/contract.ts${NC}"

