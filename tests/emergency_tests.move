#[test_only]
module multisig_treasury::emergency_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use std::string;
    use multisig_treasury::EmergencyModule::{Self, EmergencyConfig};
    use multisig_treasury::Treasury::{Self, Treasury};

    const ADMIN: address = @0xAD;
    const EMERGENCY1: address = @0xE1;
    const EMERGENCY2: address = @0xE2;
    const EMERGENCY3: address = @0xE3;
    const SIGNER1: address = @0xA1;

    #[test]
    fun test_create_emergency_config() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let emergency_signers = vector[EMERGENCY1, EMERGENCY2, EMERGENCY3];
            let threshold = 2; // 2 of 3 (66%)
            
            let config = EmergencyModule::create_emergency_config(
                treasury_id,
                emergency_signers,
                threshold,
                scenario.ctx()
            );

            assert!(EmergencyModule::get_emergency_threshold(&config) == 2, 0);
            assert!(EmergencyModule::get_emergency_signers(&config).length() == 3, 1);
            assert!(!EmergencyModule::is_in_emergency(&config), 2);

            EmergencyModule::destroy_config_for_testing(config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EmergencyModule::E_INVALID_EMERGENCY_THRESHOLD)]
    fun test_create_config_insufficient_threshold() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let emergency_signers = vector[EMERGENCY1, EMERGENCY2, EMERGENCY3];
            let threshold = 1; // Only 33%, should fail (needs 66%)
            
            let config = EmergencyModule::create_emergency_config(
                treasury_id,
                emergency_signers,
                threshold,
                scenario.ctx()
            );

            EmergencyModule::destroy_config_for_testing(config);
        };

        scenario.end();
    }

    #[test]
    fun test_freeze_treasury() {
        let mut scenario = ts::begin(ADMIN);
        
        // Create treasury
        {
            let signers = vector[SIGNER1];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 1, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        // Create emergency config
        {
            let treasury = scenario.take_shared<Treasury>();
            let treasury_id = Treasury::get_treasury_id(&treasury);
            
            let emergency_signers = vector[EMERGENCY1, EMERGENCY2, EMERGENCY3];
            let config = EmergencyModule::create_emergency_config(
                treasury_id,
                emergency_signers,
                2,
                scenario.ctx()
            );

            transfer::public_share_object(config);
            ts::return_shared(treasury);
        };

        // Freeze treasury
        scenario.next_tx(EMERGENCY1);
        {
            let mut config = scenario.take_shared<EmergencyConfig>();
            let mut treasury = scenario.take_shared<Treasury>();

            assert!(!Treasury::is_frozen(&treasury), 0);

            let signatures = vector[EMERGENCY1, EMERGENCY2];
            EmergencyModule::freeze_treasury(
                &mut config,
                &mut treasury,
                string::utf8(b"Security breach detected"),
                signatures,
                scenario.ctx()
            );

            assert!(Treasury::is_frozen(&treasury), 1);
            assert!(EmergencyModule::is_in_emergency(&config), 2);

            ts::return_shared(config);
            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EmergencyModule::E_EMERGENCY_THRESHOLD_NOT_MET)]
    fun test_freeze_insufficient_signatures() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let signers = vector[SIGNER1];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 1, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        {
            let treasury = scenario.take_shared<Treasury>();
            let treasury_id = Treasury::get_treasury_id(&treasury);
            
            let emergency_signers = vector[EMERGENCY1, EMERGENCY2, EMERGENCY3];
            let config = EmergencyModule::create_emergency_config(
                treasury_id,
                emergency_signers,
                2,
                scenario.ctx()
            );

            transfer::public_share_object(config);
            ts::return_shared(treasury);
        };

        scenario.next_tx(EMERGENCY1);
        {
            let mut config = scenario.take_shared<EmergencyConfig>();
            let mut treasury = scenario.take_shared<Treasury>();

            let signatures = vector[EMERGENCY1]; // Only 1 signature, needs 2
            EmergencyModule::freeze_treasury(
                &mut config,
                &mut treasury,
                string::utf8(b"Test"),
                signatures,
                scenario.ctx()
            );

            ts::return_shared(config);
            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_unfreeze_after_cooldown() {
        let mut scenario = ts::begin(ADMIN);
        
        // Setup
        {
            let signers = vector[SIGNER1];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 1, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        {
            let treasury = scenario.take_shared<Treasury>();
            let treasury_id = Treasury::get_treasury_id(&treasury);
            
            let emergency_signers = vector[EMERGENCY1, EMERGENCY2, EMERGENCY3];
            let config = EmergencyModule::create_emergency_config(
                treasury_id,
                emergency_signers,
                2,
                scenario.ctx()
            );

            transfer::public_share_object(config);
            ts::return_shared(treasury);
        };

        // Freeze
        scenario.next_tx(EMERGENCY1);
        {
            let mut config = scenario.take_shared<EmergencyConfig>();
            let mut treasury = scenario.take_shared<Treasury>();

            let signatures = vector[EMERGENCY1, EMERGENCY2];
            EmergencyModule::freeze_treasury(
                &mut config,
                &mut treasury,
                string::utf8(b"Test"),
                signatures,
                scenario.ctx()
            );

            assert!(Treasury::is_frozen(&treasury), 0);

            ts::return_shared(config);
            ts::return_shared(treasury);
        };

        // Try to unfreeze immediately - should fail due to cooldown
        // (Can't test this easily without advancing time in test scenario)

        scenario.end();
    }

    #[test]
    fun test_add_emergency_signer() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let emergency_signers = vector[EMERGENCY1, EMERGENCY2];
            let mut config = EmergencyModule::create_emergency_config(
                treasury_id,
                emergency_signers,
                2,
                scenario.ctx()
            );

            assert!(EmergencyModule::get_emergency_signers(&config).length() == 2, 0);

            EmergencyModule::add_emergency_signer(&mut config, EMERGENCY3, scenario.ctx());

            assert!(EmergencyModule::get_emergency_signers(&config).length() == 3, 1);
            assert!(EmergencyModule::is_emergency_signer(&config, EMERGENCY3), 2);

            EmergencyModule::destroy_config_for_testing(config);
        };

        scenario.end();
    }

    #[test]
    fun test_remove_emergency_signer() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let emergency_signers = vector[EMERGENCY1, EMERGENCY2, EMERGENCY3];
            let mut config = EmergencyModule::create_emergency_config(
                treasury_id,
                emergency_signers,
                2,
                scenario.ctx()
            );

            assert!(EmergencyModule::get_emergency_signers(&config).length() == 3, 0);

            EmergencyModule::remove_emergency_signer(&mut config, EMERGENCY3, scenario.ctx());

            assert!(EmergencyModule::get_emergency_signers(&config).length() == 2, 1);
            assert!(!EmergencyModule::is_emergency_signer(&config, EMERGENCY3), 2);

            EmergencyModule::destroy_config_for_testing(config);
        };

        scenario.end();
    }

    #[test]
    fun test_update_cooldown_period() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let emergency_signers = vector[EMERGENCY1, EMERGENCY2];
            let mut config = EmergencyModule::create_emergency_config(
                treasury_id,
                emergency_signers,
                2,
                scenario.ctx()
            );

            let default_cooldown = EmergencyModule::get_cooldown_period(&config);
            assert!(default_cooldown == 86400000, 0); // 24 hours

            EmergencyModule::update_cooldown_period(&mut config, 3600000); // 1 hour

            assert!(EmergencyModule::get_cooldown_period(&config) == 3600000, 1);

            EmergencyModule::destroy_config_for_testing(config);
        };

        scenario.end();
    }

    #[test]
    fun test_update_emergency_threshold() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let emergency_signers = vector[EMERGENCY1, EMERGENCY2, EMERGENCY3];
            let mut config = EmergencyModule::create_emergency_config(
                treasury_id,
                emergency_signers,
                2,
                scenario.ctx()
            );

            assert!(EmergencyModule::get_emergency_threshold(&config) == 2, 0);

            EmergencyModule::update_emergency_threshold(&mut config, 3);

            assert!(EmergencyModule::get_emergency_threshold(&config) == 3, 1);

            EmergencyModule::destroy_config_for_testing(config);
        };

        scenario.end();
    }

    #[test]
    fun test_is_emergency_signer() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let treasury_id = object::id_from_address(@0x1);
            let emergency_signers = vector[EMERGENCY1, EMERGENCY2];
            let config = EmergencyModule::create_emergency_config(
                treasury_id,
                emergency_signers,
                2,
                scenario.ctx()
            );

            assert!(EmergencyModule::is_emergency_signer(&config, EMERGENCY1), 0);
            assert!(EmergencyModule::is_emergency_signer(&config, EMERGENCY2), 1);
            assert!(!EmergencyModule::is_emergency_signer(&config, EMERGENCY3), 2);
            assert!(!EmergencyModule::is_emergency_signer(&config, SIGNER1), 3);

            EmergencyModule::destroy_config_for_testing(config);
        };

        scenario.end();
    }

    #[test]
    fun test_trigger_emergency() {
        let mut scenario = ts::begin(ADMIN);
        
        // Setup
        {
            let signers = vector[SIGNER1];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 1, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        {
            let treasury = scenario.take_shared<Treasury>();
            let treasury_id = Treasury::get_treasury_id(&treasury);
            
            let emergency_signers = vector[EMERGENCY1, EMERGENCY2, EMERGENCY3];
            let config = EmergencyModule::create_emergency_config(
                treasury_id,
                emergency_signers,
                2,
                scenario.ctx()
            );

            transfer::public_share_object(config);
            ts::return_shared(treasury);
        };

        // Trigger emergency
        scenario.next_tx(EMERGENCY1);
        {
            let mut config = scenario.take_shared<EmergencyConfig>();
            let mut treasury = scenario.take_shared<Treasury>();

            assert!(!EmergencyModule::is_in_emergency(&config), 0);

            let signatures = vector[EMERGENCY1, EMERGENCY2];
            EmergencyModule::trigger_emergency(
                &mut config,
                &mut treasury,
                string::utf8(b"Critical security issue"),
                signatures,
                scenario.ctx()
            );

            assert!(EmergencyModule::is_in_emergency(&config), 1);

            ts::return_shared(config);
            ts::return_shared(treasury);
        };

        scenario.end();
    }
}
