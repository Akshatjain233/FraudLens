-- ==============================================================================
-- FraudLens AI - Fraud Investigation (Module 5)
-- Author: Senior Data Analytics Lead, American Express
-- Purpose: Actionable queries driving the day-to-day workflow of Fraud Analysts.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- Query 1: Active Investigation Queue (Pending Cases)
-- ------------------------------------------------------------------------------
/*
Business Question: What cases do I need to work on right now?
Why this matters: This is the primary operational queue for the investigation floor.
Business Insight: Prioritizes workload strictly by SLA (Critical first, then High).
Interview Question: "How do you fetch an active work queue efficiently?"
SQL Concepts Used: WHERE IN, ORDER BY.
Expected Output: transaction_id, customer_id, amount, priority, risk_score.
Dashboard Usage: Main table visual in the Analyst Workbench.
Optimization Strategy: Queries the vw_priority_cases view which is indexed on priority and status.
*/
SELECT 
    transaction_id,
    customer_id,
    amount,
    priority,
    risk_score,
    sender_historic_fraud_rate,
    sender_prior_drains
FROM vw_priority_cases
ORDER BY 
    CASE priority 
        WHEN 'Critical' THEN 1 
        WHEN 'High' THEN 2 
    END ASC, 
    amount DESC;

-- ------------------------------------------------------------------------------
-- Query 2: Transactions Above Fraud Median (High-Value Suspicion)
-- ------------------------------------------------------------------------------
/*
Business Question: Which pending cases represent a financial risk above our known median fraud size ($441k)?
Why this matters: High-value cases must be assigned to Senior Investigators, not junior analysts.
SQL Concepts Used: Filtering, Subqueries (Implicit via hardcoded business rule derived from EDA).
Expected Output: transaction_id, amount, priority.
Dashboard Usage: "VIP / High Value Escalation" tab.
Optimization Strategy: Fast numerical filter on amount.
*/
SELECT 
    transaction_id,
    customer_id,
    amount,
    transaction_type,
    priority,
    risk_score
FROM FRAUD_INVESTIGATION
WHERE amount > 441000 AND investigation_status = 'Pending Review'
ORDER BY amount DESC;

-- ------------------------------------------------------------------------------
-- Query 3: Repeat Destination Accounts (Money Mules)
-- ------------------------------------------------------------------------------
/*
Business Question: Which destination accounts are receiving funds from multiple different high-risk senders?
Why this matters: Money launderers use "mule" accounts to consolidate stolen funds from multiple victims.
Business Insight: Taking down one mule network can stop dozens of future ATOs.
Interview Question: "Write a query to find accounts receiving funds from more than 3 distinct senders."
SQL Concepts Used: GROUP BY, HAVING, COUNT(DISTINCT).
Expected Output: receiver_account, distinct_victims, total_stolen_amount.
Dashboard Usage: Network/Graph analysis visualizations.
Optimization Strategy: Scanning only the high-risk transaction subset speeds up the DISTINCT count.
*/
SELECT 
    receiver_account,
    COUNT(DISTINCT sender_account) AS distinct_victims,
    SUM(amount) AS total_stolen_amount,
    COUNT(transaction_id) AS total_incoming_transfers
FROM FACT_TRANSACTIONS
WHERE risk_score >= 60 OR is_fraud = TRUE
GROUP BY receiver_account
HAVING COUNT(DISTINCT sender_account) >= 2
ORDER BY distinct_victims DESC, total_stolen_amount DESC;

-- ------------------------------------------------------------------------------
-- Query 4: Large Cash Out Anomaly Detection
-- ------------------------------------------------------------------------------
/*
Business Question: Which pending cases involve massive Cash Outs?
Why this matters: Cash out means the money is leaving the financial system entirely (e.g., ATM, wire to crypto). Recovery rate is 0%.
SQL Concepts Used: WHERE, Categorical matching.
Expected Output: transaction_id, customer_id, amount.
Dashboard Usage: "Flight Risk" queue.
Optimization Strategy: Utilizes the `vw_cashout_fraud` or raw FRAUD_INVESTIGATION table.
*/
SELECT 
    transaction_id,
    customer_id,
    amount,
    account_drained,
    risk_score
FROM FRAUD_INVESTIGATION
WHERE transaction_type = 'CASH_OUT' 
  AND amount > 100000 
  AND investigation_status = 'Pending Review'
ORDER BY amount DESC;

-- ------------------------------------------------------------------------------
-- Query 5: Accounts Receiving Multiple Fraud Transactions
-- ------------------------------------------------------------------------------
/*
Business Question: Who are the top 50 absolute worst receiver accounts in our system historically?
Why this matters: These accounts should be blacklisted at the routing level.
SQL Concepts Used: Aggregation, ORDER BY, LIMIT.
Expected Output: receiver_account, incoming_fraud_count.
Dashboard Usage: Blacklist Management Console.
Optimization Strategy: Filters on `is_fraud = TRUE` first, then groups. Efficient index usage.
*/
SELECT 
    receiver_account,
    COUNT(transaction_id) AS incoming_fraud_count,
    SUM(amount) AS total_fraud_received
FROM FACT_TRANSACTIONS
WHERE is_fraud = TRUE
GROUP BY receiver_account
ORDER BY incoming_fraud_count DESC, total_fraud_received DESC
LIMIT 50;

-- ------------------------------------------------------------------------------
-- Query 6: Analyst Workload and Status Summary
-- ------------------------------------------------------------------------------
/*
Business Question: How many cases are currently pending vs closed, segmented by Priority?
Why this matters: Floor managers need to track team throughput and identify bottlenecks.
SQL Concepts Used: GROUP BY multiple columns.
Expected Output: priority, investigation_status, case_count.
Dashboard Usage: Managerial Overview Dashboard.
Optimization Strategy: Queries the much smaller FRAUD_INVESTIGATION table.
*/
SELECT 
    priority,
    investigation_status,
    COUNT(*) AS case_count,
    SUM(amount) AS total_exposure
FROM FRAUD_INVESTIGATION
GROUP BY priority, investigation_status
ORDER BY priority, investigation_status;
