# Chapter 4: The Logic Layer: Messages and Constructors

While storage defines what your contract knows, messages and constructors define what your contract can do. These form the public interface through which users, other contracts, and external applications interact with your smart contract. Understanding how to design robust, secure, and efficient message handlers is crucial for building production-ready contracts.

In this chapter, we'll explore constructor patterns for flexible initialization, message design for clear APIs, payable messages for handling native token transfers, and environmental information access for context-aware contract behavior.

## Constructor Patterns: Flexible Initialization

Constructors are your contract's entry point—they execute exactly once during deployment and establish the initial state. Well-designed constructors provide flexibility while maintaining security and correctness guarantees.

### Multiple Constructor Pattern

Unlike many smart contract platforms that allow only one constructor, ink! supports multiple constructors, enabling flexible initialization patterns:

```rust
#[ink::contract]
mod flexible_token {
    use ink::storage::Mapping;

    #[ink(storage)]
    pub struct FlexibleToken {
        total_supply: Balance,
        balances: Mapping<AccountId, Balance>,
        owner: AccountId,
        name: String,
        symbol: String,
        decimals: u8,
    }

    #[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub enum Error {
        InvalidParameters,
        InsufficientBalance,
        Unauthorized,
    }

    impl FlexibleToken {
        /// Standard constructor with all parameters
        #[ink(constructor)]
        pub fn new(
            total_supply: Balance,
            name: String,
            symbol: String,
            decimals: u8,
        ) -> Result<Self, Error> {
            if total_supply == 0 || name.is_empty() || symbol.is_empty() {
                return Err(Error::InvalidParameters);
            }

            let caller = Self::env().caller();
            let mut balances = Mapping::default();
            balances.insert(caller, &total_supply);

            Ok(Self {
                total_supply,
                balances,
                owner: caller,
                name,
                symbol,
                decimals,
            })
        }

        /// Simple constructor with defaults
        #[ink(constructor)]
        pub fn new_simple(total_supply: Balance) -> Result<Self, Error> {
            Self::new(
                total_supply,
                "SimpleToken".to_string(),
                "STK".to_string(),
                18,
            )
        }

        /// Constructor for creating wrapped tokens
        #[ink(constructor)]
        pub fn new_wrapped(
            name: String,
            symbol: String,
        ) -> Result<Self, Error> {
            Self::new(0, name, symbol, 18)
        }

        /// Constructor that mints initial supply to specific account
        #[ink(constructor)]
        pub fn new_with_recipient(
            total_supply: Balance,
            recipient: AccountId,
            name: String,
            symbol: String,
        ) -> Result<Self, Error> {
            if total_supply == 0 || name.is_empty() || symbol.is_empty() {
                return Err(Error::InvalidParameters);
            }

            let caller = Self::env().caller();
            let mut balances = Mapping::default();
            balances.insert(recipient, &total_supply);

            Ok(Self {
                total_supply,
                balances,
                owner: caller,
                name,
                symbol,
                decimals: 18,
            })
        }
    }
}
```

### Constructor Validation Patterns

Implement comprehensive validation in constructors to prevent invalid deployments:

```rust
impl FlexibleToken {
    /// Constructor with comprehensive validation
    #[ink(constructor)]
    pub fn new_validated(
        total_supply: Balance,
        name: String,
        symbol: String,
        decimals: u8,
    ) -> Result<Self, Error> {
        // Validate total supply
        Self::validate_total_supply(total_supply)?;
        
        // Validate metadata
        Self::validate_metadata(&name, &symbol, decimals)?;
        
        // Create instance
        let caller = Self::env().caller();
        let mut balances = Mapping::default();
        balances.insert(caller, &total_supply);

        Ok(Self {
            total_supply,
            balances,
            owner: caller,
            name,
            symbol,
            decimals,
        })
    }

    /// Validate total supply constraints
    fn validate_total_supply(total_supply: Balance) -> Result<(), Error> {
        const MAX_SUPPLY: Balance = 1_000_000_000_000_000_000_000; // 1 billion with 18 decimals
        const MIN_SUPPLY: Balance = 1_000_000_000_000_000; // 0.001 with 18 decimals

        if total_supply == 0 || total_supply > MAX_SUPPLY {
            return Err(Error::InvalidParameters);
        }

        if total_supply < MIN_SUPPLY {
            return Err(Error::InvalidParameters);
        }

        Ok(())
    }

    /// Validate token metadata
    fn validate_metadata(name: &str, symbol: &str, decimals: u8) -> Result<(), Error> {
        // Name validation
        if name.is_empty() || name.len() > 50 {
            return Err(Error::InvalidParameters);
        }

        // Symbol validation
        if symbol.is_empty() || symbol.len() > 10 {
            return Err(Error::InvalidParameters);
        }

        // Decimals validation (most tokens use 0-18 decimals)
        if decimals > 18 {
            return Err(Error::InvalidParameters);
        }

        // Check for valid characters (alphanumeric only)
        if !name.chars().all(|c| c.is_alphanumeric() || c.is_whitespace()) {
            return Err(Error::InvalidParameters);
        }

        if !symbol.chars().all(|c| c.is_alphanumeric()) {
            return Err(Error::InvalidParameters);
        }

        Ok(())
    }
}
```

### Constructor Initialization Patterns

```rust
#[ink::contract]
mod initialization_patterns {
    use ink::storage::{Mapping, Lazy};

    #[ink(storage)]
    pub struct InitializationContract {
        // Always initialized
        owner: AccountId,
        created_at: u64,
        
        // Conditionally initialized
        admin_data: Option<AdminData>,
        
        // Lazy initialized
        large_config: Lazy<Configuration>,
        
        // Empty mappings (always valid)
        balances: Mapping<AccountId, Balance>,
    }

    impl InitializationContract {
        /// Minimal constructor - only essential data
        #[ink(constructor)]
        pub fn new() -> Self {
            Self {
                owner: Self::env().caller(),
                created_at: Self::env().block_timestamp(),
                admin_data: None,
                large_config: Lazy::new(),
                balances: Mapping::default(),
            }
        }

        /// Constructor with admin setup
        #[ink(constructor)]
        pub fn new_with_admin(admin_key: [u8; 32]) -> Self {
            let mut contract = Self::new();
            contract.admin_data = Some(AdminData {
                key: admin_key,
                permissions: AdminPermissions::Full,
            });
            contract
        }

        /// Constructor with pre-configuration
        #[ink(constructor)]
        pub fn new_configured(config: Configuration) -> Self {
            let mut contract = Self::new();
            contract.large_config.set(&config);
            contract
        }
    }
}
```

## Message Design: Building Clear APIs

Messages form your contract's public API. Well-designed messages are intuitive, secure, and efficient.

### Immutable vs. Mutable Messages

Understanding the distinction between read-only and state-changing operations is fundamental:

