module multisig_treasury::Proposal {
    use sui::event;
    // use sui::table::{Self, Table}; // Unused
    use std::string::{Self, String};
    use multisig_treasury::Treasury::{Self as TreasuryModule, Treasury};

    // ==================== Error Codes ====================
    const E_INVALID_PROPOSAL: u64 = 100;
    const E_ALREADY_SIGNED: u64 = 101;
    const E_NOT_AUTHORIZED_SIGNER: u64 = 102;
    const E_TIME_LOCK_NOT_EXPIRED: u64 = 103;
    const E_THRESHOLD_NOT_MET: u64 = 104;
    const E_PROPOSAL_ALREADY_EXECUTED: u64 = 105;
    const E_PROPOSAL_CANCELLED: u64 = 106;
    const E_NOT_PROPOSAL_CREATOR: u64 = 107;
    const E_TOO_MANY_TRANSACTIONS: u64 = 108;
    const E_INVALID_TRANSACTION: u64 = 109;
    const E_TREASURY_FROZEN: u64 = 110;
    const E_EMPTY_TRANSACTIONS: u64 = 111;

    // ==================== Constants ====================
    const MAX_TRANSACTIONS: u64 = 50;

    // ==================== Enums (represented as u8) ====================
    
    /// Proposal categories
    const CATEGORY_WITHDRAWAL: u8 = 0;
    const CATEGORY_ADD_SIGNER: u8 = 1;
    const CATEGORY_REMOVE_SIGNER: u8 = 2;
    const CATEGORY_UPDATE_THRESHOLD: u8 = 3;
    const CATEGORY_UPDATE_POLICY: u8 = 4;
    const CATEGORY_EMERGENCY: u8 = 5;
    const CATEGORY_OTHER: u8 = 6;

    /// Proposal status
    const STATUS_PENDING: u8 = 0;
    const STATUS_EXECUTED: u8 = 1;
    const STATUS_CANCELLED: u8 = 2;

    // ==================== Structs ====================
    
    /// Represents a single transaction in a proposal
    public struct Transaction has store, copy, drop {
        /// Recipient address
        recipient: address,
        /// Amount to transfer
        amount: u64,
        /// Optional description
        description: String,
    }

    /// Main Proposal object
    public struct Proposal has key, store {
        id: UID,
        /// Reference to the treasury this proposal is for
        treasury_id: ID,
        /// Address of the proposal creator
        creator: address,
        /// Category of the proposal
        category: u8,
        /// Title/description of the proposal
        title: String,
        /// Detailed description
        description: String,
        /// List of transactions to execute (batch)
        transactions: vector<Transaction>,
        /// Addresses that have signed this proposal
        signatures: vector<address>,
        /// Timestamp when proposal was created
        created_at: u64,
        /// Timestamp when time-lock expires (can execute after this)
        time_lock_until: u64,
        /// Current status of the proposal
        status: u8,
        /// Optional: new signer address (for add_signer proposals)
        new_signer: Option<address>,
        /// Optional: signer to remove (for remove_signer proposals)
        remove_signer: Option<address>,
        /// Optional: new threshold (for update_threshold proposals)
        new_threshold: Option<u64>,
    }

    // ==================== Events ====================
    
    public struct ProposalCreated has copy, drop {
        proposal_id: ID,
        treasury_id: ID,
        creator: address,
        category: u8,
        title: String,
        transaction_count: u64,
        time_lock_until: u64,
        created_at: u64,
    }

    public struct ProposalSigned has copy, drop {
        proposal_id: ID,
        signer: address,
        signature_count: u64,
        timestamp: u64,
    }

    public struct ProposalExecuted has copy, drop {
        proposal_id: ID,
        executor: address,
        transaction_count: u64,
        timestamp: u64,
    }

    public struct ProposalCancelled has copy, drop {
        proposal_id: ID,
        cancelled_by: address,
        timestamp: u64,
    }

    // ==================== Public Functions ====================
    
