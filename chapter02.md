# Chapter 2: Anatomy of an ink! Contract: Your First Build

The best way to see ink!’s shape is to compare it to what came before. Solidity is expressive but permissive; it trusts you to remember every overflow, every reentrancy, every storage write you forgot to persist. ink! is demanding: you must make errors explicit with `Result`, you must request mutability when you intend to change state, you must choose checked arithmetic if the numbers might betray you. In return, the compiler becomes your first auditor. The polkadot-sdk stack welcomes these Wasm contracts inside `pallet-contracts`, an execution engine that meters gas, persists key–value storage, dispatches messages, and emits events that off‑chain clients can index. Your development environment is pleasantly ordinary: install Rust with `rustup`, add the `wasm32-unknown-unknown` target, install `cargo-contract`, and you can scaffold, build, and inspect artifacts (.wasm, metadata.json, and the bundled .contract) with a few terminal commands. The ritual is simple but powerful: write Rust, mark a struct as `#[ink(storage)]`, annotate your constructors and messages, then `cargo contract build` and ship a Wasm that any polkadot-sdk node can execute. Soon you will feel the rhythm: a contract is just a Rust module with a storage root at its heart and a public surface of messages that the world may call.

Every ink! developer begins their journey with the flipper contract—a simple boolean toggle that demonstrates the fundamental building blocks of smart contract development. While deceptively simple, this contract introduces every core concept you'll use in sophisticated applications: storage management, state transitions, message handling, and the compilation pipeline.

In this chapter, we'll build the flipper contract from scratch, dissecting each component to understand how ink! transforms Rust code into deployable WebAssembly contracts. By the end, you'll understand the complete development cycle and be ready to tackle more complex contract architectures.

## Project Scaffolding: Creating Your First Contract

Let's begin by generating a new ink! project and examining the structure it creates.

### Generating the Project

```bash
# Create a new ink! contract project
cargo contract new flipper

# Navigate to the project directory
cd flipper

# Examine the project structure
tree .
```

Expected output:
```
flipper/
├── Cargo.toml
├── lib.rs
└── .gitignore
```

### Understanding Cargo.toml

The `Cargo.toml` file configures your ink! project with specific dependencies and features:

```toml
[package]
name = "flipper"
version = "0.1.0"
authors = ["Your Name <your.email@example.com>"]
edition = "2021"

[dependencies]
ink = { version = "4.3", default-features = false }

[lib]
path = "lib.rs"

[[bin]]
name = "flipper"
path = "lib.rs"

[features]
default = ["std"]
std = [
    "ink/std",
]
ink-as-dependency = []
```

**Key Configuration Details:**

- **`default-features = false`**: Disables standard library features by default
- **`std` feature**: Enables standard library support for testing and development
- **`ink-as-dependency`**: Allows this contract to be used as a dependency by other contracts
- **`[[bin]]` section**: Configures the contract as an executable binary for deployment

### The Feature Flag Pattern

ink! uses Rust's feature flag system to handle the dual nature of contract development:

```rust
#![cfg_attr(not(feature = "std"), no_std)]
```

This conditional compilation attribute means:
- **During development/testing**: `std` feature is enabled, allowing use of the standard library
- **During contract compilation**: `std` feature is disabled, creating a `no_std` environment suitable for WebAssembly

## The Anatomy of lib.rs: A Complete Walkthrough

Let's examine the complete flipper contract and understand each component:

```rust
#![cfg_attr(not(feature = "std"), no_std)]

#[ink::contract]
mod flipper {

    /// The storage struct that defines the contract's persistent state
    #[ink(storage)]
    pub struct Flipper {
        value: bool,
    }

    impl Flipper {
        /// Constructor that initializes the contract with a given value
        /// 
        /// # Arguments
        /// * `init_value` - The initial boolean value for the flipper
        #[ink(constructor)]
        pub fn new(init_value: bool) -> Self {
            Self { value: init_value }
        }

        /// Default constructor that initializes the contract with `false`
        #[ink(constructor)]
        pub fn default() -> Self {
            Self::new(Default::default())
        }

        /// Flips the current boolean value
        /// 
        /// This is a mutable message that changes the contract's state
        #[ink(message)]
        pub fn flip(&mut self) {
            self.value = !self.value;
        }

        /// Returns the current boolean value
        /// 
        /// This is an immutable message that only reads state
        #[ink(message)]
        pub fn get(&self) -> bool {
            self.value
        }
    }

    /// Unit tests for the flipper contract
    /// 
    /// These tests run in a simulated environment and verify
    /// the contract logic without deploying to a blockchain
    #[cfg(test)]
    mod tests {
        use super::*;

        #[ink::test]
        fn default_works() {
            let flipper = Flipper::default();
            assert_eq!(flipper.get(), false);
        }

        #[ink::test]
        fn it_works() {
            let mut flipper = Flipper::new(false);
            assert_eq!(flipper.get(), false);
            flipper.flip();
            assert_eq!(flipper.get(), true);
        }
    }

    /// End-to-end tests that deploy the contract to a test node
    /// 
    /// These tests verify the complete deployment and interaction cycle
    #[cfg(all(test, feature = "e2e-tests"))]
    mod e2e_tests {
        use super::*;
        use ink_e2e::build_message;

        type E2EResult<T> = std::result::Result<T, Box<dyn std::error::Error>>;

        #[ink_e2e::test]
        async fn default_works(mut client: ink_e2e::Client<C, E>) -> E2EResult<()> {
            // Instantiate the contract with default constructor
            let constructor = FlipperRef::default();
            let contract_account_id = client
                .instantiate("flipper", &ink_e2e::alice(), constructor, 0, None)
                .await
                .expect("instantiate failed")
                .account_id;

            // Call the get message to verify initial state
            let get = build_message::<FlipperRef>(contract_account_id.clone())
                .call(|flipper| flipper.get());
            let get_result = client.call_dry_run(&ink_e2e::alice(), &get, 0, None).await;
            assert_eq!(get_result.return_value(), false);

            Ok(())
        }

        #[ink_e2e::test]
        async fn it_works(mut client: ink_e2e::Client<C, E>) -> E2EResult<()> {
            // Instantiate the contract
            let constructor = FlipperRef::new(false);
            let contract_account_id = client
                .instantiate("flipper", &ink_e2e::alice(), constructor, 0, None)
                .await
                .expect("instantiate failed")
                .account_id;

            // Verify initial state
            let get = build_message::<FlipperRef>(contract_account_id.clone())
                .call(|flipper| flipper.get());
            let get_result = client.call_dry_run(&ink_e2e::alice(), &get, 0, None).await;
            assert_eq!(get_result.return_value(), false);

            // Flip the value
            let flip = build_message::<FlipperRef>(contract_account_id.clone())
                .call(|flipper| flipper.flip());
            let _flip_result = client
                .call(&ink_e2e::alice(), flip, 0, None)
                .await
                .expect("flip failed");

            // Verify the value was flipped
            let get = build_message::<FlipperRef>(contract_account_id.clone())
                .call(|flipper| flipper.get());
            let get_result = client.call_dry_run(&ink_e2e::alice(), &get, 0, None).await;
            assert_eq!(get_result.return_value(), true);

            Ok(())
        }
    }
}
```

## Macro Deep Dive: Understanding ink! Attributes

ink! uses procedural macros to transform standard Rust code into smart contract components. Let's examine each macro in detail.

### #[ink::contract]

```rust
#[ink::contract]
mod flipper {
    // Contract definition goes here
}
```

The `#[ink::contract]` macro is the entry point that:

1. **Establishes the contract module**: Creates a namespace for the contract
2. **Generates boilerplate code**: Adds necessary traits and implementations
3. **Enables ink! macros**: Makes other ink! macros available within the module
4. **Creates the contract ABI**: Generates metadata for external interaction

Behind the scenes, this macro generates:
- Implementation of the `ink::codegen::ContractCallBuilder` trait
- Storage layout information for the runtime
- Message dispatch logic for incoming calls
- Metadata structure describing the contract interface

### #[ink(storage)]

```rust
#[ink(storage)]
pub struct Flipper {
    value: bool,
}
```

The storage macro transforms a regular Rust struct into the contract's persistent state:

**What it generates:**
- **Storage key mapping**: Each field gets a unique storage key
- **Serialization code**: Implements SCALE encoding/decoding for persistence
- **Storage access methods**: Creates optimized read/write operations
- **Root key computation**: Establishes the storage root for the contract