```rust
impl FlexibleToken {
    // ========== READ-ONLY MESSAGES (Immutable) ==========
    
    /// Get account balance - pure query, no state changes
    #[ink(message)]
    pub fn balance_of(&self, account: AccountId) -> Balance {
        self.balances.get(account).unwrap_or(0)
    }

    /// Get total supply - constant value query
    #[ink(message)]
    pub fn total_supply(&self) -> Balance {
        self.total_supply
    }

    /// Check if account has sufficient balance
    #[ink(message)]
    pub fn has_sufficient_balance(&self, account: AccountId, amount: Balance) -> bool {
        self.balance_of(account) >= amount
    }

    /// Get token metadata
    #[ink(message)]
    pub fn token_info(&self) -> (String, String, u8) {
        (self.name.clone(), self.symbol.clone(), self.decimals)
    }

    // ========== STATE-CHANGING MESSAGES (Mutable) ==========

    /// Transfer tokens between accounts
    #[ink(message)]
    pub fn transfer(&mut self, to: AccountId, amount: Balance) -> Result<(), Error> {
        let caller = self.env().caller();
        self.transfer_from_to(caller, to, amount)
    }

    /// Mint new tokens (owner only)
    #[ink(message)]
    pub fn mint(&mut self, to: AccountId, amount: Balance) -> Result<(), Error> {
        self.ensure_owner()?;
        
        // Check for overflow
        let new_total_supply = self.total_supply
            .checked_add(amount)
            .ok_or(Error::ArithmeticOverflow)?;
        
        let current_balance = self.balance_of(to);
        let new_balance = current_balance
            .checked_add(amount)
            .ok_or(Error::ArithmeticOverflow)?;
        
        // Update state
        self.total_supply = new_total_supply;
        self.balances.insert(to, &new_balance);
        
        Ok(())
    }

    /// Burn tokens from caller's account
    #[ink(message)]
    pub fn burn(&mut self, amount: Balance) -> Result<(), Error> {
        let caller = self.env().caller();
        let current_balance = self.balance_of(caller);
        
        if current_balance < amount {
            return Err(Error::InsufficientBalance);
        }
        
        let new_balance = current_balance - amount;
        let new_total_supply = self.total_supply - amount;
        
        self.balances.insert(caller, &new_balance);
        self.total_supply = new_total_supply;
        
        Ok(())
    }
}
```

### Message Parameter Patterns

Design message parameters for clarity and safety:

```rust
impl FlexibleToken {
    /// Batch transfer - efficient multi-recipient transfers
    #[ink(message)]
    pub fn batch_transfer(
        &mut self,
        recipients: Vec<(AccountId, Balance)>,
    ) -> Result<u32, Error> {
        // Validate batch size to prevent gas limit issues
        const MAX_BATCH_SIZE: usize = 50;
        if recipients.len() > MAX_BATCH_SIZE {
            return Err(Error::InvalidParameters);
        }

        let caller = self.env().caller();
        let mut total_amount = 0u128;
        
        // Calculate total amount first
        for (_, amount) in &recipients {
            total_amount = total_amount
                .checked_add(*amount)
                .ok_or(Error::ArithmeticOverflow)?;
        }
        
        // Check sufficient balance
        if self.balance_of(caller) < total_amount {
            return Err(Error::InsufficientBalance);
        }
        
        // Execute transfers
        let mut successful_transfers = 0;
        for (to, amount) in recipients {
            if self.transfer_from_to(caller, to, amount).is_ok() {
                successful_transfers += 1;
            }
        }
        
        Ok(successful_transfers)
    }

    /// Transfer with metadata - includes reason/memo
    #[ink(message)]
    pub fn transfer_with_memo(
        &mut self,
        to: AccountId,
        amount: Balance,
        memo: Vec<u8>,
    ) -> Result<(), Error> {
        // Limit memo size to prevent abuse
        const MAX_MEMO_SIZE: usize = 256;
        if memo.len() > MAX_MEMO_SIZE {
            return Err(Error::InvalidParameters);
        }

        // Execute transfer
        self.transfer(to, amount)?;
        
        // Emit event with memo (covered in next chapter)
        self.env().emit_event(TransferWithMemo {
            from: Some(self.env().caller()),
            to: Some(to),
            amount,
            memo,
        });
        
        Ok(())
    }

    /// Conditional transfer - only execute if condition is met
    #[ink(message)]
    pub fn conditional_transfer(
        &mut self,
        to: AccountId,
        amount: Balance,
        min_balance_required: Balance,
    ) -> Result<bool, Error> {
        // Check if recipient meets minimum balance requirement
        let recipient_balance = self.balance_of(to);
        if recipient_balance < min_balance_required {
            return Ok(false); // Condition not met, no transfer
        }
        
        // Execute transfer
        self.transfer(to, amount)?;
        Ok(true) // Transfer executed
    }
}
```

### Error Handling Patterns

Comprehensive error handling makes contracts robust and user-friendly:

```rust
#[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
#[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
pub enum Error {
    // Balance-related errors
    InsufficientBalance,
    ArithmeticOverflow,
    ArithmeticUnderflow,
    
    // Authorization errors
    Unauthorized,
    NotOwner,
    
    // Parameter validation errors
    InvalidParameters,
    InvalidAddress,
    InvalidAmount,
    
    // State-related errors
    ContractPaused,
    TransferDisabled,
    
    // Custom business logic errors
    TransferLimitExceeded,
    RecipientBlacklisted,
}

impl FlexibleToken {
    /// Robust transfer with comprehensive error handling
    #[ink(message)]
    pub fn robust_transfer(&mut self, to: AccountId, amount: Balance) -> Result<(), Error> {
        // Parameter validation
        if amount == 0 {
            return Err(Error::InvalidAmount);
        }
        
        if to == AccountId::from([0u8; 32]) {
            return Err(Error::InvalidAddress);
        }
        
        let caller = self.env().caller();
        
        // Self-transfer check
        if caller == to {
            return Ok(()); // No-op for self transfers
        }
        
        // Balance checks with specific error messages
        let caller_balance = self.balance_of(caller);
        if caller_balance == 0 {
            return Err(Error::InsufficientBalance);
        }
        
        if caller_balance < amount {
            return Err(Error::InsufficientBalance);
        }
        
        // Arithmetic safety checks
        let new_caller_balance = caller_balance
            .checked_sub(amount)
            .ok_or(Error::ArithmeticUnderflow)?;
        
        let to_balance = self.balance_of(to);
        let new_to_balance = to_balance
            .checked_add(amount)
            .ok_or(Error::ArithmeticOverflow)?;
        
        // Execute transfer
        self.balances.insert(caller, &new_caller_balance);
        self.balances.insert(to, &new_to_balance);
        
        Ok(())
    }

    /// Helper function for consistent error checking
    fn ensure_owner(&self) -> Result<(), Error> {
        if self.env().caller() != self.owner {
            Err(Error::NotOwner)
        } else {
            Ok(())
        }
    }

    /// Helper for amount validation
    fn validate_amount(&self, amount: Balance) -> Result<(), Error> {
        if amount == 0 {
            return Err(Error::InvalidAmount);
        }
        
        // Check against maximum per-transaction limit
        const MAX_TRANSFER_AMOUNT: Balance = 1_000_000_000_000_000_000_000; // 1 million tokens
        if amount > MAX_TRANSFER_AMOUNT {
            return Err(Error::TransferLimitExceeded);
        }
        
        Ok(())
    }
}
```

## Payable Messages: Handling Native Token Transfers

Payable messages allow contracts to receive native tokens (like DOT on Polkadot) alongside message calls, enabling powerful patterns for token sales, deposits, and payment processing.

### Basic Payable Message Pattern

```rust
#[ink::contract]
mod payable_contract {
    #[ink(storage)]
    pub struct PayableContract {
        owner: AccountId,
        total_deposits: Balance,
        user_deposits: ink::storage::Mapping<AccountId, Balance>,
    }

    impl PayableContract {
        #[ink(constructor)]
        pub fn new() -> Self {
            Self {
                owner: Self::env().caller(),
                total_deposits: 0,
                user_deposits: ink::storage::Mapping::default(),
            }
        }

        /// Accept deposits of native tokens
        #[ink(message, payable)]
        pub fn deposit(&mut self) -> Result<(), Error> {
            let caller = self.env().caller();
            let deposited_value = self.env().transferred_value();
            
            // Validate deposit amount
            if deposited_value == 0 {
                return Err(Error::InvalidAmount);
            }
            
            // Update user's deposit balance
            let current_deposit = self.user_deposits.get(caller).unwrap_or(0);
            let new_deposit = current_deposit
                .checked_add(deposited_value)
                .ok_or(Error::ArithmeticOverflow)?;
            
            self.user_deposits.insert(caller, &new_deposit);
            
            // Update total deposits
            self.total_deposits = self.total_deposits
                .checked_add(deposited_value)
                .ok_or(Error::ArithmeticOverflow)?;
            
            Ok(())
        }

        /// Withdraw deposited tokens
        #[ink(message)]
        pub fn withdraw(&mut self, amount: Balance) -> Result<(), Error> {
            let caller = self.env().caller();
            let user_deposit = self.user_deposits.get(caller).unwrap_or(0);
            
            if user_deposit < amount {
                return Err(Error::InsufficientBalance);
            }
            
            // Update balances
            let new_deposit = user_deposit - amount;
            self.user_deposits.insert(caller, &new_deposit);
            self.total_deposits -= amount;
            
            // Transfer tokens back to user
            self.env().transfer(caller, amount)
                .map_err(|_| Error::TransferFailed)?;
            
            Ok(())
        }

        /// Check user's deposit balance
        #[ink(message)]
        pub fn deposit_of(&self, account: AccountId) -> Balance {
            self.user_deposits.get(account).unwrap_or(0)
        }
    }
}
```

