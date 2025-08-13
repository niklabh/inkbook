# Chapter 6: Advanced ink! Patterns and Techniques

As your ink! contracts grow in complexity, you'll need sophisticated patterns and techniques to manage code organization, error handling, access control, and upgradability. This chapter explores advanced patterns that separate hobbyist contracts from production-ready systems used in critical applications.

We'll cover comprehensive error handling strategies, trait-based contract architectures, access control patterns, and contract upgradability techniques. These patterns form the foundation for building maintainable, secure, and scalable smart contract systems.

## Comprehensive Error Handling

Robust error handling is crucial for production contracts. Users need clear feedback about what went wrong, and systems need to handle failures gracefully.

### Structured Error Types

Design error enums that provide clear, actionable information:

```rust
#[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
#[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
pub enum Error {
    // Arithmetic errors
    ArithmeticOverflow,
    ArithmeticUnderflow,
    DivisionByZero,
    
    // Balance and transfer errors
    InsufficientBalance,
    InsufficientAllowance,
    TransferToSelf,
    TransferAmountZero,
    
    // Authorization errors
    Unauthorized,
    NotOwner,
    NotApproved,
    
    // State errors
    ContractPaused,
    ContractFinalized,
    InvalidState,
    
    // Parameter validation errors
    InvalidAddress,
    InvalidAmount,
    InvalidParameters,
    ArrayLengthMismatch,
    
    // Business logic errors
    DeadlineExpired,
    QuotaExceeded,
    RequirementNotMet,
    
    // System errors
    CrossContractCallFailed,
    StorageCorrupted,
    ExternalCallFailed,
}

impl Error {
    /// Get user-friendly error message
    pub fn message(&self) -> &'static str {
        match self {
            Error::ArithmeticOverflow => "Arithmetic operation would overflow",
            Error::ArithmeticUnderflow => "Arithmetic operation would underflow",
            Error::InsufficientBalance => "Account balance is insufficient for this operation",
            Error::Unauthorized => "Account is not authorized to perform this action",
            Error::ContractPaused => "Contract is currently paused",
            Error::InvalidAmount => "Amount must be greater than zero",
            Error::DeadlineExpired => "Operation deadline has passed",
            // ... other error messages
            _ => "Unknown error occurred",
        }
    }

    /// Get error category for logging and monitoring
    pub fn category(&self) -> ErrorCategory {
        match self {
            Error::ArithmeticOverflow | Error::ArithmeticUnderflow | Error::DivisionByZero => {
                ErrorCategory::Arithmetic
            }
            Error::InsufficientBalance | Error::TransferAmountZero => {
                ErrorCategory::Balance
            }
            Error::Unauthorized | Error::NotOwner | Error::NotApproved => {
                ErrorCategory::Authorization
            }
            Error::ContractPaused | Error::InvalidState => {
                ErrorCategory::State
            }
            _ => ErrorCategory::General,
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum ErrorCategory {
    Arithmetic,
    Balance,
    Authorization,
    State,
    Validation,
    System,
    General,
}
```

### Error Context and Propagation

Implement error context to provide debugging information:

```rust
#[ink::contract]
mod advanced_error_handling {
    use super::*;

    #[ink(storage)]
    pub struct AdvancedContract {
        balances: ink::storage::Mapping<AccountId, Balance>,
        paused: bool,
        owner: AccountId,
    }

    impl AdvancedContract {
        #[ink(constructor)]
        pub fn new() -> Self {
            Self {
                balances: ink::storage::Mapping::default(),
                paused: false,
                owner: Self::env().caller(),
            }
        }

        /// Transfer with comprehensive error handling
        #[ink(message)]
        pub fn transfer(&mut self, to: AccountId, amount: Balance) -> Result<(), Error> {
            // Pre-condition checks with specific errors
            self.ensure_not_paused()?;
            self.validate_transfer_params(to, amount)?;
            
            let from = self.env().caller();
            
            // Execute transfer with detailed error context
            self.execute_transfer(from, to, amount)
                .map_err(|e| self.add_context(e, "transfer", &[("from", &from), ("to", &to), ("amount", &amount)]))
        }

        /// Batch transfer with partial success handling
        #[ink(message)]
        pub fn batch_transfer(
            &mut self,
            recipients: Vec<(AccountId, Balance)>,
        ) -> Result<BatchResult, Error> {
            self.ensure_not_paused()?;
            
            if recipients.len() > 100 {
                return Err(Error::InvalidParameters);
            }

            let mut results = Vec::new();
            let mut total_successful = 0;
            let from = self.env().caller();

            for (i, (to, amount)) in recipients.iter().enumerate() {
                match self.execute_transfer(from, *to, *amount) {
                    Ok(()) => {
                        results.push(TransferResult::Success);
                        total_successful += 1;
                    }
                    Err(e) => {
                        results.push(TransferResult::Failed(e));
                        // Continue with remaining transfers
                    }
                }
            }

            Ok(BatchResult {
                total_attempted: recipients.len() as u32,
                total_successful,
                individual_results: results,
            })
        }

        /// Internal transfer with detailed error tracking
        fn execute_transfer(
            &mut self,
            from: AccountId,
            to: AccountId,
            amount: Balance,
        ) -> Result<(), Error> {
            // Get balances with error context
            let from_balance = self.balances.get(from).unwrap_or(0);
            let to_balance = self.balances.get(to).unwrap_or(0);

            // Validate sufficient balance
            if from_balance < amount {
                return Err(Error::InsufficientBalance);
            }

            // Safe arithmetic with overflow protection
            let new_from_balance = from_balance
                .checked_sub(amount)
                .ok_or(Error::ArithmeticUnderflow)?;

            let new_to_balance = to_balance
                .checked_add(amount)
                .ok_or(Error::ArithmeticOverflow)?;

            // Update balances
            self.balances.insert(from, &new_from_balance);
            self.balances.insert(to, &new_to_balance);

            // Emit success event
            self.env().emit_event(Transfer {
                from: Some(from),
                to: Some(to),
                value: amount,
            });

            Ok(())
        }

        /// Validation helpers with specific error types
        fn ensure_not_paused(&self) -> Result<(), Error> {
            if self.paused {
                Err(Error::ContractPaused)
            } else {
                Ok(())
            }
        }

        fn validate_transfer_params(&self, to: AccountId, amount: Balance) -> Result<(), Error> {
            if amount == 0 {
                return Err(Error::TransferAmountZero);
            }

            if to == AccountId::from([0; 32]) {
                return Err(Error::InvalidAddress);
            }

            let from = self.env().caller();
            if from == to {
                return Err(Error::TransferToSelf);
            }

            Ok(())
        }

        /// Add context information to errors (for debugging)
        fn add_context(
            &self,
            error: Error,
            operation: &str,
            params: &[(&str, &dyn core::fmt::Debug)],
        ) -> Error {
            // In production, you might log this information
            // For now, we just return the original error
            error
        }
    }

    /// Result types for complex operations
    #[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub struct BatchResult {
        pub total_attempted: u32,
        pub total_successful: u32,
        pub individual_results: Vec<TransferResult>,
    }

    #[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub enum TransferResult {
        Success,
        Failed(Error),
    }
}
```