    /// Create a new withdrawal proposal with batch transactions
    /// 
    /// # Arguments
    /// * `treasury` - Reference to Treasury
    /// * `title` - Proposal title
    /// * `description` - Detailed description
    /// * `transactions` - Vector of transactions to execute
    /// * `time_lock_duration` - Duration in milliseconds before execution is allowed
    /// * `ctx` - Transaction context
    public fun create_withdrawal_proposal(
        treasury: &Treasury,
        title: String,
        description: String,
        transactions: vector<Transaction>,
        time_lock_duration: u64,
        ctx: &mut TxContext
    ): Proposal {
        // Validate inputs
        assert!(!transactions.is_empty(), E_EMPTY_TRANSACTIONS);
        assert!(transactions.length() <= MAX_TRANSACTIONS, E_TOO_MANY_TRANSACTIONS);
        assert!(!TreasuryModule::is_frozen(treasury), E_TREASURY_FROZEN);

        // Validate creator is a signer
        let creator = ctx.sender();
        assert!(TreasuryModule::is_signer(treasury, creator), E_NOT_AUTHORIZED_SIGNER);

        let proposal_uid = object::new(ctx);
        let proposal_id = proposal_uid.to_inner();
        let created_at = ctx.epoch_timestamp_ms();
        let time_lock_until = created_at + time_lock_duration;

        let proposal = Proposal {
            id: proposal_uid,
            treasury_id: TreasuryModule::get_treasury_id(treasury),
            creator,
            category: CATEGORY_WITHDRAWAL,
            title,
            description,
            transactions,
            signatures: vector::empty(),
            created_at,
            time_lock_until,
            status: STATUS_PENDING,
            new_signer: option::none(),
            remove_signer: option::none(),
            new_threshold: option::none(),
        };

        // Emit creation event
        event::emit(ProposalCreated {
            proposal_id,
            treasury_id: proposal.treasury_id,
            creator,
            category: CATEGORY_WITHDRAWAL,
            title: proposal.title,
            transaction_count: proposal.transactions.length(),
            time_lock_until,
            created_at,
        });

        proposal
    }

    /// Create a proposal to add a new signer
    public fun create_add_signer_proposal(
        treasury: &Treasury,
        title: String,
        description: String,
        new_signer_addr: address,
        time_lock_duration: u64,
        ctx: &mut TxContext
    ): Proposal {
        assert!(!TreasuryModule::is_frozen(treasury), E_TREASURY_FROZEN);
        
        let creator = ctx.sender();
        assert!(TreasuryModule::is_signer(treasury, creator), E_NOT_AUTHORIZED_SIGNER);

        let proposal_uid = object::new(ctx);
        let proposal_id = proposal_uid.to_inner();
        let created_at = ctx.epoch_timestamp_ms();

        let proposal = Proposal {
            id: proposal_uid,
            treasury_id: TreasuryModule::get_treasury_id(treasury),
            creator,
            category: CATEGORY_ADD_SIGNER,
            title,
            description,
            transactions: vector::empty(),
            signatures: vector::empty(),
            created_at,
            time_lock_until: created_at + time_lock_duration,
            status: STATUS_PENDING,
            new_signer: option::some(new_signer_addr),
            remove_signer: option::none(),
            new_threshold: option::none(),
        };

        event::emit(ProposalCreated {
            proposal_id,
            treasury_id: proposal.treasury_id,
            creator,
            category: CATEGORY_ADD_SIGNER,
            title: proposal.title,
            transaction_count: 0,
            time_lock_until: proposal.time_lock_until,
            created_at,
        });

        proposal
    }

    /// Create a proposal to remove a signer
    public fun create_remove_signer_proposal(
        treasury: &Treasury,
        title: String,
        description: String,
        signer_to_remove: address,
        time_lock_duration: u64,
        ctx: &mut TxContext
    ): Proposal {
        assert!(!TreasuryModule::is_frozen(treasury), E_TREASURY_FROZEN);
        
        let creator = ctx.sender();
        assert!(TreasuryModule::is_signer(treasury, creator), E_NOT_AUTHORIZED_SIGNER);

        let proposal_uid = object::new(ctx);
        let proposal_id = proposal_uid.to_inner();
        let created_at = ctx.epoch_timestamp_ms();

        let proposal = Proposal {
            id: proposal_uid,
            treasury_id: TreasuryModule::get_treasury_id(treasury),
            creator,
            category: CATEGORY_REMOVE_SIGNER,
            title,
            description,
            transactions: vector::empty(),
            signatures: vector::empty(),
            created_at,
            time_lock_until: created_at + time_lock_duration,
            status: STATUS_PENDING,
            new_signer: option::none(),
            remove_signer: option::some(signer_to_remove),
            new_threshold: option::none(),
        };

        event::emit(ProposalCreated {
            proposal_id,
            treasury_id: proposal.treasury_id,
            creator,
            category: CATEGORY_REMOVE_SIGNER,
            title: proposal.title,
            transaction_count: 0,
            time_lock_until: proposal.time_lock_until,
            created_at,
        });

        proposal
    }