**Storage Layout:**
```
Storage Root: 0x00000000...
├── value: Key(0x00000001) -> bool
└── (future fields would get 0x00000002, 0x00000003, etc.)
```

**Critical constraints:**
- Only **one** struct per contract can have `#[ink(storage)]`
- All fields must implement `scale::Encode` and `scale::Decode`
- The struct becomes the single source of truth for contract state

### #[ink(constructor)]

```rust
#[ink(constructor)]
pub fn new(init_value: bool) -> Self {
    Self { value: init_value }
}
```

Constructor macros define how contracts are initialized:

**Generated functionality:**
- **Deployment dispatch**: Routes deployment calls to the correct constructor
- **State initialization**: Ensures storage is properly set up
- **Return value handling**: Manages the contract instance creation
- **Gas accounting**: Tracks gas usage during deployment

**Key characteristics:**
- Must return `Self` (the storage struct)
- Can accept parameters for customized initialization
- Multiple constructors are allowed (overloading)
- Cannot access `self.env()` (no environment context yet)

**Constructor vs. Function:**
```rust
// Constructor - called once during deployment
#[ink(constructor)]
pub fn new() -> Self {
    Self { value: false }
}

// Message - called after deployment
#[ink(message)]
pub fn initialize(&mut self) {
    self.value = false; // This modifies existing state
}
```

### #[ink(message)]

```rust
// Immutable message (read-only)
#[ink(message)]
pub fn get(&self) -> bool {
    self.value
}

// Mutable message (can modify state)
#[ink(message)]
pub fn flip(&mut self) {
    self.value = !self.value;
}
```

Message macros define the contract's public API:

**Generated functionality:**
- **Message dispatch**: Routes external calls to the correct method
- **Parameter serialization**: Handles input/output encoding
- **Gas metering**: Tracks and limits execution cost
- **Environment access**: Provides `self.env()` for blockchain interaction

**Immutable vs. Mutable Messages:**

| Aspect | `&self` (Immutable) | `&mut self` (Mutable) |
|--------|-------------------|----------------------|
| **State changes** | Not allowed | Allowed |
| **Gas cost** | Lower (no state writes) | Higher (potential state writes) |
| **Concurrency** | Multiple simultaneous calls | Sequential execution |
| **Rollback** | N/A | State reverts on error |

### Conditional Compilation Deep Dive

The `#![cfg_attr(not(feature = "std"), no_std)]` attribute manages dual compilation modes:

**Standard Mode (std enabled):**
```rust
// Full standard library available
use std::collections::HashMap;
use std::vec::Vec;

#[cfg(feature = "std")]
fn debug_function() {
    println!("Debug information"); // Available in std mode
}
```

**No-std Mode (contract compilation):**
```rust
// Limited to core and alloc
use ink::prelude::vec::Vec;
use ink::prelude::collections::BTreeMap;

#[cfg(not(feature = "std"))]
fn optimized_function() {
    // Code optimized for WASM execution
}
```

**Feature-gated dependencies:**
```toml
[dependencies]
ink = { version = "4.3", default-features = false }
scale = { version = "3", default-features = false, features = ["derive"] }

[features]
std = [
    "ink/std",
    "scale/std",
]
```

## The Compilation Pipeline: From Rust to WASM

Understanding the compilation process helps debug issues and optimize contracts.

### Step 1: Cargo Contract Build

```bash
cargo contract build
```

This command executes several phases:

#### Phase 1: Rust Compilation
```bash
# Equivalent to:
cargo build --target wasm32-unknown-unknown --release
```

**Compiler optimizations applied:**
- **Dead code elimination**: Removes unused functions
- **Inlining**: Reduces function call overhead
- **Constant folding**: Evaluates constants at compile time
- **Loop optimization**: Unrolls small loops for performance

#### Phase 2: WASM Optimization
```bash
# Using wasm-opt (part of Binaryen toolkit)
wasm-opt target/wasm32-unknown-unknown/release/flipper.wasm \
    -o optimized.wasm \
    -Oz  # Optimize for size
```

**Optimizations include:**
- **Size reduction**: Removes metadata and debug info
- **Instruction optimization**: Uses more efficient WASM instructions
- **Memory layout optimization**: Improves cache locality

#### Phase 3: Metadata Generation

The build process generates contract metadata in JSON format:

```json
{
  "source": {
    "hash": "0x1234...",
    "language": "ink! 4.3.0",
    "compiler": "rustc 1.75.0"
  },
  "contract": {
    "name": "flipper",
    "version": "0.1.0",
    "authors": ["Developer"]
  },
  "spec": {
    "constructors": [
      {
        "label": "new",
        "payable": false,
        "selector": "0x9bae9d5e",
        "args": [
          {
            "label": "init_value",
            "type": {
              "displayName": ["bool"],
              "type": 0
            }
          }
        ],
        "docs": ["Constructor that initializes..."]
      }
    ],
    "messages": [
      {
        "label": "flip",
        "mutates": true,
        "payable": false,
        "selector": "0x633aa551",
        "args": [],
        "returnType": null,
        "docs": ["Flips the current boolean value"]
      }
    ]
  }
}
```

**Metadata purposes:**
- **UI generation**: Enables automatic UI creation for contract interaction
- **Type safety**: Provides type information for external callers
- **Documentation**: Includes inline documentation for methods
- **Selector mapping**: Maps function selectors to method names

### Step 4: Bundle Creation

The final `.contract` file combines the WASM binary and metadata:

```bash
# Bundle structure (simplified)
flipper.contract = {
    "wasm": "<base64-encoded-wasm-binary>",
    "metadata": { /* metadata object */ }
}
```

## Build Output Analysis

Let's examine the artifacts created by the build process:

### Directory Structure After Build

```bash
ls -la target/ink/
```

```
target/ink/
├── flipper.wasm          # Optimized WebAssembly binary (3.2KB)
├── flipper.json          # Contract metadata (15.7KB)
└── flipper.contract      # Bundle file (18.9KB)
```

### WASM Binary Analysis

```bash
# Examine WASM structure using wasm-objdump
wasm-objdump -h target/ink/flipper.wasm
```

Expected sections:
```
Sections:
     Type start=0x0000000a end=0x00000023 (size=0x00000019) count: 6
 Function start=0x00000025 end=0x0000002e (size=0x00000009) count: 8
    Table start=0x00000030 end=0x00000035 (size=0x00000005) count: 1
   Memory start=0x00000037 end=0x0000003a (size=0x00000003) count: 1
   Global start=0x0000003c end=0x00000047 (size=0x0000000b) count: 1
   Export start=0x00000049 end=0x000000ce (size=0x00000085) count: 7
     Code start=0x000000d1 end=0x00000c53 (size=0x00000b82) count: 8
```

### Gas Estimation

```bash
# Estimate gas usage for contract operations
cargo contract call --contract $CONTRACT_ADDRESS \
                   --message get \
                   --dry-run
```

Typical gas usage for flipper operations:
- **Deployment**: ~150,000 gas
- **flip()**: ~8,000 gas
- **get()**: ~2,000 gas

### Memory Layout

The contract's memory layout in WASM:

```
WASM Memory Layout:
┌─────────────────┐ 0x10000 (64KB)
│   Stack Space   │
├─────────────────┤ 0x8000
│  Contract Data  │
├─────────────────┤ 0x4000
│ Global Variables│
├─────────────────┤ 0x1000
│  Static Data    │
└─────────────────┘ 0x0000
```

## Advanced Build Configuration

### Custom Optimization Settings

Create a `.cargo/config.toml` file for custom build settings:

```toml
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

### Feature Flags for Different Builds

```toml
[features]
default = ["std"]
std = ["ink/std"]

# Enable additional optimizations
aggressive-optimizations = []

# Enable debug prints in WASM
debug-prints = []

# Enable ink! allocator debugging
ink-debug = ["ink/ink-debug"]
```

### Build Scripts for Complex Projects

Create a `build.sh` script for reproducible builds:

```bash
#!/bin/bash

# Clean previous builds
cargo contract clean

# Build with maximum optimizations
RUSTFLAGS="-C target-cpu=mvp -C target-feature=-sign-ext" \
cargo contract build --release

# Verify the build
echo "Build artifacts:"
ls -lh target/ink/

# Check WASM size
echo "WASM size: $(wc -c < target/ink/flipper.wasm) bytes"

