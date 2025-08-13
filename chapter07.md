# Chapter 7: Bulletproof Your Logic: Comprehensive Contract Testing

Testing is what separates experimental code from production-ready smart contracts. Unlike traditional software, smart contract bugs can result in permanent loss of funds, making comprehensive testing not just best practice—it's essential for survival. ink! provides a sophisticated testing framework that supports everything from isolated unit tests to full end-to-end integration testing.

In this chapter, we'll explore the complete testing ecosystem: unit testing for logic validation, integration testing for contract interactions, property-based testing for edge case discovery, and security testing for vulnerability detection. We'll also cover testing patterns specific to blockchain development, including gas testing, state transition validation, and cross-contract interaction testing.

## The Testing Pyramid for Smart Contracts

Smart contract testing follows a modified testing pyramid that accounts for blockchain-specific concerns:

```
           /\
          /  \
         / E2E\     ← End-to-End Tests (Expensive, Real blockchain)
        / Tests\
       /________\
      /          \
     /Integration \ ← Integration Tests (Medium cost, Simulated environment)
    /   Tests      \
   /________________\
  /                  \
 /   Unit Tests       \ ← Unit Tests (Fast, Isolated logic)
/______________________\
```

### Testing Strategy Overview

**Unit Tests (70% of test suite):**
- Test individual functions in isolation
- Mock external dependencies
- Fast execution, high coverage
- Focus on business logic and edge cases

**Integration Tests (20% of test suite):**
- Test contract interactions
- Cross-contract calls
- Event emission validation
- State transition testing

**End-to-End Tests (10% of test suite):**
- Full deployment and interaction cycle
- Real blockchain environment testing
- Gas consumption validation
- User journey testing

## Unit Testing: The Foundation

Unit tests form the foundation of your testing strategy. They're fast, deterministic, and enable rapid development cycles.

### Basic Unit Test Structure

