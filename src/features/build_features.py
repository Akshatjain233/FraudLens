import pandas as pd
import numpy as np
import os
import logging
from typing import Tuple

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def load_data(input_path: str) -> pd.DataFrame:
    """Loads the raw transaction dataset."""
    logging.info(f"Loading data from {input_path}")
    if not os.path.exists(input_path):
        logging.warning(f"Input file not found at {input_path}. Creating a dummy dataframe for demonstration purposes.")
        # Create a dummy dataframe matching PaySim structure to allow the pipeline to run even without data
        return pd.DataFrame({
            'step': [1, 14, 24, 25],
            'type': ['PAYMENT', 'TRANSFER', 'CASH_OUT', 'TRANSFER'],
            'amount': [9839.64, 181.00, 1500000.00, 450000.00],
            'nameOrig': ['C123', 'C456', 'C789', 'C101'],
            'oldbalanceOrg': [170136.0, 181.0, 1500000.0, 450000.0],
            'newbalanceOrig': [160296.36, 0.0, 0.0, 0.0],
            'nameDest': ['M123', 'C987', 'C654', 'C321'],
            'oldbalanceDest': [0.0, 0.0, 0.0, 10000.0],
            'newbalanceDest': [0.0, 0.0, 1500000.0, 460000.0],
            'isFraud': [0, 1, 1, 0],
            'isFlaggedFraud': [0, 0, 1, 0]
        })
    return pd.read_csv(input_path)

def add_time_features(df: pd.DataFrame) -> pd.DataFrame:
    """Derives hour and day features from the simulation step."""
    logging.info("Adding time features (Hour, Day)...")
    # step is 1 hour of time
    df['Hour'] = (df['step'] - 1) % 24
    df['Day'] = (df['step'] - 1) // 24 + 1
    return df

def add_transaction_segments(df: pd.DataFrame) -> pd.DataFrame:
    """
    Segments transactions into sizes based on EDA findings:
    - Median fraud: ~441K
    - 75th Percentile fraud: ~1.5M
    """
    logging.info("Adding transaction size segments...")
    bins = [0, 100000, 441000, 1500000, float('inf')]
    labels = ['Routine', 'Significant', 'High-Value', 'Extreme']
    df['Transaction_Size'] = pd.cut(df['amount'], bins=bins, labels=labels, right=False)
    # Handle negative or zero amounts safely
    df['Transaction_Size'] = df['Transaction_Size'].fillna('Routine').astype(str)
    return df

def add_risk_features(df: pd.DataFrame) -> pd.DataFrame:
    """Engineers specific risk flags based on transaction type and balance changes."""
    logging.info("Adding risk features...")
    
    # 1. Transaction Risk based on Type
    risk_mapping = {'TRANSFER': 'High', 'CASH_OUT': 'Medium'}
    df['Transaction_Risk'] = df['type'].map(risk_mapping).fillna('Low')
    
    # 2. Balance Inconsistency
    # Expected new balance for originator: oldbalance - amount (for outgoing)
    outgoing_mask = df['type'].isin(['CASH_OUT', 'TRANSFER'])
    expected_new_balance = np.where(outgoing_mask, df['oldbalanceOrg'] - df['amount'], df['oldbalanceOrg'])
    
    # Calculate error, round to handle floating point issues
    df['Orig_Balance_Error'] = np.round(np.abs(expected_new_balance - df['newbalanceOrig']), 2)
    df['Balance_Inconsistency_Flag'] = (df['Orig_Balance_Error'] > 0.01).astype(int)
    
    # 3. Account Drained
    df['Account_Drained'] = ((df['oldbalanceOrg'] > 0) & 
                             (df['newbalanceOrig'] == 0) & 
                             outgoing_mask).astype(int)
    return df

def calculate_risk_score(df: pd.DataFrame) -> pd.DataFrame:
    """Calculates a rule-based risk score from 0 to 100 based on business logic."""
    logging.info("Calculating rule-based Risk Score...")
    score = np.zeros(len(df))
    
    # Account Drained (+35)
    score += np.where(df['Account_Drained'] == 1, 35, 0)
    
    # Transaction Type Risk
    score += np.where(df['type'] == 'TRANSFER', 20, 0)
    score += np.where(df['type'] == 'CASH_OUT', 10, 0)
    
    # Transaction Size Risk
    score += np.where(df['Transaction_Size'] == 'Extreme', 25, 0)
    score += np.where(df['Transaction_Size'] == 'High-Value', 15, 0)
    
    # Balance Inconsistency
    score += np.where(df['Balance_Inconsistency_Flag'] == 1, 15, 0)
    
    # Previously Flagged Fraud
    score += np.where(df['isFlaggedFraud'] == 1, 20, 0)
    
    # Cap score at 100
    df['Risk_Score'] = np.clip(score, 0, 100).astype(int)
    return df

def assign_priority(df: pd.DataFrame) -> pd.DataFrame:
    """Assigns priority queues based on Risk Score."""
    logging.info("Assigning investigation priority...")
    conditions = [
        df['Risk_Score'] >= 80,
        df['Risk_Score'] >= 60,
        df['Risk_Score'] >= 40
    ]
    choices = ['Critical', 'High', 'Medium']
    df['Priority'] = np.select(conditions, choices, default='Low')
    return df

def select_and_order_columns(df: pd.DataFrame) -> pd.DataFrame:
    """Orders columns logically, separating original from engineered features."""
    original_cols = [
        'step', 'type', 'amount', 'nameOrig', 'oldbalanceOrg', 'newbalanceOrig',
        'nameDest', 'oldbalanceDest', 'newbalanceDest', 'isFraud', 'isFlaggedFraud'
    ]
    
    # Generate Transaction_ID if not present
    if 'Transaction_ID' not in df.columns:
        df.insert(0, 'Transaction_ID', ['TXN_' + str(i) for i in df.index])
    else:
        original_cols.insert(0, 'Transaction_ID')
        
    engineered_cols = [
        'Hour', 'Day', 'Transaction_Size', 'Transaction_Risk', 
        'Orig_Balance_Error', 'Balance_Inconsistency_Flag', 
        'Account_Drained', 'Risk_Score', 'Priority'
    ]
    
    final_cols = [col for col in original_cols + engineered_cols if col in df.columns]
    
    # Ensure generated Transaction_ID is included if we just created it
    if 'Transaction_ID' not in final_cols and 'Transaction_ID' in df.columns:
        final_cols.insert(0, 'Transaction_ID')
        
    return df[final_cols]

def run_pipeline(input_path: str, output_path: str):
    """Executes the full feature engineering pipeline."""
    try:
        df = load_data(input_path)
        df = add_time_features(df)
        df = add_transaction_segments(df)
        df = add_risk_features(df)
        df = calculate_risk_score(df)
        df = assign_priority(df)
        df = select_and_order_columns(df)
        
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        df.to_csv(output_path, index=False)
        logging.info(f"Pipeline complete. Saved engineered dataset to {output_path}")
        
    except Exception as e:
        logging.error(f"Pipeline failed: {e}")

if __name__ == "__main__":
    # Define generic paths
    INPUT_FILE = "data/raw/transactions.csv"
    OUTPUT_FILE = "data/processed/engineered_transactions.csv"
    
    run_pipeline(INPUT_FILE, OUTPUT_FILE)
