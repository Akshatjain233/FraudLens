-- ==============================================================================
-- FraudLens AI - GenAI & NLP Queries (Module 8)
-- Author: Senior Data Analytics Lead, American Express
-- Purpose: Pre-defined SQL templates to power the Text-to-SQL GenAI Copilot.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- Prompt: "Why did fraud increase today?"
-- ------------------------------------------------------------------------------
/*
Business Purpose: Allows the GenAI agent to analyze daily spikes by breaking down the day's fraud by transaction type and size.
Business Value: Instant RCA (Root Cause Analysis).
SQL Concepts Used: Aggregation, GROUP BY.
Expected Result: Breakdown of exactly what drove the fraud on a given day.
GenAI Usage: The LLM will ingest this output and respond: "Fraud increased today primarily due to a 400% spike in Extreme-sized Cash Outs."
*/
SELECT 
    type,
    transaction_size,
    COUNT(*) AS fraud_count,
    SUM(amount) AS fraud_amount
FROM FACT_TRANSACTIONS
WHERE is_fraud = TRUE AND day = 14 -- GenAI injects the specific day here
GROUP BY type, transaction_size
ORDER BY fraud_amount DESC;

-- ------------------------------------------------------------------------------
-- Prompt: "Show me the highest priority cases."
-- ------------------------------------------------------------------------------
/*
Business Purpose: Fetches the immediate actionable queue for the analyst talking to the Copilot.
Business Value: Seamless workflow integration.
SQL Concepts Used: View abstraction.
Expected Result: Top 10 Critical cases.
GenAI Usage: The LLM formats this into a markdown table with actionable hyperlinks.
*/
SELECT 
    transaction_id,
    customer_id,
    amount,
    sender_prior_drains
FROM vw_priority_cases
WHERE priority = 'Critical'
ORDER BY amount DESC
LIMIT 10;

-- ------------------------------------------------------------------------------
-- Prompt: "Which customer requires the most urgent investigation?"
-- ------------------------------------------------------------------------------
/*
Business Purpose: Surfaces the absolute worst active customer entity in the system.
Business Value: Proactive risk mitigation.
SQL Concepts Used: ORDER BY multiple heuristic fields.
Expected Result: The single highest risk customer ID and their stats.
GenAI Usage: "Customer C123 requires urgent review. They have 4 recorded account drains and an average risk score of 95."
*/
SELECT 
    customer_id,
    total_transactions,
    fraud_transactions,
    account_drained_count,
    average_risk_score
FROM CUSTOMER_SUMMARY
WHERE high_risk_customer_flag = TRUE
ORDER BY average_risk_score DESC, account_drained_count DESC
LIMIT 1;

-- ------------------------------------------------------------------------------
-- Prompt: "Which transaction has the highest risk score right now?"
-- ------------------------------------------------------------------------------
/*
Business Purpose: Points the analyst to the "smoking gun" transaction of the day.
Expected Result: A single transaction record.
GenAI Usage: Natural language extraction of the transaction details to summarize *why* the score is 100.
*/
SELECT 
    transaction_id,
    type,
    amount,
    sender_account,
    receiver_account,
    risk_score,
    account_drained,
    balance_change
FROM FACT_TRANSACTIONS
WHERE investigation_status = 'Pending Review' -- Assumes joining or querying FRAUD_INVESTIGATION context
ORDER BY risk_score DESC, amount DESC
LIMIT 1;

-- ------------------------------------------------------------------------------
-- Prompt: "Generate the weekly executive summary dataset."
-- ------------------------------------------------------------------------------
/*
Business Purpose: Provides the core dataset for GenAI to write a 3-paragraph executive summary email.
SQL Concepts Used: Subqueries, Aggregation.
Expected Result: Rolled up metrics for a 7-day period.
GenAI Usage: "This week, FraudLens processed..."
*/
SELECT 
    SUM(total_transactions) AS weekly_volume,
    SUM(fraud_transactions) AS weekly_fraud_volume,
    SUM(fraud_amount) AS weekly_fraud_exposure,
    MAX(highest_fraud_amount) AS peak_fraud_event
FROM DAILY_FRAUD_SUMMARY
WHERE day BETWEEN 1 AND 7; -- GenAI parameterizes the date range
