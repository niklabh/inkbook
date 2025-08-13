# Chapter 5: Interoperability: Events and Cross-Contract Calls

Smart contracts don't exist in isolation—they need to communicate with off-chain applications and interact with other contracts to create sophisticated decentralized systems. ink! provides two primary mechanisms for this interoperability: events for off-chain communication and cross-contract calls for on-chain composition.

In this chapter, we'll explore how to design effective event systems for user interfaces and monitoring, implement secure cross-contract calling patterns, and build composable contract architectures that leverage the strengths of multiple specialized contracts.

## Events: Communicating with the Outside World

Events are the primary way smart contracts communicate with off-chain applications. They provide a lightweight, indexable mechanism for notifying external systems about contract state changes and important occurrences.

### Basic Event Definition and Emission

Events in ink! are defined as structs with the `#[ink(event)]` attribute:

```rust
#[ink::contract]
mod event_contract {
    /// Transfer event emitted when tokens are moved between accounts
    #[ink(event)]
    pub struct Transfer {
        #[ink(topic)]
        from: Option<AccountId>,
        #[ink(topic)]
        to: Option<AccountId>,
        value: Balance,
    }

    /// Approval event for allowance changes
    #[ink(event)]
    pub struct Approval {
        #[ink(topic)]
        owner: AccountId,
        #[ink(topic)]
        spender: AccountId,
        value: Balance,
    }

    /// Custom business event
    #[ink(event)]
    pub struct PriceUpdate {
        #[ink(topic)]
        token: AccountId,
        old_price: Balance,
        new_price: Balance,
        timestamp: u64,
    }

    #[ink(storage)]
    pub struct EventContract {
        balances: ink::storage::Mapping<AccountId, Balance>,
        allowances: ink::storage::Mapping<(AccountId, AccountId), Balance>,
    }

    impl EventContract {
        #[ink(constructor)]
        pub fn new() -> Self {
            Self {
                balances: ink::storage::Mapping::default(),
                allowances: ink::storage::Mapping::default(),
            }
        }

        #[ink(message)]
        pub fn transfer(&mut self, to: AccountId, value: Balance) -> Result<(), Error> {
            let caller = self.env().caller();
            
            // Perform transfer logic (abbreviated)
            let from_balance = self.balances.get(caller).unwrap_or(0);
            if from_balance < value {
                return Err(Error::InsufficientBalance);
            }
            
            let to_balance = self.balances.get(to).unwrap_or(0);
            self.balances.insert(caller, &(from_balance - value));
            self.balances.insert(to, &(to_balance + value));
            
            // Emit transfer event
            self.env().emit_event(Transfer {
                from: Some(caller),
                to: Some(to),
                value,
            });
            
            Ok(())
        }

        #[ink(message)]
        pub fn mint(&mut self, to: AccountId, value: Balance) -> Result<(), Error> {
            // Only owner can mint (authorization logic omitted)
            
            let balance = self.balances.get(to).unwrap_or(0);
            self.balances.insert(to, &(balance + value));
            
            // Emit transfer event (minting is from None)
            self.env().emit_event(Transfer {
                from: None, // None indicates minting
                to: Some(to),
                value,
            });
            
            Ok(())
        }
    }
}
```

### Understanding Topics: Efficient Event Filtering

The `#[ink(topic)]` attribute makes event fields indexable, enabling efficient filtering and searching:

