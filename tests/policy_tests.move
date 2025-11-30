#[test_only]
module multisig_treasury::policy_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use std::string;
    use multisig_treasury::PolicyManager::{Self, PolicyConfig};
    use multisig_treasury::Treasury;

    const ADMIN: address = @0xAD;
    const RECIPIENT1: address = @0xB1;
    const RECIPIENT2: address = @0xB2;

    #[test]
    fun test_create_policy_config() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let policy = PolicyManager::create_policy_config(treasury_id, scenario.ctx());

            assert!(!PolicyManager::is_spending_limit_enabled(&policy), 0);
            assert!(!PolicyManager::is_whitelist_enabled(&policy), 1);
            assert!(!PolicyManager::is_time_lock_enabled(&policy), 2);

            PolicyManager::destroy_policy_for_testing(policy);
        };

        scenario.end();
    }

    #[test]
    fun test_set_spending_limit() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let mut policy = PolicyManager::create_policy_config(treasury_id, scenario.ctx());

            PolicyManager::set_spending_limit(&mut policy, 0, 10000, scenario.ctx()); // Daily, 10000 limit

            assert!(PolicyManager::is_spending_limit_enabled(&policy), 0);
            let (enabled, period, limit, spent) = PolicyManager::get_spending_limit(&policy);
            assert!(enabled, 1);
            assert!(period == 0, 2); // PERIOD_DAILY
            assert!(limit == 10000, 3);
            assert!(spent == 0, 4);

            PolicyManager::destroy_policy_for_testing(policy);
        };

        scenario.end();
    }

    #[test]
    fun test_spending_limit_validation() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let mut policy = PolicyManager::create_policy_config(treasury_id, scenario.ctx());

            PolicyManager::set_spending_limit(&mut policy, 0, 1000, scenario.ctx());

            let current_time = scenario.ctx().epoch_timestamp_ms();

            // Should pass - within limit
            assert!(
                PolicyManager::validate_all_policies(
                    &mut policy,
                    RECIPIENT1,
                    500,
                    0,
                    2,
                    current_time
                ),
                0
            );

            // Record spending
            PolicyManager::record_spending(&mut policy, 500, current_time);

            // Should pass - still within limit
            assert!(
                PolicyManager::validate_all_policies(
                    &mut policy,
                    RECIPIENT1,
                    400,
                    0,
                    2,
                    current_time
                ),
                1
            );

            // Should fail - exceeds limit
            assert!(
                !PolicyManager::validate_all_policies(
                    &mut policy,
                    RECIPIENT1,
                    600,
                    0,
                    2,
                    current_time
                ),
                2
            );

            PolicyManager::destroy_policy_for_testing(policy);
        };

        scenario.end();
    }

    #[test]
    fun test_whitelist_policy() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let mut policy = PolicyManager::create_policy_config(treasury_id, scenario.ctx());

            let current_time = scenario.ctx().epoch_timestamp_ms();
            let expiry = current_time + 86400000; // 1 day

            PolicyManager::add_to_whitelist(
                &mut policy,
                RECIPIENT1,
                expiry,
                string::utf8(b"Approved recipient"),
                scenario.ctx()
            );

            assert!(PolicyManager::is_whitelist_enabled(&policy), 0);

            // Should pass - whitelisted
            assert!(
                PolicyManager::validate_all_policies(
                    &mut policy,
                    RECIPIENT1,
                    100,
                    0,
                    2,
                    current_time
                ),
                1
            );

            // Should fail - not whitelisted
            assert!(
                !PolicyManager::validate_all_policies(
                    &mut policy,
                    RECIPIENT2,
                    100,
                    0,
                    2,
                    current_time
                ),
                2
            );

            PolicyManager::destroy_policy_for_testing(policy);
        };

        scenario.end();
    }

    #[test]
    fun test_whitelist_expiry() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let mut policy = PolicyManager::create_policy_config(treasury_id, scenario.ctx());

            let current_time = scenario.ctx().epoch_timestamp_ms();
            let expiry = current_time + 1000; // 1 second

            PolicyManager::add_to_whitelist(
                &mut policy,
                RECIPIENT1,
                expiry,
                string::utf8(b"Test"),
                scenario.ctx()
            );

            // Should pass - not expired
            assert!(
                PolicyManager::validate_all_policies(
                    &mut policy,
                    RECIPIENT1,
                    100,
                    0,
                    2,
                    current_time
                ),
                0
            );

            // Should fail - expired
            assert!(
                !PolicyManager::validate_all_policies(
                    &mut policy,
                    RECIPIENT1,
                    100,
                    0,
                    2,
                    expiry + 1000
                ),
                1
            );

            PolicyManager::destroy_policy_for_testing(policy);
        };

        scenario.end();
    }

    #[test]
    fun test_remove_from_whitelist() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let mut policy = PolicyManager::create_policy_config(treasury_id, scenario.ctx());

            let current_time = scenario.ctx().epoch_timestamp_ms();
            let expiry = current_time + 86400000;

            PolicyManager::add_to_whitelist(&mut policy, RECIPIENT1, expiry, string::utf8(b"Test"), scenario.ctx());
            
            // Should pass
            assert!(
                PolicyManager::validate_all_policies(&mut policy, RECIPIENT1, 100, 0, 2, current_time),
                0
            );

            // Remove from whitelist
            PolicyManager::remove_from_whitelist(&mut policy, RECIPIENT1, scenario.ctx());

            // Should fail now
            assert!(
                !PolicyManager::validate_all_policies(&mut policy, RECIPIENT1, 100, 0, 2, current_time),
                1
            );

            PolicyManager::destroy_policy_for_testing(policy);
        };

        scenario.end();
    }

    #[test]
    fun test_amount_threshold_policy() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let mut policy = PolicyManager::create_policy_config(treasury_id, scenario.ctx());

            // Add tiers: 0-1000 needs 2 sigs, 1000+ needs 3 sigs
            PolicyManager::add_threshold_tier(&mut policy, 0, 2, scenario.ctx());
            PolicyManager::add_threshold_tier(&mut policy, 1000, 3, scenario.ctx());

            let current_time = scenario.ctx().epoch_timestamp_ms();

            // 500 with 2 signatures - should pass
            assert!(
                PolicyManager::validate_all_policies(&mut policy, RECIPIENT1, 500, 0, 2, current_time),
                0
            );

            // 1500 with 2 signatures - should fail (needs 3)
            assert!(
                !PolicyManager::validate_all_policies(&mut policy, RECIPIENT1, 1500, 0, 2, current_time),
                1
            );

            // 1500 with 3 signatures - should pass
            assert!(
                PolicyManager::validate_all_policies(&mut policy, RECIPIENT1, 1500, 0, 3, current_time),
                2
            );

            PolicyManager::destroy_policy_for_testing(policy);
        };

        scenario.end();
    }

    #[test]
    fun test_time_lock_calculation() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let mut policy = PolicyManager::create_policy_config(treasury_id, scenario.ctx());

            // Set time-lock: base 1000ms + (amount / 100)
            PolicyManager::set_time_lock_policy(&mut policy, 1000, 100, scenario.ctx());

            assert!(PolicyManager::is_time_lock_enabled(&policy), 0);

            // Amount 500: time_lock = 1000 + (500/100) = 1005
            let time_lock = PolicyManager::calculate_time_lock(&policy, 500);
            assert!(time_lock == 1005, 1);

            // Amount 10000: time_lock = 1000 + (10000/100) = 1100
            let time_lock2 = PolicyManager::calculate_time_lock(&policy, 10000);
            assert!(time_lock2 == 1100, 2);

            PolicyManager::destroy_policy_for_testing(policy);
        };

        scenario.end();
    }

    #[test]
    fun test_set_required_categories() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let mut policy = PolicyManager::create_policy_config(treasury_id, scenario.ctx());

            let categories = vector[0, 1, 2]; // Allow categories 0, 1, 2
            PolicyManager::set_required_categories(&mut policy, categories, scenario.ctx());

            let current_time = scenario.ctx().epoch_timestamp_ms();

            // Category 0 - should pass
            assert!(
                PolicyManager::validate_all_policies(&mut policy, RECIPIENT1, 100, 0, 2, current_time),
                0
            );

            // Category 5 - should fail
            assert!(
                !PolicyManager::validate_all_policies(&mut policy, RECIPIENT1, 100, 5, 2, current_time),
                1
            );

            PolicyManager::destroy_policy_for_testing(policy);
        };

        scenario.end();
    }

    #[test]
    fun test_disable_policies() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let mut policy = PolicyManager::create_policy_config(treasury_id, scenario.ctx());

            // Enable policies
            PolicyManager::set_spending_limit(&mut policy, 0, 1000, scenario.ctx());
            PolicyManager::set_time_lock_policy(&mut policy, 1000, 100, scenario.ctx());

            assert!(PolicyManager::is_spending_limit_enabled(&policy), 0);
            assert!(PolicyManager::is_time_lock_enabled(&policy), 1);

            // Disable policies
            PolicyManager::disable_spending_limit(&mut policy, scenario.ctx());
            PolicyManager::disable_time_lock(&mut policy, scenario.ctx());

            assert!(!PolicyManager::is_spending_limit_enabled(&policy), 2);
            assert!(!PolicyManager::is_time_lock_enabled(&policy), 3);

            PolicyManager::destroy_policy_for_testing(policy);
        };

        scenario.end();
    }

    #[test]
    fun test_spending_reset_after_period() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let mut policy = PolicyManager::create_policy_config(treasury_id, scenario.ctx());

            PolicyManager::set_spending_limit(&mut policy, 0, 1000, scenario.ctx()); // Daily limit

            let current_time = scenario.ctx().epoch_timestamp_ms();

            // Spend 800
            PolicyManager::record_spending(&mut policy, 800, current_time);
            assert!(PolicyManager::get_current_spent_for_testing(&policy) == 800, 0);

            // Try to spend 300 - should fail
            assert!(
                !PolicyManager::validate_all_policies(&mut policy, RECIPIENT1, 300, 0, 2, current_time),
                1
            );

            // After 1 day, should reset
            let next_day = current_time + 86400001; // Just over 1 day
            
            // Should pass now (reset)
            assert!(
                PolicyManager::validate_all_policies(&mut policy, RECIPIENT1, 300, 0, 2, next_day),
                2
            );

            PolicyManager::destroy_policy_for_testing(policy);
        };

        scenario.end();
    }
}
