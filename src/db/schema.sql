-- ==============================================================================
-- FraudLens AI - Enterprise Analytics Database Schema
-- Author: Senior Data Warehouse Architect, American Express
-- Database Engine: MySQL / InnoDB
-- ==============================================================================

CREATE DATABASE IF NOT EXISTS fraudlens_db;
USE fraudlens_db;

-- ------------------------------------------------------------------------------
-- 1. DIM_TRANSACTION_TYPE
-- ------------------------------------------------------------------------------
-- One row per transaction mechanism. 
-- Justification: Normalization ensures metadata about transaction risk profiles 
-- is managed centrally rather than repeated across 6M rows.
CREATE TABLE IF NOT EXISTS DIM_TRANSACTION_TYPE (
    type VARCHAR(50) PRIMARY KEY,
    risk_level VARCHAR(20) NOT NULL,
    business_category VARCHAR(50) NOT NULL
) ENGINE=InnoDB;

-- Pre-populate Dimension
INSERT IGNORE INTO DIM_TRANSACTION_TYPE (type, risk_level, business_category) VALUES
('TRANSFER', 'High', 'Outgoing Funds Transfer'),
('CASH_OUT', 'High', 'Withdrawal'),
('CASH_IN', 'Low', 'Deposit'),
('PAYMENT', 'Low', 'Merchant Payment'),
('DEBIT', 'Low', 'Direct Debit');

-- ------------------------------------------------------------------------------
-- 2. FACT_TRANSACTIONS
-- ------------------------------------------------------------------------------
-- Core fact table containing every transaction at the most granular level.
-- Primary Key: transaction_id (Enterprise Standardized)
-- Foreign Key: type -> DIM_TRANSACTION_TYPE
CREATE TABLE IF NOT EXISTS FACT_TRANSACTIONS (
    transaction_id VARCHAR(50) PRIMARY KEY,
    step INT NOT NULL,
    hour TINYINT NOT NULL,
    day SMALLINT NOT NULL,
    type VARCHAR(50) NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    transaction_size VARCHAR(20) NOT NULL,
    sender_account VARCHAR(50) NOT NULL,
    receiver_account VARCHAR(50) NOT NULL,
    oldbalanceOrg DECIMAL(15,2) NOT NULL,
    newbalanceOrig DECIMAL(15,2) NOT NULL,
    balance_change DECIMAL(15,2) NOT NULL,
    account_drained BOOLEAN NOT NULL,
    oldbalanceDest DECIMAL(15,2) NOT NULL,
    newbalanceDest DECIMAL(15,2) NOT NULL,
    is_fraud BOOLEAN NOT NULL,
    is_flagged_fraud BOOLEAN NOT NULL,
    risk_score TINYINT NOT NULL,
    priority VARCHAR(20) NOT NULL,
    
    FOREIGN KEY (type) REFERENCES DIM_TRANSACTION_TYPE(type)
) ENGINE=InnoDB;

-- Indexes for Query Optimization
-- Avoid indexing high cardinality columns like Amount. Target filtering patterns.
CREATE INDEX idx_sender ON FACT_TRANSACTIONS(sender_account);
CREATE INDEX idx_receiver ON FACT_TRANSACTIONS(receiver_account);
CREATE INDEX idx_fraud_priority ON FACT_TRANSACTIONS(is_fraud, priority);
CREATE INDEX idx_temporal ON FACT_TRANSACTIONS(day, hour);

-- ------------------------------------------------------------------------------
-- 3. CUSTOMER_SUMMARY
-- ------------------------------------------------------------------------------
-- Materialized aggregation table providing a holistic view of sender risk.
-- Populated via ETL pipeline to guarantee sub-second GenAI/Power BI performance.
CREATE TABLE IF NOT EXISTS CUSTOMER_SUMMARY (
    customer_id VARCHAR(50) PRIMARY KEY,
    total_transactions INT NOT NULL,
    fraud_transactions INT NOT NULL,
    fraud_percentage DECIMAL(5,2) NOT NULL,
    average_amount DECIMAL(15,2) NOT NULL,
    highest_transaction DECIMAL(15,2) NOT NULL,
    average_risk_score INT NOT NULL,
    account_drained_count INT NOT NULL,
    high_risk_customer_flag BOOLEAN NOT NULL
) ENGINE=InnoDB;

