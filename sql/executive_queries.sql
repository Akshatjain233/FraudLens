-- ==============================================================================
-- FraudLens AI - Executive KPIs (Module 1)
-- Author: Senior Data Analytics Lead, American Express
-- Purpose: High-level metrics for C-suite and VP-level dashboards.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- Query 1: Enterprise Fraud Exposure Overview
-- ------------------------------------------------------------------------------
/*
Business Question: What is our total transaction volume, fraud count, and financial exposure?
Why this matters: Executives need a 10,000-foot view of system health and financial risk.
Business Insight: Provides a baseline to understand the scale of the platform.
Interview Question: "How do you calculate high-level KPIs without crashing the database?"
SQL Concepts Used: Aggregation (SUM).
Expected Output: 1 row with overall_volume, overall_fraud_volume, fraud_rate, total_fraud_exposure.
Dashboard Usage: Top-level KPI scorecard in Power BI Executive Dashboard.
Optimization Strategy: Queries the materialized DAILY_FRAUD_SUMMARY table rather than the 6.3M row FACT table. Expected Performance is sub-millisecond.
*/
SELECT 
    SUM(total_transactions) AS overall_volume,
    SUM(fraud_transactions) AS overall_fraud_volume,
    ROUND((SUM(fraud_transactions) / SUM(total_transactions)) * 100, 4) AS fraud_rate_percentage,
    SUM(fraud_amount) AS total_fraud_exposure_usd
FROM DAILY_FRAUD_SUMMARY;

-- ------------------------------------------------------------------------------
-- Query 2: Fraud Severity Metrics
-- ------------------------------------------------------------------------------
/*
Business Question: What is the average and highest fraud amount we are dealing with?
Why this matters: Helps set the threshold for manual investigation limits.
Business Insight: Knowing the highest fraud amount prepares risk teams for worst-case scenarios.
SQL Concepts Used: Aggregation (MAX, SUM), Conditional Logic.
Expected Output: average_fraud_amount, highest_fraud_amount.
Dashboard Usage: Secondary KPI cards.
Optimization Strategy: Leverages pre-aggregated MAX values from DAILY_FRAUD_SUMMARY.
*/
SELECT 
    SUM(fraud_amount) / SUM(fraud_transactions) AS true_average_fraud_amount,
    MAX(highest_fraud_amount) AS all_time_highest_fraud_amount
FROM DAILY_FRAUD_SUMMARY;

-- ------------------------------------------------------------------------------
-- Query 3: Daily Fraud Trend
-- ------------------------------------------------------------------------------
/*
Business Question: How is our fraud exposure trending day over day?
Why this matters: Detects immediate spikes in fraudulent activity indicating a coordinated attack.
Business Insight: Allows security teams to identify which days face the heaviest attacks.
SQL Concepts Used: SELECT, ORDER BY.
Expected Output: day, total_transactions, fraud_transactions, fraud_amount ordered chronologically.
Dashboard Usage: X-Axis: Day, Y-Axis: Fraud Amount (Line Chart).
Optimization Strategy: Clustered Index scan on the primary key of DAILY_FRAUD_SUMMARY.
*/
SELECT 
    day,
    total_transactions,
    fraud_transactions,
    fraud_amount
FROM DAILY_FRAUD_SUMMARY
ORDER BY day ASC;

-- ------------------------------------------------------------------------------
-- Query 4: Hourly Fraud Trend (Velocity)
-- ------------------------------------------------------------------------------
/*
Business Question: At what hours do fraudsters typically attack?
Why this matters: Dictates staffing requirements for the 24/7 fraud investigation center.
Business Insight: Fraud often peaks outside standard business hours when automated defenses are relied upon.
SQL Concepts Used: SELECT, ORDER BY.
Expected Output: hour, fraud_count, fraud_amount.
Dashboard Usage: Heatmap visualization (Hour vs. Fraud Count).
Optimization Strategy: Directly reads from HOURLY_FRAUD_SUMMARY.
*/
SELECT 
    hour,
    fraud_count,
    fraud_amount