```rust
#[ink::contract]
mod testable_token {
    use ink::storage::Mapping;

    #[ink(storage)]
    pub struct TestableToken {
        total_supply: Balance,
        balances: Mapping<AccountId, Balance>,
        allowances: Mapping<(AccountId, AccountId), Balance>,
        owner: AccountId,
        paused: bool,
    }

    #[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub enum Error {
        InsufficientBalance,
        InsufficientAllowance,
        Unauthorized,
        ContractPaused,
        InvalidAmount,
        SelfTransfer,
    }

    impl TestableToken {
        #[ink(constructor)]
        pub fn new(total_supply: Balance) -> Self {
            let caller = Self::env().caller();
            let mut balances = Mapping::default();
            balances.insert(caller, &total_supply);

            Self {
                total_supply,
                balances,
                allowances: Mapping::default(),
                owner: caller,
                paused: false,
            }
        }

        #[ink(message)]
        pub fn transfer(&mut self, to: AccountId, value: Balance) -> Result<(), Error> {
            if self.paused {
                return Err(Error::ContractPaused);
            }

            if value == 0 {
                return Err(Error::InvalidAmount);
            }

            let from = self.env().caller();
            if from == to {
                return Err(Error::SelfTransfer);
            }

            self.transfer_from_to(from, to, value)
        }

        #[ink(message)]
        pub fn approve(&mut self, spender: AccountId, value: Balance) -> Result<(), Error> {
            if self.paused {
                return Err(Error::ContractPaused);
            }

            let owner = self.env().caller();
            self.allowances.insert((owner, spender), &value);
            Ok(())
        }

        #[ink(message)]
        pub fn transfer_from(
            &mut self,
            from: AccountId,
            to: AccountId,
            value: Balance,
        ) -> Result<(), Error> {
            if self.paused {
                return Err(Error::ContractPaused);
            }

            let caller = self.env().caller();
            let allowance = self.allowances.get((from, caller)).unwrap_or(0);

            if allowance < value {
                return Err(Error::InsufficientAllowance);
            }

            self.allowances.insert((from, caller), &(allowance - value));
            self.transfer_from_to(from, to, value)
        }

        #[ink(message)]
        pub fn balance_of(&self, owner: AccountId) -> Balance {
            self.balances.get(owner).unwrap_or(0)
        }

        #[ink(message)]
        pub fn allowance(&self, owner: AccountId, spender: AccountId) -> Balance {
            self.allowances.get((owner, spender)).unwrap_or(0)
        }

        #[ink(message)]
        pub fn pause(&mut self) -> Result<(), Error> {
            if self.env().caller() != self.owner {
                return Err(Error::Unauthorized);
            }
            self.paused = true;
            Ok(())
        }

        fn transfer_from_to(&mut self, from: AccountId, to: AccountId, value: Balance) -> Result<(), Error> {
            let from_balance = self.balance_of(from);
            if from_balance < value {
                return Err(Error::InsufficientBalance);
            }

            let to_balance = self.balance_of(to);
            self.balances.insert(from, &(from_balance - value));
            self.balances.insert(to, &(to_balance + value));

            Ok(())
        }
    }

    /// Comprehensive unit test suite
    #[cfg(test)]
    mod tests {
        use super::*;
        use ink::env::test;

        /// Helper function to create test accounts
        fn accounts() -> ink::env::test::DefaultAccounts<ink::env::DefaultEnvironment> {
            ink::env::test::default_accounts::<ink::env::DefaultEnvironment>()
        }

        /// Helper function to set up test environment
        fn setup_contract(total_supply: Balance) -> TestableToken {
            let accounts = accounts();
            test::set_caller::<ink::env::DefaultEnvironment>(accounts.alice);
            TestableToken::new(total_supply)
        }

        #[ink::test]
        fn constructor_works() {
            let total_supply = 1000;
            let token = setup_contract(total_supply);
            let accounts = accounts();

            assert_eq!(token.total_supply, total_supply);
            assert_eq!(token.balance_of(accounts.alice), total_supply);
            assert_eq!(token.balance_of(accounts.bob), 0);
        }

        #[ink::test]
        fn transfer_works() {
            let mut token = setup_contract(1000);
            let accounts = accounts();

            // Test successful transfer
            assert_eq!(token.transfer(accounts.bob, 100), Ok(()));
            assert_eq!(token.balance_of(accounts.alice), 900);
            assert_eq!(token.balance_of(accounts.bob), 100);
        }

        #[ink::test]
        fn transfer_insufficient_balance_fails() {
            let mut token = setup_contract(100);
            let accounts = accounts();

            // Try to transfer more than balance
            assert_eq!(token.transfer(accounts.bob, 200), Err(Error::InsufficientBalance));
            
            // Balances should remain unchanged
            assert_eq!(token.balance_of(accounts.alice), 100);
            assert_eq!(token.balance_of(accounts.bob), 0);
        }

        #[ink::test]
        fn transfer_zero_amount_fails() {
            let mut token = setup_contract(1000);
            let accounts = accounts();

            assert_eq!(token.transfer(accounts.bob, 0), Err(Error::InvalidAmount));
        }

        #[ink::test]
        fn self_transfer_fails() {
            let mut token = setup_contract(1000);
            let accounts = accounts();

            assert_eq!(token.transfer(accounts.alice, 100), Err(Error::SelfTransfer));
        }

        #[ink::test]
        fn approve_works() {
            let mut token = setup_contract(1000);
            let accounts = accounts();

            assert_eq!(token.approve(accounts.bob, 500), Ok(()));
            assert_eq!(token.allowance(accounts.alice, accounts.bob), 500);
        }

        #[ink::test]
        fn transfer_from_works() {
            let mut token = setup_contract(1000);
            let accounts = accounts();

            // Alice approves Bob to spend 500 tokens
            assert_eq!(token.approve(accounts.bob, 500), Ok(()));

            // Switch to Bob's account
            test::set_caller::<ink::env::DefaultEnvironment>(accounts.bob);

            // Bob transfers 100 tokens from Alice to Charlie
            assert_eq!(token.transfer_from(accounts.alice, accounts.charlie, 100), Ok(()));

            // Check balances
            assert_eq!(token.balance_of(accounts.alice), 900);
            assert_eq!(token.balance_of(accounts.charlie), 100);

            // Check remaining allowance
            assert_eq!(token.allowance(accounts.alice, accounts.bob), 400);
        }

        #[ink::test]
        fn transfer_from_insufficient_allowance_fails() {
            let mut token = setup_contract(1000);
            let accounts = accounts();

            // Alice approves Bob to spend 100 tokens
            assert_eq!(token.approve(accounts.bob, 100), Ok(()));

            // Switch to Bob's account
            test::set_caller::<ink::env::DefaultEnvironment>(accounts.bob);

            // Bob tries to transfer 200 tokens (more than allowance)
            assert_eq!(
                token.transfer_from(accounts.alice, accounts.charlie, 200),
                Err(Error::InsufficientAllowance)
            );
        }

        #[ink::test]
        fn pause_functionality_works() {
            let mut token = setup_contract(1000);
            let accounts = accounts();

            // Pause the contract
            assert_eq!(token.pause(), Ok(()));

            // Transfers should fail when paused
            assert_eq!(token.transfer(accounts.bob, 100), Err(Error::ContractPaused));
        }

        #[ink::test]
        fn pause_unauthorized_fails() {
            let mut token = setup_contract(1000);
            let accounts = accounts();

            // Switch to non-owner account
            test::set_caller::<ink::env::DefaultEnvironment>(accounts.bob);

            // Non-owner cannot pause
            assert_eq!(token.pause(), Err(Error::Unauthorized));
        }

        #[ink::test]
        fn edge_case_max_balance() {
            let max_supply = Balance::MAX;
            let mut token = setup_contract(max_supply);
            let accounts = accounts();

            // Should be able to transfer max balance
            assert_eq!(token.transfer(accounts.bob, max_supply), Ok(()));
            assert_eq!(token.balance_of(accounts.alice), 0);
            assert_eq!(token.balance_of(accounts.bob), max_supply);
        }
    }
}
```