-- ------------------------------------------------------------------------------
-- 4. FRAUD_INVESTIGATION
-- ------------------------------------------------------------------------------
-- Operational table containing ONLY verified or suspected fraud cases.
-- Designed to be updated by Analysts.
CREATE TABLE IF NOT EXISTS FRAUD_INVESTIGATION (
    transaction_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50) NOT NULL,
    receiver_id VARCHAR(50) NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    risk_score TINYINT NOT NULL,
    priority VARCHAR(20) NOT NULL,
    transaction_type VARCHAR(50) NOT NULL,
    account_drained BOOLEAN NOT NULL,
    is_flagged_fraud BOOLEAN NOT NULL,
    
    -- Future mutable fields for Analysts
    investigation_status VARCHAR(50) DEFAULT 'Pending Review',
    analyst_notes TEXT,
    recommendation VARCHAR(100) DEFAULT NULL,
    
    FOREIGN KEY (transaction_id) REFERENCES FACT_TRANSACTIONS(transaction_id)
) ENGINE=InnoDB;

CREATE INDEX idx_investigation_status ON FRAUD_INVESTIGATION(investigation_status, priority);

-- ------------------------------------------------------------------------------
-- 5. DAILY_FRAUD_SUMMARY
-- ------------------------------------------------------------------------------
-- Executive aggregation table for fast line-chart rendering.
CREATE TABLE IF NOT EXISTS DAILY_FRAUD_SUMMARY (
    day SMALLINT PRIMARY KEY,
    total_transactions INT NOT NULL,
    fraud_transactions INT NOT NULL,
    fraud_percentage DECIMAL(5,2) NOT NULL,
    fraud_amount DECIMAL(20,2) NOT NULL,
    average_fraud_amount DECIMAL(15,2) NOT NULL,
    highest_fraud_amount DECIMAL(15,2) NOT NULL
) ENGINE=InnoDB;

-- ------------------------------------------------------------------------------
-- 6. HOURLY_FRAUD_SUMMARY
-- ------------------------------------------------------------------------------
-- Velocity aggregation table for thermal mapping of attacks.
CREATE TABLE IF NOT EXISTS HOURLY_FRAUD_SUMMARY (
    hour TINYINT PRIMARY KEY,
    fraud_count INT NOT NULL,
    fraud_amount DECIMAL(20,2) NOT NULL,
    fraud_rate DECIMAL(5,2) NOT NULL
) ENGINE=InnoDB;


-- ==============================================================================
-- ANALYTICAL VIEWS
-- Business Justification: Views decouple the underlying schema from reporting layers,
-- abstracting complex logic so Power BI and GenAI SQL Agents can query cleanly.
-- ==============================================================================

-- 1. vw_high_risk_transactions
-- Exposes active cases requiring immediate attention without table scanning.
CREATE OR REPLACE VIEW vw_high_risk_transactions AS
SELECT transaction_id, sender_account, receiver_account, amount, risk_score, priority, type
FROM FACT_TRANSACTIONS
WHERE risk_score >= 60;

-- 2. vw_high_risk_customers
-- Rapid lookup for GenAI profiles asking "who are our riskiest active senders?"
CREATE OR REPLACE VIEW vw_high_risk_customers AS
SELECT customer_id, total_transactions, fraud_transactions, average_risk_score, account_drained_count
FROM CUSTOMER_SUMMARY
WHERE high_risk_customer_flag = TRUE;

-- 3. vw_daily_fraud & vw_hourly_fraud
-- Exposes the materialized summaries for BI tools seamlessly.
CREATE OR REPLACE VIEW vw_daily_fraud AS
SELECT * FROM DAILY_FRAUD_SUMMARY ORDER BY day ASC;

CREATE OR REPLACE VIEW vw_hourly_fraud AS
SELECT * FROM HOURLY_FRAUD_SUMMARY ORDER BY hour ASC;

-- 4. vw_cashout_fraud & vw_transfer_fraud
-- Typology-specific views for specialized fraud teams.
CREATE OR REPLACE VIEW vw_cashout_fraud AS
SELECT transaction_id, sender_account, amount, account_drained
FROM FACT_TRANSACTIONS
WHERE type = 'CASH_OUT' AND is_fraud = TRUE;

CREATE OR REPLACE VIEW vw_transfer_fraud AS
SELECT transaction_id, sender_account, receiver_account, amount, account_drained
FROM FACT_TRANSACTIONS
WHERE type = 'TRANSFER' AND is_fraud = TRUE;

-- 5. vw_priority_cases
-- The ultimate Analyst operational view. Joins investigation queue with customer profile history.
CREATE OR REPLACE VIEW vw_priority_cases AS
SELECT 
    f.transaction_id,
    f.customer_id,
    f.amount,
    f.priority,
    f.investigation_status,
    c.fraud_percentage AS sender_historic_fraud_rate,
    c.account_drained_count AS sender_prior_drains
FROM FRAUD_INVESTIGATION f
JOIN CUSTOMER_SUMMARY c ON f.customer_id = c.customer_id
WHERE f.priority IN ('Critical', 'High') AND f.investigation_status = 'Pending Review';