# Validate metadata
echo "Validating metadata..."
cargo contract info target/ink/flipper.contract
```

## Troubleshooting Common Build Issues

### Issue: "cannot find macro `ink` in this scope"

**Cause**: Missing or incorrect ink! dependency

**Solution**:
```toml
[dependencies]
ink = { version = "4.3", default-features = false }

[features]
std = ["ink/std"]
```

### Issue: "trait bound `MyStruct: scale::Encode` is not satisfied"

**Cause**: Custom types in storage must implement SCALE codecs

**Solution**:
```rust
#[derive(scale::Encode, scale::Decode)]
#[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
pub struct MyStruct {
    field: u32,
}
```

### Issue: WASM binary too large

**Cause**: Inefficient code or large dependencies

**Solutions**:
1. **Remove debug symbols**:
   ```toml
   [profile.release]
   debug = false
   ```

2. **Enable aggressive optimizations**:
   ```toml
   [profile.release]
   opt-level = "z"
   lto = true
   codegen-units = 1
   ```

3. **Review dependencies**: Remove unnecessary crates

### Issue: "memory allocation failed"

**Cause**: Contract exceeds memory limits

**Solution**: Increase stack size:
```toml
[target.wasm32-unknown-unknown]
rustflags = ["-C", "link-arg=-z", "-C", "link-arg=stack-size=131072"]
```

## Best Practices for Contract Structure

### 1. Organize Code with Modules

```rust
#[ink::contract]
mod my_contract {
    // Keep the storage struct simple
    #[ink(storage)]
    pub struct MyContract {
        // Only essential state here
    }

    // Organize complex logic in implementation blocks
    impl MyContract {
        // Constructors first
        #[ink(constructor)]
        pub fn new() -> Self { /* ... */ }

        // Public messages next
        #[ink(message)]
        pub fn public_method(&self) { /* ... */ }

        // Private helper methods last
        fn private_helper(&self) { /* ... */ }
    }

    // Separate error definitions
    #[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub enum Error {
        CustomError,
    }
}
```

### 2. Document Everything

```rust
/// A simple flipper contract for demonstration
/// 
/// This contract maintains a boolean value that can be toggled
/// and provides read access to external callers.
#[ink::contract]
mod flipper {
    /// The contract's storage containing a single boolean value
    /// 
    /// This value represents the current state of the flipper
    /// and persists across contract calls.
    #[ink(storage)]
    pub struct Flipper {
        /// The current boolean state
        value: bool,
    }

    impl Flipper {
        /// Creates a new flipper contract with the specified initial value
        /// 
        /// # Arguments
        /// 
        /// * `init_value` - The initial boolean value for the flipper
        /// 
        /// # Examples
        /// 
        /// ```
        /// let flipper = Flipper::new(true);
        /// assert_eq!(flipper.get(), true);
        /// ```
        #[ink(constructor)]
        pub fn new(init_value: bool) -> Self {
            Self { value: init_value }
        }
    }
}
```

### 3. Use Type Aliases for Clarity

```rust
#[ink::contract]
mod flipper {
    // Type aliases improve readability
    type FlipCount = u32;
    type FlipperResult<T> = Result<T, Error>;

    #[ink(storage)]
    pub struct Flipper {
        value: bool,
        flip_count: FlipCount,
    }
}
```

## Summary

In this chapter, we deconstructed the flipper contract to understand the fundamental building blocks of ink! development:

**Key Concepts Learned:**

1. **Project Structure**: How `cargo contract new` scaffolds a complete ink! project with proper configuration

2. **Macro System**: Deep understanding of `#[ink::contract]`, `#[ink(storage)]`, `#[ink(constructor)]`, and `#[ink(message)]` macros

3. **Compilation Pipeline**: From Rust source to optimized WebAssembly, including metadata generation

4. **Build Artifacts**: Understanding the purpose and contents of `.wasm`, `.json`, and `.contract` files

5. **Feature Flags**: How ink! uses conditional compilation to support both development and production environments

6. **Testing Framework**: Both unit tests and end-to-end tests for comprehensive validation

**Essential Patterns:**
- Storage structs as the single source of truth
- Constructor overloading for flexible initialization
- Immutable vs. mutable message patterns
- Comprehensive error handling with custom error types

With this foundation, you're ready to explore more sophisticated state management patterns. In the next chapter, we'll dive deep into ink!'s storage system, learning how to efficiently manage complex data structures and optimize for gas costs.
