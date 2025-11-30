module multisig_treasury::PolicyManager {
    use sui::event;
    // use sui::table::{Self, Table}; // Unused
    use std::string::String;

    // ==================== Error Codes ====================
    const E_SPENDING_LIMIT_EXCEEDED: u64 = 200;
    const E_RECIPIENT_NOT_WHITELISTED: u64 = 201;
    // const E_INVALID_CATEGORY: u64 = 202; // Unused
    // const E_AMOUNT_THRESHOLD_NOT_MET: u64 = 203; // Unused
    // const E_TIME_LOCK_TOO_SHORT: u64 = 204; // Unused
    // const E_WHITELIST_EXPIRED: u64 = 205; // Unused
    const E_INVALID_PERIOD: u64 = 206;
    const E_INVALID_POLICY_CONFIG: u64 = 207;

    // ==================== Constants ====================
    
    /// Time periods for spending limits
    const PERIOD_DAILY: u8 = 0;
    const PERIOD_WEEKLY: u8 = 1;
    const PERIOD_MONTHLY: u8 = 2;

    /// Milliseconds in time periods
    const MS_PER_DAY: u64 = 86400000;
    const MS_PER_WEEK: u64 = 604800000;
    const MS_PER_MONTH: u64 = 2592000000; // 30 days

    // ==================== Structs ====================
    
    /// Whitelist entry with expiration
    public struct WhitelistEntry has store, copy, drop {
        address: address,
        expires_at: u64,
        description: String,
    }

    /// Spending limit configuration
    public struct SpendingLimitPolicy has store, copy, drop {
        enabled: bool,
        period: u8, // DAILY, WEEKLY, or MONTHLY
        limit: u64,
        current_spent: u64,
        period_start: u64,
    }

    /// Whitelist policy configuration
    public struct WhitelistPolicy has store, copy, drop {
        enabled: bool,
        entries: vector<WhitelistEntry>,
    }

    /// Category policy - requires specific categories for proposals
    public struct CategoryPolicy has store, copy, drop {
        enabled: bool,
        required_categories: vector<u8>,
    }

    /// Amount threshold policy - different thresholds based on amount
    public struct AmountThresholdPolicy has store, copy, drop {
        enabled: bool,
        tiers: vector<ThresholdTier>,
    }

    /// Threshold tier for amount-based thresholds
    public struct ThresholdTier has store, copy, drop {
        min_amount: u64,
        required_signatures: u64,
    }

    /// Time-lock policy with formula: time_lock = base + (amount / factor)
    public struct TimeLockPolicy has store, copy, drop {
        enabled: bool,
        base_time_lock: u64, // Base time lock in milliseconds
        amount_factor: u64,  // Divide amount by this to get additional time
    }

    /// Main policy configuration object
    public struct PolicyConfig has key, store {
        id: UID,
        treasury_id: ID,
        spending_limit: SpendingLimitPolicy,
        whitelist: WhitelistPolicy,
        category: CategoryPolicy,
        amount_threshold: AmountThresholdPolicy,
        time_lock: TimeLockPolicy,
        created_at: u64,
        updated_at: u64,
    }

    // ==================== Events ====================
    
    public struct PolicyConfigCreated has copy, drop {
        policy_id: ID,
        treasury_id: ID,
        created_at: u64,
    }

    public struct PolicyUpdated has copy, drop {
        policy_id: ID,
        updated_by: address,
        timestamp: u64,
    }

    public struct SpendingLimitExceeded has copy, drop {
        policy_id: ID,
        attempted_amount: u64,
        current_spent: u64,
        limit: u64,
        timestamp: u64,
    }

    public struct WhitelistViolation has copy, drop {
        policy_id: ID,
        recipient: address,
        timestamp: u64,
    }

    public struct SpendingReset has copy, drop {
        policy_id: ID,
        period: u8,
        timestamp: u64,
    }

    // ==================== Public Functions ====================
    
    /// Create a new policy configuration
    public fun create_policy_config(
        treasury_id: ID,
        ctx: &mut TxContext
    ): PolicyConfig {
        let policy_uid = object::new(ctx);
        let policy_id = policy_uid.to_inner();
        let created_at = ctx.epoch_timestamp_ms();

        let policy_config = PolicyConfig {
            id: policy_uid,
            treasury_id,
            spending_limit: SpendingLimitPolicy {
                enabled: false,
                period: PERIOD_DAILY,
                limit: 0,
                current_spent: 0,
                period_start: created_at,
            },
            whitelist: WhitelistPolicy {
                enabled: false,
                entries: vector::empty(),
            },
            category: CategoryPolicy {
                enabled: false,
                required_categories: vector::empty(),
            },
            amount_threshold: AmountThresholdPolicy {
                enabled: false,
                tiers: vector::empty(),
            },
            time_lock: TimeLockPolicy {
                enabled: false,
                base_time_lock: 0,
                amount_factor: 1,
            },
            created_at,
            updated_at: created_at,
        };

        event::emit(PolicyConfigCreated {
            policy_id,
            treasury_id,
            created_at,
        });

        policy_config
    }

    /// Enable and configure spending limit policy
    public fun set_spending_limit(
        policy: &mut PolicyConfig,
        period: u8,
        limit: u64,
        ctx: &mut TxContext
    ) {
        assert!(period <= PERIOD_MONTHLY, E_INVALID_PERIOD);

        policy.spending_limit.enabled = true;
        policy.spending_limit.period = period;
        policy.spending_limit.limit = limit;
        policy.spending_limit.current_spent = 0;
        policy.spending_limit.period_start = ctx.epoch_timestamp_ms();
        policy.updated_at = ctx.epoch_timestamp_ms();

        event::emit(PolicyUpdated {
            policy_id: object::id(policy),
            updated_by: ctx.sender(),
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Add address to whitelist
    public fun add_to_whitelist(
        policy: &mut PolicyConfig,
        address: address,
        expires_at: u64,
        description: String,
        ctx: &mut TxContext
    ) {
        let entry = WhitelistEntry {
            address,
            expires_at,
            description,
        };

        policy.whitelist.entries.push_back(entry);
        policy.whitelist.enabled = true;
        policy.updated_at = ctx.epoch_timestamp_ms();

        event::emit(PolicyUpdated {
            policy_id: object::id(policy),
            updated_by: ctx.sender(),
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Remove address from whitelist
    public fun remove_from_whitelist(
        policy: &mut PolicyConfig,
        address: address,
        ctx: &mut TxContext
    ) {
        let entries = &mut policy.whitelist.entries;
        let mut i = 0;
        let len = entries.length();

        while (i < len) {
            if (entries[i].address == address) {
                entries.remove(i);
                policy.updated_at = ctx.epoch_timestamp_ms();
                
                event::emit(PolicyUpdated {
                    policy_id: object::id(policy),
                    updated_by: ctx.sender(),
                    timestamp: ctx.epoch_timestamp_ms(),
                });
                return
            };
            i = i + 1;
        };
    }

    /// Set required categories
    public fun set_required_categories(
        policy: &mut PolicyConfig,
        categories: vector<u8>,
        ctx: &mut TxContext
    ) {
        policy.category.enabled = true;
        policy.category.required_categories = categories;
        policy.updated_at = ctx.epoch_timestamp_ms();

        event::emit(PolicyUpdated {
            policy_id: object::id(policy),
            updated_by: ctx.sender(),
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Add amount threshold tier
    public fun add_threshold_tier(
        policy: &mut PolicyConfig,
        min_amount: u64,
        required_signatures: u64,
        ctx: &mut TxContext
    ) {
        let tier = ThresholdTier {
            min_amount,
            required_signatures,
        };

        policy.amount_threshold.tiers.push_back(tier);
        policy.amount_threshold.enabled = true;
        policy.updated_at = ctx.epoch_timestamp_ms();

        event::emit(PolicyUpdated {
            policy_id: object::id(policy),
            updated_by: ctx.sender(),
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Configure time-lock policy
    public fun set_time_lock_policy(
        policy: &mut PolicyConfig,
        base_time_lock: u64,
        amount_factor: u64,
        ctx: &mut TxContext
    ) {
        assert!(amount_factor > 0, E_INVALID_POLICY_CONFIG);

        policy.time_lock.enabled = true;
        policy.time_lock.base_time_lock = base_time_lock;
        policy.time_lock.amount_factor = amount_factor;
        policy.updated_at = ctx.epoch_timestamp_ms();

        event::emit(PolicyUpdated {
            policy_id: object::id(policy),
            updated_by: ctx.sender(),
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Validate all policies for a withdrawal
    /// 
    /// # Arguments
    /// * `policy` - Mutable reference to PolicyConfig
    /// * `recipient` - Recipient address
    /// * `amount` - Amount to withdraw
    /// * `category` - Proposal category
    /// * `signature_count` - Number of signatures
    /// * `current_time` - Current timestamp
    /// 
    /// # Returns
    /// * bool - true if all policies pass
    public fun validate_all_policies(
        policy: &mut PolicyConfig,
        recipient: address,
        amount: u64,
        category: u8,
        signature_count: u64,
        current_time: u64
    ): bool {
        // Validate spending limit
        if (policy.spending_limit.enabled) {
            if (!validate_spending_limit(policy, amount, current_time)) {
                return false
            };
        };

        // Validate whitelist
        if (policy.whitelist.enabled) {
            if (!validate_whitelist(policy, recipient, current_time)) {
                return false
            };
        };

        // Validate category
        if (policy.category.enabled) {
            if (!validate_category(policy, category)) {
                return false
            };
        };

        // Validate amount threshold
        if (policy.amount_threshold.enabled) {
            if (!validate_amount_threshold(policy, amount, signature_count)) {
                return false
            };
        };

        true
    }

    /// Calculate required time-lock based on amount
    /// Formula: time_lock = base + (amount / factor)
    public fun calculate_time_lock(
        policy: &PolicyConfig,
        amount: u64
    ): u64 {
        if (!policy.time_lock.enabled) {
            return 0
        };

        policy.time_lock.base_time_lock + (amount / policy.time_lock.amount_factor)
    }

    /// Record spending for tracking
    public fun record_spending(
        policy: &mut PolicyConfig,
        amount: u64,
        current_time: u64
    ) {
        if (!policy.spending_limit.enabled) {
            return
        };

        // Check if we need to reset the period
        reset_spending_if_needed(policy, current_time);

        // Add to current spending
        policy.spending_limit.current_spent = policy.spending_limit.current_spent + amount;
    }

    // ==================== Internal Validation Functions ====================
    
    /// Validate spending limit
    fun validate_spending_limit(
        policy: &mut PolicyConfig,
        amount: u64,
        current_time: u64
    ): bool {
        // Reset if period has expired
        reset_spending_if_needed(policy, current_time);

        let new_total = policy.spending_limit.current_spent + amount;
        
        if (new_total > policy.spending_limit.limit) {
            event::emit(SpendingLimitExceeded {
                policy_id: object::id(policy),
                attempted_amount: amount,
                current_spent: policy.spending_limit.current_spent,
                limit: policy.spending_limit.limit,
                timestamp: current_time,
            });
            return false
        };

        true
    }

    /// Reset spending counter if period has expired
    fun reset_spending_if_needed(
        policy: &mut PolicyConfig,
        current_time: u64
    ) {
        let period_duration = if (policy.spending_limit.period == PERIOD_DAILY) {
            MS_PER_DAY
        } else if (policy.spending_limit.period == PERIOD_WEEKLY) {
            MS_PER_WEEK
        } else {
            MS_PER_MONTH
        };

        if (current_time >= policy.spending_limit.period_start + period_duration) {
            policy.spending_limit.current_spent = 0;
            policy.spending_limit.period_start = current_time;

            event::emit(SpendingReset {
                policy_id: object::id(policy),
                period: policy.spending_limit.period,
                timestamp: current_time,
            });
        };
    }

    /// Validate recipient is whitelisted
    fun validate_whitelist(
        policy: &PolicyConfig,
        recipient: address,
        current_time: u64
    ): bool {
        let entries = &policy.whitelist.entries;
        let mut i = 0;
        let len = entries.length();

        while (i < len) {
            let entry = &entries[i];
            if (entry.address == recipient) {
                // Check if not expired
                if (current_time <= entry.expires_at) {
                    return true
                };
            };
            i = i + 1;
        };

        event::emit(WhitelistViolation {
            policy_id: object::id(policy),
            recipient,
            timestamp: current_time,
        });

        false
    }

    /// Validate category is allowed
    fun validate_category(
        policy: &PolicyConfig,
        category: u8
    ): bool {
        policy.category.required_categories.contains(&category)
    }

    /// Validate amount threshold requirements
    fun validate_amount_threshold(
        policy: &PolicyConfig,
        amount: u64,
        signature_count: u64
    ): bool {
        let tiers = &policy.amount_threshold.tiers;
        let mut i = 0;
        let len = tiers.length();
        let mut required_sigs = 0;

        // Find the highest tier that applies
        while (i < len) {
            let tier = &tiers[i];
            if (amount >= tier.min_amount && tier.required_signatures > required_sigs) {
                required_sigs = tier.required_signatures;
            };
            i = i + 1;
        };

        signature_count >= required_sigs
    }

    // ==================== View Functions ====================
    
    /// Get spending limit info
    public fun get_spending_limit(policy: &PolicyConfig): (bool, u8, u64, u64) {
        (
            policy.spending_limit.enabled,
            policy.spending_limit.period,
            policy.spending_limit.limit,
            policy.spending_limit.current_spent
        )
    }

    /// Get whitelist entries
    public fun get_whitelist_entries(policy: &PolicyConfig): vector<WhitelistEntry> {
        policy.whitelist.entries
    }

    /// Check if whitelist is enabled
    public fun is_whitelist_enabled(policy: &PolicyConfig): bool {
        policy.whitelist.enabled
    }

    /// Check if spending limit is enabled
    public fun is_spending_limit_enabled(policy: &PolicyConfig): bool {
        policy.spending_limit.enabled
    }

    /// Check if time-lock policy is enabled
    public fun is_time_lock_enabled(policy: &PolicyConfig): bool {
        policy.time_lock.enabled
    }

    /// Get policy ID
    public fun get_policy_id(policy: &PolicyConfig): ID {
        object::id(policy)
    }

    /// Disable spending limit
    public fun disable_spending_limit(policy: &mut PolicyConfig, ctx: &mut TxContext) {
        policy.spending_limit.enabled = false;
        policy.updated_at = ctx.epoch_timestamp_ms();
    }

    /// Disable whitelist
    public fun disable_whitelist(policy: &mut PolicyConfig, ctx: &mut TxContext) {
        policy.whitelist.enabled = false;
        policy.updated_at = ctx.epoch_timestamp_ms();
    }

    /// Disable time-lock policy
    public fun disable_time_lock(policy: &mut PolicyConfig, ctx: &mut TxContext) {
        policy.time_lock.enabled = false;
        policy.updated_at = ctx.epoch_timestamp_ms();
    }

    // ==================== Test Only Functions ====================
    
    #[test_only]
    public fun destroy_policy_for_testing(policy: PolicyConfig) {
        let PolicyConfig {
            id,
            treasury_id: _,
            spending_limit: _,
            whitelist: _,
            category: _,
            amount_threshold: _,
            time_lock: _,
            created_at: _,
            updated_at: _,
        } = policy;
        
        object::delete(id);
    }

    #[test_only]
    public fun get_current_spent_for_testing(policy: &PolicyConfig): u64 {
        policy.spending_limit.current_spent
    }
}