### Recovery and Fallback Mechanisms

Implement recovery patterns for handling failures gracefully:

```rust
impl AdvancedContract {
    /// Emergency pause mechanism
    #[ink(message)]
    pub fn emergency_pause(&mut self) -> Result<(), Error> {
        if self.env().caller() != self.owner {
            return Err(Error::NotOwner);
        }

        self.paused = true;

        self.env().emit_event(EmergencyPause {
            triggered_by: self.env().caller(),
            timestamp: self.env().block_timestamp(),
        });

        Ok(())
    }

    /// Recovery function with validation
    #[ink(message)]
    pub fn recover_from_emergency(&mut self) -> Result<(), Error> {
        if self.env().caller() != self.owner {
            return Err(Error::NotOwner);
        }

        if !self.paused {
            return Err(Error::InvalidState);
        }

        // Perform recovery validations
        self.validate_contract_state()?;

        self.paused = false;

        self.env().emit_event(EmergencyRecovery {
            executed_by: self.env().caller(),
            timestamp: self.env().block_timestamp(),
        });

        Ok(())
    }

    /// Validate contract invariants
    fn validate_contract_state(&self) -> Result<(), Error> {
        // Implement contract-specific validation logic
        // For example, check that total balances don't exceed total supply
        Ok(())
    }

    /// Graceful degradation - limited functionality during issues
    #[ink(message)]
    pub fn safe_mode_transfer(&mut self, to: AccountId, amount: Balance) -> Result<(), Error> {
        // Only allow small transfers in safe mode
        const SAFE_MODE_LIMIT: Balance = 1000;
        
        if amount > SAFE_MODE_LIMIT {
            return Err(Error::QuotaExceeded);
        }

        // Use more conservative validation
        self.validate_transfer_params(to, amount)?;
        
        let from = self.env().caller();
        let from_balance = self.balances.get(from).unwrap_or(0);
        
        if from_balance < amount {
            return Err(Error::InsufficientBalance);
        }

        // Execute with extra safety checks
        self.execute_transfer(from, to, amount)
    }
}
```

## Trait-Based Contract Architecture

Use Rust traits to create modular, reusable contract interfaces and implementations.

### Standard Interface Definitions

Define common interfaces as traits:

```rust
/// Standard token interface
#[ink::trait_definition]
pub trait PSP22 {
    /// Returns the total token supply.
    #[ink(message)]
    fn total_supply(&self) -> Balance;

    /// Returns the account balance for the specified `owner`.
    #[ink(message)]
    fn balance_of(&self, owner: AccountId) -> Balance;

    /// Returns the amount which `spender` is still allowed to withdraw from `owner`.
    #[ink(message)]
    fn allowance(&self, owner: AccountId, spender: AccountId) -> Balance;

    /// Transfers `value` amount of tokens from the caller's account to account `to`.
    #[ink(message)]
    fn transfer(&mut self, to: AccountId, value: Balance) -> Result<(), PSP22Error>;

    /// Allows `spender` to withdraw from the caller's account multiple times.
    #[ink(message)]
    fn approve(&mut self, spender: AccountId, value: Balance) -> Result<(), PSP22Error>;

    /// Transfers `value` tokens on behalf of `from` to the account `to`.
    #[ink(message)]
    fn transfer_from(&mut self, from: AccountId, to: AccountId, value: Balance) -> Result<(), PSP22Error>;
}

/// Access control interface
#[ink::trait_definition]
pub trait AccessControl {
    /// Returns `true` if `account` has been granted `role`.
    #[ink(message)]
    fn has_role(&self, role: RoleType, account: AccountId) -> bool;

    /// Grants `role` to `account`.
    #[ink(message)]
    fn grant_role(&mut self, role: RoleType, account: AccountId) -> Result<(), AccessControlError>;

    /// Revokes `role` from `account`.
    #[ink(message)]
    fn revoke_role(&mut self, role: RoleType, account: AccountId) -> Result<(), AccessControlError>;

    /// Returns the admin role that controls `role`.
    #[ink(message)]
    fn get_role_admin(&self, role: RoleType) -> RoleType;
}

/// Pausable contract interface
#[ink::trait_definition]
pub trait Pausable {
    /// Returns `true` if the contract is paused.
    #[ink(message)]
    fn paused(&self) -> bool;

    /// Pauses all contract operations.
    #[ink(message)]
    fn pause(&mut self) -> Result<(), PausableError>;

    /// Unpauses all contract operations.
    #[ink(message)]
    fn unpause(&mut self) -> Result<(), PausableError>;
}
```

