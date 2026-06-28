-- ==============================================================================
-- FraudLens AI - Risk Analytics (Module 4)
-- Author: Senior Data Analytics Lead, American Express
-- Purpose: Analyzing the performance of the Risk Score heuristic and risk vectors.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- Query 1: Risk Score Distribution
-- ------------------------------------------------------------------------------
/*
Business Question: What is the distribution of our Risk Scores across all transactions?
Why this matters: If 90% of transactions score 80+, our rules are too strict (false positives). If everything scores 0, we are missing fraud.
Business Insight: Calibrates the risk engine thresholds.
SQL Concepts Used: GROUP BY, ORDER BY.
Expected Output: risk_score, transaction_count.
Dashboard Usage: Histogram visualizing the bell curve (or power law) of risk.
Optimization Strategy: Grouping directly on FACT_TRANSACTIONS using an index on risk_score if created, otherwise a full scan.
*/
SELECT 
    risk_score,
    COUNT(*) AS transaction_count
FROM FACT_TRANSACTIONS
GROUP BY risk_score
ORDER BY risk_score DESC;

-- ------------------------------------------------------------------------------
-- Query 2: Priority Queue Distribution
-- ------------------------------------------------------------------------------
/*
Business Question: What volume of alerts are hitting our investigation queues?
Why this matters: SLA Management. If there are 10,000 'Critical' cases, we lack the staffing to review them within the 1-hour SLA.
Business Insight: Directly drives Analyst hiring models.
SQL Concepts Used: GROUP BY, Aggregation.
Expected Output: priority, transaction_count, total_amount_at_risk.
Dashboard Usage: KPI cards showing backlog size by tier.
Optimization Strategy: Single pass over the indexed priority column.
*/
SELECT 
    priority,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_amount_at_risk
FROM FACT_TRANSACTIONS
GROUP BY priority
ORDER BY 
    CASE priority 
        WHEN 'Critical' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Medium' THEN 3
        ELSE 4 
    END;

-- ------------------------------------------------------------------------------
-- Query 3: Average Risk by Transaction Type
-- ------------------------------------------------------------------------------
/*
Business Question: Do certain transaction mechanisms naturally carry higher calculated risk?
Why this matters: Validates that the engine is scoring Transfers and Cash Outs higher than Payments.
SQL Concepts Used: GROUP BY, AVG.
Expected Output: type, avg_risk_score.
Dashboard Usage: Bar chart overlay in the Risk Module.
Optimization Strategy: Fast aggregation over 5 transaction types.
*/
SELECT 
    type,
    ROUND(AVG(risk_score), 2) AS average_risk_score
FROM FACT_TRANSACTIONS
GROUP BY type
ORDER BY average_risk_score DESC;

-- ------------------------------------------------------------------------------
-- Query 4: Highest Risk Transactions Not Yet Fraud-Flagged
-- ------------------------------------------------------------------------------
/*
Business Question: Which transactions scored critically high (80+) but were missed by the legacy 'isFlaggedFraud' system?
Why this matters: Proves the ROI and superiority of the new FraudLens AI risk scoring engine over the old system.
Interview Question: "How do you measure the lift of a new rule engine?"
SQL Concepts Used: WHERE with compound logic.
Expected Output: transaction_id, risk_score, amount, type.
Dashboard Usage: "Value Add" report for Executive Sponsors.
Optimization Strategy: Indexed filtering on `priority` and `is_flagged_fraud`.
*/
SELECT 
    transaction_id,
    risk_score,
    amount,
    type,
    priority
FROM FACT_TRANSACTIONS
WHERE risk_score >= 80 AND is_flagged_fraud = FALSE
ORDER BY risk_score DESC, amount DESC
LIMIT 50;

-- ------------------------------------------------------------------------------
-- Query 5: Account Drained Typology Analysis
-- ------------------------------------------------------------------------------
/*
Business Question: What percentage of our true fraud involves draining an account completely?
Why this matters: Confirms the Account Drained flag is our strongest predictor of Account Takeover (ATO).
Business Insight: If this percentage is high, any transaction draining an account must automatically route to 'Critical'.
SQL Concepts Used: Conditional Aggregation.
Expected Output: total_fraud_cases, cases_with_account_drained, drained_percentage.
Dashboard Usage: Typology breakdown chart.
Optimization Strategy: Scans only the fraudulent subset.
*/
SELECT 
    COUNT(*) AS total_fraud_cases,
    SUM(account_drained) AS cases_with_account_drained,
    ROUND((SUM(account_drained) / COUNT(*)) * 100, 2) AS drained_percentage
FROM FACT_TRANSACTIONS
WHERE is_fraud = TRUE;

-- ------------------------------------------------------------------------------
-- Query 6: Legacy Fraud Flag Analysis (False Negatives)
-- ------------------------------------------------------------------------------
/*
Business Question: How accurate was the legacy 'isFlaggedFraud' rule?
Why this matters: The old system only flagged massive transfers. We need to document its failure rate.
SQL Concepts Used: Aggregation, WHERE.
Expected Output: total_actual_fraud, missed_by_legacy, legacy_failure_rate.
Dashboard Usage: System comparison matrix.
Optimization Strategy: Direct math over the filtered fraud base.
*/
SELECT 
    COUNT(*) AS total_actual_fraud,
    SUM(CASE WHEN is_flagged_fraud = FALSE THEN 1 ELSE 0 END) AS missed_by_legacy,
    ROUND((SUM(CASE WHEN is_flagged_fraud = FALSE THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) AS legacy_failure_rate
FROM FACT_TRANSACTIONS
WHERE is_fraud = TRUE;

-- ------------------------------------------------------------------------------
-- Query 7: Risk Ranking across the Enterprise
-- ------------------------------------------------------------------------------
/*
Business Question: What is the risk distribution percentiles (e.g., what score puts a transaction in the top 5% of risk)?
Why this matters: Dynamic thresholding. If transaction volume doubles, we can adjust the 'High' queue to only capture the top 5% statistically.
Interview Question: "How do you calculate quartiles or deciles in SQL?"
SQL Concepts Used: NTILE(100) for percentiles.
Expected Output: risk_score, percentile_rank.
Dashboard Usage: Analytical deep dive table.
Optimization Strategy: Window function partitioning. High execution cost, runs offline or during batch.
*/
WITH RiskPercentiles AS (
    SELECT 
        transaction_id,
        risk_score,
        NTILE(100) OVER (ORDER BY risk_score ASC) AS risk_percentile
    FROM FACT_TRANSACTIONS
)
SELECT 
    risk_percentile,
    MIN(risk_score) AS min_score_in_percentile,
    MAX(risk_score) AS max_score_in_percentile
FROM RiskPercentiles
GROUP BY risk_percentile
ORDER BY risk_percentile DESC;
