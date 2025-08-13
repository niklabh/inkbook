# Chapter 3: Deep Dive into State: Managing Contract Storage

Storage is the heart of any smart contract—it's where your contract's state persists between transactions and across blockchain upgrades. Unlike traditional applications where you might use databases or file systems, smart contracts store data directly on the blockchain, making every byte precious and every access pattern critical for gas efficiency.

In this chapter, we'll explore ink!'s sophisticated storage system, from basic primitives to advanced optimization techniques. You'll learn how to design storage layouts that scale, when to use different storage types, and how to avoid common pitfalls that can make your contracts expensive or unusable.

## Understanding the Storage Model

### The Single Storage Root Principle

Every ink! contract has exactly one storage struct marked with `#[ink(storage)]`. This struct serves as the root of all persistent data:

```rust
#[ink::contract]
mod my_contract {
    #[ink(storage)]
    pub struct MyContract {
        // This is the ONLY persistent storage in your contract
        value: u32,
        owner: AccountId,
        balances: ink::storage::Mapping<AccountId, Balance>,
    }
    
    // This struct is NOT storage - it's just a regular Rust struct
    pub struct TempData {
        calculation: u64,
    }
}
```

**Why only one storage struct?**
- **Deterministic layout**: Ensures consistent storage access patterns
- **Gas optimization**: Single root eliminates storage lookup overhead  
- **Upgrade safety**: Prevents storage layout conflicts during contract upgrades

### Storage Key Generation

ink! automatically generates unique storage keys for each field using a deterministic algorithm:

```rust
#[ink(storage)]
pub struct MyContract {
    value: u32,        // Storage key: 0x00000000
    owner: AccountId,  // Storage key: 0x00000001
    data: Vec<u8>,     // Storage key: 0x00000002
}
```

**Key generation algorithm:**
1. Start with base key `0x00000000`
2. Increment by 1 for each field in declaration order
3. Apply cryptographic hashing for nested structures

**Visualizing storage layout:**

```
Blockchain Storage:
┌─────────────────────────────────┐
│ Contract Address: 0xABC123...   │
├─────────────────────────────────┤
│ Storage Root                    │
│ ├─ Key 0x00000000: value        │
│ ├─ Key 0x00000001: owner        │
│ └─ Key 0x00000002: data         │
└─────────────────────────────────┘
```

## Supported Storage Types

### Primitive Types

All Rust primitive types work directly in storage:

```rust
#[ink(storage)]
pub struct PrimitiveStorage {
    // Unsigned integers
    small_number: u8,      // 1 byte
    medium_number: u32,    // 4 bytes
    large_number: u128,    // 16 bytes
    
    // Signed integers
    signed_value: i64,     // 8 bytes
    
    // Boolean
    flag: bool,            // 1 byte (but stored as u8)
    
    // Arrays (fixed size)
    bytes: [u8; 32],       // 32 bytes
    numbers: [u64; 10],    // 80 bytes
}
```

**Gas implications:**
- Reading any primitive costs ~200 gas base + size penalty
- Writing costs ~5,000 gas base + size penalty
- Arrays are stored as single items (efficient for small, fixed sizes)

### Custom Structs and Enums

Any type implementing the required traits can be stored:

```rust
// Custom struct for storage
#[derive(scale::Encode, scale::Decode)]
#[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
pub struct UserProfile {
    name: Vec<u8>,
    age: u8,
    verified: bool,
}

// Custom enum for storage
#[derive(scale::Encode, scale::Decode)]
#[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
pub enum Status {
    Pending,
    Active { since: u64 },
    Suspended { reason: Vec<u8> },
}

#[ink(storage)]
pub struct ProfileContract {
    profiles: ink::storage::Mapping<AccountId, UserProfile>,
    user_status: ink::storage::Mapping<AccountId, Status>,
}
```

**Required trait implementations:**
- `scale::Encode`: Serializes data for storage
- `scale::Decode`: Deserializes data from storage  
- `scale_info::TypeInfo`: Provides type metadata (std feature only)