```rust
#[ink::contract]
mod advanced_events {
    /// Event with multiple indexed topics for efficient filtering
    #[ink(event)]
    pub struct OrderCreated {
        #[ink(topic)]
        order_id: u64,
        #[ink(topic)]
        creator: AccountId,
        #[ink(topic)]
        token_pair: (AccountId, AccountId), // Can index complex types
        amount: Balance,
        price: Balance,
        order_type: OrderType,
        timestamp: u64,
    }

    /// Event without topics (less efficient to filter but smaller size)
    #[ink(event)]
    pub struct SystemUpdate {
        message: Vec<u8>,
        update_type: UpdateType,
        data: Vec<u8>,
    }

    /// Event with selective topics for different use cases
    #[ink(event)]
    pub struct TradeExecuted {
        #[ink(topic)]
        order_id: u64,        // Always indexed - primary identifier
        #[ink(topic)]
        buyer: AccountId,     // Indexed - user-specific filtering
        #[ink(topic)]
        seller: AccountId,    // Indexed - user-specific filtering
        token_sold: AccountId, // Not indexed - reduces event size
        token_bought: AccountId, // Not indexed
        amount_sold: Balance,  // Not indexed
        amount_bought: Balance, // Not indexed
        fee: Balance,         // Not indexed
        timestamp: u64,       // Not indexed
    }

    impl AdvancedEvents {
        #[ink(message)]
        pub fn create_order(
            &mut self,
            token_pair: (AccountId, AccountId),
            amount: Balance,
            price: Balance,
            order_type: OrderType,
        ) -> Result<u64, Error> {
            let order_id = self.next_order_id;
            self.next_order_id += 1;
            
            let creator = self.env().caller();
            let timestamp = self.env().block_timestamp();
            
            // Store order (storage operations omitted)
            
            // Emit event with indexed topics
            self.env().emit_event(OrderCreated {
                order_id,     // Indexed - can filter by specific order
                creator,      // Indexed - can filter by creator
                token_pair,   // Indexed - can filter by trading pair
                amount,       // Not indexed - reduces gas cost
                price,        // Not indexed
                order_type,   // Not indexed
                timestamp,    // Not indexed
            });
            
            Ok(order_id)
        }
    }
}
```

**Topic guidelines:**
- **Index frequently filtered fields**: User addresses, IDs, status values
- **Limit topic count**: Each topic increases event size and gas cost
- **Complex types as topics**: Tuples and enums work, but increase indexing overhead
- **Consider query patterns**: Index fields that UIs and services will filter by

### Event-Driven Architecture Patterns

Design event systems that support rich off-chain applications:

```rust
#[ink::contract]
mod marketplace {
    /// Comprehensive event system for a marketplace
    
    /// Item lifecycle events
    #[ink(event)]
    pub struct ItemListed {
        #[ink(topic)]
        item_id: u64,
        #[ink(topic)]
        seller: AccountId,
        #[ink(topic)]
        category: Category,
        price: Balance,
        description: Vec<u8>,
        timestamp: u64,
    }

    #[ink(event)]
    pub struct ItemSold {
        #[ink(topic)]
        item_id: u64,
        #[ink(topic)]
        seller: AccountId,
        #[ink(topic)]
        buyer: AccountId,
        final_price: Balance,
        timestamp: u64,
    }

    #[ink(event)]
    pub struct ItemCancelled {
        #[ink(topic)]
        item_id: u64,
        #[ink(topic)]
        seller: AccountId,
        timestamp: u64,
    }

    /// Bid events for auction-style listings
    #[ink(event)]
    pub struct BidPlaced {
        #[ink(topic)]
        item_id: u64,
        #[ink(topic)]
        bidder: AccountId,
        bid_amount: Balance,
        previous_highest: Balance,
        timestamp: u64,
    }

    /// System events
    #[ink(event)]
    pub struct FeeUpdated {
        old_fee_percentage: u16,
        new_fee_percentage: u16,
        updated_by: AccountId,
        timestamp: u64,
    }

    #[ink(event)]
    pub struct UserVerified {
        #[ink(topic)]
        user: AccountId,
        verification_level: VerificationLevel,
        verified_by: AccountId,
        timestamp: u64,
    }

    impl Marketplace {
        #[ink(message)]
        pub fn list_item(
            &mut self,
            category: Category,
            price: Balance,
            description: Vec<u8>,
        ) -> Result<u64, Error> {
            let item_id = self.next_item_id;
            self.next_item_id += 1;
            
            let seller = self.env().caller();
            let timestamp = self.env().block_timestamp();
            
            // Create and store item
            let item = Item {
                id: item_id,
                seller,
                category,
                price,
                description: description.clone(),
                status: ItemStatus::Active,
                created_at: timestamp,
            };
            
            self.items.insert(item_id, &item);
            
            // Emit comprehensive event for off-chain indexing
            self.env().emit_event(ItemListed {
                item_id,
                seller,
                category,
                price,
                description,
                timestamp,
            });
            
            Ok(item_id)
        }

        #[ink(message)]
        pub fn purchase_item(&mut self, item_id: u64) -> Result<(), Error> {
            let buyer = self.env().caller();
            let timestamp = self.env().block_timestamp();
            
            // Get and validate item
            let mut item = self.items.get(item_id).ok_or(Error::ItemNotFound)?;
            
            if item.status != ItemStatus::Active {
                return Err(Error::ItemNotAvailable);
            }
            
            if buyer == item.seller {
                return Err(Error::CannotBuyOwnItem);
            }
            
            // Process payment (implementation omitted)
            
            // Update item status
            item.status = ItemStatus::Sold;
            item.sold_to = Some(buyer);
            item.sold_at = Some(timestamp);
            
            self.items.insert(item_id, &item);
            
            // Emit sale event
            self.env().emit_event(ItemSold {
                item_id,
                seller: item.seller,
                buyer,
                final_price: item.price,
                timestamp,
            });
            
            Ok(())
        }
    }
}
```