### Modular Contract Implementation

Implement contracts using composition of traits:

```rust
#[ink::contract]
mod modular_token {
    use super::*;

    #[ink(storage)]
    pub struct ModularToken {
        // PSP22 data
        total_supply: Balance,
        balances: ink::storage::Mapping<AccountId, Balance>,
        allowances: ink::storage::Mapping<(AccountId, AccountId), Balance>,
        
        // Access control data
        roles: ink::storage::Mapping<(RoleType, AccountId), ()>,
        role_admins: ink::storage::Mapping<RoleType, RoleType>,
        
        // Pausable data
        paused: bool,
        
        // Token metadata
        name: String,
        symbol: String,
        decimals: u8,
    }

    // Role definitions
    const DEFAULT_ADMIN_ROLE: RoleType = 0;
    const MINTER_ROLE: RoleType = 1;
    const PAUSER_ROLE: RoleType = 2;

    impl ModularToken {
        #[ink(constructor)]
        pub fn new(
            total_supply: Balance,
            name: String,
            symbol: String,
            decimals: u8,
        ) -> Self {
            let caller = Self::env().caller();
            let mut instance = Self {
                total_supply,
                balances: ink::storage::Mapping::default(),
                allowances: ink::storage::Mapping::default(),
                roles: ink::storage::Mapping::default(),
                role_admins: ink::storage::Mapping::default(),
                paused: false,
                name,
                symbol,
                decimals,
            };

            // Set up initial balance
            instance.balances.insert(caller, &total_supply);
            
            // Set up default admin role
            instance.roles.insert((DEFAULT_ADMIN_ROLE, caller), &());
            instance.role_admins.insert(MINTER_ROLE, &DEFAULT_ADMIN_ROLE);
            instance.role_admins.insert(PAUSER_ROLE, &DEFAULT_ADMIN_ROLE);

            instance
        }

        /// Mint tokens (requires MINTER_ROLE)
        #[ink(message)]
        pub fn mint(&mut self, to: AccountId, amount: Balance) -> Result<(), Error> {
            let caller = self.env().caller();
            
            // Check permissions
            if !self.has_role(MINTER_ROLE, caller) {
                return Err(Error::Unauthorized);
            }

            // Check if paused
            if self.paused() {
                return Err(Error::ContractPaused);
            }

            // Mint logic
            let to_balance = self.balances.get(to).unwrap_or(0);
            let new_balance = to_balance.checked_add(amount)
                .ok_or(Error::ArithmeticOverflow)?;
            
            self.balances.insert(to, &new_balance);
            self.total_supply = self.total_supply.checked_add(amount)
                .ok_or(Error::ArithmeticOverflow)?;

            // Emit transfer event (from None = mint)
            self.env().emit_event(Transfer {
                from: None,
                to: Some(to),
                value: amount,
            });

            Ok(())
        }

        /// Burn tokens from caller's account
        #[ink(message)]
        pub fn burn(&mut self, amount: Balance) -> Result<(), Error> {
            if self.paused() {
                return Err(Error::ContractPaused);
            }

            let caller = self.env().caller();
            let caller_balance = self.balances.get(caller).unwrap_or(0);
            
            if caller_balance < amount {
                return Err(Error::InsufficientBalance);
            }

            let new_balance = caller_balance - amount;
            self.balances.insert(caller, &new_balance);
            self.total_supply -= amount;

            // Emit transfer event (to None = burn)
            self.env().emit_event(Transfer {
                from: Some(caller),
                to: None,
                value: amount,
            });

            Ok(())
        }
    }

    // Implement PSP22 trait
    impl PSP22 for ModularToken {
        #[ink(message)]
        fn total_supply(&self) -> Balance {
            self.total_supply
        }

        #[ink(message)]
        fn balance_of(&self, owner: AccountId) -> Balance {
            self.balances.get(owner).unwrap_or(0)
        }

        #[ink(message)]
        fn allowance(&self, owner: AccountId, spender: AccountId) -> Balance {
            self.allowances.get((owner, spender)).unwrap_or(0)
        }

        #[ink(message)]
        fn transfer(&mut self, to: AccountId, value: Balance) -> Result<(), PSP22Error> {
            if self.paused() {
                return Err(PSP22Error::Custom("Contract is paused".into()));
            }

            let from = self.env().caller();
            self.internal_transfer(from, to, value)
        }

        #[ink(message)]
        fn approve(&mut self, spender: AccountId, value: Balance) -> Result<(), PSP22Error> {
            if self.paused() {
                return Err(PSP22Error::Custom("Contract is paused".into()));
            }

            let owner = self.env().caller();
            self.allowances.insert((owner, spender), &value);

            self.env().emit_event(Approval {
                owner,
                spender,
                value,
            });

            Ok(())
        }

        #[ink(message)]
        fn transfer_from(
            &mut self,
            from: AccountId,
            to: AccountId,
            value: Balance,
        ) -> Result<(), PSP22Error> {
            if self.paused() {
                return Err(PSP22Error::Custom("Contract is paused".into()));
            }

            let caller = self.env().caller();
            let allowance = self.allowance(from, caller);
            
            if allowance < value {
                return Err(PSP22Error::InsufficientAllowance);
            }

            // Update allowance
            self.allowances.insert((from, caller), &(allowance - value));
            
            // Execute transfer
            self.internal_transfer(from, to, value)
        }
    }

    // Implement AccessControl trait
    impl AccessControl for ModularToken {
        #[ink(message)]
        fn has_role(&self, role: RoleType, account: AccountId) -> bool {
            self.roles.contains((role, account))
        }

        #[ink(message)]
        fn grant_role(&mut self, role: RoleType, account: AccountId) -> Result<(), AccessControlError> {
            let caller = self.env().caller();
            let admin_role = self.get_role_admin(role);
            
            if !self.has_role(admin_role, caller) {
                return Err(AccessControlError::MissingRole);
            }

            self.roles.insert((role, account), &());

            self.env().emit_event(RoleGranted {
                role,
                account,
                sender: caller,
            });

            Ok(())
        }

        #[ink(message)]
        fn revoke_role(&mut self, role: RoleType, account: AccountId) -> Result<(), AccessControlError> {
            let caller = self.env().caller();
            let admin_role = self.get_role_admin(role);
            
            if !self.has_role(admin_role, caller) {
                return Err(AccessControlError::MissingRole);
            }

            self.roles.remove((role, account));

            self.env().emit_event(RoleRevoked {
                role,
                account,
                sender: caller,
            });

            Ok(())
        }

        #[ink(message)]
        fn get_role_admin(&self, role: RoleType) -> RoleType {
            self.role_admins.get(role).unwrap_or(DEFAULT_ADMIN_ROLE)
        }
    }

    // Implement Pausable trait
    impl Pausable for ModularToken {
        #[ink(message)]
        fn paused(&self) -> bool {
            self.paused
        }

        #[ink(message)]
        fn pause(&mut self) -> Result<(), PausableError> {
            let caller = self.env().caller();
            
            if !self.has_role(PAUSER_ROLE, caller) {
                return Err(PausableError::CallerNotPauser);
            }

            if self.paused {
                return Err(PausableError::AlreadyPaused);
            }

            self.paused = true;

            self.env().emit_event(Paused { account: caller });

            Ok(())
        }

        #[ink(message)]
        fn unpause(&mut self) -> Result<(), PausableError> {
            let caller = self.env().caller();
            
            if !self.has_role(PAUSER_ROLE, caller) {
                return Err(PausableError::CallerNotPauser);
            }

            if !self.paused {
                return Err(PausableError::NotPaused);
            }

            self.paused = false;

            self.env().emit_event(Unpaused { account: caller });

            Ok(())
        }
    }

    // Internal helper functions
    impl ModularToken {
        fn internal_transfer(
            &mut self,
            from: AccountId,
            to: AccountId,
            value: Balance,
        ) -> Result<(), PSP22Error> {
            let from_balance = self.balance_of(from);
            
            if from_balance < value {
                return Err(PSP22Error::InsufficientBalance);
            }

            let to_balance = self.balance_of(to);
            
            self.balances.insert(from, &(from_balance - value));
            self.balances.insert(to, &(to_balance + value));

            self.env().emit_event(Transfer {
                from: Some(from),
                to: Some(to),
                value,
            });

            Ok(())
        }
    }
}
```