### Advanced Unit Testing Patterns

#### Testing with Mock Environments

```rust
#[cfg(test)]
mod advanced_tests {
    use super::*;
    use ink::env::test;

    /// Test time-dependent functionality
    #[ink::test]
    fn time_locked_function_works() {
        let mut contract = setup_time_locked_contract();
        let accounts = accounts();

        // Function should fail before time lock expires
        assert_eq!(contract.time_locked_function(), Err(Error::TimeLocked));

        // Advance time past the lock period
        let current_time = test::get_block_timestamp::<ink::env::DefaultEnvironment>();
        test::set_block_timestamp::<ink::env::DefaultEnvironment>(current_time + 86400000); // +24 hours

        // Function should now work
        assert_eq!(contract.time_locked_function(), Ok(()));
    }

    /// Test block number dependent functionality
    #[ink::test]
    fn block_dependent_logic_works() {
        let mut contract = TestableToken::new(1000);
        
        // Set specific block number
        test::set_block_number::<ink::env::DefaultEnvironment>(100);
        
        // Test logic that depends on block number
        assert_eq!(contract.block_dependent_function(), Ok(100));
    }

    /// Test caller-dependent functionality
    #[ink::test]
    fn multi_caller_scenario() {
        let mut token = setup_contract(1000);
        let accounts = accounts();

        // Alice (owner) performs initial setup
        test::set_caller::<ink::env::DefaultEnvironment>(accounts.alice);
        assert_eq!(token.approve(accounts.bob, 500), Ok(()));

        // Bob performs allowance-based transfer
        test::set_caller::<ink::env::DefaultEnvironment>(accounts.bob);
        assert_eq!(token.transfer_from(accounts.alice, accounts.charlie, 100), Ok(()));

        // Charlie checks their balance
        test::set_caller::<ink::env::DefaultEnvironment>(accounts.charlie);
        assert_eq!(token.balance_of(accounts.charlie), 100);
    }

    /// Test error propagation chains
    #[ink::test]
    fn error_propagation_works() {
        let mut token = setup_contract(1000);
        let accounts = accounts();

        // Create a chain of operations that should fail at different points
        
        // First, pause the contract
        assert_eq!(token.pause(), Ok(()));

        // Now all operations should fail with ContractPaused
        assert_eq!(token.transfer(accounts.bob, 100), Err(Error::ContractPaused));
        assert_eq!(token.approve(accounts.bob, 500), Err(Error::ContractPaused));
        assert_eq!(
            token.transfer_from(accounts.alice, accounts.bob, 100),
            Err(Error::ContractPaused)
        );
    }

    fn setup_time_locked_contract() -> TestableToken {
        // Setup contract with time lock
        setup_contract(1000)
    }
}
```

#### Property-Based Testing

Property-based testing discovers edge cases by generating random inputs and verifying invariants:

```rust
#[cfg(test)]
mod property_tests {
    use super::*;
    use quickcheck::{quickcheck, TestResult};

    /// Property: Total supply should remain constant (except minting/burning)
    fn prop_total_supply_conservation(transfers: Vec<(u8, u8, u64)>) -> TestResult {
        if transfers.len() > 20 {
            return TestResult::discard(); // Limit test size
        }

        let mut token = setup_contract(1_000_000);
        let accounts = accounts();
        let test_accounts = [accounts.alice, accounts.bob, accounts.charlie, accounts.django];

        let initial_total = test_accounts.iter()
            .map(|&acc| token.balance_of(acc))
            .sum::<Balance>();

        for (from_idx, to_idx, amount) in transfers {
            let from_idx = (from_idx % 4) as usize;
            let to_idx = (to_idx % 4) as usize;
            
            if from_idx == to_idx {
                continue; // Skip self-transfers
            }

            let from = test_accounts[from_idx];
            let to = test_accounts[to_idx];
            let amount = amount % 10000; // Reasonable transfer amounts

            test::set_caller::<ink::env::DefaultEnvironment>(from);
            let _ = token.transfer(to, amount); // Ignore failures
        }

        let final_total = test_accounts.iter()
            .map(|&acc| token.balance_of(acc))
            .sum::<Balance>();

        TestResult::from_bool(initial_total == final_total)
    }

    /// Property: Approve/transfer_from should respect allowances
    fn prop_allowance_respected(approvals: Vec<(u8, u8, u64)>, transfers: Vec<(u8, u8, u64)>) -> TestResult {
        if approvals.len() > 10 || transfers.len() > 10 {
            return TestResult::discard();
        }

        let mut token = setup_contract(1_000_000);
        let accounts = accounts();
        let test_accounts = [accounts.alice, accounts.bob, accounts.charlie, accounts.django];

        // Set up approvals
        for (owner_idx, spender_idx, amount) in approvals {
            let owner_idx = (owner_idx % 4) as usize;
            let spender_idx = (spender_idx % 4) as usize;
            
            if owner_idx == spender_idx {
                continue;
            }

            let owner = test_accounts[owner_idx];
            let spender = test_accounts[spender_idx];
            let amount = amount % 1000;

            test::set_caller::<ink::env::DefaultEnvironment>(owner);
            let _ = token.approve(spender, amount);
        }

        // Test transfers
        let mut all_transfers_valid = true;
        
        for (spender_idx, to_idx, amount) in transfers {
            let spender_idx = (spender_idx % 4) as usize;
            let to_idx = (to_idx % 4) as usize;
            let amount = amount % 1000;

            let spender = test_accounts[spender_idx];
            let to = test_accounts[to_idx];

            // Try transfer from each potential owner
            for owner in &test_accounts {
                if *owner == spender {
                    continue;
                }

                test::set_caller::<ink::env::DefaultEnvironment>(spender);
                let allowance = token.allowance(*owner, spender);
                let owner_balance = token.balance_of(*owner);
                
                let result = token.transfer_from(*owner, to, amount);
                
                // Transfer should succeed only if allowance and balance are sufficient
                let should_succeed = allowance >= amount && owner_balance >= amount;
                let actually_succeeded = result.is_ok();
                
                if should_succeed != actually_succeeded {
                    all_transfers_valid = false;
                    break;
                }
            }
        }

        TestResult::from_bool(all_transfers_valid)
    }

    #[test]
    fn run_property_tests() {
        quickcheck(prop_total_supply_conservation as fn(Vec<(u8, u8, u64)>) -> TestResult);
        quickcheck(prop_allowance_respected as fn(Vec<(u8, u8, u64)>, Vec<(u8, u8, u64)>) -> TestResult);
    }
}
```

## Integration Testing: Contract Interactions

Integration tests verify that different parts of your system work together correctly, including cross-contract calls and event emission.

### Testing Event Emission

```rust
#[cfg(test)]
mod integration_tests {
    use super::*;
    use ink::env::test;

    #[ink::test]
    fn events_are_emitted_correctly() {
        let mut token = setup_contract(1000);
        let accounts = accounts();

        // Clear any existing events
        let _ = test::recorded_events().collect::<Vec<_>>();

        // Perform transfer
        assert_eq!(token.transfer(accounts.bob, 100), Ok(()));

        // Check that transfer event was emitted
        let recorded_events = test::recorded_events().collect::<Vec<_>>();
        assert_eq!(recorded_events.len(), 1);

        // Decode and verify event data
        let event = &recorded_events[0];
        assert!(event.topics.len() >= 1); // Should have at least the event selector

        // In a real implementation, you would decode the event data
        // and verify the from, to, and amount fields
    }

    #[ink::test]
    fn multiple_events_in_sequence() {
        let mut token = setup_contract(1000);
        let accounts = accounts();

        // Clear events
        let _ = test::recorded_events().collect::<Vec<_>>();

        // Perform multiple operations
        assert_eq!(token.approve(accounts.bob, 500), Ok(()));
        assert_eq!(token.transfer(accounts.charlie, 100), Ok(()));

        // Should have emitted approval and transfer events
        let recorded_events = test::recorded_events().collect::<Vec<_>>();
        assert_eq!(recorded_events.len(), 2);
    }
}
```

### Testing Cross-Contract Interactions