### Event Data Optimization

Design events for efficient storage and transmission:

```rust
#[ink::contract]
mod optimized_events {
    /// Optimized event - only essential data
    #[ink(event)]
    pub struct TransferOptimized {
        #[ink(topic)]
        from: AccountId,
        #[ink(topic)]
        to: AccountId,
        amount: Balance, // u128 - fixed size
    }

    /// Heavy event - includes extensive metadata
    #[ink(event)]
    pub struct TransferDetailed {
        #[ink(topic)]
        from: AccountId,
        #[ink(topic)]
        to: AccountId,
        amount: Balance,
        fee: Balance,
        exchange_rate: Option<Balance>,
        memo: Vec<u8>,                    // Variable size - expensive
        transaction_metadata: Metadata,   // Complex struct - expensive
        timestamp: u64,
    }

    /// Efficient pattern: Multiple focused events instead of one heavy event
    #[ink(event)]
    pub struct Transfer {
        #[ink(topic)]
        from: AccountId,
        #[ink(topic)]
        to: AccountId,
        amount: Balance,
    }

    #[ink(event)]
    pub struct TransferMetadata {
        #[ink(topic)]
        transaction_id: u64, // Links to main transfer
        memo: Vec<u8>,
        metadata: Metadata,
    }

    impl OptimizedEvents {
        #[ink(message)]
        pub fn transfer_with_metadata(
            &mut self,
            to: AccountId,
            amount: Balance,
            memo: Option<Vec<u8>>,
            metadata: Option<Metadata>,
        ) -> Result<(), Error> {
            let from = self.env().caller();
            let transaction_id = self.get_next_transaction_id();
            
            // Perform transfer
            self.execute_transfer(from, to, amount)?;
            
            // Always emit core transfer event
            self.env().emit_event(Transfer { from, to, amount });
            
            // Conditionally emit metadata event only if needed
            if memo.is_some() || metadata.is_some() {
                self.env().emit_event(TransferMetadata {
                    transaction_id,
                    memo: memo.unwrap_or_default(),
                    metadata: metadata.unwrap_or_default(),
                });
            }
            
            Ok(())
        }
    }
}
```

## Cross-Contract Calls: Building Composable Systems

Cross-contract calls enable contracts to interact with each other, creating composable systems where specialized contracts work together to provide complex functionality.

### Basic Cross-Contract Call Pattern