### Extensible Architecture with Hooks

Implement hook patterns for extensible contracts:

```rust
#[ink::contract]
mod extensible_contract {
    #[ink(storage)]
    pub struct ExtensibleContract {
        // Core state
        balances: ink::storage::Mapping<AccountId, Balance>,
        
        // Hook configurations
        transfer_hooks: Vec<AccountId>, // Contracts to call on transfers
        mint_hooks: Vec<AccountId>,     // Contracts to call on mints
        
        // Hook settings
        max_hooks: u8,
        hook_gas_limit: u64,
    }

    impl ExtensibleContract {
        #[ink(constructor)]
        pub fn new() -> Self {
            Self {
                balances: ink::storage::Mapping::default(),
                transfer_hooks: Vec::new(),
                mint_hooks: Vec::new(),
                max_hooks: 10,
                hook_gas_limit: 10_000,
            }
        }

        /// Transfer with hooks
        #[ink(message)]
        pub fn transfer(&mut self, to: AccountId, amount: Balance) -> Result<(), Error> {
            let from = self.env().caller();
            
            // Execute pre-transfer hooks
            self.execute_transfer_hooks(HookType::PreTransfer, from, to, amount)?;
            
            // Perform the actual transfer
            self.internal_transfer(from, to, amount)?;
            
            // Execute post-transfer hooks
            self.execute_transfer_hooks(HookType::PostTransfer, from, to, amount)?;
            
            Ok(())
        }

        /// Add a transfer hook contract
        #[ink(message)]
        pub fn add_transfer_hook(&mut self, hook_contract: AccountId) -> Result<(), Error> {
            // Only owner can add hooks (authorization check omitted)
            
            if self.transfer_hooks.len() >= self.max_hooks as usize {
                return Err(Error::QuotaExceeded);
            }

            if self.transfer_hooks.contains(&hook_contract) {
                return Err(Error::InvalidParameters);
            }

            self.transfer_hooks.push(hook_contract);
            Ok(())
        }

        /// Execute transfer hooks safely
        fn execute_transfer_hooks(
            &self,
            hook_type: HookType,
            from: AccountId,
            to: AccountId,
            amount: Balance,
        ) -> Result<(), Error> {
            for hook_contract in &self.transfer_hooks {
                // Call hook with limited gas and error isolation
                let result = self.call_transfer_hook(*hook_contract, hook_type, from, to, amount);
                
                // Log hook failures but don't fail the transaction
                if result.is_err() {
                    self.env().emit_event(HookFailed {
                        hook_contract: *hook_contract,
                        hook_type,
                        reason: "Hook execution failed".into(),
                    });
                }
            }
            
            Ok(())
        }

        /// Safe hook call with gas limits
        fn call_transfer_hook(
            &self,
            hook_contract: AccountId,
            hook_type: HookType,
            from: AccountId,
            to: AccountId,
            amount: Balance,
        ) -> Result<(), Error> {
            // Build cross-contract call with limited gas
            let _result = ink::env::call::build_call::<ink::env::DefaultEnvironment>()
                .call(hook_contract)
                .gas_limit(self.hook_gas_limit)
                .transferred_value(0)
                .exec_input(
                    ink::env::call::ExecutionInput::new(
                        // Hook interface selector (simplified)
                        ink::env::call::Selector::new([0x12, 0x34, 0x56, 0x78])
                    )
                    .push_arg(hook_type)
                    .push_arg(from)
                    .push_arg(to)
                    .push_arg(amount)
                )
                .returns::<()>()
                .try_invoke();

            // Handle result appropriately
            Ok(())
        }

        fn internal_transfer(&mut self, from: AccountId, to: AccountId, amount: Balance) -> Result<(), Error> {
            let from_balance = self.balances.get(from).unwrap_or(0);
            
            if from_balance < amount {
                return Err(Error::InsufficientBalance);
            }

            let to_balance = self.balances.get(to).unwrap_or(0);
            
            self.balances.insert(from, &(from_balance - amount));
            self.balances.insert(to, &(to_balance + amount));
            
            Ok(())
        }
    }

    #[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub enum HookType {
        PreTransfer,
        PostTransfer,
        PreMint,
        PostMint,
    }
}
```

