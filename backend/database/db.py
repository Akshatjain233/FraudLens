"""
FraudLens AI - Database Access Layer
Purpose: Provides safe, read-only connections to MySQL for the FastAPI application.
Calculations are pushed down to MySQL. Gemini never runs SQL.
"""

import os
import sqlalchemy as sa
from sqlalchemy.orm import sessionmaker

MYSQL_USER = os.getenv("MYSQL_USER", "root")
MYSQL_PASS = os.getenv("MYSQL_PASS", "")
MYSQL_HOST = os.getenv("MYSQL_HOST", "localhost")
MYSQL_PORT = os.getenv("MYSQL_PORT", "3306")
MYSQL_DB = os.getenv("MYSQL_DB", "fraudlens_db")

auth = f"{MYSQL_USER}:{MYSQL_PASS}" if MYSQL_PASS else f"{MYSQL_USER}"
DATABASE_URL = f"mysql+pymysql://{auth}@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DB}"

engine = sa.create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    """Dependency for FastAPI to get a database session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def get_transaction_details(db, txn_id: str):
    """Executes deterministic SQL to retrieve facts for the GenAI Prompt."""
    query = sa.text("""
        SELECT 
            f.transaction_id, f.amount, f.risk_score, f.priority, f.type, f.account_drained,
            c.fraud_percentage
        FROM FACT_TRANSACTIONS f
        LEFT JOIN CUSTOMER_SUMMARY c ON f.sender_account = c.customer_id
        WHERE f.transaction_id = :txn_id
    """)
    result = db.execute(query, {"txn_id": txn_id}).fetchone()
    if not result:
        return None
    return dict(result._mapping)

def get_executive_kpis(db, day: int):
    """Retrieves macro health KPIs."""
    query = sa.text("""
        SELECT 
            day, total_transactions, fraud_transactions, fraud_percentage, fraud_amount, highest_fraud_amount
        FROM DAILY_FRAUD_SUMMARY
        WHERE day = :day
    """)
    result = db.execute(query, {"day": day}).fetchone()
    if not result:
        return None
    return dict(result._mapping)

def get_customer_details(db, customer_id: str):
    """Retrieves customer lifetime behavior metrics."""
    query = sa.text("""
        SELECT 
            customer_id, total_transactions, fraud_transactions, fraud_percentage, 
            average_amount, account_drained_count, high_risk_customer_flag
        FROM CUSTOMER_SUMMARY
        WHERE customer_id = :customer_id
    """)
    result = db.execute(query, {"customer_id": customer_id}).fetchone()
    if not result:
        return None
    return dict(result._mapping)
