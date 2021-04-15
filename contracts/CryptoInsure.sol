// SPDX-License-Identifier: MIT
pragma solidity >= 0.4.0;

import "./PriceFeed.sol";

contract CryptoInsure {

    struct PricingPlan {
        uint percentageMarkup;
        uint noOfPayments; // no of installments over the term
        uint waitingPeriodInMonths;
    }

    struct Policy {
        bool exists; // used internally to check for existence in mapping
        bool pendingFirstInstallment;
        uint balance; // the insured amount
        uint startDate; // policy start date
        uint termInMonths; // the length of the insured period
        int bnbPriceAtStart; // peg the price of BNB against USD at start
        int bnbPriceAtClaim;
        uint noOfInstallmentsPaid; // no of paid installments
        uint totalRepayment; // the total repayment amount over the insured period
        bool isClaimApproved; // true if a claim made was approved else false
        bool isWithdrawn;
        uint noOfClaims; // claim > 1 means invalid/declined claims
        PricingPlan pricingPlan;
    }

    address private owner;
    mapping (address => Policy) private policies;
    mapping (uint => PricingPlan) pricingPlans;
    PriceFeed private priceFeed;

    modifier isOwner() {
        require(msg.sender == owner);
        _; // continue executing rest of method body
    }

    modifier isPolicyActive(address clientAddress) {
        Policy memory policy = policies[clientAddress];
        require(policy.exists && block.timestamp < calculateInstallmentDate(policy) && !policy.isClaimApproved && block.timestamp < retrievePolicyEndDate(policy));
        _;
    }

    constructor() { 
        owner = msg.sender;
        pricingPlans[6].percentageMarkup = 140;
        pricingPlans[6].noOfPayments = 1;
        pricingPlans[6].waitingPeriodInMonths = 2;
        pricingPlans[12].percentageMarkup = 120;
        pricingPlans[12].noOfPayments = 2;
        pricingPlans[12].waitingPeriodInMonths = 3;
    }

    function retrievePolicyEndDate(Policy memory policy) private pure returns(uint endDate) {
        return policy.startDate + (policy.termInMonths * 30 days);
    }

    function retrieveInstallmentAmount(Policy memory policy) private pure returns(uint installmentAmount) {
        return policy.totalRepayment / policy.pricingPlan.noOfPayments;
    }   

    function calculateInstallmentDate(Policy memory policy) private view returns(uint nextInstallmentDate) {
        if (policy.pendingFirstInstallment) {
            return block.timestamp;
        } 
        uint remainingPayments = policy.pricingPlan.noOfPayments - policy.noOfInstallmentsPaid;
        if (remainingPayments == 0) {
            return 0;
        }
        return policy.startDate + ((policy.termInMonths / 2) * 30 days);
    } 

    function registerPolicy(uint amntToInsure, uint termInMonths) public payable returns(bool registered) { 
        if (msg.value < 1 || policies[msg.sender].exists) { // 1 BNB is the minimum insured amount
            revert();
        } 
        Policy memory policy;
        policy.exists = true;
        policy.startDate = block.timestamp;
        policy.pricingPlan = pricingPlans[termInMonths];
        policy.pendingFirstInstallment = true;
        policy.totalRepayment = msg.value * pricingPlans[termInMonths].percentageMarkup;
        policy.bnbPriceAtStart = priceFeed.getLatestBNBPrice();
        policies[msg.sender] = policy;
    }

    function retrievePolicyDetails(address clientAddress) public view returns(uint balance, uint totalRepayment, uint noOfInstallments, 
                                                                              uint installmentAmount, uint waitingPeriod, bool isInArrears, 
                                                                              uint startDate, uint endDate, bool pendingFirstInstallment) {
        require(policies[clientAddress].exists);
        Policy memory policy = policies[clientAddress];
        bool isInArrears = block.timestamp >= calculateInstallmentDate(policy);
        return (policy.balance, policy.totalRepayment, policy.pricingPlan.noOfPayments, 
                retrieveInstallmentAmount(policy), policy.pricingPlan.waitingPeriodInMonths, 
                isInArrears, policy.startDate, retrievePolicyEndDate(policy), policy.pendingFirstInstallment);
    }

    function hasPolicyMatured(address clientAddress) public view returns(bool) {
        require(policies[clientAddress].exists);
        return block.timestamp >= retrievePolicyEndDate(policies[clientAddress]);
    }

    function isClaimApproved(address clientAddress) public view returns(bool approved) { // this method might be useless
        require(policies[clientAddress].exists);
        return policies[clientAddress].isClaimApproved;
    }

    function makeClaim(address clientAddress) public isPolicyActive(clientAddress) returns(bool) {
        Policy memory policy = policies[clientAddress];
        policy.bnbPriceAtClaim = priceFeed.getLatestBNBPrice();

        int claimThreshold =  1 - policy.bnbPriceAtClaim /  policy.bnbPriceAtStart;
        if (4 <= claimThreshold) {  // fix calculation to handle decimals
            return false;
        }
        policy.isClaimApproved = true;
        return true;
    }

    function withdraw() public view returns(bool) {
        require(policies[msg.sender].exists);
        Policy memory policy = policies[msg.sender];
        
    }

    function changeAddress(address newAddress) public returns(bool changed) {
        require(policies[msg.sender].exists);
        Policy memory policy = policies[msg.sender]; // need to still test
        delete(policies[msg.sender]);
        policies[newAddress] = policy;
        return true;
    } 

    function payInstallment(address clientAddress) public payable returns(bool) {
        Policy memory policy = policies[clientAddress];
        if (!policy.exists || msg.value < retrieveInstallmentAmount(policy)) {
            revert();
        }
        policy.noOfInstallmentsPaid += 1;
        policy.pendingFirstInstallment = false;
        return true;
    } 

    // assuming a maximum of 2 installments over 12 month period for now
    function getNextInstallmentDate(address clientAddress) public view returns(uint) {
        require(policies[clientAddress].exists);
        Policy memory policy = policies[clientAddress];
        return calculateInstallmentDate(policy);
    } 

    function cancelPolicy() public returns(bool cancelled) {
        require(policies[msg.sender].exists);
        policies[msg.sender].termInMonths = 0;
        return true;
    }   

    function ownerCancelPolicy(address clientAddress) public isOwner() returns(bool cancelled) {
        require(policies[clientAddress].exists);
        policies[msg.sender].termInMonths = 0; // find a way to reset policy
        return true;
    }   

}