## Standard Library Usage in no_std

Learn to effectively use Rust's core libraries in the constrained no_std environment:

```rust
#[ink::contract]
mod stdlib_usage {
    // Import commonly used collections
    use ink::prelude::{
        vec::Vec,
        collections::{BTreeMap, BTreeSet},
        string::String,
    };

    #[ink(storage)]
    pub struct StdLibContract {
        // Vector for ordered data
        transaction_history: Vec<Transaction>,
        
        // BTreeMap for sorted key-value pairs
        user_scores: BTreeMap<AccountId, u64>,
        
        // BTreeSet for unique collections
        verified_users: BTreeSet<AccountId>,
        
        // String for text data
        contract_metadata: String,
    }

    #[derive(Debug, Clone, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub struct Transaction {
        pub from: AccountId,
        pub to: AccountId,
        pub amount: Balance,
        pub timestamp: u64,
    }

    impl StdLibContract {
        #[ink(constructor)]
        pub fn new(metadata: String) -> Self {
            Self {
                transaction_history: Vec::new(),
                user_scores: BTreeMap::new(),
                verified_users: BTreeSet::new(),
                contract_metadata: metadata,
            }
        }

        /// Demonstrate Vec usage for transaction history
        #[ink(message)]
        pub fn record_transaction(&mut self, to: AccountId, amount: Balance) -> Result<(), Error> {
            let from = self.env().caller();
            let timestamp = self.env().block_timestamp();
            
            let transaction = Transaction {
                from,
                to,
                amount,
                timestamp,
            };

            // Add to history (be careful with size in production)
            self.transaction_history.push(transaction);
            
            // Limit history size to prevent storage bloat
            const MAX_HISTORY: usize = 1000;
            if self.transaction_history.len() > MAX_HISTORY {
                self.transaction_history.remove(0); // Remove oldest
            }

            Ok(())
        }

        /// Get recent transactions with pagination
        #[ink(message)]
        pub fn get_recent_transactions(&self, count: u32) -> Vec<Transaction> {
            let count = count.min(100) as usize; // Limit response size
            let len = self.transaction_history.len();
            
            if len <= count {
                self.transaction_history.clone()
            } else {
                self.transaction_history[len - count..].to_vec()
            }
        }

        /// Demonstrate BTreeMap usage for scoring
        #[ink(message)]
        pub fn update_user_score(&mut self, user: AccountId, score: u64) -> Result<(), Error> {
            self.user_scores.insert(user, score);
            Ok(())
        }

        /// Get top scorers using BTreeMap iteration
        #[ink(message)]
        pub fn get_top_scorers(&self, count: u32) -> Vec<(AccountId, u64)> {
            let count = count.min(50) as usize;
            
            // BTreeMap keeps entries sorted by key, but we want sorted by value
            let mut scores: Vec<_> = self.user_scores.iter().collect();
            scores.sort_by(|a, b| b.1.cmp(a.1)); // Sort by score descending
            
            scores.into_iter()
                .take(count)
                .map(|(account, score)| (*account, *score))
                .collect()
        }

        /// Demonstrate BTreeSet usage for verification
        #[ink(message)]
        pub fn verify_user(&mut self, user: AccountId) -> Result<(), Error> {
            // Only admin can verify (check omitted)
            self.verified_users.insert(user);
            Ok(())
        }

        #[ink(message)]
        pub fn is_verified(&self, user: AccountId) -> bool {
            self.verified_users.contains(&user)
        }

        /// Get all verified users
        #[ink(message)]
        pub fn get_verified_users(&self) -> Vec<AccountId> {
            self.verified_users.iter().cloned().collect()
        }

        /// String manipulation examples
        #[ink(message)]
        pub fn update_metadata(&mut self, new_metadata: String) -> Result<(), Error> {
            // Validate metadata size
            if new_metadata.len() > 1000 {
                return Err(Error::InvalidParameters);
            }

            // String operations work in no_std
            let mut combined = self.contract_metadata.clone();
            combined.push_str(" | ");
            combined.push_str(&new_metadata);
            
            self.contract_metadata = combined;
            Ok(())
        }

        /// Advanced collection operations
        #[ink(message)]
        pub fn get_user_stats(&self, user: AccountId) -> UserStats {
            let score = self.user_scores.get(&user).copied().unwrap_or(0);
            let is_verified = self.verified_users.contains(&user);
            
            // Count user's transactions
            let transaction_count = self.transaction_history
                .iter()
                .filter(|tx| tx.from == user || tx.to == user)
                .count() as u32;

            UserStats {
                score,
                is_verified,
                transaction_count,
            }
        }

        /// Batch operations with iterators
        #[ink(message)]
        pub fn batch_verify_users(&mut self, users: Vec<AccountId>) -> Result<u32, Error> {
            if users.len() > 100 {
                return Err(Error::InvalidParameters);
            }

            let mut verified_count = 0;
            
            for user in users {
                if self.verified_users.insert(user) {
                    verified_count += 1; // insert returns true if newly inserted
                }
            }

            Ok(verified_count)
        }
    }

    #[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub struct UserStats {
        pub score: u64,
        pub is_verified: bool,
        pub transaction_count: u32,
    }
}
```

