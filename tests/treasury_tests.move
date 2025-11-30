#[test_only]
module multisig_treasury::treasury_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_utils;
    use multisig_treasury::Treasury::{Self, Treasury, TreasuryAdminCap};

    // Test addresses
    const ADMIN: address = @0xAD;
    const SIGNER1: address = @0xA1;
    const SIGNER2: address = @0xA2;
    const SIGNER3: address = @0xA3;
    const USER: address = @0xB1;

    #[test]
    fun test_create_treasury_success() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let threshold = 2;
            
            let (treasury, admin_cap) = Treasury::create_treasury(
                signers,
                threshold,
                scenario.ctx()
            );

            assert!(Treasury::get_threshold(&treasury) == 2, 0);
            assert!(Treasury::get_signers(&treasury).length() == 3, 1);
            assert!(Treasury::get_balance(&treasury) == 0, 2);
            assert!(!Treasury::is_frozen(&treasury), 3);

            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = Treasury::E_INVALID_THRESHOLD)]
    fun test_create_treasury_invalid_threshold() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let signers = vector[SIGNER1, SIGNER2];
            let threshold = 3; // More than signers
            
            let (treasury, admin_cap) = Treasury::create_treasury(
                signers,
                threshold,
                scenario.ctx()
            );

            transfer::public_transfer(admin_cap, ADMIN);
            Treasury::destroy_treasury_for_testing(treasury);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = Treasury::E_DUPLICATE_SIGNER)]
    fun test_create_treasury_duplicate_signers() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER1]; // Duplicate
            let threshold = 2;
            
            let (treasury, admin_cap) = Treasury::create_treasury(
                signers,
                threshold,
                scenario.ctx()
            );

            transfer::public_transfer(admin_cap, ADMIN);
            Treasury::destroy_treasury_for_testing(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_deposit() {
        let mut scenario = ts::begin(ADMIN);
        
        // Create treasury
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let (treasury, admin_cap) = Treasury::create_treasury(
                signers,
                2,
                scenario.ctx()
            );

            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        // Deposit funds
        scenario.next_tx(USER);
        {
            let mut treasury = scenario.take_shared<Treasury>();
            let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            
            Treasury::deposit(&mut treasury, coin, scenario.ctx());
            
            assert!(Treasury::get_balance(&treasury) == 1000, 0);
            assert!(Treasury::get_total_deposits(&treasury) == 1000, 1);

            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_can_execute_valid_signatures() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let treasury = Treasury::create_treasury_for_testing(
                signers,
                2,
                scenario.ctx()
            );

            let signatures = vector[SIGNER1, SIGNER2];
            assert!(Treasury::can_execute(&treasury, &signatures), 0);

            Treasury::destroy_treasury_for_testing(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_can_execute_insufficient_signatures() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let treasury = Treasury::create_treasury_for_testing(
                signers,
                2,
                scenario.ctx()
            );

            let signatures = vector[SIGNER1]; // Only 1 signature
            assert!(!Treasury::can_execute(&treasury, &signatures), 0);

            Treasury::destroy_treasury_for_testing(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_can_execute_invalid_signer() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let treasury = Treasury::create_treasury_for_testing(
                signers,
                2,
                scenario.ctx()
            );

            let signatures = vector[SIGNER1, USER]; // USER not a signer
            assert!(!Treasury::can_execute(&treasury, &signatures), 0);

            Treasury::destroy_treasury_for_testing(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_freeze_and_unfreeze() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let mut treasury = Treasury::create_treasury_for_testing(
                signers,
                2,
                scenario.ctx()
            );

            assert!(!Treasury::is_frozen(&treasury), 0);

            Treasury::freeze_treasury(&mut treasury, scenario.ctx());
            assert!(Treasury::is_frozen(&treasury), 1);

            Treasury::unfreeze_treasury(&mut treasury, scenario.ctx());
            assert!(!Treasury::is_frozen(&treasury), 2);

            Treasury::destroy_treasury_for_testing(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_add_signer() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let signers = vector[SIGNER1, SIGNER2];
            let mut treasury = Treasury::create_treasury_for_testing(
                signers,
                2,
                scenario.ctx()
            );

            assert!(Treasury::get_signers(&treasury).length() == 2, 0);

            Treasury::add_signer(&mut treasury, SIGNER3, scenario.ctx());
            
            assert!(Treasury::get_signers(&treasury).length() == 3, 1);
            assert!(Treasury::is_signer(&treasury, SIGNER3), 2);

            Treasury::destroy_treasury_for_testing(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_remove_signer() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let mut treasury = Treasury::create_treasury_for_testing(
                signers,
                2,
                scenario.ctx()
            );

            assert!(Treasury::get_signers(&treasury).length() == 3, 0);

            Treasury::remove_signer(&mut treasury, SIGNER3, scenario.ctx());
            
            assert!(Treasury::get_signers(&treasury).length() == 2, 1);
            assert!(!Treasury::is_signer(&treasury, SIGNER3), 2);

            Treasury::destroy_treasury_for_testing(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_update_threshold() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let mut treasury = Treasury::create_treasury_for_testing(
                signers,
                2,
                scenario.ctx()
            );

            assert!(Treasury::get_threshold(&treasury) == 2, 0);

            Treasury::update_threshold(&mut treasury, 3, scenario.ctx());
            
            assert!(Treasury::get_threshold(&treasury) == 3, 1);

            Treasury::destroy_treasury_for_testing(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_is_signer() {
        let mut scenario = ts::begin(ADMIN);
        
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let treasury = Treasury::create_treasury_for_testing(
                signers,
                2,
                scenario.ctx()
            );

            assert!(Treasury::is_signer(&treasury, SIGNER1), 0);
            assert!(Treasury::is_signer(&treasury, SIGNER2), 1);
            assert!(Treasury::is_signer(&treasury, SIGNER3), 2);
            assert!(!Treasury::is_signer(&treasury, USER), 3);

            Treasury::destroy_treasury_for_testing(treasury);
        };

        scenario.end();
    }
}
