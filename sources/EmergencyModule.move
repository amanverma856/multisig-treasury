module multisig_treasury::EmergencyModule {
    use sui::event;
    // use sui::table::{Self, Table}; // Unused
    use std::string::{Self, String};
    use multisig_treasury::Treasury::{Self as TreasuryModule, Treasury};

    // ==================== Error Codes ====================
    const E_NOT_EMERGENCY_SIGNER: u64 = 300;
    const E_EMERGENCY_THRESHOLD_NOT_MET: u64 = 301;
    const E_ALREADY_IN_EMERGENCY: u64 = 302;
    const E_NOT_IN_EMERGENCY: u64 = 303;
    const E_COOLDOWN_NOT_EXPIRED: u64 = 304;
    const E_DUPLICATE_EMERGENCY_SIGNER: u64 = 305;
    const E_INVALID_EMERGENCY_THRESHOLD: u64 = 306;
    const E_EMERGENCY_SIGNER_NOT_FOUND: u64 = 307;
    const E_CANNOT_REMOVE_LAST_EMERGENCY_SIGNER: u64 = 308;

    // ==================== Constants ====================
    
    /// Default cooldown period (24 hours in milliseconds)
    const DEFAULT_COOLDOWN_PERIOD: u64 = 86400000;

    /// Minimum super-majority percentage (66%)
    const MIN_SUPER_MAJORITY_PERCENT: u64 = 66;

    // ==================== Structs ====================
    
    /// Emergency configuration and state
    public struct EmergencyConfig has key, store {
        id: UID,
        /// Reference to the treasury
        treasury_id: ID,
        /// List of emergency signer addresses
        emergency_signers: vector<address>,
        /// Required threshold for emergency actions (super-majority)
        emergency_threshold: u64,
        /// Whether currently in emergency mode
        in_emergency: bool,
        /// Timestamp when emergency was triggered
        emergency_triggered_at: u64,
        /// Cooldown period before unfreeze is allowed (milliseconds)
        cooldown_period: u64,
        /// Audit log of emergency actions
        audit_log: vector<AuditEntry>,
        /// Creation timestamp
        created_at: u64,
    }

    /// Audit log entry for emergency actions
    public struct AuditEntry has store, copy, drop {
        action: String,
        triggered_by: address,
        timestamp: u64,
        reason: String,
        signatures: vector<address>,
    }

    /// Emergency action proposal (for multi-sig emergency actions)
    public struct EmergencyAction has key, store {
        id: UID,
        config_id: ID,
        action_type: u8, // 0 = freeze, 1 = unfreeze, 2 = emergency_withdraw
        reason: String,
        signatures: vector<address>,
        created_at: u64,
        executed: bool,
    }

    // ==================== Action Types ====================
    const ACTION_FREEZE: u8 = 0;
    const ACTION_UNFREEZE: u8 = 1;
    const ACTION_EMERGENCY_WITHDRAW: u8 = 2;

    // ==================== Events ====================
    
    public struct EmergencyConfigCreated has copy, drop {
        config_id: ID,
        treasury_id: ID,
        emergency_signers: vector<address>,
        threshold: u64,
        created_at: u64,
    }

    public struct EmergencyTriggered has copy, drop {
        config_id: ID,
        treasury_id: ID,
        triggered_by: address,
        reason: String,
        timestamp: u64,
    }

    public struct TreasuryFrozen has copy, drop {
        config_id: ID,
        treasury_id: ID,
        frozen_by: address,
        signatures: vector<address>,
        reason: String,
        timestamp: u64,
    }

    public struct TreasuryUnfrozen has copy, drop {
        config_id: ID,
        treasury_id: ID,
        unfrozen_by: address,
        signatures: vector<address>,
        timestamp: u64,
    }

    public struct EmergencyWithdrawal has copy, drop {
        config_id: ID,
        treasury_id: ID,
        amount: u64,
        recipient: address,
        signatures: vector<address>,
        timestamp: u64,
    }

    public struct EmergencySignerAdded has copy, drop {
        config_id: ID,
        new_signer: address,
        timestamp: u64,
    }

    public struct EmergencySignerRemoved has copy, drop {
        config_id: ID,
        removed_signer: address,
        timestamp: u64,
    }

    public struct AuditLogEntry has copy, drop {
        config_id: ID,
        action: String,
        triggered_by: address,
        timestamp: u64,
    }

    // ==================== Public Functions ====================
    
    /// Create emergency configuration
    /// 
    /// # Arguments
    /// * `treasury_id` - ID of the treasury to protect
    /// * `emergency_signers` - List of emergency signer addresses
    /// * `emergency_threshold` - Required signatures (should be super-majority)
    /// * `ctx` - Transaction context
    public fun create_emergency_config(
        treasury_id: ID,
        emergency_signers: vector<address>,
        emergency_threshold: u64,
        ctx: &mut TxContext
    ): EmergencyConfig {
        let signer_count = emergency_signers.length();
        let config = EmergencyConfig {
            id: config_uid,
            treasury_id,
            emergency_signers,
            emergency_threshold,
            in_emergency: false,
            emergency_triggered_at: 0,
            cooldown_period: DEFAULT_COOLDOWN_PERIOD,
            audit_log: vector::empty(),
            created_at,
        };

        event::emit(EmergencyConfigCreated {
            config_id,
            treasury_id,
            emergency_signers: config.emergency_signers,
            threshold: emergency_threshold,
            created_at,
        });

        config
    }

    /// Trigger emergency mode (requires super-majority)
    /// 
    /// # Arguments
    /// * `config` - Mutable reference to EmergencyConfig
    /// * `treasury` - Mutable reference to Treasury
    /// * `reason` - Reason for emergency
    /// * `signatures` - Emergency signer signatures
    /// * `ctx` - Transaction context
    public fun trigger_emergency(
        config: &mut EmergencyConfig,
        treasury: &mut Treasury,
        reason: String,
        signatures: vector<address>,
        ctx: &mut TxContext
    ) {
        // Validate not already in emergency
        assert!(!config.in_emergency, E_ALREADY_IN_EMERGENCY);
        
        // Validate signatures
        assert!(signatures.length() >= config.emergency_threshold, E_EMERGENCY_THRESHOLD_NOT_MET);
        assert!(validate_emergency_signatures(config, &signatures), E_NOT_EMERGENCY_SIGNER);

        // Set emergency mode
        config.in_emergency = true;
        config.emergency_triggered_at = ctx.epoch_timestamp_ms();

        // Add to audit log
        let audit_entry = AuditEntry {
            action: string::utf8(b"EMERGENCY_TRIGGERED"),
            triggered_by: ctx.sender(),
            timestamp: ctx.epoch_timestamp_ms(),
            reason,
            signatures,
        };
        config.audit_log.push_back(audit_entry);

        // Emit events
        event::emit(EmergencyTriggered {
            config_id: object::id(config),
            treasury_id: config.treasury_id,
            triggered_by: ctx.sender(),
            reason,
            timestamp: ctx.epoch_timestamp_ms(),
        });

        // Emit treasury event
        TreasuryModule::emit_emergency_triggered(treasury, reason, ctx);
    }

    /// Freeze treasury (emergency action)
    /// 
    /// # Arguments
    /// * `config` - Mutable reference to EmergencyConfig
    /// * `treasury` - Mutable reference to Treasury
    /// * `reason` - Reason for freezing
    /// * `signatures` - Emergency signer signatures
    /// * `ctx` - Transaction context
    public fun freeze_treasury(
        config: &mut EmergencyConfig,
        treasury: &mut Treasury,
        reason: String,
        signatures: vector<address>,
        ctx: &mut TxContext
    ) {
        // Validate signatures
        assert!(signatures.length() >= config.emergency_threshold, E_EMERGENCY_THRESHOLD_NOT_MET);
        assert!(validate_emergency_signatures(config, &signatures), E_NOT_EMERGENCY_SIGNER);

        // Freeze the treasury
        TreasuryModule::freeze_treasury(treasury, ctx);

        // Set emergency mode
        config.in_emergency = true;
        config.emergency_triggered_at = ctx.epoch_timestamp_ms();

        // Add to audit log
        let audit_entry = AuditEntry {
            action: string::utf8(b"TREASURY_FROZEN"),
            triggered_by: ctx.sender(),
            timestamp: ctx.epoch_timestamp_ms(),
            reason,
            signatures,
        };
        config.audit_log.push_back(audit_entry);

        // Emit event
        event::emit(TreasuryFrozen {
            config_id: object::id(config),
            treasury_id: config.treasury_id,
            frozen_by: ctx.sender(),
            signatures,
            reason,
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Unfreeze treasury (requires cooldown period)
    /// 
    /// # Arguments
    /// * `config` - Mutable reference to EmergencyConfig
    /// * `treasury` - Mutable reference to Treasury
    /// * `signatures` - Emergency signer signatures
    /// * `ctx` - Transaction context
    public fun unfreeze_treasury(
        config: &mut EmergencyConfig,
        treasury: &mut Treasury,
        signatures: vector<address>,
        ctx: &mut TxContext
    ) {
        // Validate in emergency mode
        assert!(config.in_emergency, E_NOT_IN_EMERGENCY);
        
        // Validate cooldown period has expired
        let current_time = ctx.epoch_timestamp_ms();
        assert!(
            current_time >= config.emergency_triggered_at + config.cooldown_period,
            E_COOLDOWN_NOT_EXPIRED
        );

        // Validate signatures
        assert!(signatures.length() >= config.emergency_threshold, E_EMERGENCY_THRESHOLD_NOT_MET);
        assert!(validate_emergency_signatures(config, &signatures), E_NOT_EMERGENCY_SIGNER);

        // Unfreeze the treasury
        TreasuryModule::unfreeze_treasury(treasury, ctx);

        // Exit emergency mode
        config.in_emergency = false;

        // Add to audit log
        let audit_entry = AuditEntry {
            action: string::utf8(b"TREASURY_UNFROZEN"),
            triggered_by: ctx.sender(),
            timestamp: current_time,
            reason: string::utf8(b"Cooldown expired, emergency resolved"),
            signatures,
        };
        config.audit_log.push_back(audit_entry);

        // Emit event
        event::emit(TreasuryUnfrozen {
            config_id: object::id(config),
            treasury_id: config.treasury_id,
            unfrozen_by: ctx.sender(),
            signatures,
            timestamp: current_time,
        });
    }

    /// Add emergency signer
    public fun add_emergency_signer(
        config: &mut EmergencyConfig,
        new_signer: address,
        ctx: &TxContext
    ) {
        assert!(!config.emergency_signers.contains(&new_signer), E_DUPLICATE_EMERGENCY_SIGNER);
        
        config.emergency_signers.push_back(new_signer);

        event::emit(EmergencySignerAdded {
            config_id: object::id(config),
            new_signer,
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Remove emergency signer
    public fun remove_emergency_signer(
        config: &mut EmergencyConfig,
        signer_to_remove: address,
        ctx: &TxContext
    ) {
        assert!(config.emergency_signers.length() > 1, E_CANNOT_REMOVE_LAST_EMERGENCY_SIGNER);
        
        let (found, index) = config.emergency_signers.index_of(&signer_to_remove);
        assert!(found, E_EMERGENCY_SIGNER_NOT_FOUND);
        
        config.emergency_signers.remove(index);

        // Adjust threshold if necessary
        if (config.emergency_threshold > config.emergency_signers.length()) {
            config.emergency_threshold = config.emergency_signers.length();
        };

        event::emit(EmergencySignerRemoved {
            config_id: object::id(config),
            removed_signer: signer_to_remove,
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Update cooldown period
    public fun update_cooldown_period(
        config: &mut EmergencyConfig,
        new_cooldown: u64
    ) {
        config.cooldown_period = new_cooldown;
    }

    /// Update emergency threshold
    public fun update_emergency_threshold(
        config: &mut EmergencyConfig,
        new_threshold: u64
    ) {
        assert!(
            new_threshold > 0 && new_threshold <= config.emergency_signers.length(),
            E_INVALID_EMERGENCY_THRESHOLD
        );
        
        // Ensure super-majority
        let signer_count = config.emergency_signers.length();
        let mut min_threshold = (signer_count * MIN_SUPER_MAJORITY_PERCENT) / 100;
        if (min_threshold == 0) {
            min_threshold = 1;
        };
        assert!(new_threshold >= min_threshold, E_INVALID_EMERGENCY_THRESHOLD);

        config.emergency_threshold = new_threshold;
    }

    /// Validate emergency signatures
    fun validate_emergency_signatures(
        config: &EmergencyConfig,
        signatures: &vector<address>
    ): bool {
        let len = signatures.length();
        let mut i = 0;

        while (i < len) {
            let signer = signatures[i];
            
            // Check if signer is authorized emergency signer
            if (!config.emergency_signers.contains(&signer)) {
                return false
            };

            // Check for duplicates
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

    /// Check for duplicate addresses
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

    // ==================== View Functions ====================
    
    /// Get emergency signers
    public fun get_emergency_signers(config: &EmergencyConfig): vector<address> {
        config.emergency_signers
    }

    /// Get emergency threshold
    public fun get_emergency_threshold(config: &EmergencyConfig): u64 {
        config.emergency_threshold
    }

    /// Check if in emergency mode
    public fun is_in_emergency(config: &EmergencyConfig): bool {
        config.in_emergency
    }

    /// Get cooldown period
    public fun get_cooldown_period(config: &EmergencyConfig): u64 {
        config.cooldown_period
    }

    /// Get audit log
    public fun get_audit_log(config: &EmergencyConfig): vector<AuditEntry> {
        config.audit_log
    }

    /// Check if address is emergency signer
    public fun is_emergency_signer(config: &EmergencyConfig, addr: address): bool {
        config.emergency_signers.contains(&addr)
    }

    /// Get time until cooldown expires
    public fun get_time_until_cooldown_expires(
        config: &EmergencyConfig,
        current_time: u64
    ): u64 {
        if (!config.in_emergency) {
            return 0
        };

        let cooldown_end = config.emergency_triggered_at + config.cooldown_period;
        if (current_time >= cooldown_end) {
            0
        } else {
            cooldown_end - current_time
        }
    }

    // ==================== Test Only Functions ====================
    
    #[test_only]
    public fun destroy_config_for_testing(config: EmergencyConfig) {
        let EmergencyConfig {
            id,
            treasury_id: _,
            emergency_signers: _,
            emergency_threshold: _,
            in_emergency: _,
            emergency_triggered_at: _,
            cooldown_period: _,
            audit_log: _,
            created_at: _,
        } = config;
        
        object::delete(id);
    }

    #[test_only]
    public fun set_emergency_mode_for_testing(config: &mut EmergencyConfig, mode: bool) {
        config.in_emergency = mode;
    }
}