## Contract Upgradability

Implement upgradeable contract patterns while maintaining security and data integrity:

### Proxy Pattern Implementation

```rust
/// Implementation contract interface
#[ink::trait_definition]
pub trait Implementation {
    #[ink(message)]
    fn version(&self) -> u32;
    
    #[ink(message)]
    fn initialize(&mut self, data: Vec<u8>) -> Result<(), Error>;
}

#[ink::contract]
mod upgradeable_proxy {
    use super::Implementation;

    #[ink(storage)]
    pub struct UpgradeableProxy {
        /// Current implementation contract address
        implementation: AccountId,
        
        /// Contract admin who can upgrade
        admin: AccountId,
        
        /// Current version for tracking
        version: u32,
        
        /// Upgrade history for auditing
        upgrade_history: Vec<UpgradeRecord>,
        
        /// Emergency controls
        upgrade_delay: u64,  // Minimum delay between upgrades
        last_upgrade: u64,   // Timestamp of last upgrade
        emergency_pause: bool,
    }

    #[derive(Debug, Clone, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub struct UpgradeRecord {
        pub from_implementation: AccountId,
        pub to_implementation: AccountId,
        pub timestamp: u64,
        pub version: u32,
    }

    impl UpgradeableProxy {
        #[ink(constructor)]
        pub fn new(implementation: AccountId, admin: AccountId) -> Self {
            Self {
                implementation,
                admin,
                version: 1,
                upgrade_history: Vec::new(),
                upgrade_delay: 86400000, // 24 hours in milliseconds
                last_upgrade: 0,
                emergency_pause: false,
            }
        }

        /// Propose an upgrade (with timelock)
        #[ink(message)]
        pub fn propose_upgrade(&mut self, new_implementation: AccountId) -> Result<(), Error> {
            self.ensure_admin()?;
            
            if self.emergency_pause {
                return Err(Error::ContractPaused);
            }

            // Validate new implementation
            let new_impl: ink::contract_ref!(Implementation) = new_implementation.into();
            let new_version = new_impl.version();
            
            if new_version <= self.version {
                return Err(Error::InvalidVersion);
            }

            // Check upgrade delay
            let current_time = self.env().block_timestamp();
            if current_time - self.last_upgrade < self.upgrade_delay {
                return Err(Error::UpgradeTooSoon);
            }

            // Record the upgrade
            let upgrade_record = UpgradeRecord {
                from_implementation: self.implementation,
                to_implementation: new_implementation,
                timestamp: current_time,
                version: new_version,
            };

            self.upgrade_history.push(upgrade_record);
            
            // Update implementation
            self.implementation = new_implementation;
            self.version = new_version;
            self.last_upgrade = current_time;

            self.env().emit_event(UpgradeProposed {
                old_implementation: self.implementation,
                new_implementation,
                new_version,
                timestamp: current_time,
            });

            Ok(())
        }

        /// Emergency upgrade (bypasses timelock)
        #[ink(message)]
        pub fn emergency_upgrade(&mut self, new_implementation: AccountId) -> Result<(), Error> {
            self.ensure_admin()?;
            
            // Validate emergency conditions
            if !self.emergency_pause {
                return Err(Error::NotInEmergency);
            }

            // Validate new implementation
            let new_impl: ink::contract_ref!(Implementation) = new_implementation.into();
            let new_version = new_impl.version();

            // Emergency upgrades can be to any version (including downgrades)
            
            // Update implementation immediately
            let old_implementation = self.implementation;
            self.implementation = new_implementation;
            self.version = new_version;

            self.env().emit_event(EmergencyUpgrade {
                old_implementation,
                new_implementation,
                new_version,
                timestamp: self.env().block_timestamp(),
            });

            Ok(())
        }

        /// Delegate calls to current implementation
        #[ink(message)]
        pub fn delegate_call(&self, selector: [u8; 4], input: Vec<u8>) -> Result<Vec<u8>, Error> {
            if self.emergency_pause {
                return Err(Error::ContractPaused);
            }

            let result = ink::env::call::build_call::<ink::env::DefaultEnvironment>()
                .call(self.implementation)
                .gas_limit(0) // Use remaining gas
                .transferred_value(self.env().transferred_value())
                .exec_input(
                    ink::env::call::ExecutionInput::new(
                        ink::env::call::Selector::new(selector)
                    ).push_arg(input)
                )
                .returns::<Vec<u8>>()
                .try_invoke();

            match result {
                Ok(Ok(data)) => Ok(data),
                Ok(Err(_)) => Err(Error::CallReverted),
                Err(_) => Err(Error::CallFailed),
            }
        }

        /// Admin controls
        #[ink(message)]
        pub fn transfer_admin(&mut self, new_admin: AccountId) -> Result<(), Error> {
            self.ensure_admin()?;
            
            self.admin = new_admin;
            
            self.env().emit_event(AdminTransferred {
                old_admin: self.env().caller(),
                new_admin,
                timestamp: self.env().block_timestamp(),
            });
            
            Ok(())
        }

        #[ink(message)]
        pub fn set_upgrade_delay(&mut self, new_delay: u64) -> Result<(), Error> {
            self.ensure_admin()?;
            
            // Reasonable bounds on upgrade delay
            if new_delay < 3600000 || new_delay > 2592000000 { // 1 hour to 30 days
                return Err(Error::InvalidParameters);
            }
            
            self.upgrade_delay = new_delay;
            Ok(())
        }

        #[ink(message)]
        pub fn emergency_pause(&mut self) -> Result<(), Error> {
            self.ensure_admin()?;
            self.emergency_pause = true;
            
            self.env().emit_event(EmergencyPaused {
                timestamp: self.env().block_timestamp(),
            });
            
            Ok(())
        }

        #[ink(message)]
        pub fn emergency_unpause(&mut self) -> Result<(), Error> {
            self.ensure_admin()?;
            self.emergency_pause = false;
            
            self.env().emit_event(EmergencyUnpaused {
                timestamp: self.env().block_timestamp(),
            });
            
            Ok(())
        }

        /// View functions
        #[ink(message)]
        pub fn get_implementation(&self) -> AccountId {
            self.implementation
        }

        #[ink(message)]
        pub fn get_admin(&self) -> AccountId {
            self.admin
        }

        #[ink(message)]
        pub fn get_version(&self) -> u32 {
            self.version
        }

        #[ink(message)]
        pub fn get_upgrade_history(&self) -> Vec<UpgradeRecord> {
            self.upgrade_history.clone()
        }

        /// Helper functions
        fn ensure_admin(&self) -> Result<(), Error> {
            if self.env().caller() != self.admin {
                Err(Error::Unauthorized)
            } else {
                Ok(())
            }
        }
    }

    /// Events for upgrade tracking
    #[ink(event)]
    pub struct UpgradeProposed {
        #[ink(topic)]
        old_implementation: AccountId,
        #[ink(topic)]
        new_implementation: AccountId,
        new_version: u32,
        timestamp: u64,
    }

    #[ink(event)]
    pub struct EmergencyUpgrade {
        #[ink(topic)]
        old_implementation: AccountId,
        #[ink(topic)]
        new_implementation: AccountId,
        new_version: u32,
        timestamp: u64,
    }

    #[ink(event)]
    pub struct AdminTransferred {
        #[ink(topic)]
        old_admin: AccountId,
        #[ink(topic)]
        new_admin: AccountId,
        timestamp: u64,
    }
}
```