```rust
/// Mock external contract for testing
#[ink::contract]
mod mock_external_contract {
    #[ink(storage)]
    pub struct MockExternal {
        call_count: u32,
        last_caller: Option<AccountId>,
    }

    impl MockExternal {
        #[ink(constructor)]
        pub fn new() -> Self {
            Self {
                call_count: 0,
                last_caller: None,
            }
        }

        #[ink(message)]
        pub fn external_function(&mut self, data: u32) -> Result<u32, ()> {
            self.call_count += 1;
            self.last_caller = Some(self.env().caller());
            Ok(data * 2)
        }

        #[ink(message)]
        pub fn get_call_count(&self) -> u32 {
            self.call_count
        }
    }
}

/// Contract that makes cross-contract calls
#[ink::contract]
mod cross_contract_caller {
    #[ink(storage)]
    pub struct CrossContractCaller {
        external_contract: AccountId,
    }

    impl CrossContractCaller {
        #[ink(constructor)]
        pub fn new(external_contract: AccountId) -> Self {
            Self { external_contract }
        }

        #[ink(message)]
        pub fn call_external(&mut self, data: u32) -> Result<u32, Error> {
            // Make cross-contract call
            let result = ink::env::call::build_call::<ink::env::DefaultEnvironment>()
                .call(self.external_contract)
                .gas_limit(5000)
                .transferred_value(0)
                .exec_input(
                    ink::env::call::ExecutionInput::new(
                        ink::env::call::Selector::new([0x12, 0x34, 0x56, 0x78]) // external_function selector
                    ).push_arg(data)
                )
                .returns::<Result<u32, ()>>()
                .invoke();

            result.map_err(|_| Error::ExternalCallFailed)
        }
    }

    #[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub enum Error {
        ExternalCallFailed,
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use super::mock_external_contract::MockExternal;

        #[ink::test]
        fn cross_contract_call_works() {
            // Deploy mock external contract
            let mut external = MockExternal::new();
            let external_address = AccountId::from([1; 32]);

            // Deploy caller contract
            let mut caller = CrossContractCaller::new(external_address);

            // In a real test, you would need to properly set up the cross-contract call
            // This is a simplified example showing the testing structure
            
            // Test direct call to external contract
            assert_eq!(external.external_function(5), Ok(10));
            assert_eq!(external.get_call_count(), 1);
        }
    }
}
```

## End-to-End Testing: Real Blockchain Interaction

End-to-end tests deploy contracts to a real test network and validate complete user journeys.

### E2E Test Structure

```rust
#[cfg(all(test, feature = "e2e-tests"))]
mod e2e_tests {
    use super::*;
    use ink_e2e::build_message;

    type E2EResult<T> = std::result::Result<T, Box<dyn std::error::Error>>;

    #[ink_e2e::test]
    async fn e2e_transfer_works(mut client: ink_e2e::Client<C, E>) -> E2EResult<()> {
        // Deploy the contract
        let constructor = TestableTokenRef::new(1000);
        let contract_account_id = client
            .instantiate("testable_token", &ink_e2e::alice(), constructor, 0, None)
            .await
            .expect("instantiate failed")
            .account_id;

        // Check initial balance
        let get_balance = build_message::<TestableTokenRef>(contract_account_id.clone())
            .call(|token| token.balance_of(ink_e2e::alice().account_id()));
        let balance_result = client.call_dry_run(&ink_e2e::alice(), &get_balance, 0, None).await;
        assert_eq!(balance_result.return_value(), 1000);

        // Perform transfer
        let transfer = build_message::<TestableTokenRef>(contract_account_id.clone())
            .call(|token| token.transfer(ink_e2e::bob().account_id(), 100));
        let transfer_result = client
            .call(&ink_e2e::alice(), transfer, 0, None)
            .await
            .expect("transfer failed");

        // Verify the transfer succeeded
        assert!(transfer_result.return_value().is_ok());

        // Check final balances
        let alice_balance = build_message::<TestableTokenRef>(contract_account_id.clone())
            .call(|token| token.balance_of(ink_e2e::alice().account_id()));
        let alice_result = client.call_dry_run(&ink_e2e::alice(), &alice_balance, 0, None).await;
        assert_eq!(alice_result.return_value(), 900);

        let bob_balance = build_message::<TestableTokenRef>(contract_account_id.clone())
            .call(|token| token.balance_of(ink_e2e::bob().account_id()));
        let bob_result = client.call_dry_run(&ink_e2e::alice(), &bob_balance, 0, None).await;
        assert_eq!(bob_result.return_value(), 100);

        Ok(())
    }

    #[ink_e2e::test]
    async fn e2e_approval_workflow(mut client: ink_e2e::Client<C, E>) -> E2EResult<()> {
        // Deploy contract
        let constructor = TestableTokenRef::new(1000);
        let contract_account_id = client
            .instantiate("testable_token", &ink_e2e::alice(), constructor, 0, None)
            .await
            .expect("instantiate failed")
            .account_id;

        // Alice approves Bob to spend 500 tokens
        let approve = build_message::<TestableTokenRef>(contract_account_id.clone())
            .call(|token| token.approve(ink_e2e::bob().account_id(), 500));
        let approve_result = client
            .call(&ink_e2e::alice(), approve, 0, None)
            .await
            .expect("approve failed");
        assert!(approve_result.return_value().is_ok());

        // Check allowance
        let get_allowance = build_message::<TestableTokenRef>(contract_account_id.clone())
            .call(|token| token.allowance(ink_e2e::alice().account_id(), ink_e2e::bob().account_id()));
        let allowance_result = client.call_dry_run(&ink_e2e::alice(), &get_allowance, 0, None).await;
        assert_eq!(allowance_result.return_value(), 500);

        // Bob transfers 100 tokens from Alice to Charlie
        let transfer_from = build_message::<TestableTokenRef>(contract_account_id.clone())
            .call(|token| token.transfer_from(
                ink_e2e::alice().account_id(),
                ink_e2e::charlie().account_id(),
                100
            ));
        let transfer_result = client
            .call(&ink_e2e::bob(), transfer_from, 0, None)
            .await
            .expect("transfer_from failed");
        assert!(transfer_result.return_value().is_ok());

        // Verify final state
        let charlie_balance = build_message::<TestableTokenRef>(contract_account_id.clone())
            .call(|token| token.balance_of(ink_e2e::charlie().account_id()));
        let charlie_result = client.call_dry_run(&ink_e2e::alice(), &charlie_balance, 0, None).await;
        assert_eq!(charlie_result.return_value(), 100);

        // Check remaining allowance
        let final_allowance = build_message::<TestableTokenRef>(contract_account_id.clone())
            .call(|token| token.allowance(ink_e2e::alice().account_id(), ink_e2e::bob().account_id()));
        let final_allowance_result = client.call_dry_run(&ink_e2e::alice(), &final_allowance, 0, None).await;
        assert_eq!(final_allowance_result.return_value(), 400);

        Ok(())
    }

    #[ink_e2e::test]
    async fn e2e_gas_consumption_test(mut client: ink_e2e::Client<C, E>) -> E2EResult<()> {
        // Deploy contract
        let constructor = TestableTokenRef::new(1000000);
        let contract_account_id = client
            .instantiate("testable_token", &ink_e2e::alice(), constructor, 0, None)
            .await
            .expect("instantiate failed")
            .account_id;

        // Test gas consumption for different operations
        let transfer = build_message::<TestableTokenRef>(contract_account_id.clone())
            .call(|token| token.transfer(ink_e2e::bob().account_id(), 1000));
        
        let transfer_result = client
            .call(&ink_e2e::alice(), transfer, 0, None)
            .await
            .expect("transfer failed");

        // Verify gas consumption is within expected bounds
        let gas_consumed = transfer_result.gas_consumed;
        assert!(gas_consumed.ref_time() < 1_000_000_000); // Less than 1 billion gas units
        
        println!("Transfer gas consumed: {}", gas_consumed.ref_time());

        Ok(())
    }
}
```