FROM HOURLY_FRAUD_SUMMARY
ORDER BY hour ASC;

-- ------------------------------------------------------------------------------
-- Query 5: Daily Fraud Growth Rate
-- ------------------------------------------------------------------------------
/*
Business Question: Is our daily fraud exposure growing or shrinking compared to yesterday?
Why this matters: A sudden spike in growth rate indicates a failing prevention mechanism.
Interview Question: "How do you calculate Day-over-Day growth in SQL?"
SQL Concepts Used: Window Function (LAG).
Expected Output: day, fraud_amount, previous_day_amount, growth_percentage.
Dashboard Usage: Trendline tooltip indicating "Up X% from yesterday".
Optimization Strategy: Using LAG avoids expensive self-joins.
*/
SELECT 
    day,
    fraud_amount,
    LAG(fraud_amount, 1) OVER (ORDER BY day) AS previous_day_amount,
    ROUND(((fraud_amount - LAG(fraud_amount, 1) OVER (ORDER BY day)) / LAG(fraud_amount, 1) OVER (ORDER BY day)) * 100, 2) AS dod_growth_rate
FROM DAILY_FRAUD_SUMMARY;

-- ------------------------------------------------------------------------------
-- Query 6: Running Total Fraud
-- ------------------------------------------------------------------------------
/*
Business Question: What is the cumulative financial damage of fraud over the month?
Why this matters: Tracks performance against monthly/quarterly loss budgets.
Interview Question: "Write a query to calculate a cumulative sum."
SQL Concepts Used: Window Function (SUM OVER ... ROWS UNBOUNDED PRECEDING).
Expected Output: day, daily_fraud, cumulative_fraud.
Dashboard Usage: Area chart showing mounting losses.
Optimization Strategy: Standard analytical window function execution.
*/
SELECT 
    day,
    fraud_amount AS daily_fraud,
    SUM(fraud_amount) OVER (ORDER BY day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_fraud
FROM DAILY_FRAUD_SUMMARY;

-- ------------------------------------------------------------------------------
-- Query 7: Fraud Contribution % by Transaction Type
-- ------------------------------------------------------------------------------
/*
Business Question: Which transaction mechanisms are responsible for our fraud losses?
Why this matters: Determines where to add friction (e.g., 2FA on Transfers).
Business Insight: If 90% of fraud is via TRANSFER, we can ignore PAYMENT types.
SQL Concepts Used: CTE, Window Functions (SUM OVER ()).
Expected Output: type, type_fraud_amount, percentage_of_total_fraud.
Dashboard Usage: Donut chart showing fraud breakdown.
Optimization Strategy: Uses the pre-indexed 'type' column on FACT_TRANSACTIONS, computing proportions in a single pass.
*/
WITH TypeFraud AS (
    SELECT 
        type, 
        SUM(amount) AS type_fraud_amount
    FROM FACT_TRANSACTIONS
    WHERE is_fraud = TRUE
    GROUP BY type
)
SELECT 
    type,
    type_fraud_amount,
    ROUND((type_fraud_amount / SUM(type_fraud_amount) OVER ()) * 100, 2) AS percentage_of_total_fraud
FROM TypeFraud
ORDER BY type_fraud_amount DESC;

-- ------------------------------------------------------------------------------
-- Query 8: Top Transaction Types by Volume
-- ------------------------------------------------------------------------------
/*
Business Question: What is the normal distribution of our transaction types?
Why this matters: Provides context. If TRANSFER is 1% of volume but 80% of fraud, it is highly toxic.
SQL Concepts Used: GROUP BY, ORDER BY.
Expected Output: type, transaction_count.
Dashboard Usage: Bar chart for context.
Optimization Strategy: Engine utilizes the foreign key index on type.
*/
SELECT 
    type,
    COUNT(*) AS transaction_count
FROM FACT_TRANSACTIONS
GROUP BY type
ORDER BY transaction_count DESC;