### Data Migration Strategies

```rust
#[ink::contract]
mod migrateable_storage {
    #[ink(storage)]
    pub struct MigrateableStorage {
        /// Version of the storage layout
        storage_version: u32,
        
        /// Data that might need migration
        user_data: ink::storage::Mapping<AccountId, UserDataV2>,
        
        /// Migration state tracking
        migration_status: MigrationStatus,
        migration_progress: u32,
        
        /// Fallback storage for emergency recovery
        backup_data: ink::storage::Lazy<Vec<u8>>,
    }

    #[derive(Debug, Clone, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub enum MigrationStatus {
        NotRequired,
        Required,
        InProgress,
        Completed,
        Failed,
    }

    /// Version 1 of user data (legacy)
    #[derive(Debug, Clone, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub struct UserDataV1 {
        pub balance: Balance,
        pub last_activity: u64,
    }

    /// Version 2 of user data (current)
    #[derive(Debug, Clone, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub struct UserDataV2 {
        pub balance: Balance,
        pub last_activity: u64,
        pub verification_level: u8,
        pub metadata: Vec<u8>,
    }

    impl MigrateableStorage {
        #[ink(constructor)]
        pub fn new() -> Self {
            Self {
                storage_version: 2, // Current version
                user_data: ink::storage::Mapping::default(),
                migration_status: MigrationStatus::NotRequired,
                migration_progress: 0,
                backup_data: ink::storage::Lazy::new(),
            }
        }

        /// Check if migration is needed
        #[ink(message)]
        pub fn check_migration_needed(&mut self) -> MigrationStatus {
            if self.storage_version < 2 {
                self.migration_status = MigrationStatus::Required;
            }
            self.migration_status.clone()
        }

        /// Start data migration process
        #[ink(message)]
        pub fn start_migration(&mut self) -> Result<(), Error> {
            // Only admin can start migration
            self.ensure_admin()?;
            
            if self.migration_status != MigrationStatus::Required {
                return Err(Error::MigrationNotNeeded);
            }

            // Create backup before migration
            self.create_backup()?;
            
            self.migration_status = MigrationStatus::InProgress;
            self.migration_progress = 0;

            self.env().emit_event(MigrationStarted {
                from_version: self.storage_version,
                to_version: 2,
                timestamp: self.env().block_timestamp(),
            });

            Ok(())
        }

        /// Migrate user data in batches
        #[ink(message)]
        pub fn migrate_batch(&mut self, user_accounts: Vec<AccountId>) -> Result<u32, Error> {
            if self.migration_status != MigrationStatus::InProgress {
                return Err(Error::MigrationNotInProgress);
            }

            let mut migrated_count = 0;
            
            for account in user_accounts.iter().take(50) { // Limit batch size
                if let Some(old_data) = self.get_legacy_user_data(*account) {
                    let new_data = self.migrate_user_data_v1_to_v2(old_data);
                    self.user_data.insert(*account, &new_data);
                    migrated_count += 1;
                }
            }

            self.migration_progress += migrated_count;

            Ok(migrated_count)
        }

        /// Complete migration
        #[ink(message)]
        pub fn complete_migration(&mut self) -> Result<(), Error> {
            self.ensure_admin()?;
            
            if self.migration_status != MigrationStatus::InProgress {
                return Err(Error::MigrationNotInProgress);
            }

            // Update storage version
            self.storage_version = 2;
            self.migration_status = MigrationStatus::Completed;

            self.env().emit_event(MigrationCompleted {
                migrated_records: self.migration_progress,
                timestamp: self.env().block_timestamp(),
            });

            Ok(())
        }

        /// Emergency rollback
        #[ink(message)]
        pub fn emergency_rollback(&mut self) -> Result<(), Error> {
            self.ensure_admin()?;
            
            if self.migration_status == MigrationStatus::Failed {
                // Restore from backup
                if let Some(backup) = self.backup_data.get() {
                    self.restore_from_backup(backup)?;
                }
                
                self.migration_status = MigrationStatus::NotRequired;
            }

            Ok(())
        }

        /// Helper functions for migration
        fn migrate_user_data_v1_to_v2(&self, v1_data: UserDataV1) -> UserDataV2 {
            UserDataV2 {
                balance: v1_data.balance,
                last_activity: v1_data.last_activity,
                verification_level: 0, // Default for migrated users
                metadata: Vec::new(),  // Empty metadata for migrated users
            }
        }

        fn get_legacy_user_data(&self, _account: AccountId) -> Option<UserDataV1> {
            // In practice, this would read from legacy storage format
            None
        }

        fn create_backup(&mut self) -> Result<(), Error> {
            // Create backup of current state
            let backup_data = self.serialize_current_state();
            self.backup_data.set(&backup_data);
            Ok(())
        }

        fn serialize_current_state(&self) -> Vec<u8> {
            // Serialize critical state for backup
            Vec::new() // Placeholder
        }

        fn restore_from_backup(&mut self, _backup: Vec<u8>) -> Result<(), Error> {
            // Restore state from backup
            Ok(())
        }

        fn ensure_admin(&self) -> Result<(), Error> {
            // Admin check implementation
            Ok(())
        }
    }
}
```