### Token Sale Contract with Payable Messages

```rust
#[ink::contract]
mod token_sale {
    use ink::storage::Mapping;

    #[ink(storage)]
    pub struct TokenSale {
        // Sale parameters
        token_price: Balance,     // Price per token in native currency
        tokens_sold: Balance,
        max_tokens: Balance,
        sale_active: bool,
        
        // Balances
        purchased_tokens: Mapping<AccountId, Balance>,
        total_raised: Balance,
        
        // Access control
        owner: AccountId,
    }

    impl TokenSale {
        #[ink(constructor)]
        pub fn new(token_price: Balance, max_tokens: Balance) -> Result<Self, Error> {
            if token_price == 0 || max_tokens == 0 {
                return Err(Error::InvalidParameters);
            }

            Ok(Self {
                token_price,
                tokens_sold: 0,
                max_tokens,
                sale_active: true,
                purchased_tokens: Mapping::default(),
                total_raised: 0,
                owner: Self::env().caller(),
            })
        }

        /// Purchase tokens with native currency
        #[ink(message, payable)]
        pub fn buy_tokens(&mut self) -> Result<Balance, Error> {
            if !self.sale_active {
                return Err(Error::SaleInactive);
            }

            let payment = self.env().transferred_value();
            if payment == 0 {
                return Err(Error::InvalidAmount);
            }

            // Calculate tokens to purchase
            let tokens_to_buy = payment / self.token_price;
            if tokens_to_buy == 0 {
                return Err(Error::InsufficientPayment);
            }

            // Check if enough tokens are available
            let remaining_tokens = self.max_tokens - self.tokens_sold;
            let actual_tokens = tokens_to_buy.min(remaining_tokens);
            
            if actual_tokens == 0 {
                return Err(Error::SoldOut);
            }

            // Calculate actual cost and refund excess
            let actual_cost = actual_tokens * self.token_price;
            let refund = payment - actual_cost;

            // Update state
            let caller = self.env().caller();
            let current_tokens = self.purchased_tokens.get(caller).unwrap_or(0);
            let new_tokens = current_tokens + actual_tokens;
            
            self.purchased_tokens.insert(caller, &new_tokens);
            self.tokens_sold += actual_tokens;
            self.total_raised += actual_cost;

            // Process refund if necessary
            if refund > 0 {
                self.env().transfer(caller, refund)
                    .map_err(|_| Error::RefundFailed)?;
            }

            Ok(actual_tokens)
        }

        /// Emergency withdrawal (owner only)
        #[ink(message)]
        pub fn emergency_withdraw(&mut self) -> Result<(), Error> {
            if self.env().caller() != self.owner {
                return Err(Error::Unauthorized);
            }

            let contract_balance = self.env().balance();
            if contract_balance > 0 {
                self.env().transfer(self.owner, contract_balance)
                    .map_err(|_| Error::TransferFailed)?;
            }

            Ok(())
        }

        /// Withdraw raised funds (owner only)
        #[ink(message)]
        pub fn withdraw_funds(&mut self, amount: Balance) -> Result<(), Error> {
            if self.env().caller() != self.owner {
                return Err(Error::Unauthorized);
            }

            if amount > self.total_raised {
                return Err(Error::InsufficientBalance);
            }

            self.env().transfer(self.owner, amount)
                .map_err(|_| Error::TransferFailed)?;

            Ok(())
        }
    }
}
```