### Collections: Vec and BTreeMap

Standard Rust collections work in storage but with performance caveats:

```rust
use ink::prelude::{vec::Vec, collections::BTreeMap};

#[ink(storage)]
pub struct CollectionStorage {
    // Vector - good for small, sequential data
    items: Vec<u32>,
    
    // BTreeMap - good for small, sorted key-value data
    metadata: BTreeMap<Vec<u8>, Vec<u8>>,
}

impl CollectionStorage {
    #[ink(message)]
    pub fn add_item(&mut self, item: u32) {
        self.items.push(item); // Rewrites entire vector!
    }
    
    #[ink(message)]
    pub fn get_item(&self, index: usize) -> Option<u32> {
        self.items.get(index).copied() // Reads entire vector!
    }
}
```

**Performance warnings:**
- **Vec operations**: Any modification rewrites the entire vector
- **BTreeMap operations**: Potentially rebalances and rewrites tree structure
- **Gas costs scale with collection size**: $O(n)$ for most operations

## The Mapping Type: Your Primary Tool

The `ink::storage::Mapping` type is specifically designed for efficient blockchain storage:

### Basic Mapping Usage

```rust
use ink::storage::Mapping;

#[ink(storage)]
pub struct TokenContract {
    // Key-value storage with individual item access
    balances: Mapping<AccountId, Balance>,
    allowances: Mapping<(AccountId, AccountId), Balance>,
}

impl TokenContract {
    #[ink(constructor)]
    pub fn new(total_supply: Balance) -> Self {
        let mut balances = Mapping::default();
        let caller = Self::env().caller();
        balances.insert(caller, &total_supply);
        
        Self {
            balances,
            allowances: Mapping::default(),
        }
    }
    
    #[ink(message)]
    pub fn balance_of(&self, account: AccountId) -> Balance {
        // Returns default value (0) if key doesn't exist
        self.balances.get(account).unwrap_or(0)
    }
    
    #[ink(message)]
    pub fn transfer(&mut self, to: AccountId, amount: Balance) -> Result<(), Error> {
        let caller = self.env().caller();
        let caller_balance = self.balance_of(caller);
        
        if caller_balance < amount {
            return Err(Error::InsufficientBalance);
        }
        
        // Update balances - each operation touches only one storage slot
        let new_caller_balance = caller_balance - amount;
        let to_balance = self.balance_of(to);
        let new_to_balance = to_balance + amount;
        
        self.balances.insert(caller, &new_caller_balance);
        self.balances.insert(to, &new_to_balance);
        
        Ok(())
    }
}
```

### Mapping Key Types

Mappings support complex key types through hashing:

```rust
#[ink(storage)]
pub struct ComplexMappings {
    // Simple keys
    simple: Mapping<AccountId, Balance>,
    
    // Tuple keys - useful for relationships
    approvals: Mapping<(AccountId, AccountId), Balance>,
    
    // String keys (as Vec<u8>)
    names: Mapping<Vec<u8>, AccountId>,
    
    // Custom struct keys
    positions: Mapping<Position, PlayerData>,
}

// Custom key type
#[derive(scale::Encode, scale::Decode, PartialEq, Eq)]
#[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
pub struct Position {
    x: i32,
    y: i32,
}

#[derive(scale::Encode, scale::Decode)]
#[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
pub struct PlayerData {
    health: u32,
    score: u64,
}
```

### Mapping Internals: How Keys Become Storage Addresses

Understanding mapping internals helps optimize gas usage:

```rust
// Conceptual implementation (simplified)
impl<K, V> Mapping<K, V> {
    fn storage_key(&self, key: &K) -> [u8; 32] {
        let encoded_key = scale::Encode::encode(key);
        let base_key = self.base_key(); // From storage position
        
        // Combine base key with encoded key using cryptographic hash
        Blake2b256::hash(&[base_key.as_slice(), encoded_key.as_slice()])
    }
    
    fn get(&self, key: K) -> Option<V> {
        let storage_key = self.storage_key(&key);
        self.env().storage().get(&storage_key)
    }
    
    fn insert(&mut self, key: K, value: &V) {
        let storage_key = self.storage_key(&key);
        self.env().storage().set(&storage_key, value);
    }
}
```