    /// Create a proposal to update threshold
    public fun create_update_threshold_proposal(
        treasury: &Treasury,
        title: String,
        description: String,
        new_threshold_value: u64,
        time_lock_duration: u64,
        ctx: &mut TxContext
    ): Proposal {
        assert!(!TreasuryModule::is_frozen(treasury), E_TREASURY_FROZEN);
        
        let creator = ctx.sender();
        assert!(TreasuryModule::is_signer(treasury, creator), E_NOT_AUTHORIZED_SIGNER);

        let proposal_uid = object::new(ctx);
        let proposal_id = proposal_uid.to_inner();
        let created_at = ctx.epoch_timestamp_ms();

        let proposal = Proposal {
            id: proposal_uid,
            treasury_id: TreasuryModule::get_treasury_id(treasury),
            creator,
            category: CATEGORY_UPDATE_THRESHOLD,
            title,
            description,
            transactions: vector::empty(),
            signatures: vector::empty(),
            created_at,
            time_lock_until: created_at + time_lock_duration,
            status: STATUS_PENDING,
            new_signer: option::none(),
            remove_signer: option::none(),
            new_threshold: option::some(new_threshold_value),
        };

        event::emit(ProposalCreated {
            proposal_id,
            treasury_id: proposal.treasury_id,
            creator,
            category: CATEGORY_UPDATE_THRESHOLD,
            title: proposal.title,
            transaction_count: 0,
            time_lock_until: proposal.time_lock_until,
            created_at,
        });

        proposal
    }

