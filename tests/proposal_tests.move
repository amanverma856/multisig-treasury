#[test_only]
module multisig_treasury::proposal_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use std::string;
    use multisig_treasury::Treasury::{Self, Treasury};
    use multisig_treasury::Proposal::{Self, Proposal, Transaction};

    // Test addresses
    const ADMIN: address = @0xAD;
    const SIGNER1: address = @0xA1;
    const SIGNER2: address = @0xA2;
    const SIGNER3: address = @0xA3;
    const RECIPIENT: address = @0xB1;

    #[test]
    fun test_create_withdrawal_proposal() {
        let mut scenario = ts::begin(SIGNER1);
        
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

        // Create proposal
        scenario.next_tx(SIGNER1);
        {
            let treasury = scenario.take_shared<Treasury>();
            
            let tx1 = Proposal::new_transaction(
                RECIPIENT,
                100,
                string::utf8(b"Payment 1")
            );
            let transactions = vector[tx1];
            
            let proposal = Proposal::create_withdrawal_proposal(
                &treasury,
                string::utf8(b"Test Proposal"),
                string::utf8(b"Test withdrawal"),
                transactions,
                1000, // 1 second time-lock
                scenario.ctx()
            );

            assert!(Proposal::get_transaction_count(&proposal) == 1, 0);
            assert!(Proposal::get_signature_count(&proposal) == 0, 1);
            assert!(Proposal::get_creator(&proposal) == SIGNER1, 2);

            transfer::public_share_object(proposal);
            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_sign_proposal() {
        let mut scenario = ts::begin(SIGNER1);
        
        // Setup
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

        // Create proposal
        scenario.next_tx(SIGNER1);
        {
            let treasury = scenario.take_shared<Treasury>();
            let tx1 = Proposal::new_transaction(RECIPIENT, 100, string::utf8(b"Test"));
            let proposal = Proposal::create_withdrawal_proposal(
                &treasury,
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                vector[tx1],
                1000,
                scenario.ctx()
            );
            transfer::public_share_object(proposal);
            ts::return_shared(treasury);
        };

        // Sign by SIGNER2
        scenario.next_tx(SIGNER2);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let treasury = scenario.take_shared<Treasury>();

            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx());
            
            assert!(Proposal::get_signature_count(&proposal) == 1, 0);
            assert!(Proposal::has_signed(&proposal, SIGNER2), 1);

            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        // Sign by SIGNER3
        scenario.next_tx(SIGNER3);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let treasury = scenario.take_shared<Treasury>();

            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx());
            
            assert!(Proposal::get_signature_count(&proposal) == 2, 0);
            assert!(Proposal::has_signed(&proposal, SIGNER3), 1);

            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = Proposal::E_ALREADY_SIGNED)]
    fun test_sign_proposal_duplicate() {
        let mut scenario = ts::begin(SIGNER1);
        
        // Setup
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 2, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        // Create proposal
        scenario.next_tx(SIGNER1);
        {
            let treasury = scenario.take_shared<Treasury>();
            let tx1 = Proposal::new_transaction(RECIPIENT, 100, string::utf8(b"Test"));
            let proposal = Proposal::create_withdrawal_proposal(
                &treasury,
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                vector[tx1],
                1000,
                scenario.ctx()
            );
            transfer::public_share_object(proposal);
            ts::return_shared(treasury);
        };

        // Sign twice by same signer
        scenario.next_tx(SIGNER2);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let treasury = scenario.take_shared<Treasury>();

            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx());
            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx()); // Should fail

            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_batch_transactions() {
        let mut scenario = ts::begin(SIGNER1);
        
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 2, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        scenario.next_tx(SIGNER1);
        {
            let treasury = scenario.take_shared<Treasury>();
            
            // Create multiple transactions
            let mut transactions = vector::empty();
            let i = 0;
            while (i < 10) {
                let tx = Proposal::new_transaction(
                    RECIPIENT,
                    100 + i,
                    string::utf8(b"Batch payment")
                );
                transactions.push_back(tx);
                i = i + 1;
            };
            
            let proposal = Proposal::create_withdrawal_proposal(
                &treasury,
                string::utf8(b"Batch Test"),
                string::utf8(b"Multiple payments"),
                transactions,
                1000,
                scenario.ctx()
            );

            assert!(Proposal::get_transaction_count(&proposal) == 10, 0);

            transfer::public_share_object(proposal);
            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_cancel_proposal_by_creator() {
        let mut scenario = ts::begin(SIGNER1);
        
        // Setup
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 2, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        // Create proposal
        scenario.next_tx(SIGNER1);
        {
            let treasury = scenario.take_shared<Treasury>();
            let tx1 = Proposal::new_transaction(RECIPIENT, 100, string::utf8(b"Test"));
            let proposal = Proposal::create_withdrawal_proposal(
                &treasury,
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                vector[tx1],
                1000,
                scenario.ctx()
            );
            transfer::public_share_object(proposal);
            ts::return_shared(treasury);
        };

        // Cancel by creator
        scenario.next_tx(SIGNER1);
        {
            let mut proposal = scenario.take_shared<Proposal>();
            let treasury = scenario.take_shared<Treasury>();

            Proposal::cancel_proposal(&mut proposal, &treasury, scenario.ctx());
            
            assert!(Proposal::get_status(&proposal) == 2, 0); // STATUS_CANCELLED

            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_create_add_signer_proposal() {
        let mut scenario = ts::begin(SIGNER1);
        
        {
            let signers = vector[SIGNER1, SIGNER2];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 2, scenario.ctx());
            transfer::public_transfer(admin_cap, ADMIN);
            transfer::public_share_object(treasury);
        };

        scenario.next_tx(SIGNER1);
        {
            let treasury = scenario.take_shared<Treasury>();
            
            let proposal = Proposal::create_add_signer_proposal(
                &treasury,
                string::utf8(b"Add Signer"),
                string::utf8(b"Add SIGNER3"),
                SIGNER3,
                1000,
                scenario.ctx()
            );

            assert!(Proposal::get_category(&proposal) == 1, 0); // CATEGORY_ADD_SIGNER
            assert!(Proposal::get_transaction_count(&proposal) == 0, 1);

            transfer::public_share_object(proposal);
            ts::return_shared(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_validate_time_lock() {
        let mut scenario = ts::begin(SIGNER1);
        
        {
            let signers = vector[SIGNER1, SIGNER2];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 2, scenario.ctx());
            
            let tx1 = Proposal::new_transaction(RECIPIENT, 100, string::utf8(b"Test"));
            let proposal = Proposal::create_withdrawal_proposal(
                &treasury,
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                vector[tx1],
                5000, // 5 second time-lock
                scenario.ctx()
            );

            let time_lock_until = Proposal::get_time_lock_until(&proposal);
            
            // Should not be valid immediately
            assert!(!Proposal::validate_time_lock(&proposal, time_lock_until - 1000), 0);
            
            // Should be valid after time-lock
            assert!(Proposal::validate_time_lock(&proposal, time_lock_until), 1);
            assert!(Proposal::validate_time_lock(&proposal, time_lock_until + 1000), 2);

            transfer::public_transfer(admin_cap, ADMIN);
            Proposal::destroy_proposal_for_testing(proposal);
            Treasury::destroy_treasury_for_testing(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_validate_threshold() {
        let mut scenario = ts::begin(SIGNER1);
        
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let (treasury, admin_cap) = Treasury::create_treasury(signers, 2, scenario.ctx());
            
            let tx1 = Proposal::new_transaction(RECIPIENT, 100, string::utf8(b"Test"));
            let mut proposal = Proposal::create_withdrawal_proposal(
                &treasury,
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                vector[tx1],
                1000,
                scenario.ctx()
            );

            // No signatures yet
            assert!(!Proposal::validate_threshold(&proposal, 2), 0);

            // Add signatures manually for testing
            Proposal::sign_proposal(&mut proposal, &treasury, scenario.ctx());
            assert!(!Proposal::validate_threshold(&proposal, 2), 1);

            transfer::public_transfer(admin_cap, ADMIN);
            Proposal::destroy_proposal_for_testing(proposal);
            Treasury::destroy_treasury_for_testing(treasury);
        };

        scenario.end();
    }
}
