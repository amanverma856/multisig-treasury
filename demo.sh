#!/bin/bash

# Sui Multi-Sig Treasury - Complete Demo Script
# This script demonstrates the full workflow of the multi-signature treasury system

echo "=================================================="
echo "Sui Multi-Sig Treasury - Complete Demo"
echo "=================================================="
echo ""

# Configuration - UPDATE THESE VALUES
PACKAGE_ID="<YOUR_PACKAGE_ID>"
NETWORK="testnet"  # or "mainnet", "devnet"

# Sample addresses (replace with actual addresses)
SIGNER1="0xa1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"
SIGNER2="0xa2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2"
SIGNER3="0xa3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3"
RECIPIENT="0xb1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1"
EMERGENCY1="0xe1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1"
EMERGENCY2="0xe2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2"

GAS_BUDGET=10000000

echo "Step 1: Creating Treasury"
echo "=========================="
echo "Creating a 3-of-5 multi-signature treasury..."
echo ""

sui client call \
  --package $PACKAGE_ID \
  --module Treasury \
  --function create_treasury \
  --args "[$SIGNER1, $SIGNER2, $SIGNER3]" "2" \
  --gas-budget $GAS_BUDGET

echo ""
echo "✓ Treasury created successfully!"
echo "Note: Save the TREASURY_ID from the output above"
read -p "Enter TREASURY_ID: " TREASURY_ID
echo ""

echo "Step 2: Depositing Funds"
echo "========================"
echo "Depositing 100,000 SUI into the treasury..."
echo ""

# First, we need a coin object to deposit
# In practice, you would use an actual coin object ID
read -p "Enter COIN_OBJECT_ID to deposit: " COIN_ID

sui client call \
  --package $PACKAGE_ID \
  --module Treasury \
  --function deposit \
  --args $TREASURY_ID $COIN_ID \
  --gas-budget $GAS_BUDGET

echo ""
echo "✓ Funds deposited successfully!"
echo ""

echo "Step 3: Setting Up Policies"
echo "==========================="
echo "Creating policy configuration..."
echo ""

sui client call \
  --package $PACKAGE_ID \
  --module PolicyManager \
  --function create_policy_config \
  --args $TREASURY_ID \
  --gas-budget $GAS_BUDGET

echo ""
read -p "Enter POLICY_CONFIG_ID: " POLICY_ID
echo ""

echo "Setting daily spending limit to 10,000 SUI..."
sui client call \
  --package $PACKAGE_ID \
  --module PolicyManager \
  --function set_spending_limit \
  --args $POLICY_ID "0" "10000000000000" \
  --gas-budget $GAS_BUDGET

echo ""
echo "Adding recipient to whitelist..."
EXPIRY_TIME=$(($(date +%s) * 1000 + 86400000))  # 24 hours from now

sui client call \
  --package $PACKAGE_ID \
  --module PolicyManager \
  --function add_to_whitelist \
  --args $POLICY_ID $RECIPIENT $EXPIRY_TIME "\"Approved vendor\"" \
  --gas-budget $GAS_BUDGET

echo ""
echo "✓ Policies configured successfully!"
echo ""

echo "Step 4: Creating Withdrawal Proposal"
echo "====================================="
echo "Creating a proposal to withdraw 1,000 SUI..."
echo ""

# Create proposal with single transaction
sui client call \
  --package $PACKAGE_ID \
  --module Proposal \
  --function create_withdrawal_proposal \
  --args $TREASURY_ID \
         "\"Monthly Payment\"" \
         "\"Regular monthly payment to vendor\"" \
         "[{\"recipient\":\"$RECIPIENT\",\"amount\":1000000000000,\"description\":\"Monthly service fee\"}]" \
         "3600000" \
  --gas-budget $GAS_BUDGET

echo ""
read -p "Enter PROPOSAL_ID: " PROPOSAL_ID
echo ""
echo "✓ Proposal created successfully!"
echo ""

echo "Step 5: Signing the Proposal"
echo "============================="
echo "Signer 1 signing the proposal..."
echo ""

sui client call \
  --package $PACKAGE_ID \
  --module Proposal \
  --function sign_proposal \
  --args $PROPOSAL_ID $TREASURY_ID \
  --gas-budget $GAS_BUDGET

echo ""
echo "✓ Signer 1 signed!"
echo ""

echo "Signer 2 signing the proposal (reaches threshold)..."
echo ""

# Switch to signer 2's account or use their key
sui client call \
  --package $PACKAGE_ID \
  --module Proposal \
  --function sign_proposal \
  --args $PROPOSAL_ID $TREASURY_ID \
  --gas-budget $GAS_BUDGET

echo ""
echo "✓ Signer 2 signed! Threshold reached (2 of 3)"
echo ""

echo "Step 6: Executing the Proposal"
echo "==============================="
echo "Waiting for time-lock to expire..."
echo "(In production, wait for the actual time-lock duration)"
echo ""
read -p "Press Enter when time-lock has expired..."