**Gas analysis:**
- **Key hashing**: ~50 gas per key hash
- **Storage read**: ~200 gas + value size
- **Storage write**: ~5,000 gas + value size
- **Complex keys**: Additional encoding overhead

## Advanced Storage Strategies

### Lazy Loading with ink::storage::Lazy

The `Lazy<T>` type prevents automatic loading of large storage items:

```rust
use ink::storage::Lazy;

#[ink(storage)]
pub struct OptimizedContract {
    // Always loaded (small, frequently accessed)
    owner: AccountId,
    counter: u32,
    
    // Lazy loaded (large, infrequently accessed)
    large_data: Lazy<Vec<u8>>,
    configuration: Lazy<Config>,
}

#[derive(scale::Encode, scale::Decode)]
#[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
pub struct Config {
    settings: BTreeMap<Vec<u8>, Vec<u8>>,
    thresholds: [u64; 100],
    metadata: Vec<u8>,
}

impl OptimizedContract {
    #[ink(constructor)]
    pub fn new() -> Self {
        Self {
            owner: Self::env().caller(),
            counter: 0,
            // Lazy items start uninitialized
            large_data: Lazy::new(),
            configuration: Lazy::new(),
        }
    }
    
    #[ink(message)]
    pub fn increment(&mut self) {
        // Fast operation - no lazy loading triggered
        self.counter += 1;
    }
    
    #[ink(message)]
    pub fn set_config(&mut self, config: Config) {
        // Only loads/stores when explicitly accessed
        self.configuration.set(&config);
    }
    
    #[ink(message)]
    pub fn get_config_setting(&self, key: &[u8]) -> Option<Vec<u8>> {
        // Loads entire config from storage
        self.configuration.get()
            .and_then(|config| config.settings.get(key).cloned())
    }
}
```

**When to use Lazy:**
- Large data structures (> 1KB)
- Infrequently accessed data
- Optional configuration data
- Historical data that's rarely queried

**Gas savings example:**
```rust
// Without Lazy: Every message loads entire storage struct
// Gas cost: 10,000 (base) + 50,000 (large_data) + 30,000 (config) = 90,000

// With Lazy: Only loads accessed items
// Gas cost: 10,000 (base) + 0 (lazy items) = 10,000
```

### Memory Optimization with ink::storage::Packed

The `Packed<T>` type optimizes memory layout for small structs:

```rust
use ink::storage::{Mapping, Packed};

// Small struct that benefits from packing
#[derive(scale::Encode, scale::Decode, PackedLayout)]
#[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
pub struct UserStats {
    level: u8,        // 1 byte
    experience: u32,  // 4 bytes  
    active: bool,     // 1 byte
    // Total: 6 bytes instead of potential 12 with padding
}

#[ink(storage)]
pub struct GameContract {
    // Packed storage for small, frequently accessed data
    user_stats: Mapping<AccountId, Packed<UserStats>>,
    
    // Regular storage for larger data
    user_profiles: Mapping<AccountId, UserProfile>,
}

impl GameContract {
    #[ink(message)]
    pub fn level_up(&mut self, user: AccountId) -> Result<(), Error> {
        // Load packed data efficiently
        let mut stats = self.user_stats.get(user)
            .unwrap_or_default();
        
        // Modify through packed interface
        stats.level = stats.level.saturating_add(1);
        stats.experience = 0;
        
        // Store packed data
        self.user_stats.insert(user, &stats);
        
        Ok(())
    }
}
```

**Packed benefits:**
- **Reduced storage costs**: Smaller serialized size
- **Better cache locality**: More data fits in each storage read
- **Lower gas costs**: Fewer storage operations needed

**When NOT to use Packed:**
- Large structs (> 100 bytes)
- Structs with complex nested data
- Data that changes frequently (unpacking overhead)

