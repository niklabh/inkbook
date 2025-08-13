# Appendix: Cheatsheets and Further Resources

This appendix provides quick reference materials for ink! development, including command cheatsheets, common patterns, and resources for continued learning.

## cargo contract Cheatsheet

### Project Management
```bash
# Create new ink! project
cargo contract new <contract_name>

# Build contract
cargo contract build [--release]

# Check contract without building
cargo contract check

# Generate contract documentation
cargo doc --open
```

### Deployment and Interaction
```bash
# Deploy contract to network
cargo contract instantiate \
    --constructor <constructor_name> \
    --args <arg1> <arg2> ... \
    --suri <signer> \
    --url <endpoint> \
    [--value <amount>] \
    [--gas-limit <limit>] \
    [--salt <salt>]

# Call contract message
cargo contract call \
    --contract <address> \
    --message <message_name> \
    --args <arg1> <arg2> ... \
    --suri <signer> \
    --url <endpoint> \
    [--value <amount>] \
    [--gas-limit <limit>] \
    [--dry-run]

# Upload contract code (without instantiation)
cargo contract upload \
    --suri <signer> \
    --url <endpoint>

# Remove contract from chain
cargo contract remove \
    --contract <address> \
    --suri <signer> \
    --url <endpoint>
```

### Information and Verification
```bash
# Get contract info
cargo contract info <contract_file.contract>

# Verify contract on chain
cargo contract verify \
    --contract <address> \
    --url <endpoint>

# Download contract metadata
cargo contract download \
    --contract <address> \
    --url <endpoint>
```

## self.env() Reference

### Account Information
```rust
// Get the caller of current message
let caller: AccountId = self.env().caller();

// Get this contract's account ID
let contract_id: AccountId = self.env().account_id();

// Get contract's current balance
let balance: Balance = self.env().balance();

// Get transferred value (for payable messages)
let value: Balance = self.env().transferred_value();
```

### Block Information
```rust
// Get current block number
let block_number: u32 = self.env().block_number();

// Get current block timestamp (milliseconds since Unix epoch)
let timestamp: u64 = self.env().block_timestamp();
```

### Transaction Operations
```rust
// Transfer native tokens
self.env().transfer(recipient, amount)?;

// Emit contract event
self.env().emit_event(MyEvent { field: value });

// Terminate contract and transfer remaining balance
self.env().terminate_contract(beneficiary);
```

### Gas and Weight
```rust
// Get remaining gas
let gas_left = self.env().gas_left();

// Get weight limit
let weight_limit = self.env().weight_to_fee(weight);
```

## Common Patterns Quick Reference

### Storage Patterns
```rust
// Basic storage with Mapping
#[ink(storage)]
pub struct MyContract {
    value: u32,
    balances: Mapping<AccountId, Balance>,
    data: Lazy<LargeStruct>,
}

// Access patterns
let balance = self.balances.get(account).unwrap_or(0);
self.balances.insert(account, &new_balance);
self.balances.remove(account);
```

### Error Handling
```rust
// Define custom errors
#[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
#[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
pub enum Error {
    InsufficientBalance,
    Unauthorized,
    InvalidInput,
}

// Use in messages
#[ink(message)]
pub fn transfer(&mut self, to: AccountId, amount: Balance) -> Result<(), Error> {
    // Safe arithmetic
    let new_balance = self.balance
        .checked_sub(amount)
        .ok_or(Error::InsufficientBalance)?;
    
    // Update state
    self.balance = new_balance;
    Ok(())
}
```

### Event Patterns
```rust
// Define events with topics
#[ink(event)]
pub struct Transfer {
    #[ink(topic)]
    from: Option<AccountId>,
    #[ink(topic)]
    to: Option<AccountId>,
    value: Balance,
}

// Emit events
self.env().emit_event(Transfer {
    from: Some(caller),
    to: Some(recipient),
    value: amount,
});
```

### Access Control
```rust
// Owner-only modifier pattern
fn ensure_owner(&self) -> Result<(), Error> {
    if self.env().caller() != self.owner {
        return Err(Error::Unauthorized);
    }
    Ok(())
}

// Role-based access control
fn has_role(&self, role: Role, account: AccountId) -> bool {
    self.roles.get((role, account)).is_some()
}
```

### Cross-Contract Calls
```rust
// Define interface
#[ink::trait_definition]
pub trait MyInterface {
    #[ink(message)]
    fn external_method(&self, param: u32) -> Result<u32, Error>;
}

// Call external contract
let external: ink::contract_ref!(MyInterface) = external_address.into();
let result = external.external_method(value)?;
```

## Testing Patterns

