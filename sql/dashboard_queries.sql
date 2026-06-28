-- ==============================================================================
-- FraudLens AI - Dashboard & Transaction Analytics (Modules 2 & 7)
-- Author: Senior Data Analytics Lead, American Express
-- Purpose: Highly optimized queries explicitly designed for Power BI Import and DirectQuery.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- Query 1: Top 20 Highest Value Transactions
-- ------------------------------------------------------------------------------
/*
Business Question: What are the absolute largest transactions flowing through the system?
Why this matters: Liquidity management. Massive transactions, even if not fraud, require treasury oversight.
SQL Concepts Used: ORDER BY, LIMIT.
Expected Output: transaction_id, type, amount, risk_score.
Dashboard Usage: "System Whales" table visual.
Optimization Strategy: Fast sort using indexed fields.
*/
SELECT 
    transaction_id,
    sender_account,
    receiver_account,
    type,
    amount,
    risk_score
FROM FACT_TRANSACTIONS
ORDER BY amount DESC
LIMIT 20;

-- ------------------------------------------------------------------------------
-- Query 2: Transaction Size Distribution
-- ------------------------------------------------------------------------------
/*
Business Question: How are our transactions distributed across the custom risk buckets?
Why this matters: Understands the baseline volume. If 'Extreme' transactions suddenly spike, there's a systemic issue.
SQL Concepts Used: GROUP BY.
Expected Output: transaction_size, volume, total_amount.
Dashboard Usage: Treemap or Donut Chart.
Optimization Strategy: Single pass aggregation.
*/
SELECT 
    transaction_size,
    COUNT(*) AS volume,
    SUM(amount) AS total_amount
FROM FACT_TRANSACTIONS
GROUP BY transaction_size;

-- ------------------------------------------------------------------------------
-- Query 3: Moving Average Transaction Amount (Advanced SQL)
-- ------------------------------------------------------------------------------
/*
Business Question: What is the 3-day moving average of fraud amounts?
Why this matters: Smooths out daily volatility to identify true macro trends in fraud attacks.
Interview Question: "How do you calculate a rolling average in SQL?"
SQL Concepts Used: Window Function (AVG OVER ROWS BETWEEN).
Expected Output: day, daily_fraud, moving_avg_3_day.
Dashboard Usage: Trendline overlay on Daily Fraud bar chart.
Optimization Strategy: Computes directly over the highly aggregated DAILY_FRAUD_SUMMARY table (only 30 rows). Zero performance hit.
*/
SELECT 
    day,
    fraud_amount AS daily_fraud,
    AVG(fraud_amount) OVER (
        ORDER BY day 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS moving_avg_3_day
FROM DAILY_FRAUD_SUMMARY;

-- ------------------------------------------------------------------------------
-- Query 4: Common Fraud Time Windows (Advanced SQL)
-- ------------------------------------------------------------------------------
/*
Business Question: What are the most dangerous 3-hour contiguous blocks of the day?
Why this matters: Helps schedule shift breaks for the investigation team.
SQL Concepts Used: Window Function (SUM OVER ROWS).
Expected Output: hour_block_start, 3_hour_fraud_volume.
Dashboard Usage: Peak operations scheduling view.
Optimization Strategy: Window aggregation on HOURLY_FRAUD_SUMMARY.
*/
SELECT 
    hour AS hour_block_start,
    SUM(fraud_count) OVER (
        ORDER BY hour 
        ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING
    ) AS rolling_3_hour_fraud_count
FROM HOURLY_FRAUD_SUMMARY
ORDER BY rolling_3_hour_fraud_count DESC
LIMIT 5;

-- ------------------------------------------------------------------------------
-- Query 5: Executive Dashboard Summary View
-- ------------------------------------------------------------------------------
/*
Business Purpose: A single flattened result set specifically tailored for Power BI Import Mode to minimize dataset size.
Optimization Strategy: Pre-aggregates dimensions so Power BI doesn't have to join 6 million rows in memory.
*/
SELECT 
    d.day,
    d.total_transactions,
    d.fraud_transactions,
    d.fraud_amount,
    (SELECT SUM(amount) FROM FACT_TRANSACTIONS WHERE is_fraud = TRUE AND type = 'CASH_OUT' AND day = d.day) AS cash_out_fraud_amount,
    (SELECT SUM(amount) FROM FACT_TRANSACTIONS WHERE is_fraud = TRUE AND type = 'TRANSFER' AND day = d.day) AS transfer_fraud_amount
FROM DAILY_FRAUD_SUMMARY d
ORDER BY d.day;

-- ------------------------------------------------------------------------------
-- Query 6: Power BI DirectQuery - Priority Case Feed
-- ------------------------------------------------------------------------------
/*
Business Purpose: Optimized DirectQuery endpoint for the live Fraud Investigation Dashboard.
Optimization Strategy: Selects exactly what the visual needs. Filters early. Uses Indexed View.
*/
SELECT 
    transaction_id,
    customer_id,
    amount,
    priority,
    sender_historic_fraud_rate
FROM vw_priority_cases
WHERE amount > 50000; -- High value live feed filter