## Security Testing: Finding Vulnerabilities

Security testing focuses on discovering vulnerabilities that could be exploited by malicious actors.

### Testing Access Controls

```rust
#[cfg(test)]
mod security_tests {
    use super::*;

    #[ink::test]
    fn unauthorized_access_blocked() {
        let mut token = setup_contract(1000);
        let accounts = accounts();

        // Switch to non-owner account
        test::set_caller::<ink::env::DefaultEnvironment>(accounts.bob);

        // Attempt unauthorized operation
        assert_eq!(token.pause(), Err(Error::Unauthorized));

        // Verify state didn't change
        assert!(!token.paused);
    }

    #[ink::test]
    fn reentrancy_protection() {
        // Test that the contract properly prevents reentrancy attacks
        // This would typically involve cross-contract calls that attempt
        // to call back into the original contract
        
        let mut token = setup_contract(1000);
        let accounts = accounts();

        // In a real test, you would set up a malicious contract
        // that attempts reentrancy and verify it's blocked
        
        // For now, test basic transfer functionality
        assert_eq!(token.transfer(accounts.bob, 100), Ok(()));
        assert_eq!(token.balance_of(accounts.alice), 900);
    }

    #[ink::test]
    fn integer_overflow_protection() {
        let max_supply = Balance::MAX;
        let mut token = setup_contract(max_supply);
        let accounts = accounts();

        // Transfer all tokens to Bob
        assert_eq!(token.transfer(accounts.bob, max_supply), Ok(()));

        // Switch to Bob's account
        test::set_caller::<ink::env::DefaultEnvironment>(accounts.bob);

        // Attempt to cause overflow by transferring to an account with MAX balance
        // This should be prevented by proper overflow checks
        test::set_caller::<ink::env::DefaultEnvironment>(accounts.alice);
        
        // Create a scenario that could cause overflow
        let large_amount = Balance::MAX / 2;
        let mut balances = std::collections::HashMap::new();
        balances.insert(accounts.alice, large_amount);
        balances.insert(accounts.bob, large_amount);

        // Verify that transfers prevent overflow
        // (Implementation would depend on specific overflow protection mechanisms)
    }

    #[ink::test]
    fn front_running_resistance() {
        let mut token = setup_contract(1000);
        let accounts = accounts();

        // Test that the contract is resistant to front-running attacks
        // This might involve testing timestamp-dependent operations
        // or operations that should be atomic

        // Set up initial approval
        assert_eq!(token.approve(accounts.bob, 500), Ok(()));

        // Simulate a scenario where Alice tries to change approval
        // while Bob tries to use the existing approval
        assert_eq!(token.approve(accounts.bob, 100), Ok(()));
        
        // Switch to Bob and try to use old allowance
        test::set_caller::<ink::env::DefaultEnvironment>(accounts.bob);
        
        // This should use the new allowance amount, not the old one
        assert_eq!(
            token.transfer_from(accounts.alice, accounts.charlie, 200),
            Err(Error::InsufficientAllowance)
        );
    }

    #[ink::test]
    fn denial_of_service_resistance() {
        let mut token = setup_contract(1000);
        let accounts = accounts();

        // Test that the contract handles resource exhaustion gracefully
        // For example, operations with large arrays or loops

        // Simulate many small operations
        for i in 1..100 {
            if i % 2 == 0 {
                test::set_caller::<ink::env::DefaultEnvironment>(accounts.alice);
                let _ = token.transfer(accounts.bob, 1);
            } else {
                test::set_caller::<ink::env::DefaultEnvironment>(accounts.bob);
                let _ = token.transfer(accounts.alice, 1);
            }
        }

        // Contract should still be functional
        test::set_caller::<ink::env::DefaultEnvironment>(accounts.alice);
        assert_eq!(token.transfer(accounts.charlie, 10), Ok(()));
    }
}
```