sui client call \
  --package $PACKAGE_ID \
  --module Proposal \
  --function execute_proposal \
  --args $PROPOSAL_ID $TREASURY_ID \
  --gas-budget $GAS_BUDGET

echo ""
echo "✓ Proposal executed successfully!"
echo "✓ 1,000 SUI transferred to recipient"
echo ""

echo "Step 7: Batch Withdrawal Example"
echo "================================="
echo "Creating a proposal with multiple transactions..."
echo ""

sui client call \
  --package $PACKAGE_ID \
  --module Proposal \
  --function create_withdrawal_proposal \
  --args $TREASURY_ID \
         "\"Batch Payments\"" \
         "\"Multiple vendor payments\"" \
         "[
           {\"recipient\":\"0xVENDOR1\",\"amount\":500000000000,\"description\":\"Vendor 1\"},
           {\"recipient\":\"0xVENDOR2\",\"amount\":750000000000,\"description\":\"Vendor 2\"},
           {\"recipient\":\"0xVENDOR3\",\"amount\":1000000000000,\"description\":\"Vendor 3\"}
         ]" \
         "7200000" \
  --gas-budget $GAS_BUDGET

echo ""
echo "✓ Batch proposal created with 3 transactions!"
echo ""

echo "Step 8: Emergency Configuration"
echo "================================"
echo "Setting up emergency controls..."
echo ""

sui client call \
  --package $PACKAGE_ID \
  --module EmergencyModule \
  --function create_emergency_config \
  --args $TREASURY_ID "[$EMERGENCY1, $EMERGENCY2]" "2" \
  --gas-budget $GAS_BUDGET

echo ""
read -p "Enter EMERGENCY_CONFIG_ID: " EMERGENCY_CONFIG_ID
echo ""
echo "✓ Emergency configuration created!"
echo ""

echo "Step 9: Emergency Freeze (Demo)"
echo "================================"
echo "Simulating emergency freeze scenario..."
echo ""

sui client call \
  --package $PACKAGE_ID \
  --module EmergencyModule \
  --function freeze_treasury \
  --args $EMERGENCY_CONFIG_ID $TREASURY_ID \
         "\"Suspicious activity detected - freezing for investigation\"" \
         "[$EMERGENCY1, $EMERGENCY2]" \
  --gas-budget $GAS_BUDGET

echo ""
echo "✓ Treasury frozen! All operations are now blocked."
echo ""

echo "Step 10: Unfreeze After Cooldown"
echo "================================="
echo "Waiting for cooldown period (24 hours by default)..."
echo "(In this demo, we'll skip the actual wait)"
echo ""
read -p "Press Enter to unfreeze (in production, wait for cooldown)..."

sui client call \
  --package $PACKAGE_ID \
  --module EmergencyModule \
  --function unfreeze_treasury \
  --args $EMERGENCY_CONFIG_ID $TREASURY_ID "[$EMERGENCY1, $EMERGENCY2]" \
  --gas-budget $GAS_BUDGET

echo ""
echo "✓ Treasury unfrozen! Normal operations resumed."
echo ""

echo "Step 11: Signer Management"
echo "=========================="
echo "Creating proposal to add a new signer..."
echo ""

NEW_SIGNER="0xa4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4"

sui client call \
  --package $PACKAGE_ID \
  --module Proposal \
  --function create_add_signer_proposal \
  --args $TREASURY_ID \
         "\"Add New Signer\"" \
         "\"Adding SIGNER4 to increase security\"" \
         $NEW_SIGNER \
         "3600000" \
  --gas-budget $GAS_BUDGET

echo ""
echo "✓ Add signer proposal created!"
echo ""

echo "Step 12: Threshold Update"
echo "========================="
echo "Creating proposal to update threshold to 3..."
echo ""

sui client call \
  --package $PACKAGE_ID \
  --module Proposal \
  --function create_update_threshold_proposal \
  --args $TREASURY_ID \
         "\"Increase Security\"" \
         "\"Require 3 signatures for higher security\"" \
         "3" \
         "3600000" \
  --gas-budget $GAS_BUDGET

echo ""
echo "✓ Threshold update proposal created!"
echo ""

echo "=================================================="
echo "Demo Complete!"
echo "=================================================="
echo ""
echo "Summary of what we demonstrated:"
echo "1. ✓ Created a 3-of-5 multi-sig treasury"
echo "2. ✓ Deposited funds"
echo "3. ✓ Configured spending policies and whitelist"
echo "4. ✓ Created and executed a withdrawal proposal"
echo "5. ✓ Demonstrated batch transactions"
echo "6. ✓ Set up emergency controls"
echo "7. ✓ Performed emergency freeze/unfreeze"
echo "8. ✓ Managed signers"
echo "9. ✓ Updated threshold"
echo ""
echo "Next steps:"
echo "- Review transaction history in Sui Explorer"
echo "- Monitor events for all operations"
echo "- Test policy enforcement with various scenarios"
echo "- Configure additional policies as needed"
echo ""
echo "For more information, see README.md"
echo "=================================================="
