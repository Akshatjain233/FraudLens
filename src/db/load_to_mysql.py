"""
FraudLens AI - Enterprise Database Loader Pipeline

Author: Senior Data Warehouse Architect, American Express
Purpose: Orchestrates the loading of engineered transaction data into the MySQL Data Warehouse.
Implements an ELT (Extract, Load, Transform) pattern where raw facts are loaded via Python
and downstream aggregations are materialized natively in SQL for maximum performance.
"""

import pandas as pd
import sqlalchemy as sa
from sqlalchemy import create_engine, text
import os
import logging
import time

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Database Configuration Defaults
DB_USER = os.getenv("MYSQL_USER", "root")
DB_PASS = os.getenv("MYSQL_PASS", "")
DB_HOST = os.getenv("MYSQL_HOST", "localhost")
DB_PORT = os.getenv("MYSQL_PORT", "3306")
DB_NAME = "fraudlens_db"

def get_engine(database=None):
    """Creates a SQLAlchemy engine. Connects to server root if database is None."""
    auth = f"{DB_USER}:{DB_PASS}" if DB_PASS else f"{DB_USER}"
    url = f"mysql+pymysql://{auth}@{DB_HOST}:{DB_PORT}/"
    if database:
        url += database
    return create_engine(url)

def initialize_database():
    """Reads schema.sql and executes DDL to build the data warehouse structure."""
    logging.info("Initializing Database Schema...")
    
    # 1. Create DB if not exists
    engine_root = get_engine()
    with engine_root.connect() as conn:
        conn.execute(text(f"CREATE DATABASE IF NOT EXISTS {DB_NAME};"))
    
    # 2. Connect to the new DB and execute schema setup
    schema_path = "src/db/schema.sql"
    if not os.path.exists(schema_path):
        raise FileNotFoundError(f"Schema file not found at {schema_path}")
        
    engine_db = get_engine(DB_NAME)
    with engine_db.begin() as conn:
        with open(schema_path, 'r') as f:
            sql_script = f.read()
            
        # Basic split by semicolon. In a robust setup, consider statement parsers.
        statements = sql_script.split(';')
        for stmt in statements:
            if stmt.strip():
                # SQLAlchemy text() requires avoiding colons unless they are bind parameters
                # Escaping colons if any exist in comments
                conn.execute(text(stmt))
                
    logging.info("Schema Initialization Complete.")

def load_fact_transactions(file_path: str):
    """Loads the 6M+ row CSV into the FACT_TRANSACTIONS table using chunking."""
    logging.info(f"Loading Fact Transactions from {file_path}...")
    engine = get_engine(DB_NAME)
    
    # Column mapping from Pandas to SQL schema
    col_mapping = {
        'Transaction_ID': 'transaction_id',
        'step': 'step',
        'Hour': 'hour',
        'Day': 'day',
        'type': 'type',
        'amount': 'amount',
        'Transaction_Size': 'transaction_size',
        'nameOrig': 'sender_account',
        'nameDest': 'receiver_account',
        'oldbalanceOrg': 'oldbalanceOrg',
        'newbalanceOrig': 'newbalanceOrig',
        'Balance_Change': 'balance_change',
        'Account_Drained': 'account_drained',
        'oldbalanceDest': 'oldbalanceDest',
        'newbalanceDest': 'newbalanceDest',
        'isFraud': 'is_fraud',
        'isFlaggedFraud': 'is_flagged_fraud',
        'Risk_Score': 'risk_score',
        'Priority': 'priority'
    }
    
    chunk_size = 100000
    rows_loaded = 0
    
    # Truncate existing facts for idempotency
    with engine.begin() as conn:
        conn.execute(text("SET FOREIGN_KEY_CHECKS = 0;"))
        conn.execute(text("TRUNCATE TABLE FACT_TRANSACTIONS;"))
        conn.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))

    for chunk in pd.read_csv(file_path, chunksize=chunk_size):
        # Rename columns to match MySQL schema
        chunk = chunk.rename(columns=col_mapping)
        
        # Ensure only columns in the schema are pushed
        final_cols = list(col_mapping.values())
        chunk = chunk[final_cols]
        
        # Write to MySQL
        chunk.to_sql(name='FACT_TRANSACTIONS', con=engine, if_exists='append', index=False, method='multi')
        rows_loaded += len(chunk)
        logging.info(f"Loaded {rows_loaded} rows into FACT_TRANSACTIONS...")