```rust
// Define the interface for the contract we want to call
#[ink::trait_definition]
pub trait ERC20 {
    #[ink(message)]
    fn transfer(&mut self, to: AccountId, value: Balance) -> Result<(), Error>;
    
    #[ink(message)]
    fn balance_of(&self, owner: AccountId) -> Balance;
    
    #[ink(message)]
    fn total_supply(&self) -> Balance;
}

#[ink::contract]
mod cross_contract_caller {
    use super::ERC20;

    #[ink(storage)]
    pub struct CrossContractCaller {
        erc20_contract: AccountId,
    }

    impl CrossContractCaller {
        #[ink(constructor)]
        pub fn new(erc20_contract: AccountId) -> Self {
            Self { erc20_contract }
        }

        /// Call another contract's method
        #[ink(message)]
        pub fn get_token_balance(&self, account: AccountId) -> Balance {
            // Build cross-contract call
            let balance = ink::env::call::build_call::<ink::env::DefaultEnvironment>()
                .call(self.erc20_contract)
                .gas_limit(5000)
                .transferred_value(0)
                .exec_input(
                    ink::env::call::ExecutionInput::new(
                        ink::env::call::Selector::new([0x56, 0xe9, 0x31, 0xb8]) // balance_of selector
                    ).push_arg(account)
                )
                .returns::<Balance>()
                .invoke();

            balance
        }

        /// More ergonomic cross-contract call using trait
        #[ink(message)]
        pub fn transfer_tokens(
            &mut self,
            to: AccountId,
            amount: Balance,
        ) -> Result<(), Error> {
            // Create contract reference
            let mut erc20: ink::contract_ref!(ERC20) = self.erc20_contract.into();
            
            // Call the contract method directly
            erc20.transfer(to, amount).map_err(|_| Error::CrossContractCallFailed)
        }

        /// Cross-contract call with error handling
        #[ink(message)]
        pub fn safe_token_transfer(
            &mut self,
            to: AccountId,
            amount: Balance,
        ) -> Result<(), Error> {
            // Check contract balance first
            let erc20: ink::contract_ref!(ERC20) = self.erc20_contract.into();
            let contract_balance = erc20.balance_of(self.env().account_id());
            
            if contract_balance < amount {
                return Err(Error::InsufficientBalance);
            }
            
            // Perform transfer
            let mut erc20_mut: ink::contract_ref!(ERC20) = self.erc20_contract.into();
            erc20_mut.transfer(to, amount)
                .map_err(|_| Error::TransferFailed)?;
            
            Ok(())
        }
    }
}
```

### Advanced Cross-Contract Patterns

#### Factory Pattern with Cross-Contract Calls

```rust
#[ink::trait_definition]
pub trait TokenFactory {
    #[ink(message)]
    fn create_token(&mut self, name: String, symbol: String, total_supply: Balance) -> AccountId;
}

#[ink::trait_definition]
pub trait Token {
    #[ink(message)]
    fn mint(&mut self, to: AccountId, amount: Balance) -> Result<(), Error>;
    
    #[ink(message)]
    fn transfer(&mut self, to: AccountId, amount: Balance) -> Result<(), Error>;
}

#[ink::contract]
mod token_manager {
    use super::{TokenFactory, Token};

    #[ink(storage)]
    pub struct TokenManager {
        factory: AccountId,
        created_tokens: Vec<AccountId>,
        token_owners: ink::storage::Mapping<AccountId, AccountId>, // token -> owner
    }

    impl TokenManager {
        #[ink(constructor)]
        pub fn new(factory: AccountId) -> Self {
            Self {
                factory,
                created_tokens: Vec::new(),
                token_owners: ink::storage::Mapping::default(),
            }
        }

        /// Create a new token through the factory
        #[ink(message)]
        pub fn create_managed_token(
            &mut self,
            name: String,
            symbol: String,
            total_supply: Balance,
        ) -> Result<AccountId, Error> {
            let caller = self.env().caller();
            
            // Call factory to create token
            let mut factory: ink::contract_ref!(TokenFactory) = self.factory.into();
            let token_address = factory.create_token(name, symbol, total_supply);
            
            // Register the token
            self.created_tokens.push(token_address);
            self.token_owners.insert(token_address, &caller);
            
            Ok(token_address)
        }

        /// Manage token on behalf of owner
        #[ink(message)]
        pub fn mint_tokens(
            &mut self,
            token: AccountId,
            to: AccountId,
            amount: Balance,
        ) -> Result<(), Error> {
            let caller = self.env().caller();
            
            // Verify ownership
            let owner = self.token_owners.get(token).ok_or(Error::TokenNotFound)?;
            if caller != owner {
                return Err(Error::Unauthorized);
            }
            
            // Call token mint function
            let mut token_contract: ink::contract_ref!(Token) = token.into();
            token_contract.mint(to, amount)
                .map_err(|_| Error::MintFailed)?;
            
            Ok(())
        }

        /// Batch operations across multiple tokens
        #[ink(message)]
        pub fn batch_transfer(
            &mut self,
            operations: Vec<(AccountId, AccountId, Balance)>, // (token, to, amount)
        ) -> Result<u32, Error> {
            let caller = self.env().caller();
            let mut successful = 0;
            
            for (token, to, amount) in operations {
                // Verify ownership
                if let Some(owner) = self.token_owners.get(token) {
                    if caller == owner {
                        // Attempt transfer
                        let mut token_contract: ink::contract_ref!(Token) = token.into();
                        if token_contract.transfer(to, amount).is_ok() {
                            successful += 1;
                        }
                    }
                }
            }
            
            Ok(successful)
        }
    }
}
```