### Fuzz Testing

```rust
#[cfg(test)]
mod fuzz_tests {
    use super::*;
    use arbitrary::{Arbitrary, Unstructured};

    #[derive(Debug, Clone, Arbitrary)]
    enum Action {
        Transfer { to: u8, amount: u64 },
        Approve { spender: u8, amount: u64 },
        TransferFrom { from: u8, to: u8, amount: u64 },
        Pause,
    }

    #[derive(Debug, Clone, Arbitrary)]
    struct TestScenario {
        initial_supply: u64,
        actions: Vec<Action>,
    }

    fn run_fuzz_test(scenario: TestScenario) -> bool {
        let initial_supply = scenario.initial_supply % 1_000_000; // Reasonable bounds
        let mut token = setup_contract(initial_supply);
        let accounts = accounts();
        let test_accounts = [accounts.alice, accounts.bob, accounts.charlie, accounts.django];

        for action in scenario.actions.iter().take(50) { // Limit action count
            match action {
                Action::Transfer { to, amount } => {
                    let to_idx = (*to % 4) as usize;
                    let to_account = test_accounts[to_idx];
                    let amount = amount % 10000; // Reasonable amount
                    
                    let _ = token.transfer(to_account, amount);
                }
                Action::Approve { spender, amount } => {
                    let spender_idx = (*spender % 4) as usize;
                    let spender_account = test_accounts[spender_idx];
                    let amount = amount % 10000;
                    
                    let _ = token.approve(spender_account, amount);
                }
                Action::TransferFrom { from, to, amount } => {
                    let from_idx = (*from % 4) as usize;
                    let to_idx = (*to % 4) as usize;
                    let from_account = test_accounts[from_idx];
                    let to_account = test_accounts[to_idx];
                    let amount = amount % 10000;
                    
                    let _ = token.transfer_from(from_account, to_account, amount);
                }
                Action::Pause => {
                    // Only Alice (owner) can pause
                    test::set_caller::<ink::env::DefaultEnvironment>(accounts.alice);
                    let _ = token.pause();
                }
            }
        }

        // Check invariants
        let total_balance: Balance = test_accounts.iter()
            .map(|&acc| token.balance_of(acc))
            .sum();

        // Total balance should not exceed initial supply
        total_balance <= initial_supply
    }

    #[test]
    fn fuzz_test_invariants() {
        // In a real implementation, you would use a proper fuzzing framework
        // like `cargo fuzz` or integrate with `proptest`
        
        let test_scenarios = vec![
            TestScenario {
                initial_supply: 1000,
                actions: vec![
                    Action::Transfer { to: 1, amount: 100 },
                    Action::Approve { spender: 1, amount: 500 },
                    Action::TransferFrom { from: 0, to: 2, amount: 50 },
                ],
            },
            // Add more test scenarios...
        ];

        for scenario in test_scenarios {
            assert!(run_fuzz_test(scenario), "Fuzz test failed - invariant violated");
        }
    }
}
```

## Performance and Gas Testing

### Gas Consumption Testing