### Storage Clearing and Cleanup

Implement cleanup functions to recover storage costs:

```rust
#[ink::contract]
mod cleanable_contract {
    use ink::storage::Mapping;

    #[ink(storage)]
    pub struct CleanableContract {
        data: Mapping<AccountId, Vec<u8>>,
        expired_keys: Vec<AccountId>,
    }

    impl CleanableContract {
        #[ink(message)]
        pub fn clear_user_data(&mut self, user: AccountId) -> Result<(), Error> {
            // Check authorization
            if self.env().caller() != user {
                return Err(Error::Unauthorized);
            }
            
            // Remove from mapping - storage cost is refunded
            self.data.remove(user);
            Ok(())
        }
        
        #[ink(message)]
        pub fn batch_cleanup(&mut self, users: Vec<AccountId>) -> u32 {
            let mut cleaned = 0;
            
            for user in users.iter().take(50) { // Limit batch size
                if self.data.contains(user) {
                    self.data.remove(*user);
                    cleaned += 1;
                }
            }
            
            cleaned
        }
        
        #[ink(message)]
        pub fn storage_info(&self) -> (u32, u32) {
            // Note: These are estimates since mappings don't track size
            let approximate_entries = self.expired_keys.len() as u32;
            let storage_bytes = approximate_entries * 100; // Rough estimate
            
            (approximate_entries, storage_bytes)
        }
    }
}
```

## Storage Patterns and Best Practices

### Pattern 1: Hierarchical Data with Compound Keys

For complex relationships, use tuple keys to create hierarchical storage:

```rust
#[ink(storage)]
pub struct ForumContract {
    // posts[forum_id][post_id] = Post
    posts: Mapping<(u32, u32), Post>,
    
    // comments[post_id][comment_id] = Comment  
    comments: Mapping<(u32, u32), Comment>,
    
    // user_posts[user][post_id] = true (existence mapping)
    user_posts: Mapping<(AccountId, u32), ()>,
    
    // Counters for ID generation
    next_post_id: u32,
    next_comment_id: u32,
}

impl ForumContract {
    #[ink(message)]
    pub fn create_post(&mut self, forum_id: u32, content: Vec<u8>) -> Result<u32, Error> {
        let post_id = self.next_post_id;
        let author = self.env().caller();
        
        let post = Post {
            author,
            content,
            timestamp: self.env().block_timestamp(),
        };
        
        // Store with compound key
        self.posts.insert((forum_id, post_id), &post);
        self.user_posts.insert((author, post_id), &());
        
        self.next_post_id += 1;
        Ok(post_id)
    }
    
    #[ink(message)]
    pub fn get_user_posts(&self, user: AccountId, limit: u32) -> Vec<u32> {
        // Note: This is inefficient - in practice, you'd maintain
        // a separate user_post_list mapping for efficient queries
        let mut posts = Vec::new();
        
        // This would require iterating all possible post IDs
        // Better to maintain separate index structures
        
        posts
    }
}
```

### Pattern 2: Pagination for Large Data Sets

Implement pagination to handle large collections efficiently:

```rust
#[ink(storage)]
pub struct PaginatedContract {
    // Main data storage
    items: Mapping<u32, Item>,
    
    // Pagination indices
    item_count: u32,
    items_per_page: u32,
    
    // Optional: Category indices for filtered pagination
    category_items: Mapping<(Category, u32), u32>, // (category, index) -> item_id
    category_counts: Mapping<Category, u32>,
}

impl PaginatedContract {
    #[ink(message)]
    pub fn get_items_page(&self, page: u32, per_page: u32) -> Result<Vec<Item>, Error> {
        let max_per_page = 50; // Prevent gas limit issues
        let actual_per_page = per_page.min(max_per_page);
        
        let start_id = page * actual_per_page;
        let end_id = (start_id + actual_per_page).min(self.item_count);
        
        let mut results = Vec::new();
        
        for item_id in start_id..end_id {
            if let Some(item) = self.items.get(item_id) {
                results.push(item);
            }
        }
        
        Ok(results)
    }
    
    #[ink(message)]
    pub fn get_category_page(&self, category: Category, page: u32) -> Result<Vec<Item>, Error> {
        let category_count = self.category_counts.get(category).unwrap_or(0);
        let per_page = 20;
        let start_index = page * per_page;
        let end_index = (start_index + per_page).min(category_count);
        
        let mut results = Vec::new();
        
        for index in start_index..end_index {
            if let Some(item_id) = self.category_items.get((category, index)) {
                if let Some(item) = self.items.get(item_id) {
                    results.push(item);
                }
            }
        }
        
        Ok(results)
    }
}
```

