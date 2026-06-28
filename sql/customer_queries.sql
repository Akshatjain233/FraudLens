-- ==============================================================================
-- FraudLens AI - Customer Analytics (Module 3)
-- Author: Senior Data Analytics Lead, American Express
-- Purpose: Identifying high-risk individuals, repeat offenders, and customer profiles.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- Query 1: Top Risk Customers
-- ------------------------------------------------------------------------------
/*
Business Question: Who are our highest-risk active senders?
Why this matters: Accounts with historically toxic behavior should be locked or heavily monitored.
Business Insight: Proactively freezing the top 1% of high-risk customers stops future fraud before it happens.
Interview Question: "How do you define a high-risk entity in SQL?"
SQL Concepts Used: WHERE, ORDER BY, LIMIT.
Expected Output: customer_id, total_transactions, fraud_percentage, average_risk_score.
Dashboard Usage: Table visual in Customer Risk dashboard.
Optimization Strategy: Queries the materialized CUSTOMER_SUMMARY table directly. Sub-millisecond response.
*/
SELECT 
    customer_id, 
    total_transactions, 
    fraud_transactions, 
    fraud_percentage, 
    average_risk_score
FROM CUSTOMER_SUMMARY
WHERE high_risk_customer_flag = TRUE
ORDER BY average_risk_score DESC, fraud_transactions DESC
LIMIT 100;

-- ------------------------------------------------------------------------------
-- Query 2: Repeat Fraud Customers
-- ------------------------------------------------------------------------------
/*
Business Question: Which customers have successfully executed fraud more than once?
Why this matters: A single fraud event might be an anomaly or compromised card. Repeat fraud means an active fraudster account.
SQL Concepts Used: Filtering on aggregated counts.
Expected Output: customer_id, fraud_transactions.
Dashboard Usage: Used to populate the "Repeat Offenders" warning list.
Optimization Strategy: Filter on `fraud_transactions > 1` utilizing CUSTOMER_SUMMARY.
*/
SELECT 
    customer_id, 
    fraud_transactions, 
    total_transactions
FROM CUSTOMER_SUMMARY
WHERE fraud_transactions > 1
ORDER BY fraud_transactions DESC;

-- ------------------------------------------------------------------------------
-- Query 3: Customer Lifetime Value (Transactions & Amount)
-- ------------------------------------------------------------------------------
/*
Business Question: Who are our highest-spending legitimate customers?
Why this matters: We must ensure our anti-fraud models do not falsely decline our VIP customers.
Business Insight: "Whales" need white-glove service. Fraud models should treat them differently.
SQL Concepts Used: Aggregation, Filtering out fraud.
Expected Output: customer_id, lifetime_amount, transaction_count.
Dashboard Usage: Customer segmentation clustering.
Optimization Strategy: Reads from FACT_TRANSACTIONS filtering `is_fraud = FALSE`. Heavy I/O query, runs overnight.
*/
SELECT 
    sender_account AS customer_id,
    COUNT(*) AS lifetime_transaction_count,
    SUM(amount) AS lifetime_spent_amount
FROM FACT_TRANSACTIONS
WHERE is_fraud = FALSE
GROUP BY sender_account
ORDER BY lifetime_spent_amount DESC
LIMIT 50;

-- ------------------------------------------------------------------------------
-- Query 4: Customer Percentile Ranking by Spend
-- ------------------------------------------------------------------------------
/*
Business Question: How do we categorize a customer's spend percentile (e.g., Top 1%)?
Why this matters: Risk scoring models need to know if a $10k transaction is normal for a Top 1% spender or abnormal for a Bottom 50% spender.
Interview Question: "Explain the difference between NTILE, RANK, and PERCENT_RANK."
SQL Concepts Used: Window Function (PERCENT_RANK).
Expected Output: customer_id, avg_spend, spend_percentile.
Dashboard Usage: Customer profile deep-dive view.
Optimization Strategy: Window functions over grouped data.
*/
WITH CustomerSpend AS (
    SELECT 
        customer_id,
        average_amount
    FROM CUSTOMER_SUMMARY
    WHERE total_transactions > 5 -- Filter out one-off accounts
)
SELECT 
    customer_id,
    average_amount,
    ROUND(PERCENT_RANK() OVER (ORDER BY average_amount) * 100, 2) AS spend_percentile