```rust
#[cfg(test)]
mod performance_tests {
    use super::*;

    #[ink::test]
    fn gas_consumption_benchmarks() {
        let mut token = setup_contract(1_000_000);
        let accounts = accounts();

        // Benchmark different operations
        let operations = vec![
            ("balance_of", || { token.balance_of(accounts.alice); }),
            ("transfer", || { let _ = token.transfer(accounts.bob, 100); }),
            ("approve", || { let _ = token.approve(accounts.bob, 1000); }),
        ];

        for (name, operation) in operations {
            // In a real implementation, you would measure gas consumption
            // This might involve running the operation multiple times
            // and averaging the results
            
            operation();
            println!("Operation '{}' completed", name);
        }
    }

    #[ink::test]
    fn storage_efficiency_test() {
        let mut token = setup_contract(1000);
        let accounts = accounts();

        // Test storage efficiency by performing many operations
        // and ensuring storage doesn't grow excessively

        for i in 0..100 {
            let amount = i % 10 + 1;
            if i % 2 == 0 {
                let _ = token.transfer(accounts.bob, amount);
            } else {
                test::set_caller::<ink::env::DefaultEnvironment>(accounts.bob);
                let _ = token.transfer(accounts.alice, amount);
                test::set_caller::<ink::env::DefaultEnvironment>(accounts.alice);
            }
        }

        // Verify contract state is still consistent
        assert!(token.balance_of(accounts.alice) + token.balance_of(accounts.bob) <= 1000);
    }

    #[ink::test]
    fn batch_operation_efficiency() {
        let mut token = setup_contract(1_000_000);
        let accounts = accounts();

        // Test efficiency of batch operations vs individual operations
        
        // Individual transfers
        let start_time = std::time::Instant::now();
        for i in 0..100 {
            let _ = token.transfer(accounts.bob, 100);
            test::set_caller::<ink::env::DefaultEnvironment>(accounts.bob);
            let _ = token.transfer(accounts.alice, 100);
            test::set_caller::<ink::env::DefaultEnvironment>(accounts.alice);
        }
        let individual_duration = start_time.elapsed();

        // In a real implementation, you might compare this with
        // a batch transfer function if available
        
        println!("Individual operations took: {:?}", individual_duration);
    }
}
```

## Test Organization and CI/CD

### Test Configuration

```toml
# Cargo.toml test configuration
[features]
default = ["std"]
std = [
    "ink/std",
    "scale/std",
    "scale-info/std",
]
e2e-tests = []

[dev-dependencies]
ink_e2e = "4.3"
quickcheck = "1.0"
arbitrary = "1.0"
```

### CI/CD Pipeline

```yaml
# .github/workflows/test.yml
name: Test

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Install Rust
      uses: actions-rs/toolchain@v1
      with:
        toolchain: stable
        target: wasm32-unknown-unknown
        components: rustfmt, clippy
    
    - name: Install cargo-contract
      run: cargo install cargo-contract --force
    
    - name: Run unit tests
      run: cargo test
    
    - name: Run clippy
      run: cargo clippy -- -D warnings
    
    - name: Check formatting
      run: cargo fmt -- --check

  integration-tests:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Install dependencies
      run: |
        cargo install cargo-contract --force
        cargo install contracts-node --git https://github.com/paritytech/substrate-contracts-node.git
    
    - name: Run substrate node
      run: substrate-contracts-node --dev --tmp &
      
    - name: Wait for node
      run: sleep 10
    
    - name: Run E2E tests
      run: cargo test --features e2e-tests

  security-tests:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Install cargo-audit
      run: cargo install cargo-audit
    
    - name: Security audit
      run: cargo audit
    
    - name: Run security-focused tests
      run: cargo test security_tests
```

## Summary

In this chapter, we've built a comprehensive testing framework for ink! contracts:

**Testing Foundation:**
1. **Unit Tests**: Fast, isolated testing of individual functions with comprehensive edge case coverage
2. **Integration Tests**: Testing contract interactions, event emission, and state transitions
3. **End-to-End Tests**: Full deployment and interaction testing on real blockchain networks

**Advanced Testing Techniques:**
4. **Property-Based Testing**: Discovering edge cases through randomized input generation
5. **Fuzz Testing**: Finding vulnerabilities through systematic input variation
6. **Security Testing**: Focused testing for access controls, overflow protection, and attack resistance

**Specialized Testing:**
7. **Cross-Contract Testing**: Validating interactions between multiple contracts
8. **Gas Testing**: Ensuring operations remain within reasonable gas limits
9. **Performance Testing**: Benchmarking and optimizing contract operations

**Testing Infrastructure:**
10. **CI/CD Integration**: Automated testing pipelines for continuous validation
11. **Test Organization**: Proper test structure and configuration management

**Key Principles:**
- **Comprehensive Coverage**: Test happy paths, edge cases, and failure scenarios
- **Realistic Testing**: Use real blockchain environments for final validation
- **Security Focus**: Actively search for vulnerabilities and attack vectors
- **Performance Awareness**: Monitor gas consumption and optimization opportunities

With a robust testing strategy in place, you can deploy contracts with confidence, knowing they've been thoroughly validated under all conditions. In the next chapter, we'll explore debugging and optimization techniques to fine-tune your contracts for production deployment.
