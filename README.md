# Sui Multi-Signature Treasury

A production-ready, gas-efficient multi-signature treasury system for Sui Move with advanced policy management and emergency controls.

## Features

### 🔐 Multi-Signature Security
- Flexible signer list management
- Configurable approval thresholds
- Signature replay protection
- Atomic batch execution (up to 50 transactions)

### 📋 Proposal System
- Multiple proposal types (withdrawal, add/remove signer, update threshold)
- Time-lock enforcement
- Proposal cancellation by creator or unanimous vote
- Comprehensive event logging

### 🛡️ Policy Management
- **Spending Limits**: Daily/weekly/monthly spending caps with automatic reset
- **Whitelist**: Approved recipients with expiration dates
- **Category Policies**: Required categories for proposals
- **Amount Thresholds**: Different signature requirements based on amount
- **Time-Lock Formula**: Dynamic time-locks based on transaction amount

### 🚨 Emergency Module
- Emergency signer list with super-majority threshold (minimum 66%)
- Treasury freeze/unfreeze capabilities
- Cooldown period enforcement (default 24 hours)
- Comprehensive audit logging

## Architecture

```
multisig_treasury/
├── sources/
│   ├── Treasury.move          # Core treasury with multi-sig validation
│   ├── Proposal.move          # Proposal lifecycle management
│   ├── PolicyManager.move     # Modular policy system
│   └── EmergencyModule.move   # Emergency controls
└── tests/
    ├── treasury_tests.move
    ├── proposal_tests.move
    ├── policy_tests.move
    ├── emergency_tests.move
    └── integration_tests.move
```

## Installation