### Advanced Payable Patterns

```rust
impl TokenSale {
    /// Tiered pricing based on purchase amount
    #[ink(message, payable)]
    pub fn buy_tokens_tiered(&mut self) -> Result<Balance, Error> {
        let payment = self.env().transferred_value();
        let tokens_to_buy = self.calculate_tiered_tokens(payment)?;
        
        // Execute purchase with calculated tokens
        self.execute_purchase(tokens_to_buy, payment)
    }

    /// Calculate tokens with tiered pricing
    fn calculate_tiered_tokens(&self, payment: Balance) -> Result<Balance, Error> {
        const TIER1_THRESHOLD: Balance = 1_000_000_000_000; // 1 token
        const TIER2_THRESHOLD: Balance = 10_000_000_000_000; // 10 tokens
        
        let discount_price = if payment >= TIER2_THRESHOLD {
            self.token_price * 80 / 100 // 20% discount
        } else if payment >= TIER1_THRESHOLD {
            self.token_price * 90 / 100 // 10% discount
        } else {
            self.token_price
        };

        Ok(payment / discount_price)
    }

    /// Presale with whitelist and limits
    #[ink(message, payable)]
    pub fn presale_purchase(&mut self, max_purchase: Balance) -> Result<Balance, Error> {
        let caller = self.env().caller();
        
        // Check whitelist (implementation depends on whitelist mechanism)
        if !self.is_whitelisted(caller) {
            return Err(Error::NotWhitelisted);
        }
        
        let payment = self.env().transferred_value();
        let tokens_to_buy = payment / self.token_price;
        
        // Check individual purchase limit
        if tokens_to_buy > max_purchase {
            return Err(Error::PurchaseLimitExceeded);
        }
        
        // Check lifetime purchase limit
        let current_tokens = self.purchased_tokens.get(caller).unwrap_or(0);
        const LIFETIME_LIMIT: Balance = 100_000_000_000_000; // 100 tokens
        
        if current_tokens + tokens_to_buy > LIFETIME_LIMIT {
            return Err(Error::LifetimeLimitExceeded);
        }
        
        self.execute_purchase(tokens_to_buy, payment)
    }
}
```

## Accessing Environmental Information

Contract messages can access rich environmental information about the blockchain state and transaction context.

### Core Environmental Functions

```rust
#[ink::contract]
mod environment_aware {
    #[ink(storage)]
    pub struct EnvironmentAware {
        creation_time: u64,
        creator: AccountId,
        call_count: u32,
        last_caller: Option<AccountId>,
    }

    impl EnvironmentAware {
        #[ink(constructor)]
        pub fn new() -> Self {
            Self {
                creation_time: Self::env().block_timestamp(),
                creator: Self::env().caller(),
                call_count: 0,
                last_caller: None,
            }
        }

        /// Demonstrate environmental information access
        #[ink(message)]
        pub fn environment_info(&mut self) -> EnvironmentInfo {
            self.call_count += 1;
            self.last_caller = Some(self.env().caller());

            EnvironmentInfo {
                // Transaction context
                caller: self.env().caller(),
                contract_address: self.env().account_id(),
                
                // Value information
                transferred_value: self.env().transferred_value(),
                contract_balance: self.env().balance(),
                
                // Block information
                block_number: self.env().block_number(),
                block_timestamp: self.env().block_timestamp(),
                
                // Contract information
                creation_time: self.creation_time,
                creator: self.creator,
                call_count: self.call_count,
            }
        }

        /// Time-locked function - only callable after certain time
        #[ink(message)]
        pub fn time_locked_function(&self) -> Result<(), Error> {
            const LOCK_DURATION: u64 = 86400000; // 24 hours in milliseconds
            let unlock_time = self.creation_time + LOCK_DURATION;
            
            if self.env().block_timestamp() < unlock_time {
                return Err(Error::TimeLocked);
            }
            
            // Function logic here
            Ok(())
        }

        /// Access control based on caller
        #[ink(message)]
        pub fn admin_function(&self) -> Result<(), Error> {
            if self.env().caller() != self.creator {
                return Err(Error::Unauthorized);
            }
            
            // Admin logic here
            Ok(())
        }

        /// Function that requires minimum payment
        #[ink(message, payable)]
        pub fn paid_function(&self) -> Result<(), Error> {
            const MINIMUM_PAYMENT: Balance = 1_000_000_000_000; // 0.001 token
            
            if self.env().transferred_value() < MINIMUM_PAYMENT {
                return Err(Error::InsufficientPayment);
            }
            
            // Paid function logic here
            Ok(())
        }
    }

    #[derive(scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub struct EnvironmentInfo {
        pub caller: AccountId,
        pub contract_address: AccountId,
        pub transferred_value: Balance,
        pub contract_balance: Balance,
        pub block_number: u32,
        pub block_timestamp: u64,
        pub creation_time: u64,
        pub creator: AccountId,
        pub call_count: u32,
    }
}
```