### Pattern 3: Efficient Existence Checks

Use empty tuples `()` as values for efficient set-like behavior:

```rust
#[ink(storage)]
pub struct AccessControlContract {
    // Set membership using () as value
    admins: Mapping<AccountId, ()>,
    banned_users: Mapping<AccountId, ()>,
    
    // Time-based permissions
    temporary_access: Mapping<AccountId, u64>, // account -> expiry_timestamp
}

impl AccessControlContract {
    #[ink(message)]
    pub fn add_admin(&mut self, account: AccountId) -> Result<(), Error> {
        self.ensure_admin()?;
        self.admins.insert(account, &());
        Ok(())
    }
    
    #[ink(message)]
    pub fn is_admin(&self, account: AccountId) -> bool {
        self.admins.contains(account)
    }
    
    #[ink(message)]  
    pub fn has_access(&self, account: AccountId) -> bool {
        // Check if admin
        if self.admins.contains(account) {
            return true;
        }
        
        // Check if banned
        if self.banned_users.contains(account) {
            return false;
        }
        
        // Check temporary access
        if let Some(expiry) = self.temporary_access.get(account) {
            return self.env().block_timestamp() < expiry;
        }
        
        false
    }
    
    fn ensure_admin(&self) -> Result<(), Error> {
        if !self.is_admin(self.env().caller()) {
            return Err(Error::Unauthorized);
        }
        Ok(())
    }
}
```

## Gas Optimization Strategies

### 1. Minimize Storage Operations

```rust
// ❌ Inefficient: Multiple storage writes
#[ink(message)]
pub fn bad_transfer(&mut self, to: AccountId, amount: Balance) -> Result<(), Error> {
    let caller = self.env().caller();
    
    // Each balance_of() call reads from storage
    if self.balance_of(caller) < amount {
        return Err(Error::InsufficientBalance);
    }
    
    // Multiple storage writes
    self.balances.insert(caller, &(self.balance_of(caller) - amount));
    self.balances.insert(to, &(self.balance_of(to) + amount));
    
    Ok(())
}

// ✅ Efficient: Batch reads, minimize writes
#[ink(message)]
pub fn good_transfer(&mut self, to: AccountId, amount: Balance) -> Result<(), Error> {
    let caller = self.env().caller();
    
    // Read once, store in memory
    let caller_balance = self.balances.get(caller).unwrap_or(0);
    let to_balance = self.balances.get(to).unwrap_or(0);
    
    if caller_balance < amount {
        return Err(Error::InsufficientBalance);
    }
    
    // Calculate new balances in memory
    let new_caller_balance = caller_balance - amount;
    let new_to_balance = to_balance + amount;
    
    // Write once per account
    self.balances.insert(caller, &new_caller_balance);
    self.balances.insert(to, &new_to_balance);
    
    Ok(())
}
```

### 2. Use Appropriate Data Types