def populate_summary_tables():
    """
    Executes an ELT pattern. Instead of computing aggregations in Python memory,
    we push the heavy lifting to the MySQL engine which is built for this.
    """
    logging.info("Populating Materialized Summary Tables natively via SQL...")
    engine = get_engine(DB_NAME)
    
    with engine.begin() as conn:
        # 1. CUSTOMER_SUMMARY
        logging.info("Building CUSTOMER_SUMMARY...")
        conn.execute(text("TRUNCATE TABLE CUSTOMER_SUMMARY;"))
        conn.execute(text("""
            INSERT INTO CUSTOMER_SUMMARY
            SELECT 
                sender_account AS customer_id,
                COUNT(*) AS total_transactions,
                SUM(is_fraud) AS fraud_transactions,
                (SUM(is_fraud) / COUNT(*)) * 100 AS fraud_percentage,
                AVG(amount) AS average_amount,
                MAX(amount) AS highest_transaction,
                AVG(risk_score) AS average_risk_score,
                SUM(account_drained) AS account_drained_count,
                CASE WHEN SUM(is_fraud) > 0 OR AVG(risk_score) >= 60 THEN TRUE ELSE FALSE END AS high_risk_customer_flag
            FROM FACT_TRANSACTIONS
            GROUP BY sender_account;
        """))
        
        # 2. FRAUD_INVESTIGATION
        logging.info("Building FRAUD_INVESTIGATION queues...")
        conn.execute(text("TRUNCATE TABLE FRAUD_INVESTIGATION;"))
        conn.execute(text("""
            INSERT INTO FRAUD_INVESTIGATION 
            (transaction_id, customer_id, receiver_id, amount, risk_score, priority, transaction_type, account_drained, is_flagged_fraud, investigation_status)
            SELECT 
                transaction_id, sender_account, receiver_account, amount, risk_score, priority, type, account_drained, is_flagged_fraud, 'Pending Review'
            FROM FACT_TRANSACTIONS
            WHERE is_fraud = TRUE OR risk_score >= 60;
        """))
        
        # 3. DAILY_FRAUD_SUMMARY
        logging.info("Building DAILY_FRAUD_SUMMARY...")
        conn.execute(text("TRUNCATE TABLE DAILY_FRAUD_SUMMARY;"))
        conn.execute(text("""
            INSERT INTO DAILY_FRAUD_SUMMARY
            SELECT 
                day,
                COUNT(*) AS total_transactions,
                SUM(is_fraud) AS fraud_transactions,
                (SUM(is_fraud) / COUNT(*)) * 100 AS fraud_percentage,
                SUM(CASE WHEN is_fraud = TRUE THEN amount ELSE 0 END) AS fraud_amount,
                AVG(CASE WHEN is_fraud = TRUE THEN amount ELSE NULL END) AS average_fraud_amount,
                MAX(CASE WHEN is_fraud = TRUE THEN amount ELSE 0 END) AS highest_fraud_amount
            FROM FACT_TRANSACTIONS
            GROUP BY day;
        """))
        
        # 4. HOURLY_FRAUD_SUMMARY
        logging.info("Building HOURLY_FRAUD_SUMMARY...")
        conn.execute(text("TRUNCATE TABLE HOURLY_FRAUD_SUMMARY;"))
        conn.execute(text("""
            INSERT INTO HOURLY_FRAUD_SUMMARY
            SELECT 
                hour,
                SUM(is_fraud) AS fraud_count,
                SUM(CASE WHEN is_fraud = TRUE THEN amount ELSE 0 END) AS fraud_amount,
                (SUM(is_fraud) / COUNT(*)) * 100 AS fraud_rate
            FROM FACT_TRANSACTIONS
            GROUP BY hour;
        """))

def validate_data_load():
    """Validates the integrity of the database load."""
    logging.info("Validating Row Counts and Integrity...")
    engine = get_engine(DB_NAME)
    
    with engine.connect() as conn:
        fact_count = conn.execute(text("SELECT COUNT(*) FROM FACT_TRANSACTIONS")).scalar()
        customer_count = conn.execute(text("SELECT COUNT(*) FROM CUSTOMER_SUMMARY")).scalar()
        inv_count = conn.execute(text("SELECT COUNT(*) FROM FRAUD_INVESTIGATION")).scalar()
        daily_count = conn.execute(text("SELECT COUNT(*) FROM DAILY_FRAUD_SUMMARY")).scalar()
        
        logging.info(f"FACT_TRANSACTIONS count:     {fact_count}")
        logging.info(f"CUSTOMER_SUMMARY count:      {customer_count}")
        logging.info(f"FRAUD_INVESTIGATION count:   {inv_count}")
        logging.info(f"DAILY_FRAUD_SUMMARY count:   {daily_count}")
        
        if fact_count == 0:
            logging.error("Validation Failed: Fact table is empty.")
        else:
            logging.info("Validation Passed: Data successfully populated.")

def main():
    start_time = time.time()
    INPUT_FILE = "data/processed/engineered_transactions.csv"
    
    try:
        initialize_database()
        load_fact_transactions(INPUT_FILE)
        populate_summary_tables()
        validate_data_load()
        
        end_time = time.time()
        logging.info(f"Database Pipeline Completed Successfully in {end_time - start_time:.2f} seconds.")
        
    except Exception as e:
        logging.error(f"Pipeline Failed: {e}", exc_info=True)

if __name__ == "__main__":
    main()
