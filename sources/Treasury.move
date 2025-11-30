module multisig_treasury::Treasury {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::event;
    // use sui::table::{Self, Table}; // Unused
    use std::string::String;

    // ==================== Error Codes ====================
    // ==================== Error Codes ====================
    const E_TREASURY_FROZEN: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_INVALID_THRESHOLD: u64 = 3;
    // const E_SIGNER_NOT_AUTHORIZED: u64 = 4; // Unused
    const E_DUPLICATE_SIGNER: u64 = 5;
    // const E_THRESHOLD_NOT_MET: u64 = 6; // Unused
    const E_INVALID_SIGNER_COUNT: u64 = 7;
    const E_SIGNER_ALREADY_EXISTS: u64 = 8;
    const E_SIGNER_NOT_FOUND: u64 = 9;
    const E_CANNOT_REMOVE_LAST_SIGNER: u64 = 10;

    // ==================== Structs ====================
    
    /// Main Treasury object that holds funds and manages multi-sig operations
    public struct Treasury has key, store {
        id: UID,
        /// List of authorized signer addresses
        signers: vector<address>,
        /// Minimum number of signatures required for execution
        threshold: u64,
        /// Balance of SUI coins in the treasury
        balance: Balance<SUI>,
        /// Flag indicating if treasury is frozen (emergency mode)
        frozen: bool,
        /// Policy configuration reference (optional)
        policy_enabled: bool,
        /// Creation timestamp
        created_at: u64,
        /// Total deposits counter
        total_deposits: u64,
        /// Total withdrawals counter
        total_withdrawals: u64,
    }

    /// Capability to manage treasury (admin operations)
    public struct TreasuryAdminCap has key, store {
        id: UID,
        treasury_id: ID,
    }

    // ==================== Events ====================
    
    public struct TreasuryCreated has copy, drop {
        treasury_id: ID,
        signers: vector<address>,
        threshold: u64,
        created_at: u64,
    }

    public struct Deposit has copy, drop {
        treasury_id: ID,
        amount: u64,
        depositor: address,
        timestamp: u64,
        new_balance: u64,
    }

    public struct Withdrawal has copy, drop {
        treasury_id: ID,
        amount: u64,
        recipient: address,
        timestamp: u64,
        remaining_balance: u64,
    }

    public struct ProposalExecuted has copy, drop {
        treasury_id: ID,
        proposal_id: ID,
        executor: address,
        timestamp: u64,
    }

    public struct EmergencyTriggered has copy, drop {
        treasury_id: ID,
        triggered_by: address,
        reason: String,
        timestamp: u64,
    }

    public struct TreasuryFrozen has copy, drop {
        treasury_id: ID,
        frozen_by: address,
        timestamp: u64,
    }

    public struct TreasuryUnfrozen has copy, drop {
        treasury_id: ID,
        unfrozen_by: address,
        timestamp: u64,
    }

    public struct SignerAdded has copy, drop {
        treasury_id: ID,
        new_signer: address,
        timestamp: u64,
    }

    public struct SignerRemoved has copy, drop {
        treasury_id: ID,
        removed_signer: address,
        timestamp: u64,
    }

    public struct ThresholdUpdated has copy, drop {
        treasury_id: ID,
        old_threshold: u64,
        new_threshold: u64,
        timestamp: u64,
    }

    // ==================== Public Functions ====================
    
    /// Create a new multi-signature treasury
    /// 
    /// # Arguments
    /// * `signers` - List of authorized signer addresses
    /// * `threshold` - Minimum signatures required (must be <= signers.length)
    /// * `ctx` - Transaction context
    /// 
    /// # Returns
    /// * Treasury object and TreasuryAdminCap
    public fun create_treasury(
        signers: vector<address>,
        threshold: u64,
        ctx: &mut TxContext
    ): (Treasury, TreasuryAdminCap) {
        let signer_count = signers.length();
        
        // Validate inputs
        assert!(signer_count > 0, E_INVALID_SIGNER_COUNT);
        assert!(threshold > 0 && threshold <= signer_count, E_INVALID_THRESHOLD);
        assert!(!has_duplicates(&signers), E_DUPLICATE_SIGNER);

        let treasury_uid = object::new(ctx);
        let treasury_id = treasury_uid.to_inner();
        
        let treasury = Treasury {
            id: treasury_uid,
            signers,
            threshold,
            balance: balance::zero<SUI>(),
            frozen: false,
            policy_enabled: false,
            created_at: ctx.epoch_timestamp_ms(),
            total_deposits: 0,
            total_withdrawals: 0,
        };

        let admin_cap = TreasuryAdminCap {
            id: object::new(ctx),
            treasury_id,
        };

        // Emit creation event
        event::emit(TreasuryCreated {
            treasury_id,
            signers: treasury.signers,
            threshold: treasury.threshold,
            created_at: treasury.created_at,
        });

        (treasury, admin_cap)
    }

    /// Deposit SUI coins into the treasury
    /// 
    /// # Arguments
    /// * `treasury` - Mutable reference to Treasury
    /// * `coin` - SUI coin to deposit
    /// * `ctx` - Transaction context
    public fun deposit(
        treasury: &mut Treasury,
        coin: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let amount = coin.value();
        let depositor = ctx.sender();
        
        // Add coin to treasury balance
        treasury.balance.join(coin.into_balance());
        treasury.total_deposits = treasury.total_deposits + amount;

        // Emit deposit event
        event::emit(Deposit {
            treasury_id: object::id(treasury),
            amount,
            depositor,
            timestamp: ctx.epoch_timestamp_ms(),
            new_balance: treasury.balance.value(),
        });
    }

    /// Internal withdrawal function (called after validation)
    /// 
    /// # Arguments
    /// * `treasury` - Mutable reference to Treasury
    /// * `amount` - Amount to withdraw
    /// * `recipient` - Address to receive funds
    /// * `ctx` - Transaction context
    /// 
    /// # Returns
    /// * Coin<SUI> to be transferred to recipient
    public(package) fun withdraw_internal(
        treasury: &mut Treasury,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ): Coin<SUI> {
        // Check treasury is not frozen
        assert!(!treasury.frozen, E_TREASURY_FROZEN);
        
        // Check sufficient balance
        assert!(treasury.balance.value() >= amount, E_INSUFFICIENT_BALANCE);

        // Withdraw from balance
        let withdrawn_balance = treasury.balance.split(amount);
        let coin = coin::from_balance(withdrawn_balance, ctx);
        
        treasury.total_withdrawals = treasury.total_withdrawals + amount;

        // Emit withdrawal event
        event::emit(Withdrawal {
            treasury_id: object::id(treasury),
            amount,
            recipient,
            timestamp: ctx.epoch_timestamp_ms(),
            remaining_balance: treasury.balance.value(),
        });

        coin
    }

    /// Check if a proposal can be executed based on signatures
    /// 
    /// # Arguments
    /// * `treasury` - Reference to Treasury
    /// * `signatures` - Vector of signer addresses who approved
    /// 
    /// # Returns
    /// * bool - true if threshold is met and all signers are valid
    public fun can_execute(
        treasury: &Treasury,
        signatures: &vector<address>
    ): bool {
        // Check if frozen
        if (treasury.frozen) {
            return false
        };

        // Check threshold
        if (signatures.length() < treasury.threshold) {
            return false
        };

        // Validate all signatures are from authorized signers
        validate_signatures(treasury, signatures)
    }

    /// Freeze the treasury (emergency mode)
    /// 
    /// # Arguments
    /// * `treasury` - Mutable reference to Treasury
    /// * `ctx` - Transaction context
    public(package) fun freeze_treasury(
        treasury: &mut Treasury,
        ctx: &TxContext
    ) {
        treasury.frozen = true;
        
        event::emit(TreasuryFrozen {
            treasury_id: object::id(treasury),
            frozen_by: ctx.sender(),
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Unfreeze the treasury
    /// 
    /// # Arguments
    /// * `treasury` - Mutable reference to Treasury
    /// * `ctx` - Transaction context
    public(package) fun unfreeze_treasury(
        treasury: &mut Treasury,
        ctx: &TxContext
    ) {
        treasury.frozen = false;
        
        event::emit(TreasuryUnfrozen {
            treasury_id: object::id(treasury),
            unfrozen_by: ctx.sender(),
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Add a new signer to the treasury
    /// 
    /// # Arguments
    /// * `treasury` - Mutable reference to Treasury
    /// * `new_signer` - Address of new signer to add
    /// * `ctx` - Transaction context
    public(package) fun add_signer(
        treasury: &mut Treasury,
        new_signer: address,
        ctx: &TxContext
    ) {
        // Check signer doesn't already exist
        assert!(!treasury.signers.contains(&new_signer), E_SIGNER_ALREADY_EXISTS);
        
        treasury.signers.push_back(new_signer);

        event::emit(SignerAdded {
            treasury_id: object::id(treasury),
            new_signer,
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Remove a signer from the treasury
    /// 
    /// # Arguments
    /// * `treasury` - Mutable reference to Treasury
    /// * `signer_to_remove` - Address of signer to remove
    /// * `ctx` - Transaction context
    public(package) fun remove_signer(
        treasury: &mut Treasury,
        signer_to_remove: address,
        ctx: &TxContext
    ) {
        // Cannot remove last signer
        assert!(treasury.signers.length() > 1, E_CANNOT_REMOVE_LAST_SIGNER);
        
        // Find and remove signer
        let (found, index) = treasury.signers.index_of(&signer_to_remove);
        assert!(found, E_SIGNER_NOT_FOUND);
        
        treasury.signers.remove(index);

        // Adjust threshold if necessary
        if (treasury.threshold > treasury.signers.length()) {
            treasury.threshold = treasury.signers.length();
        };

        event::emit(SignerRemoved {
            treasury_id: object::id(treasury),
            removed_signer: signer_to_remove,
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Update the signature threshold
    /// 
    /// # Arguments
    /// * `treasury` - Mutable reference to Treasury
    /// * `new_threshold` - New threshold value
    /// * `ctx` - Transaction context
    public(package) fun update_threshold(
        treasury: &mut Treasury,
        new_threshold: u64,
        ctx: &TxContext
    ) {
        assert!(new_threshold > 0 && new_threshold <= treasury.signers.length(), E_INVALID_THRESHOLD);
        
        let old_threshold = treasury.threshold;
        treasury.threshold = new_threshold;

        event::emit(ThresholdUpdated {
            treasury_id: object::id(treasury),
            old_threshold,
            new_threshold,
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Emit proposal executed event
    public(package) fun emit_proposal_executed(
        treasury: &Treasury,
        proposal_id: ID,
        ctx: &TxContext
    ) {
        event::emit(ProposalExecuted {
            treasury_id: object::id(treasury),
            proposal_id,
            executor: ctx.sender(),
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Emit emergency triggered event
    public(package) fun emit_emergency_triggered(
        treasury: &Treasury,
        reason: String,
        ctx: &TxContext
    ) {
        event::emit(EmergencyTriggered {
            treasury_id: object::id(treasury),
            triggered_by: ctx.sender(),
            reason,
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    // ==================== View Functions ====================
    
    /// Get treasury balance
    public fun get_balance(treasury: &Treasury): u64 {
        treasury.balance.value()
    }

    /// Get treasury signers
    public fun get_signers(treasury: &Treasury): vector<address> {
        treasury.signers
    }

    /// Get treasury threshold
    public fun get_threshold(treasury: &Treasury): u64 {
        treasury.threshold
    }

    /// Check if treasury is frozen
    public fun is_frozen(treasury: &Treasury): bool {
        treasury.frozen
    }

    /// Check if address is a signer
    public fun is_signer(treasury: &Treasury, addr: address): bool {
        treasury.signers.contains(&addr)
    }

    /// Get treasury ID
    public fun get_treasury_id(treasury: &Treasury): ID {
        object::id(treasury)
    }

    /// Get total deposits
    public fun get_total_deposits(treasury: &Treasury): u64 {
        treasury.total_deposits
    }

    /// Get total withdrawals
    public fun get_total_withdrawals(treasury: &Treasury): u64 {
        treasury.total_withdrawals
    }

    // ==================== Internal Helper Functions ====================
    
    /// Validate that all signatures are from authorized signers and no duplicates
    fun validate_signatures(
        treasury: &Treasury,
        signatures: &vector<address>
    ): bool {
        let len = signatures.length();
        let mut i = 0;

        // Check each signature
        while (i < len) {
            let signer = signatures[i];
            
            // Check if signer is authorized
            if (!treasury.signers.contains(&signer)) {
                return false
            };

            // Check for duplicates in signatures
            let mut j = i + 1;
            while (j < len) {
                if (signatures[j] == signer) {
                    return false
                };
                j = j + 1;
            };

            i = i + 1;
        };

        true
    }

    /// Check if vector has duplicate addresses
    fun has_duplicates(addresses: &vector<address>): bool {
        let len = addresses.length();
        let mut i = 0;

        while (i < len) {
            let mut j = i + 1;
            while (j < len) {
                if (addresses[i] == addresses[j]) {
                    return true
                };
                j = j + 1;
            };
            i = i + 1;
        };

        false
    }

    // ==================== Test Only Functions ====================
    
    #[test_only]
    public fun create_treasury_for_testing(
        signers: vector<address>,
        threshold: u64,
        ctx: &mut TxContext
    ): Treasury {
        let (treasury, admin_cap) = create_treasury(signers, threshold, ctx);
        transfer::public_transfer(admin_cap, ctx.sender());
        treasury
    }

    #[test_only]
    public fun destroy_treasury_for_testing(treasury: Treasury) {
        let Treasury {
            id,
            signers: _,
            threshold: _,
            balance,
            frozen: _,
            policy_enabled: _,
            created_at: _,
            total_deposits: _,
            total_withdrawals: _,
        } = treasury;
        
        balance.destroy_zero();
        object::delete(id);
    }
}