### Advanced Environmental Patterns

```rust
impl EnvironmentAware {
    /// Rate limiting based on block timestamps
    #[ink(message)]
    pub fn rate_limited_function(&mut self) -> Result<(), Error> {
        const RATE_LIMIT_DURATION: u64 = 60000; // 1 minute in milliseconds
        
        let caller = self.env().caller();
        let current_time = self.env().block_timestamp();
        
        // Check last call time for this caller
        if let Some(last_call_time) = self.last_call_times.get(caller) {
            if current_time - last_call_time < RATE_LIMIT_DURATION {
                return Err(Error::RateLimited);
            }
        }
        
        // Update last call time
        self.last_call_times.insert(caller, &current_time);
        
        // Function logic here
        Ok(())
    }

    /// Block number based lottery
    #[ink(message)]
    pub fn block_lottery(&self) -> bool {
        let block_number = self.env().block_number();
        // Simple lottery: win if block number is divisible by 10
        block_number % 10 == 0
    }

    /// Contract balance management
    #[ink(message)]
    pub fn balance_check(&self) -> BalanceStatus {
        let balance = self.env().balance();
        const LOW_BALANCE_THRESHOLD: Balance = 1_000_000_000_000; // 0.001 token
        const CRITICAL_BALANCE_THRESHOLD: Balance = 100_000_000_000; // 0.0001 token

        if balance < CRITICAL_BALANCE_THRESHOLD {
            BalanceStatus::Critical
        } else if balance < LOW_BALANCE_THRESHOLD {
            BalanceStatus::Low
        } else {
            BalanceStatus::Healthy
        }
    }

    /// Emergency functions based on contract state
    #[ink(message)]
    pub fn emergency_function(&mut self) -> Result<(), Error> {
        // Only allow if contract balance is critically low
        if self.balance_check() != BalanceStatus::Critical {
            return Err(Error::EmergencyConditionNotMet);
        }
        
        // Emergency logic here
        Ok(())
    }
}
```

### Gas Estimation and Optimization

```rust
impl EnvironmentAware {
    /// Gas-aware batch processing
    #[ink(message)]
    pub fn gas_aware_batch_process(&mut self, items: Vec<u32>) -> Result<u32, Error> {
        const GAS_LIMIT_PER_ITEM: u64 = 1000; // Estimated gas per item
        const MAX_GAS_BUDGET: u64 = 50000;    // Maximum gas budget for this function
        
        let max_items = (MAX_GAS_BUDGET / GAS_LIMIT_PER_ITEM) as usize;
        let items_to_process = items.len().min(max_items);
        
        let mut processed = 0;
        for item in items.iter().take(items_to_process) {
            // Process item
            self.process_item(*item)?;
            processed += 1;
        }
        
        Ok(processed)
    }

    /// Weight-based function limits
    #[ink(message)]
    pub fn complex_calculation(&self, complexity: u32) -> Result<u64, Error> {
        // Limit complexity to prevent gas issues
        const MAX_COMPLEXITY: u32 = 1000;
        if complexity > MAX_COMPLEXITY {
            return Err(Error::ComplexityTooHigh);
        }
        
        // Perform calculation with known gas costs
        let mut result = 0u64;
        for i in 0..complexity {
            result = result.wrapping_add(i as u64 * 12345);
        }
        
        Ok(result)
    }
}
```

