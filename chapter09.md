# Chapter 9: From Localhost to Live: Deployment and Interaction

Moving from development to production requires understanding deployment workflows, network configuration, and interaction patterns. This chapter covers the complete deployment lifecycle from local testing to mainnet deployment.

## Local Development Environment

### Setting Up a Local Test Network

```bash
# Install and run a local polkadot-sdk node with contracts support
cargo install contracts-node --git https://github.com/paritytech/substrate-contracts-node.git

# Start local development node
substrate-contracts-node --dev --tmp

# The node will output connection information:
# Local node identity: 12D3KooW...
# Running JSON-RPC HTTP server: addr=127.0.0.1:9933
# Running JSON-RPC WS server: addr=127.0.0.1:9944
```

### Contract Deployment Process

```bash
# 1. Build the contract
cargo contract build --release

# 2. Deploy (instantiate) the contract
cargo contract instantiate \
    --constructor new \
    --args 1000000 "MyToken" "MTK" 18 \
    --suri //Alice \
    --url ws://127.0.0.1:9944

# 3. Call contract methods
cargo contract call \
    --contract 5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY \
    --message transfer \
    --args 5FHneW46xGXgs5mUiveU4sbTyGBzmstUspZC92UhjJM694ty 1000 \
    --suri //Alice \
    --url ws://127.0.0.1:9944
```

## Using Contracts UI

The Contracts UI provides a graphical interface for contract interaction:

1. **Connect to Network**: Navigate to [contracts-ui.substrate.io](https://contracts-ui.substrate.io/)
2. **Upload Contract**: Upload your `.contract` file
3. **Instantiate**: Deploy with constructor parameters
4. **Interact**: Call messages through the UI

### UI Workflow Example

```markdown
1. Open Contracts UI
2. Connect to ws://127.0.0.1:9944
3. Click "Upload a new contract"
4. Upload mytoken.contract file
5. Click "Deploy" and fill constructor parameters:
   - total_supply: 1000000
   - name: "MyToken"
   - symbol: "MTK"
   - decimals: 18
6. Click "Deploy" and sign transaction
7. Navigate to deployed contract
8. Call "transfer" message with recipient and amount
```

## Production Deployment Considerations

### Network Selection

**Testnet Deployment (Recommended First):**
```bash
# Deploy to a testnet first (example with Rococo Contracts parachain)
cargo contract instantiate \
    --constructor new \
    --args 1000000 "MyToken" "MTK" 18 \
    --suri "your mnemonic phrase here" \
    --url wss://rococo-contracts-rpc.polkadot.io
```

**Mainnet Deployment:**
```bash
# Deploy to mainnet (example)
cargo contract instantiate \
    --constructor new \
    --args 1000000 "MyToken" "MTK" 18 \
    --suri "your secure mnemonic phrase" \
    --url wss://mainnet-contracts-rpc.polkadot.io
```

### Security Checklist for Production

- [ ] Contract audited by security professionals
- [ ] All tests passing (unit, integration, E2E)
- [ ] Gas limits tested and optimized
- [ ] Access controls properly implemented
- [ ] Emergency pause mechanisms in place
- [ ] Upgrade mechanisms tested (if applicable)
- [ ] Event emission verified
- [ ] Cross-contract calls validated

### Deployment Script Example

```bash
#!/bin/bash
# deploy.sh - Production deployment script

set -e

NETWORK=${1:-"testnet"}
CONTRACT_NAME=${2:-"my_token"}

echo "Deploying $CONTRACT_NAME to $NETWORK"

# Build optimized contract
echo "Building contract..."
cargo contract build --release

# Verify build artifacts
if [ ! -f "target/ink/$CONTRACT_NAME.contract" ]; then
    echo "Error: Contract build failed"
    exit 1
fi

# Deploy based on network
case $NETWORK in
    "testnet")
        URL="wss://rococo-contracts-rpc.polkadot.io"
        SURI="//Alice"  # Test account
        ;;
    "mainnet")
        URL="wss://mainnet-contracts-rpc.polkadot.io"
        SURI="$PRODUCTION_SURI"  # Production account from env
        ;;
    *)
        echo "Unknown network: $NETWORK"
        exit 1
        ;;
esac

echo "Deploying to $URL..."

# Deploy contract
CONTRACT_ADDRESS=$(cargo contract instantiate \
    --constructor new \
    --args 1000000 "ProductionToken" "PROD" 18 \
    --suri "$SURI" \
    --url "$URL" \
    --output-json | jq -r '.contract')

echo "Contract deployed at: $CONTRACT_ADDRESS"

# Verify deployment
echo "Verifying deployment..."
cargo contract call \
    --contract "$CONTRACT_ADDRESS" \
    --message total_supply \
    --suri "$SURI" \
    --url "$URL" \
    --dry-run

echo "Deployment successful!"
```

## Contract Interaction Patterns

### CLI Interaction Examples

```bash
# Query contract state (dry run - no gas cost)
cargo contract call \
    --contract $CONTRACT_ADDR \
    --message balance_of \
    --args 5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY \
    --suri //Alice \
    --dry-run

# Execute state-changing transaction
cargo contract call \
    --contract $CONTRACT_ADDR \
    --message transfer \
    --args 5FHneW46xGXgs5mUiveU4sbTyGBzmstUspZC92UhjJM694ty 1000 \
    --suri //Alice \
    --gas-limit 100000000000 \
    --proof-size 1000000
```

### JavaScript/TypeScript Integration

```typescript
// contract-client.ts
import { ApiPromise, WsProvider } from '@polkadot/api';
import { ContractPromise } from '@polkadot/api-contract';
import metadata from './metadata.json';

async function connectToContract() {
    const wsProvider = new WsProvider('ws://127.0.0.1:9944');
    const api = await ApiPromise.create({ provider: wsProvider });
    
    const contractAddress = '5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY';
    const contract = new ContractPromise(api, metadata, contractAddress);
    
    return { api, contract };
}

async function queryBalance(userAddress: string) {
    const { contract } = await connectToContract();
    
    const { result, output } = await contract.query.balanceOf(
        userAddress,
        { gasLimit: -1 },
        userAddress
    );
    
    if (result.isOk) {
        return output?.toHuman();
    }
    throw new Error('Query failed');
}

async function transferTokens(fromKeypair: any, to: string, amount: number) {
    const { api, contract } = await connectToContract();
    
    const tx = contract.tx.transfer(
        { gasLimit: 100000000000 },
        to,
        amount
    );
    
    return new Promise((resolve, reject) => {
        tx.signAndSend(fromKeypair, (result) => {
            if (result.status.isFinalized) {
                resolve(result);
            } else if (result.status.isDropped) {
                reject(new Error('Transaction dropped'));
            }
        });
    });
}
```

## Monitoring and Maintenance

### Event Monitoring

```typescript
// event-monitor.ts
async function monitorTransferEvents() {
    const { api, contract } = await connectToContract();
    
    // Subscribe to contract events
    await api.query.system.events((events) => {
        events.forEach((record) => {
            const { event } = record;
            
            if (api.events.contracts.ContractEmitted.is(event)) {
                const [contractAddress, data] = event.data;
                
                // Decode contract event
                const decodedEvent = contract.abi.decodeEvent(data);
                
                if (decodedEvent.event.identifier === 'Transfer') {
                    console.log('Transfer event:', decodedEvent.args);
                }
            }
        });
    });
}
```

### Health Checks

```bash
#!/bin/bash
# health-check.sh

CONTRACT_ADDR="5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY"
URL="wss://rococo-contracts-rpc.polkadot.io"

# Check if contract is responsive
echo "Checking contract health..."

RESPONSE=$(cargo contract call \
    --contract $CONTRACT_ADDR \
    --message total_supply \
    --suri //Alice \
    --url $URL \
    --dry-run \
    --output-json 2>/dev/null)

if [ $? -eq 0 ]; then
    TOTAL_SUPPLY=$(echo $RESPONSE | jq -r '.data.Ok')
    echo "✅ Contract healthy - Total supply: $TOTAL_SUPPLY"
else
    echo "❌ Contract health check failed"
    exit 1
fi
```

## Summary

Successfully deploying and maintaining ink! contracts in production requires:

**Deployment Pipeline:**
- Local testing with substrate-contracts-node
- Testnet validation before mainnet deployment
- Automated deployment scripts with proper error handling

**Interaction Methods:**
- CLI tools for direct contract interaction
- Web UI for user-friendly management
- JavaScript/TypeScript SDKs for application integration

**Production Readiness:**
- Comprehensive security audits
- Performance optimization and gas testing
- Monitoring and alerting systems
- Emergency response procedures

**Maintenance Operations:**
- Event monitoring for application state tracking
- Health checks for contract availability
- Performance monitoring for gas optimization
- Upgrade procedures for contract evolution

With proper deployment and interaction patterns, your ink! contracts can operate reliably in production environments while providing clear interfaces for users and applications.