#### Proxy Pattern for Upgradeable Contracts

```rust
#[ink::trait_definition]
pub trait Upgradeable {
    #[ink(message)]
    fn version(&self) -> u32;
    
    #[ink(message)]
    fn upgrade(&mut self, new_implementation: AccountId) -> Result<(), Error>;
}

#[ink::contract]
mod proxy_contract {
    use super::Upgradeable;

    #[ink(storage)]
    pub struct ProxyContract {
        implementation: AccountId,
        admin: AccountId,
        version: u32,
    }

    impl ProxyContract {
        #[ink(constructor)]
        pub fn new(implementation: AccountId) -> Self {
            Self {
                implementation,
                admin: Self::env().caller(),
                version: 1,
            }
        }

        /// Delegate call to current implementation
        #[ink(message)]
        pub fn delegate_call(&self, selector: [u8; 4], input: Vec<u8>) -> Vec<u8> {
            // Build delegate call to implementation
            let result = ink::env::call::build_call::<ink::env::DefaultEnvironment>()
                .call(self.implementation)
                .gas_limit(0) // Use all available gas
                .transferred_value(0)
                .exec_input(
                    ink::env::call::ExecutionInput::new(
                        ink::env::call::Selector::new(selector)
                    ).push_arg(input)
                )
                .returns::<Vec<u8>>()
                .invoke();

            result
        }

        /// Upgrade to new implementation (admin only)
        #[ink(message)]
        pub fn upgrade_implementation(&mut self, new_implementation: AccountId) -> Result<(), Error> {
            if self.env().caller() != self.admin {
                return Err(Error::Unauthorized);
            }

            // Verify new implementation is compatible
            let new_impl: ink::contract_ref!(Upgradeable) = new_implementation.into();
            let new_version = new_impl.version();
            
            if new_version <= self.version {
                return Err(Error::InvalidVersion);
            }

            // Update implementation
            self.implementation = new_implementation;
            self.version = new_version;

            Ok(())
        }

        /// Fallback function for unknown calls
        #[ink(message)]
        pub fn fallback(&self) -> ! {
            // In a real implementation, this would delegate all unknown calls
            // to the implementation contract
            panic!("Fallback not implemented in this example");
        }
    }
}
```

### Security Considerations for Cross-Contract Calls

Cross-contract calls introduce security risks that must be carefully managed:

```rust
#[ink::contract]
mod secure_cross_contract {
    use ink::storage::Mapping;

    #[ink(storage)]
    pub struct SecureCrossContract {
        trusted_contracts: Mapping<AccountId, bool>,
        reentrancy_guard: bool,
        call_depth: u32,
    }

    impl SecureCrossContract {
        #[ink(constructor)]
        pub fn new() -> Self {
            Self {
                trusted_contracts: Mapping::default(),
                reentrancy_guard: false,
                call_depth: 0,
            }
        }

        /// Reentrancy protection modifier
        fn non_reentrant(&mut self) -> Result<(), Error> {
            if self.reentrancy_guard {
                return Err(Error::ReentrancyDetected);
            }
            self.reentrancy_guard = true;
            Ok(())
        }

        fn end_non_reentrant(&mut self) {
            self.reentrancy_guard = false;
        }

        /// Safe cross-contract call with reentrancy protection
        #[ink(message)]
        pub fn safe_external_call(
            &mut self,
            target: AccountId,
            selector: [u8; 4],
            input: Vec<u8>,
        ) -> Result<Vec<u8>, Error> {
            // Reentrancy protection
            self.non_reentrant()?;

            // Depth protection
            const MAX_CALL_DEPTH: u32 = 10;
            if self.call_depth >= MAX_CALL_DEPTH {
                self.end_non_reentrant();
                return Err(Error::CallDepthExceeded);
            }

            // Trust verification
            if !self.trusted_contracts.get(target).unwrap_or(false) {
                self.end_non_reentrant();
                return Err(Error::UntrustedContract);
            }

            self.call_depth += 1;

            // Perform the call with gas limit
            let result = ink::env::call::build_call::<ink::env::DefaultEnvironment>()
                .call(target)
                .gas_limit(100_000) // Limited gas to prevent issues
                .transferred_value(0)
                .exec_input(
                    ink::env::call::ExecutionInput::new(
                        ink::env::call::Selector::new(selector)
                    ).push_arg(input)
                )
                .returns::<Vec<u8>>()
                .try_invoke();

            self.call_depth -= 1;
            self.end_non_reentrant();

            match result {
                Ok(Ok(data)) => Ok(data),
                Ok(Err(_)) => Err(Error::CallReverted),
                Err(_) => Err(Error::CallFailed),
            }
        }

        /// Add trusted contract (admin only)
        #[ink(message)]
        pub fn add_trusted_contract(&mut self, contract: AccountId) -> Result<(), Error> {
            // Admin check omitted for brevity
            self.trusted_contracts.insert(contract, &true);
            Ok(())
        }

        /// Circuit breaker pattern
        #[ink(message)]
        pub fn emergency_stop(&mut self) -> Result<(), Error> {
            // Admin check omitted for brevity
            // In emergency, disable all cross-contract calls
            // Implementation would set a global flag
            Ok(())
        }
    }
}
```

### Cross-Contract Call Patterns for DeFi

Implement common DeFi patterns using cross-contract composition:

```rust
#[ink::trait_definition]
pub trait PriceOracle {
    #[ink(message)]
    fn get_price(&self, token: AccountId) -> Result<Balance, Error>;
}

#[ink::trait_definition]
pub trait LiquidityPool {
    #[ink(message)]
    fn swap(&mut self, token_in: AccountId, token_out: AccountId, amount_in: Balance) -> Result<Balance, Error>;
    
    #[ink(message)]
    fn add_liquidity(&mut self, token_a: AccountId, token_b: AccountId, amount_a: Balance, amount_b: Balance) -> Result<(), Error>;
}

#[ink::contract]
mod defi_aggregator {
    use super::{PriceOracle, LiquidityPool, Token};

    #[ink(storage)]
    pub struct DeFiAggregator {
        price_oracle: AccountId,
        liquidity_pools: Vec<AccountId>,
        supported_tokens: ink::storage::Mapping<AccountId, bool>,
    }

    impl DeFiAggregator {
        #[ink(constructor)]
        pub fn new(price_oracle: AccountId) -> Self {
            Self {
                price_oracle,
                liquidity_pools: Vec::new(),
                supported_tokens: ink::storage::Mapping::default(),
            }
        }

        /// Find best swap rate across multiple pools
        #[ink(message)]
        pub fn find_best_swap(
            &self,
            token_in: AccountId,
            token_out: AccountId,
            amount_in: Balance,
        ) -> Result<(AccountId, Balance), Error> {
            let mut best_pool = AccountId::from([0; 32]);
            let mut best_output = 0;

            // Check each pool for best rate
            for pool_address in &self.liquidity_pools {
                // Simulate swap to get output amount
                let pool: ink::contract_ref!(LiquidityPool) = (*pool_address).into();
                
                // In a real implementation, you'd call a view function
                // that simulates the swap without executing it
                if let Ok(output) = self.simulate_swap(pool_address, token_in, token_out, amount_in) {
                    if output > best_output {
                        best_output = output;
                        best_pool = *pool_address;
                    }
                }
            }

            if best_output == 0 {
                return Err(Error::NoLiquidityFound);
            }

            Ok((best_pool, best_output))
        }

        /// Execute optimal swap
        #[ink(message)]
        pub fn optimal_swap(
            &mut self,
            token_in: AccountId,
            token_out: AccountId,
            amount_in: Balance,
            min_amount_out: Balance,
        ) -> Result<Balance, Error> {
            // Find best pool
            let (best_pool, expected_output) = self.find_best_swap(token_in, token_out, amount_in)?;

            if expected_output < min_amount_out {
                return Err(Error::SlippageTooHigh);
            }

            // Transfer tokens from user to this contract
            let mut token_contract: ink::contract_ref!(Token) = token_in.into();
            token_contract.transfer(self.env().account_id(), amount_in)
                .map_err(|_| Error::TransferFailed)?;

            // Execute swap through best pool
            let mut pool: ink::contract_ref!(LiquidityPool) = best_pool.into();
            let actual_output = pool.swap(token_in, token_out, amount_in)
                .map_err(|_| Error::SwapFailed)?;

            // Transfer output tokens to user
            let mut output_token: ink::contract_ref!(Token) = token_out.into();
            output_token.transfer(self.env().caller(), actual_output)
                .map_err(|_| Error::TransferFailed)?;

            Ok(actual_output)
        }

        /// Price-aware arbitrage execution
        #[ink(message)]
        pub fn execute_arbitrage(
            &mut self,
            token_a: AccountId,
            token_b: AccountId,
            amount: Balance,
        ) -> Result<Balance, Error> {
            // Get oracle price
            let oracle: ink::contract_ref!(PriceOracle) = self.price_oracle.into();
            let oracle_price = oracle.get_price(token_a)?;

            // Find pools with price deviation
            let mut profitable_pools = Vec::new();
            
            for pool in &self.liquidity_pools {
                if let Ok(pool_price) = self.get_pool_price(*pool, token_a, token_b) {
                    let price_diff = if pool_price > oracle_price {
                        pool_price - oracle_price
                    } else {
                        oracle_price - pool_price
                    };
                    
                    // 1% threshold for profitability
                    if price_diff > oracle_price / 100 {
                        profitable_pools.push((*pool, pool_price));
                    }
                }
            }

            if profitable_pools.is_empty() {
                return Err(Error::NoArbitrageOpportunity);
            }

            // Execute arbitrage (simplified)
            // In practice, this would involve complex multi-step swaps
            Ok(0) // Placeholder return
        }

        /// Helper function to simulate swap without execution
        fn simulate_swap(
            &self,
            pool: &AccountId,
            token_in: AccountId,
            token_out: AccountId,
            amount_in: Balance,
        ) -> Result<Balance, Error> {
            // In practice, this would call a view function on the pool
            // that calculates output without state changes
            Ok(0) // Placeholder
        }

        fn get_pool_price(
            &self,
            pool: AccountId,
            token_a: AccountId,
            token_b: AccountId,
        ) -> Result<Balance, Error> {
            // Get current pool price for token pair
            Ok(0) // Placeholder
        }
    }
}
```

## Testing Interoperability

