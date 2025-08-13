# Chapter 8: Debugging and Optimization

Production ink! contracts require efficient debugging workflows and optimized performance. This chapter covers debugging techniques, gas optimization strategies, and performance monitoring for smart contracts.

## Debugging Techniques

### Using debug_println! for Development

```rust
#[ink::contract]
mod debuggable_contract {
    #[ink(storage)]
    pub struct DebuggableContract {
        value: u32,
        operations: u32,
    }

    impl DebuggableContract {
        #[ink(constructor)]
        pub fn new(initial_value: u32) -> Self {
            ink::env::debug_println!("Creating contract with value: {}", initial_value);
            Self {
                value: initial_value,
                operations: 0,
            }
        }

        #[ink(message)]
        pub fn add(&mut self, amount: u32) -> Result<(), Error> {
            ink::env::debug_println!("Adding {} to current value {}", amount, self.value);
            
            let new_value = self.value.checked_add(amount)
                .ok_or(Error::ArithmeticOverflow)?;
            
            self.value = new_value;
            self.operations += 1;
            
            ink::env::debug_println!("New value: {}, operations: {}", self.value, self.operations);
            Ok(())
        }
    }
}
```

### Gas Analysis and Optimization

```rust
impl DebuggableContract {
    /// Gas-optimized version
    #[ink(message)]
    pub fn batch_add_optimized(&mut self, amounts: Vec<u32>) -> Result<u32, Error> {
        let mut total = 0u32;
        
        // Single overflow check for total
        for amount in &amounts {
            total = total.checked_add(*amount)
                .ok_or(Error::ArithmeticOverflow)?;
        }
        
        // Single final update
        self.value = self.value.checked_add(total)
            .ok_or(Error::ArithmeticOverflow)?;
        
        self.operations += amounts.len() as u32;
        Ok(amounts.len() as u32)
    }
}
```

## Performance Optimization

### Storage Access Patterns

```rust
// ❌ Inefficient: Multiple storage reads
#[ink(message)]
pub fn inefficient_calculation(&self) -> u32 {
    let a = self.balances.get(user1).unwrap_or(0);
    let b = self.balances.get(user1).unwrap_or(0); // Duplicate read!
    let c = self.balances.get(user2).unwrap_or(0);
    a + b + c
}

// ✅ Efficient: Cache storage reads
#[ink(message)]
pub fn efficient_calculation(&self) -> u32 {
    let user1_balance = self.balances.get(user1).unwrap_or(0);
    let user2_balance = self.balances.get(user2).unwrap_or(0);
    user1_balance * 2 + user2_balance
}
```

### Gas Estimation Tools

```bash
# Estimate gas for dry run
cargo contract call --contract $CONTRACT_ADDRESS \
                   --message transfer \
                   --args $TO $AMOUNT \
                   --dry-run \
                   --gas-limit 1000000
```

## Common Performance Pitfalls

1. **Large Vector Operations**: Use `Mapping` instead of `Vec` for large datasets
2. **Redundant Storage Access**: Cache frequently accessed values
3. **Inefficient Loops**: Limit loop iterations and use batch operations
4. **Oversized Types**: Use appropriately sized integer types

## Summary

Effective debugging and optimization ensure your contracts perform efficiently in production:

- Use `debug_println!` for development debugging
- Analyze gas consumption patterns
- Optimize storage access patterns
- Monitor performance metrics
- Profile and benchmark critical operations

With proper debugging and optimization techniques, your contracts will run efficiently and provide clear feedback during development and production operation.