### Unit Test Setup
```rust
#[cfg(test)]
mod tests {
    use super::*;
    use ink::env::test;

    fn default_accounts() -> ink::env::test::DefaultAccounts<ink::env::DefaultEnvironment> {
        ink::env::test::default_accounts::<ink::env::DefaultEnvironment>()
    }

    fn setup_contract() -> MyContract {
        let accounts = default_accounts();
        test::set_caller::<ink::env::DefaultEnvironment>(accounts.alice);
        MyContract::new()
    }

    #[ink::test]
    fn test_name() {
        let mut contract = setup_contract();
        // Test logic here
        assert_eq!(contract.get_value(), expected_value);
    }
}
```

### E2E Test Setup
```rust
#[cfg(all(test, feature = "e2e-tests"))]
mod e2e_tests {
    use super::*;
    use ink_e2e::build_message;

    type E2EResult<T> = std::result::Result<T, Box<dyn std::error::Error>>;

    #[ink_e2e::test]
    async fn e2e_test(mut client: ink_e2e::Client<C, E>) -> E2EResult<()> {
        // Deploy contract
        let constructor = MyContractRef::new();
        let contract_account_id = client
            .instantiate("my_contract", &ink_e2e::alice(), constructor, 0, None)
            .await
            .expect("instantiate failed")
            .account_id;

        // Call message
        let message = build_message::<MyContractRef>(contract_account_id.clone())
            .call(|contract| contract.my_message());
        let result = client.call(&ink_e2e::alice(), message, 0, None).await;
        
        assert!(result.is_ok());
        Ok(())
    }
}
```

## Build Configuration

### Cargo.toml Template
```toml
[package]
name = "my_contract"
version = "0.1.0"
authors = ["Your Name <your.email@example.com>"]
edition = "2021"

[dependencies]
ink = { version = "4.3", default-features = false }
scale = { package = "parity-scale-codec", version = "3", default-features = false, features = ["derive"] }
scale-info = { version = "2.6", default-features = false, features = ["derive"], optional = true }

[dev-dependencies]
ink_e2e = "4.3"

[lib]
path = "lib.rs"

[features]
default = ["std"]
std = [
    "ink/std",
    "scale/std",
    "scale-info/std",
]
ink-as-dependency = []
e2e-tests = []

[profile.release]
overflow-checks = false
lto = true
codegen-units = 1
panic = "abort"
```

### Optimization Settings
```toml
# .cargo/config.toml
[build]
target = "wasm32-unknown-unknown"

[target.wasm32-unknown-unknown]
rustflags = [
  "-C", "link-arg=-z",
  "-C", "link-arg=stack-size=65536",
  "-C", "link-arg=--import-memory",
  "-C", "target-feature=+bulk-memory",
]
```

## Network Endpoints

### Testnet Endpoints
```bash
# Rococo Contracts Parachain (Testnet)
wss://rococo-contracts-rpc.polkadot.io

# Local Development Node
ws://127.0.0.1:9944
```

### Development Tools
```bash
# Install local contracts node
cargo install contracts-node --git https://github.com/paritytech/substrate-contracts-node.git

# Start local node
substrate-contracts-node --dev --tmp

# Contracts UI
https://ui.use.ink/
```

## Common Error Solutions

### Compilation Errors
```bash
# Error: "could not find `Cargo.toml`"
# Solution: Run commands from project root directory

# Error: "target `wasm32-unknown-unknown` not found"
# Solution: Add WebAssembly target
rustup target add wasm32-unknown-unknown

# Error: "cargo-contract not found"
# Solution: Install cargo-contract
cargo install cargo-contract --force
```

### Runtime Errors
```bash
# Error: "Module not found"
# Solution: Check contract address and network

# Error: "Insufficient gas"
# Solution: Increase gas limit
--gas-limit 100000000000

# Error: "Insufficient balance"
# Solution: Fund account or reduce transfer amount
```

## Further Resources

### Official Documentation
- [ink! Documentation](https://use.ink/)
- [polkadot-sdk Documentation](https://docs.polkadot.com/)

### Community Resources
- [polkadot-sdk Stack Exchange](https://substrate.stackexchange.com/)
- [GitHub Repository](https://github.com/use-ink/ink)

### Educational Content
- [ink! Examples Repository](https://github.com/use-ink/ink-examples)

### Development Tools
- [Contracts UI](https://ui.use.ink/)
- [Polkadot.js Apps](https://polkadot.js.org/apps/)
- [polkadot-sdk Contracts Node](https://github.com/paritytech/substrate-contracts-node)

### Security Resources
- [ink! Linter](https://use.ink/docs/v6/linter/overview)

This appendix serves as your quick reference guide for daily ink! development. Bookmark it for easy access to commands, patterns, and resources that will accelerate your smart contract development workflow.