Comprehensive testing for events and cross-contract calls:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use ink::env::test;

    #[ink::test]
    fn event_emission_works() {
        let mut contract = EventContract::new();
        let alice = AccountId::from([1; 32]);
        let bob = AccountId::from([2; 32]);

        // Set up initial balance
        contract.balances.insert(alice, &1000);

        // Capture emitted events
        let emitted_events = test::recorded_events().collect::<Vec<_>>();
        let events_before = emitted_events.len();

        // Execute transfer
        assert!(contract.transfer(bob, 100).is_ok());

        // Check event emission
        let emitted_events = test::recorded_events().collect::<Vec<_>>();
        assert_eq!(emitted_events.len(), events_before + 1);

        // Decode and verify event
        let event = &emitted_events[events_before];
        // Event verification logic would go here
    }

    #[ink::test]
    fn cross_contract_call_simulation() {
        // This would typically require a more complex test setup
        // with multiple contract instances
        
        let caller = CrossContractCaller::new(AccountId::from([1; 32]));
        
        // In practice, you'd deploy a mock ERC20 contract
        // and test actual cross-contract calls
        
        // For now, we can test the construction and basic logic
        assert_eq!(caller.erc20_contract, AccountId::from([1; 32]));
    }
}

/// End-to-end tests for cross-contract calls
#[cfg(all(test, feature = "e2e-tests"))]
mod e2e_tests {
    use super::*;
    use ink_e2e::build_message;

    #[ink_e2e::test]
    async fn cross_contract_integration_works(mut client: ink_e2e::Client<C, E>) -> E2EResult<()> {
        // Deploy ERC20 contract
        let erc20_constructor = Erc20Ref::new(1000, "Test".to_string(), "TST".to_string(), 18);
        let erc20_acc_id = client
            .instantiate("erc20", &ink_e2e::alice(), erc20_constructor, 0, None)
            .await
            .expect("ERC20 instantiate failed")
            .account_id;

        // Deploy cross-contract caller
        let caller_constructor = CrossContractCallerRef::new(erc20_acc_id);
        let caller_acc_id = client
            .instantiate("cross_contract_caller", &ink_e2e::alice(), caller_constructor, 0, None)
            .await
            .expect("Caller instantiate failed")
            .account_id;

        // Test cross-contract call
        let get_balance = build_message::<CrossContractCallerRef>(caller_acc_id.clone())
            .call(|caller| caller.get_token_balance(ink_e2e::alice().account_id()));
        
        let balance_result = client.call_dry_run(&ink_e2e::alice(), &get_balance, 0, None).await;
        assert_eq!(balance_result.return_value(), 1000);

        Ok(())
    }
}
```

## Summary

In this chapter, we've explored the powerful interoperability features that make ink! contracts part of larger ecosystems:

**Event Systems:**
1. **Event Definition**: Creating structured events with `#[ink(event)]` and topic indexing
2. **Efficient Filtering**: Using `#[ink(topic)]` for off-chain query optimization
3. **Event Architecture**: Designing event systems that support rich user interfaces
4. **Data Optimization**: Balancing event richness with gas efficiency

**Cross-Contract Calls:**
5. **Basic Patterns**: Using trait definitions and contract references for type-safe calls
6. **Advanced Patterns**: Factory patterns, proxy patterns, and upgradeable architectures
7. **Security Considerations**: Reentrancy protection, call depth limits, and trust management
8. **DeFi Composition**: Building complex financial applications through contract composition

**Testing Strategies:**
9. **Event Testing**: Verifying event emission and data correctness
10. **Integration Testing**: End-to-end testing of cross-contract interactions

**Key Takeaways:**
- Events provide efficient communication with off-chain applications
- Cross-contract calls enable powerful composability patterns
- Security must be carefully considered when calling external contracts
- Proper testing ensures reliable interoperability

With solid interoperability foundations established, you're ready to explore advanced ink! patterns and techniques. In the next chapter, we'll cover sophisticated design patterns, error handling strategies, and architectural approaches for building robust, production-ready smart contracts.
