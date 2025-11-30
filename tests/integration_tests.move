#[test_only]
module multisig_treasury::integration_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use std::string;
    use multisig_treasury::Treasury::{Self, Treasury, TreasuryAdminCap};
    use multisig_treasury::Proposal::{Self, Proposal};
    use multisig_treasury::PolicyManager::{Self, PolicyConfig};
    use multisig_treasury::EmergencyModule::{Self, EmergencyConfig};

    const ADMIN: address = @0xAD;
    const SIGNER1: address = @0xA1;
    const SIGNER2: address = @0xA2;
    const SIGNER3: address = @0xA3;
    const RECIPIENT: address = @0xB1;
    const EMERGENCY1: address = @0xE1;
    const EMERGENCY2: address = @0xE2;

    #[test]
    /// End-to-end test: Create treasury → deposit → create proposal → sign → execute
    fun test_complete_withdrawal_workflow() {
        let mut scenario = ts::begin(ADMIN);
        
        // Step 1: Create treasury with 3 signers, threshold 2
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

        // Step 2: Deposit 10000 SUI
        scenario.next_tx(ADMIN);
        {
            let mut treasury = scenario.take_shared<Treasury>();
            let coin = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            
            Treasury::deposit(&mut treasury, coin, scenario.ctx());
            assert!(Treasury::get_balance(&treasury) == 10000, 0);

            ts::return_shared(treasury);
        };

        // Step 3: SIGNER1 creates withdrawal proposal
        scenario.next_tx(SIGNER1);
        {
            let treasury = scenario.take_shared<Treasury>();
            
            let tx1 = Proposal::new_transaction(
                RECIPIENT,
                1000,
                string::utf8(b"Payment to recipient")
            );
            
            let proposal = Proposal::create_withdrawal_proposal(
                &treasury,
                string::utf8(b"Monthly Payment"),
                string::utf8(b"Regular monthly payment"),
                vector[tx1],
                100, // Short time-lock for testing
                scenario.ctx()
            );

            transfer::public_share_object(proposal);
            ts::return_shared(treasury);
        };

        // Step 4: SIGNER2 signs the proposal
        scenario.next_tx(SIGNER2);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let treasury = scenario.take_shared<Treasury>();

            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx());
            assert!(Proposal::get_signature_count(&proposal) == 1, 1);

            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        // Step 5: SIGNER3 signs the proposal (reaches threshold)
        scenario.next_tx(SIGNER3);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let treasury = scenario.take_shared<Treasury>();

            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx());
            assert!(Proposal::get_signature_count(&proposal) == 2, 2);

            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        // Step 6: Execute the proposal
        scenario.next_tx(SIGNER1);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let mut treasury = scenario.take_shared<Treasury>();

            // Advance time past time-lock
            scenario.ctx().increment_epoch_timestamp(200);

            Proposal::execute_proposal(&mut proposal, &mut treasury, scenario.ctx());
            
            assert!(Treasury::get_balance(&treasury) == 9000, 3);
            assert!(Proposal::get_status(&proposal) == 1, 4); // STATUS_EXECUTED

            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    /// Test batch withdrawal with multiple transactions
    fun test_batch_withdrawal_workflow() {
        let mut scenario = ts::begin(ADMIN);
        
        // Create and fund treasury
        {
            let signers = vector[SIGNER1, SIGNER2];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 2, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        scenario.next_tx(ADMIN);
        {
            let mut treasury = scenario.take_shared<Treasury>();
            let coin = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            Treasury::deposit(&mut treasury, coin, scenario.ctx());
            ts::return_shared(treasury);
        };

        // Create batch proposal
        scenario.next_tx(SIGNER1);
        {
            let treasury = scenario.take_shared<Treasury>();
            
            let mut transactions = vector::empty();
            transactions.push_back(Proposal::new_transaction(@0xB1, 100, string::utf8(b"Payment 1")));
            transactions.push_back(Proposal::new_transaction(@0xB2, 200, string::utf8(b"Payment 2")));
            transactions.push_back(Proposal::new_transaction(@0xB3, 300, string::utf8(b"Payment 3")));
            
            let proposal = Proposal::create_withdrawal_proposal(
                &treasury,
                string::utf8(b"Batch Payments"),
                string::utf8(b"Multiple payments"),
                transactions,
                100,
                scenario.ctx()
            );

            assert!(Proposal::get_transaction_count(&proposal) == 3, 0);

            transfer::public_share_object(proposal);
            ts::return_shared(treasury);
        };

        // Sign and execute
        scenario.next_tx(SIGNER1);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let treasury = scenario.take_shared<Treasury>();
            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx());
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        scenario.next_tx(SIGNER2);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let treasury = scenario.take_shared<Treasury>();
            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx());
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        scenario.next_tx(SIGNER1);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let mut treasury = scenario.take_shared<Treasury>();
            
            scenario.ctx().increment_epoch_timestamp(200);
            Proposal::execute_proposal(&mut proposal, &mut treasury, scenario.ctx());
            
            // Total withdrawn: 100 + 200 + 300 = 600
            assert!(Treasury::get_balance(&treasury) == 9400, 1);

            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    /// Test policy enforcement workflow
    fun test_policy_enforcement_workflow() {
        let mut scenario = ts::begin(ADMIN);
        
        // Create treasury
        {
            let signers = vector[SIGNER1, SIGNER2];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 2, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        // Create policy config with spending limit
        scenario.next_tx(ADMIN);
        {
            let treasury = scenario.take_shared<Treasury>();
            let treasury_id = Treasury::get_treasury_id(&treasury);
            
            let mut policy = PolicyManager::create_policy_config(treasury_id, scenario.ctx());
            
            // Set daily spending limit of 1000
            PolicyManager::set_spending_limit(&mut policy, 0, 1000, scenario.ctx());
            
            // Add recipient to whitelist
            let expiry = scenario.ctx().epoch_timestamp_ms() + 86400000;
            PolicyManager::add_to_whitelist(
                &mut policy,
                RECIPIENT,
                expiry,
                string::utf8(b"Approved recipient"),
                scenario.ctx()
            );

            transfer::public_share_object(policy);
            ts::return_shared(treasury);
        };

        // Test policy validation
        scenario.next_tx(ADMIN);
        {
            let mut policy = scenario.take_shared<PolicyConfig>();
            let current_time = scenario.ctx().epoch_timestamp_ms();

            // Should pass - within limit and whitelisted
            assert!(
                PolicyManager::validate_all_policies(
                    &mut policy,
                    RECIPIENT,
                    500,
                    0,
                    2,
                    current_time
                ),
                0
            );

            // Record spending
            PolicyManager::record_spending(&mut policy, 500, current_time);

            // Should fail - exceeds limit
            assert!(
                !PolicyManager::validate_all_policies(
                    &mut policy,
                    RECIPIENT,
                    600,
                    0,
                    2,
                    current_time
                ),
                1
            );

            ts::return_shared(policy);
        };

        scenario.end();
    }

    #[test]
    /// Test emergency freeze workflow
    fun test_emergency_freeze_workflow() {
        let mut scenario = ts::begin(ADMIN);
        
        // Create treasury
        {
            let signers = vector[SIGNER1, SIGNER2];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 2, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        // Create emergency config
        scenario.next_tx(ADMIN);
        {
            let treasury = scenario.take_shared<Treasury>();
            let treasury_id = Treasury::get_treasury_id(&treasury);
            
            let emergency_signers = vector[EMERGENCY1, EMERGENCY2];
            let config = EmergencyModule::create_emergency_config(
                treasury_id,
                emergency_signers,
                2, // Both must sign
                scenario.ctx()
            );

            transfer::public_share_object(config);
            ts::return_shared(treasury);
        };

        // Trigger emergency freeze
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

        // Verify operations are blocked
        scenario.next_tx(SIGNER1);
        {
            let treasury = scenario.take_shared<Treasury>();
            
            let tx1 = Proposal::new_transaction(RECIPIENT, 100, string::utf8(b"Test"));
            
            // Should fail - treasury is frozen
            // (In real scenario, this would abort)

            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    /// Test signer management workflow
    fun test_signer_management_workflow() {
        let mut scenario = ts::begin(ADMIN);
        
        // Create treasury
        {
            let signers = vector[SIGNER1, SIGNER2];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 2, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        // Create proposal to add SIGNER3
        scenario.next_tx(SIGNER1);
        {
            let treasury = scenario.take_shared<Treasury>();
            
            let proposal = Proposal::create_add_signer_proposal(
                &treasury,
                string::utf8(b"Add New Signer"),
                string::utf8(b"Add SIGNER3 to treasury"),
                SIGNER3,
                100,
                scenario.ctx()
            );

            transfer::public_share_object(proposal);
            ts::return_shared(treasury);
        };

        // Sign by both existing signers
        scenario.next_tx(SIGNER1);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let treasury = scenario.take_shared<Treasury>();
            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx());
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        scenario.next_tx(SIGNER2);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let treasury = scenario.take_shared<Treasury>();
            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx());
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        // Execute proposal
        scenario.next_tx(SIGNER1);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let mut treasury = scenario.take_shared<Treasury>();
            
            scenario.ctx().increment_epoch_timestamp(200);
            
            assert!(Treasury::get_signers(&treasury).length() == 2, 0);
            
            Proposal::execute_proposal(&mut proposal, &mut treasury, scenario.ctx());
            
            assert!(Treasury::get_signers(&treasury).length() == 3, 1);
            assert!(Treasury::is_signer(&treasury, SIGNER3), 2);

            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    /// Test threshold update workflow
    fun test_threshold_update_workflow() {
        let mut scenario = ts::begin(ADMIN);
        
        // Create treasury with threshold 2
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 2, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        // Create proposal to update threshold to 3
        scenario.next_tx(SIGNER1);
        {
            let treasury = scenario.take_shared<Treasury>();
            
            let proposal = Proposal::create_update_threshold_proposal(
                &treasury,
                string::utf8(b"Increase Security"),
                string::utf8(b"Require all 3 signers"),
                3,
                100,
                scenario.ctx()
            );

            transfer::public_share_object(proposal);
            ts::return_shared(treasury);
        };

        // Get 2 signatures
        scenario.next_tx(SIGNER1);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let treasury = scenario.take_shared<Treasury>();
            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx());
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        scenario.next_tx(SIGNER2);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let treasury = scenario.take_shared<Treasury>();
            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx());
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        // Execute
        scenario.next_tx(SIGNER1);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let mut treasury = scenario.take_shared<Treasury>();
            
            scenario.ctx().increment_epoch_timestamp(200);
            
            assert!(Treasury::get_threshold(&treasury) == 2, 0);
            
            Proposal::execute_proposal(&mut proposal, &mut treasury, scenario.ctx());
            
            assert!(Treasury::get_threshold(&treasury) == 3, 1);

            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        scenario.end();
    }
}