## Summary

In this chapter, we've explored advanced patterns that elevate ink! contracts to production quality:

**Comprehensive Error Handling:**
1. **Structured Error Types**: Clear, categorized errors with user-friendly messages
2. **Error Context**: Adding debugging information and propagation strategies
3. **Recovery Mechanisms**: Emergency controls and graceful degradation patterns

**Trait-Based Architecture:**
4. **Standard Interfaces**: Defining reusable contract interfaces with traits
5. **Modular Implementation**: Composing complex contracts from trait implementations
6. **Extensible Patterns**: Hook systems for pluggable functionality

**Standard Library Usage:**
7. **Collections in no_std**: Effective use of Vec, BTreeMap, and BTreeSet
8. **String Handling**: Text processing in constrained environments
9. **Iterator Patterns**: Efficient data processing techniques

**Contract Upgradability:**
10. **Proxy Patterns**: Safe contract upgrades with timelock and emergency controls
11. **Data Migration**: Strategies for evolving storage layouts
12. **Version Management**: Tracking and auditing contract upgrades

**Key Principles:**
- **Safety First**: Multiple layers of validation and protection
- **Modularity**: Composable components that can be tested independently
- **Auditability**: Clear upgrade paths and historical tracking
- **Graceful Degradation**: Systems that continue operating under adverse conditions

These advanced patterns provide the foundation for building enterprise-grade smart contracts that can evolve, scale, and operate reliably in production environments. In the next chapter, we'll explore comprehensive testing strategies to ensure these sophisticated contracts work correctly under all conditions.