FROM CustomerSpend
ORDER BY spend_percentile DESC;

-- ------------------------------------------------------------------------------
-- Query 5: Customers with Multiple Account Drains
-- ------------------------------------------------------------------------------
/*
Business Question: Which customers repeatedly drain their accounts to exactly $0?
Why this matters: Normal users leave residual balances. Draining an account to $0 multiple times is a classic money laundering or mule account typology.
Business Insight: Identifies "Burner" accounts used purely to wash stolen funds.
SQL Concepts Used: Filtering on aggregated flags.
Expected Output: customer_id, account_drained_count, total_transactions.
Dashboard Usage: Filter for "Mule Ring Detection".
Optimization Strategy: Reads pre-calculated `account_drained_count` from CUSTOMER_SUMMARY.
*/
SELECT 
    customer_id, 
    account_drained_count, 
    total_transactions
FROM CUSTOMER_SUMMARY
WHERE account_drained_count >= 2
ORDER BY account_drained_count DESC;

-- ------------------------------------------------------------------------------
-- Query 6: Customer Ranking by Fraud Losses
-- ------------------------------------------------------------------------------
/*
Business Question: Rank the top 100 customers responsible for the largest financial fraud losses.
Why this matters: Prioritizes legal and recovery team efforts.
SQL Concepts Used: Window Function (DENSE_RANK).
Expected Output: loss_rank, customer_id, total_fraud_loss.
Dashboard Usage: Recovery Team priority queue.
Optimization Strategy: Pre-aggregation in CTE before applying Window Function.
*/
WITH FraudLosses AS (
    SELECT 
        sender_account AS customer_id,
        SUM(amount) AS total_fraud_loss
    FROM FACT_TRANSACTIONS
    WHERE is_fraud = TRUE
    GROUP BY sender_account
)
SELECT 
    DENSE_RANK() OVER (ORDER BY total_fraud_loss DESC) AS loss_rank,
    customer_id,
    total_fraud_loss
FROM FraudLosses
LIMIT 100;

-- ------------------------------------------------------------------------------
-- Query 7: Fraud Percentage by Customer Volume Tier
-- ------------------------------------------------------------------------------
/*
Business Question: Does fraud happen more frequently to new customers or established customers?
Why this matters: Determines if we need stricter onboarding verification or better behavioral models for older accounts.
SQL Concepts Used: CASE statement for dynamic bucketing.
Expected Output: customer_tenure_tier, total_customers, fraud_customers, fraud_rate.
Dashboard Usage: Bar chart mapping account age/volume to fraud risk.
Optimization Strategy: Evaluates the materialized CUSTOMER_SUMMARY in a single pass.
*/
SELECT 
    CASE 
        WHEN total_transactions = 1 THEN 'Single Transaction (New/Burner)'
        WHEN total_transactions BETWEEN 2 AND 10 THEN 'Occasional (2-10)'
        WHEN total_transactions BETWEEN 11 AND 50 THEN 'Regular (11-50)'
        ELSE 'High Volume (50+)'
    END AS customer_volume_tier,
    COUNT(*) AS customer_count,
    SUM(CASE WHEN fraud_transactions > 0 THEN 1 ELSE 0 END) AS customers_with_fraud,
    ROUND((SUM(CASE WHEN fraud_transactions > 0 THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) AS fraud_rate
FROM CUSTOMER_SUMMARY
GROUP BY customer_volume_tier
ORDER BY fraud_rate DESC;