    /// Sign a proposal
    /// 
    /// # Arguments
    /// * `proposal` - Mutable reference to Proposal
    /// * `treasury` - Reference to Treasury (for validation)
    /// * `ctx` - Transaction context
    public fun sign_proposal(
        proposal: &mut Proposal,
        treasury: &Treasury,
        ctx: &mut TxContext
    ) {
        // Validate proposal is still pending
        assert!(proposal.status == STATUS_PENDING, E_PROPOSAL_ALREADY_EXECUTED);
        
        // Validate signer is authorized
        let signer = ctx.sender();
        assert!(TreasuryModule::is_signer(treasury, signer), E_NOT_AUTHORIZED_SIGNER);
        
        // Check not already signed
        assert!(!proposal.signatures.contains(&signer), E_ALREADY_SIGNED);

        // Add signature
        proposal.signatures.push_back(signer);

        // Emit signed event
        event::emit(ProposalSigned {
            proposal_id: object::id(proposal),
            signer,
            signature_count: proposal.signatures.length(),
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    /// Execute a proposal (after validation)
    /// 
    /// # Arguments
    /// * `proposal` - Mutable reference to Proposal
    /// * `treasury` - Mutable reference to Treasury
    /// * `ctx` - Transaction context
    public fun execute_proposal(
        proposal: &mut Proposal,
        treasury: &mut Treasury,
        ctx: &mut TxContext
    ) {
        // Validate proposal can be executed
        assert!(proposal.status == STATUS_PENDING, E_PROPOSAL_ALREADY_EXECUTED);
        assert!(!TreasuryModule::is_frozen(treasury), E_TREASURY_FROZEN);
        
        // Validate time-lock
        assert!(ctx.epoch_timestamp_ms() >= proposal.time_lock_until, E_TIME_LOCK_NOT_EXPIRED);
        
        // Validate threshold
        assert!(proposal.signatures.length() >= TreasuryModule::get_threshold(treasury), E_THRESHOLD_NOT_MET);
        
        // Validate signatures
        assert!(TreasuryModule::can_execute(treasury, &proposal.signatures), E_INVALID_PROPOSAL);

        // Execute based on category
        if (proposal.category == CATEGORY_WITHDRAWAL) {
            execute_withdrawal_proposal(proposal, treasury, ctx);
        } else if (proposal.category == CATEGORY_ADD_SIGNER) {
            execute_add_signer_proposal(proposal, treasury, ctx);
        } else if (proposal.category == CATEGORY_REMOVE_SIGNER) {
            execute_remove_signer_proposal(proposal, treasury, ctx);
        } else if (proposal.category == CATEGORY_UPDATE_THRESHOLD) {
            execute_update_threshold_proposal(proposal, treasury, ctx);
        };

        // Mark as executed
        proposal.status = STATUS_EXECUTED;

        // Emit executed event
        event::emit(ProposalExecuted {
            proposal_id: object::id(proposal),
            executor: ctx.sender(),
            transaction_count: proposal.transactions.length(),
            timestamp: ctx.epoch_timestamp_ms(),
        });

        // Emit treasury event
        TreasuryModule::emit_proposal_executed(treasury, object::id(proposal), ctx);
    }

    /// Cancel a proposal (only by creator or unanimous signers)
    /// 
    /// # Arguments
    /// * `proposal` - Mutable reference to Proposal
    /// * `treasury` - Reference to Treasury
    /// * `ctx` - Transaction context
    public fun cancel_proposal(
        proposal: &mut Proposal,
        treasury: &Treasury,
        ctx: &mut TxContext
    ) {
        assert!(proposal.status == STATUS_PENDING, E_PROPOSAL_ALREADY_EXECUTED);
        
        let canceller = ctx.sender();
        
        // Either creator can cancel, or all signers must agree
        let is_creator = canceller == proposal.creator;
        let all_signed = proposal.signatures.length() == TreasuryModule::get_signers(treasury).length();
        
        assert!(is_creator || all_signed, E_NOT_PROPOSAL_CREATOR);

        proposal.status = STATUS_CANCELLED;

        event::emit(ProposalCancelled {
            proposal_id: object::id(proposal),
            cancelled_by: canceller,
            timestamp: ctx.epoch_timestamp_ms(),
        });
    }

    // ==================== Internal Execution Functions ====================
    
    /// Execute withdrawal transactions
    fun execute_withdrawal_proposal(
        proposal: &Proposal,
        treasury: &mut Treasury,
        ctx: &mut TxContext
    ) {
        let mut i = 0;
        let len = proposal.transactions.length();

        while (i < len) {
            let tx = &proposal.transactions[i];
            
            // Withdraw and transfer
            let coin = TreasuryModule::withdraw_internal(
                treasury,
                tx.amount,
                tx.recipient,
                ctx
            );
            
            transfer::public_transfer(coin, tx.recipient);
            
            i = i + 1;
        };
    }

    /// Execute add signer proposal
    fun execute_add_signer_proposal(
        proposal: &Proposal,
        treasury: &mut Treasury,
        ctx: &TxContext
    ) {
        if (proposal.new_signer.is_some()) {
            let new_signer = *proposal.new_signer.borrow();
            TreasuryModule::add_signer(treasury, new_signer, ctx);
        };
    }

    /// Execute remove signer proposal
    fun execute_remove_signer_proposal(
        proposal: &Proposal,
        treasury: &mut Treasury,
        ctx: &TxContext
    ) {
        if (proposal.remove_signer.is_some()) {
            let signer_to_remove = *proposal.remove_signer.borrow();
            TreasuryModule::remove_signer(treasury, signer_to_remove, ctx);
        };
    }

    /// Execute update threshold proposal
    fun execute_update_threshold_proposal(
        proposal: &Proposal,
        treasury: &mut Treasury,
        ctx: &TxContext
    ) {
        if (proposal.new_threshold.is_some()) {
            let new_threshold = *proposal.new_threshold.borrow();
            TreasuryModule::update_threshold(treasury, new_threshold, ctx);
        };
    }

    // ==================== Helper Functions ====================
    
    /// Create a transaction object
    public fun new_transaction(
        recipient: address,
        amount: u64,
        description: String
    ): Transaction {
        Transaction {
            recipient,
            amount,
            description,
        }
    }

    /// Validate time-lock has expired
    public fun validate_time_lock(proposal: &Proposal, current_time: u64): bool {
        current_time >= proposal.time_lock_until
    }

    /// Validate threshold is met
    public fun validate_threshold(proposal: &Proposal, required_threshold: u64): bool {
        proposal.signatures.length() >= required_threshold
    }

    // ==================== View Functions ====================
    
    /// Get proposal ID
    public fun get_proposal_id(proposal: &Proposal): ID {
        object::id(proposal)
    }

    /// Get proposal creator
    public fun get_creator(proposal: &Proposal): address {
        proposal.creator
    }

    /// Get proposal category
    public fun get_category(proposal: &Proposal): u8 {
        proposal.category
    }

    /// Get proposal status
    public fun get_status(proposal: &Proposal): u8 {
        proposal.status
    }

    /// Get signature count
    public fun get_signature_count(proposal: &Proposal): u64 {
        proposal.signatures.length()
    }

    /// Get signatures
    public fun get_signatures(proposal: &Proposal): vector<address> {
        proposal.signatures
    }

    /// Get transaction count
    public fun get_transaction_count(proposal: &Proposal): u64 {
        proposal.transactions.length()
    }

    /// Get time lock until
    public fun get_time_lock_until(proposal: &Proposal): u64 {
        proposal.time_lock_until
    }

    /// Check if address has signed
    public fun has_signed(proposal: &Proposal, addr: address): bool {
        proposal.signatures.contains(&addr)
    }

    // ==================== Test Only Functions ====================
    
    #[test_only]
    public fun destroy_proposal_for_testing(proposal: Proposal) {
        let Proposal {
            id,
            treasury_id: _,
            creator: _,
            category: _,
            title: _,
            description: _,
            transactions: _,
            signatures: _,
            created_at: _,
            time_lock_until: _,
            status: _,
            new_signer: _,
            remove_signer: _,
            new_threshold: _,
        } = proposal;
        
        object::delete(id);
    }

    #[test_only]
    public fun get_transactions_for_testing(proposal: &Proposal): vector<Transaction> {
        proposal.transactions
    }
}