```rust
// ❌ Oversized types waste gas
#[ink(storage)]
pub struct WastefulStorage {
    small_counter: u256,    // Overkill for counters
    flags: Vec<bool>,       // Vec has overhead for simple flags
    status: String,         // String has UTF-8 overhead
}

// ✅ Right-sized types save gas
#[ink(storage)]
pub struct EfficientStorage {
    small_counter: u32,     // Sufficient for most counters
    flags: u64,             // Bitfield for up to 64 boolean flags
    status: u8,             // Enum represented as u8
}

impl EfficientStorage {
    // Bitfield operations for flags
    fn set_flag(&mut self, position: u8, value: bool) {
        if position < 64 {
            if value {
                self.flags |= 1 << position;
            } else {
                self.flags &= !(1 << position);
            }
        }
    }
    
    fn get_flag(&self, position: u8) -> bool {
        if position < 64 {
            (self.flags >> position) & 1 == 1
        } else {
            false
        }
    }
}
```

### 3. Lazy Initialization Patterns

```rust
#[ink(storage)]
pub struct LazyContract {
    // Always present
    owner: AccountId,
    
    // Lazy-initialized when first needed
    configuration: Lazy<Configuration>,
    user_data: Mapping<AccountId, UserData>,
}

impl LazyContract {
    #[ink(constructor)]
    pub fn new() -> Self {
        Self {
            owner: Self::env().caller(),
            // Don't initialize Lazy - saves deployment gas
            configuration: Lazy::new(),
            user_data: Mapping::default(),
        }
    }
    
    #[ink(message)]
    pub fn get_config(&self) -> Configuration {
        // Initialize with default if not present
        self.configuration.get().unwrap_or_else(|| {
            Configuration::default()
        })
    }
    
    #[ink(message)]
    pub fn set_config(&mut self, config: Configuration) -> Result<(), Error> {
        self.ensure_owner()?;
        self.configuration.set(&config);
        Ok(())
    }
}
```

## Testing Storage Behavior

### Unit Tests for Storage Logic

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[ink::test]
    fn storage_operations_work() {
        let mut contract = MyContract::new();
        
        // Test initial state
        assert_eq!(contract.get_value(1), None);
        
        // Test insertion
        contract.set_value(1, 42);
        assert_eq!(contract.get_value(1), Some(42));
        
        // Test overwrite
        contract.set_value(1, 100);
        assert_eq!(contract.get_value(1), Some(100));
        
        // Test multiple keys
        contract.set_value(2, 200);
        assert_eq!(contract.get_value(1), Some(100));
        assert_eq!(contract.get_value(2), Some(200));
    }
    
    #[ink::test]
    fn large_data_storage() {
        let mut contract = MyContract::new();
        
        // Test storage of larger data structures
        let large_vec: Vec<u8> = (0..1000).map(|i| (i % 256) as u8).collect();
        contract.set_large_data(large_vec.clone());
        
        assert_eq!(contract.get_large_data(), Some(large_vec));
    }
    
    #[ink::test] 
    fn mapping_edge_cases() {
        let mut contract = MyContract::new();
        
        // Test with complex keys
        let key1 = (AccountId::from([1; 32]), 42u32);
        let key2 = (AccountId::from([2; 32]), 42u32);
        
        contract.set_complex_value(key1, vec![1, 2, 3]);
        contract.set_complex_value(key2, vec![4, 5, 6]);
        
        assert_eq!(contract.get_complex_value(key1), Some(vec![1, 2, 3]));
        assert_eq!(contract.get_complex_value(key2), Some(vec![4, 5, 6]));
    }
}
```

### Property-Based Testing for Storage

```rust
#[cfg(test)]
mod property_tests {
    use super::*;
    use quickcheck::{quickcheck, TestResult};

    #[quickcheck]
    fn storage_consistency(operations: Vec<(u32, Option<u32>)>) -> TestResult {
        let mut contract = MyContract::new();
        let mut expected_state = std::collections::HashMap::new();
        
        for (key, value_opt) in operations {
            match value_opt {
                Some(value) => {
                    contract.set_value(key, value);
                    expected_state.insert(key, value);
                }
                None => {
                    contract.remove_value(key);
                    expected_state.remove(&key);
                }
            }
            
            // Verify consistency after each operation
            for (&check_key, &expected_value) in &expected_state {
                if contract.get_value(check_key) != Some(expected_value) {
                    return TestResult::failed();
                }
            }
        }
        
        TestResult::passed()
    }
}
```

## Common Storage Pitfalls and Solutions

### Pitfall 1: Large Vector Modifications

```rust
// ❌ Problem: Modifying large vectors is extremely expensive
#[ink(storage)]
pub struct ExpensiveContract {
    items: Vec<Item>,  // Gets rewritten entirely on each modification
}