## Message Testing Patterns

Comprehensive testing ensures your message handlers work correctly under all conditions:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[ink::test]
    fn constructor_validation_works() {
        // Test valid constructor
        let token = FlexibleToken::new(
            1_000_000,
            "TestToken".to_string(),
            "TEST".to_string(),
            18,
        );
        assert!(token.is_ok());

        // Test invalid parameters
        let invalid_token = FlexibleToken::new(
            0, // Invalid total supply
            "TestToken".to_string(),
            "TEST".to_string(),
            18,
        );
        assert_eq!(invalid_token, Err(Error::InvalidParameters));
    }

    #[ink::test]
    fn transfer_works() {
        let mut token = FlexibleToken::new_simple(1000).unwrap();
        let alice = AccountId::from([1; 32]);
        let bob = AccountId::from([2; 32]);

        // Initial balance check
        assert_eq!(token.balance_of(alice), 1000);
        assert_eq!(token.balance_of(bob), 0);

        // Test transfer
        let result = token.transfer(bob, 100);
        assert!(result.is_ok());

        // Verify balances
        assert_eq!(token.balance_of(alice), 900);
        assert_eq!(token.balance_of(bob), 100);
    }

    #[ink::test]
    fn payable_message_works() {
        let mut contract = PayableContract::new();
        let alice = AccountId::from([1; 32]);

        // Simulate payable call
        ink::env::test::set_caller::<ink::env::DefaultEnvironment>(alice);
        ink::env::test::set_value_transferred::<ink::env::DefaultEnvironment>(1000);

        let result = contract.deposit();
        assert!(result.is_ok());
        assert_eq!(contract.deposit_of(alice), 1000);
    }

    #[ink::test]
    fn environment_access_works() {
        let mut contract = EnvironmentAware::new();
        
        // Test environment info
        let info = contract.environment_info();
        assert!(info.block_timestamp > 0);
        assert_eq!(info.call_count, 1);
    }
}
```

## Summary

In this chapter, we've explored the logic layer that brings your contracts to life:

**Constructor Patterns:**
1. **Multiple Constructors**: Providing flexibility for different initialization scenarios
2. **Comprehensive Validation**: Ensuring contracts deploy with valid state
3. **Initialization Strategies**: From minimal to fully-configured deployment options

**Message Design:**
4. **Clear API Design**: Distinguishing between read-only and state-changing operations
5. **Parameter Patterns**: Designing intuitive and safe message interfaces
6. **Error Handling**: Providing comprehensive, actionable error information

**Payable Messages:**
7. **Native Token Integration**: Handling deposits, withdrawals, and payments
8. **Token Sale Patterns**: Building sophisticated purchase mechanisms
9. **Financial Logic**: Implementing safe arithmetic and refund mechanisms

**Environmental Awareness:**
10. **Context Access**: Leveraging blockchain state for smart contract logic
11. **Time-based Logic**: Implementing locks, delays, and scheduling
12. **Gas Management**: Writing gas-aware functions that scale

**Testing Strategies:**
13. **Comprehensive Coverage**: Testing constructors, messages, and error conditions
14. **Environment Simulation**: Testing payable and environment-dependent functions

With solid message and constructor design patterns established, you're ready to explore how contracts communicate with the outside world and each other. In the next chapter, we'll cover events for off-chain communication and cross-contract calls for on-chain interoperability.