### Prerequisites
- [Sui CLI](https://docs.sui.io/build/install) installed
- Sui wallet configured

### Build

```bash
# Clone the repository
cd multisig-treasury

# Build the project
sui move build

# Run tests
sui move test

# Run specific test module
sui move test treasury_tests
sui move test integration_tests
```

## Quick Start

### 1. Create a Treasury

```bash
sui client call \
  --package <PACKAGE_ID> \
  --module Treasury \
  --function create_treasury \
  --args "[\"0xSIGNER1\", \"0xSIGNER2\", \"0xSIGNER3\"]" "2" \
  --gas-budget 10000000
```

### 2. Deposit Funds

```bash
sui client call \
  --package <PACKAGE_ID> \
  --module Treasury \
  --function deposit \
  --args <TREASURY_ID> <COIN_OBJECT_ID> \
  --gas-budget 10000000
```

### 3. Create a Withdrawal Proposal

```bash
sui client call \
  --package <PACKAGE_ID> \
  --module Proposal \
  --function create_withdrawal_proposal \
  --args <TREASURY_ID> "\"Monthly Payment\"" "\"Regular payment\"" \
         "[{\"recipient\":\"0xRECIPIENT\",\"amount\":1000,\"description\":\"Payment\"}]" \
         "3600000" \
  --gas-budget 10000000
```

### 4. Sign the Proposal

```bash
# Signer 1
sui client call \
  --package <PACKAGE_ID> \
  --module Proposal \
  --function sign_proposal \
  --args <PROPOSAL_ID> <TREASURY_ID> \
  --gas-budget 10000000

# Signer 2 (reaches threshold)
sui client call \
  --package <PACKAGE_ID> \
  --module Proposal \
  --function sign_proposal \
  --args <PROPOSAL_ID> <TREASURY_ID> \
  --gas-budget 10000000
```

### 5. Execute the Proposal

```bash
# After time-lock expires
sui client call \
  --package <PACKAGE_ID> \
  --module Proposal \
  --function execute_proposal \
  --args <PROPOSAL_ID> <TREASURY_ID> \
  --gas-budget 10000000
```

## Usage Examples

### Setting Up Policies

```bash
# Create policy configuration
sui client call \
  --package <PACKAGE_ID> \
  --module PolicyManager \
  --function create_policy_config \
  --args <TREASURY_ID> \
  --gas-budget 10000000

# Set daily spending limit (10,000 SUI)
sui client call \
  --package <PACKAGE_ID> \
  --module PolicyManager \
  --function set_spending_limit \
  --args <POLICY_ID> "0" "10000000000000" \
  --gas-budget 10000000

# Add to whitelist
sui client call \
  --package <PACKAGE_ID> \
  --module PolicyManager \
  --function add_to_whitelist \
  --args <POLICY_ID> "0xRECIPIENT" "<EXPIRY_TIMESTAMP>" "\"Approved vendor\"" \
  --gas-budget 10000000
```

### Emergency Controls

```bash
# Create emergency configuration
sui client call \
  --package <PACKAGE_ID> \
  --module EmergencyModule \
  --function create_emergency_config \
  --args <TREASURY_ID> "[\"0xEMERGENCY1\", \"0xEMERGENCY2\"]" "2" \
  --gas-budget 10000000

# Freeze treasury (requires super-majority)
sui client call \
  --package <PACKAGE_ID> \
  --module EmergencyModule \
  --function freeze_treasury \
  --args <CONFIG_ID> <TREASURY_ID> "\"Security breach detected\"" \
         "[\"0xEMERGENCY1\", \"0xEMERGENCY2\"]" \
  --gas-budget 10000000

# Unfreeze after cooldown
sui client call \
  --package <PACKAGE_ID> \
  --module EmergencyModule \
  --function unfreeze_treasury \
  --args <CONFIG_ID> <TREASURY_ID> "[\"0xEMERGENCY1\", \"0xEMERGENCY2\"]" \
  --gas-budget 10000000
```

## Testing

The project includes comprehensive test coverage (>80%):

```bash
# Run all tests
sui move test

# Run with coverage
sui move test --coverage

# Run specific test
sui move test test_complete_withdrawal_workflow
```

### Test Categories

- **Unit Tests**: Individual module functionality
- **Integration Tests**: End-to-end workflows
- **Edge Cases**: Error conditions and boundary cases

## Security Considerations

### Best Practices

1. **Threshold Selection**: Use at least 2-of-3 or 3-of-5 for production
2. **Emergency Signers**: Keep separate from regular signers
3. **Time-Locks**: Set appropriate delays based on transaction amounts
4. **Whitelist**: Regularly review and update approved recipients
5. **Spending Limits**: Configure conservative daily/weekly limits

### Audit Recommendations

- Review all signer addresses before deployment
- Test emergency procedures in testnet
- Monitor events for suspicious activity
- Implement off-chain monitoring for large transactions

## Gas Optimization

The system is designed for gas efficiency:

- Minimal storage writes
- Efficient signature validation
- Batch transaction support
- Optimized data structures

## Events

All critical operations emit events for monitoring:

- `TreasuryCreated`, `Deposit`, `Withdrawal`
- `ProposalCreated`, `ProposalSigned`, `ProposalExecuted`
- `TreasuryFrozen`, `TreasuryUnfrozen`
- `EmergencyTriggered`
- `PolicyUpdated`, `SpendingLimitExceeded`

## Deployment

### Testnet

```bash
# Build
sui move build

# Publish
sui client publish --gas-budget 100000000

# Note the package ID for future interactions
```

### Mainnet

1. Thoroughly test on testnet
2. Conduct security audit
3. Update package address in Move.toml
4. Publish with sufficient gas budget
5. Transfer admin capabilities to secure multi-sig

## API Reference

### Treasury Module

- `create_treasury(signers, threshold)`: Initialize new treasury
- `deposit(treasury, coin)`: Add funds
- `withdraw_internal(treasury, amount, recipient)`: Internal withdrawal
- `freeze_treasury(treasury)`: Freeze operations
- `add_signer(treasury, signer)`: Add authorized signer
- `remove_signer(treasury, signer)`: Remove signer

### Proposal Module

- `create_withdrawal_proposal(...)`: Create withdrawal proposal
- `create_add_signer_proposal(...)`: Propose new signer
- `create_remove_signer_proposal(...)`: Propose signer removal
- `create_update_threshold_proposal(...)`: Propose threshold change
- `sign_proposal(proposal, treasury)`: Sign existing proposal
- `execute_proposal(proposal, treasury)`: Execute approved proposal
- `cancel_proposal(proposal, treasury)`: Cancel pending proposal

### PolicyManager Module

- `create_policy_config(treasury_id)`: Initialize policies
- `set_spending_limit(policy, period, limit)`: Configure spending limits
- `add_to_whitelist(policy, address, expiry)`: Add approved recipient
- `add_threshold_tier(policy, min_amount, required_sigs)`: Set amount tiers
- `set_time_lock_policy(policy, base, factor)`: Configure time-locks
- `validate_all_policies(...)`: Validate transaction against all policies

### EmergencyModule

- `create_emergency_config(treasury_id, signers, threshold)`: Setup emergency controls
- `freeze_treasury(config, treasury, reason, signatures)`: Emergency freeze
- `unfreeze_treasury(config, treasury, signatures)`: Unfreeze after cooldown
- `trigger_emergency(config, treasury, reason, signatures)`: Trigger emergency mode

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

For issues and questions:
- GitHub Issues: [Project Issues]
- Documentation: [Sui Move Docs](https://docs.sui.io/build/move)

## Changelog

### v1.0.0
- Initial release
- Core treasury with multi-sig
- Proposal system with batch support
- Policy manager with 5 policy types
- Emergency module with freeze controls
- Comprehensive test suite (>80% coverage)