// ❌ This rewrites the entire vector for each push
impl ExpensiveContract {
    #[ink(message)]
    pub fn add_item(&mut self, item: Item) {
        self.items.push(item); // O(n) gas cost!
    }
}

// ✅ Solution: Use Mapping for individual item access
#[ink(storage)]
pub struct EfficientContract {
    items: Mapping<u32, Item>,
    item_count: u32,
}

impl EfficientContract {
    #[ink(message)]
    pub fn add_item(&mut self, item: Item) {
        self.items.insert(self.item_count, &item); // O(1) gas cost
        self.item_count += 1;
    }
}
```

### Pitfall 2: Inefficient Existence Checks

```rust
// ❌ Problem: Loading entire values just to check existence
#[ink(message)]
pub fn expensive_contains(&self, user: AccountId) -> bool {
    self.user_data.get(user).is_some() // Loads entire UserData struct!
}

// ✅ Solution: Use separate existence mapping
#[ink(storage)]
pub struct OptimizedContract {
    user_data: Mapping<AccountId, UserData>,
    user_exists: Mapping<AccountId, ()>, // Just for existence checks
}

#[ink(message)]
pub fn cheap_contains(&self, user: AccountId) -> bool {
    self.user_exists.contains(user) // Only checks key existence
}
```

### Pitfall 3: Unbounded Loops Over Storage

```rust
// ❌ Problem: Loops that could exceed gas limits
#[ink(message)]
pub fn dangerous_sum(&self) -> u32 {
    let mut sum = 0;
    // This could run out of gas if there are many items
    for i in 0..self.item_count {
        if let Some(value) = self.items.get(i) {
            sum += value;
        }
    }
    sum
}

// ✅ Solution: Implement pagination or maintain aggregates
#[ink(storage)]
pub struct SafeContract {
    items: Mapping<u32, u32>,
    item_count: u32,
    running_sum: u32, // Maintained incrementally
}

#[ink(message)]
pub fn safe_sum(&self) -> u32 {
    self.running_sum // O(1) access
}

#[ink(message)]
pub fn add_item(&mut self, value: u32) {
    self.items.insert(self.item_count, &value);
    self.running_sum += value; // Update aggregate
    self.item_count += 1;
}
```

## Summary

In this chapter, we've explored the sophisticated storage system that makes ink! contracts efficient and scalable:

**Key Storage Concepts:**

1. **Single Storage Root**: Every contract has exactly one `#[ink(storage)]` struct that serves as the root of all persistent data

2. **Storage Key Generation**: Deterministic key generation ensures consistent access patterns and upgrade safety  

3. **Type Support**: From primitives to complex custom types, with required SCALE codec implementations

4. **Mapping Efficiency**: The primary tool for key-value storage with $O(1)$ access patterns

**Advanced Techniques:**

5. **Lazy Loading**: `Lazy<T>` prevents automatic loading of large, infrequently accessed data

6. **Memory Packing**: `Packed<T>` optimizes storage layout for small structs  

7. **Storage Patterns**: Hierarchical data with compound keys, pagination for large sets, and efficient existence checks

**Optimization Strategies:**

8. **Gas Efficiency**: Minimize storage operations, use appropriate data types, and implement lazy initialization

9. **Avoiding Pitfalls**: Understanding why large vector modifications, inefficient existence checks, and unbounded loops can be expensive

**Testing Approaches:**

10. **Comprehensive Testing**: Both unit tests for logic and property-based tests for storage consistency

With a solid understanding of storage management, you're ready to build the logic layer that operates on this persistent state. In the next chapter, we'll explore how to design robust message handlers and constructors that leverage your storage system effectively.
