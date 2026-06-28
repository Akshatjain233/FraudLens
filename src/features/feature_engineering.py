"""
FraudLens AI - Enterprise Feature Engineering Pipeline

Author: Senior Data Engineer & Analytics Engineer, American Express
Purpose: Transforms the raw PaySim transactional data into an enterprise-ready analytics dataset.
This pipeline engineers high-signal business features designed for explainability in Fraud Investigations.
"""

import pandas as pd
import numpy as np
import os
import logging
import time

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

def load_data(input_path: str) -> pd.DataFrame:
    """
    Purpose:
        Loads raw transactional data into memory with efficient types.
    Parameters:
        input_path (str): The file path to the raw CSV.
    Returns:
        pd.DataFrame: The loaded dataset.
    Business significance:
        Foundation of the analytics pipeline. Must handle large volumes efficiently.
    """
    logging.info(f"Loading Dataset from {input_path}...")
    if not os.path.exists(input_path):
        raise FileNotFoundError(f"Input data not found at: {input_path}")
    
    # We load with default types first, optimization happens during processing
    df = pd.read_csv(input_path)
    return df

def generate_transaction_id(df: pd.DataFrame) -> pd.DataFrame:
    """
    Purpose:
        Generates enterprise-standard transaction IDs (e.g., TXN00000001).
    Parameters:
        df (pd.DataFrame): The current dataset.
    Returns:
        pd.DataFrame: The dataset with 'Transaction_ID'.
    Business significance:
        A unique, standard primary key is required for joining datasets in the data warehouse
        and tracking investigations in case management systems.
    """
    logging.info("Generating Transaction IDs...")
    
    # List comprehension for fast, memory-efficient string formatting
    txn_ids = ['TXN%08d' % i for i in range(1, len(df) + 1)]
    df.insert(0, 'Transaction_ID', txn_ids)
    
    # Validation
    _validate_feature(df, 'Transaction_ID', expected_type='object', check_nulls=True)
    return df

def create_time_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Purpose:
        Extracts specific 'Hour' and 'Day' integers from the continuous simulation 'step'.
    Parameters:
        df (pd.DataFrame): Dataset with 'step' column.
    Returns:
        pd.DataFrame: Dataset with 'Hour' and 'Day'.
    Business significance:
        Identifies temporal anomalies. Fraud rings often operate at specific times of day
        or have synchronized velocity bursts on certain days.
    """
    logging.info("Creating Time Features...")
    
    # Assuming step is 1 hour of time, starting at step 1
    # Modulo 24 gives Hour 0-23
    df['Hour'] = ((df['step'] - 1) % 24).astype(np.int8)
    
    # Integer division by 24 gives Day 1-n
    df['Day'] = ((df['step'] - 1) // 24 + 1).astype(np.int16)
    
    # Validation
    _validate_feature(df, 'Hour', min_val=0, max_val=23, check_nulls=True)
    _validate_feature(df, 'Day', min_val=1, check_nulls=True)
    return df

def create_transaction_size(df: pd.DataFrame) -> pd.DataFrame:
    """
    Purpose:
        Categorizes transactions into business-meaningful sizes based on empirical fraud thresholds.
    Parameters:
        df (pd.DataFrame): Dataset with 'amount'.
    Returns:
        pd.DataFrame: Dataset with 'Transaction_Size'.
    Business significance:
        Drives routing logic. From EDA, median fraud is ~441K and 75th pct is ~1.5M.
        This provides immediate risk context to analysts.
    """
    logging.info("Creating Transaction Size Categories...")
    
    bins = [0, 100000, 441000, 1500000, np.inf]
    labels = ['Routine', 'Significant', 'High-Value', 'Extreme']
    
    df['Transaction_Size'] = pd.cut(df['amount'], bins=bins, labels=labels, right=False)
    
    # Fill any negative or exact 0 edge cases (though EDA says none exist)
    if df['Transaction_Size'].isnull().any():
        logging.warning("Suspicious amounts detected (negative). Defaulting to Routine.")
        df['Transaction_Size'] = df['Transaction_Size'].fillna('Routine')
        
    df['Transaction_Size'] = df['Transaction_Size'].astype('category')
    
    # Validation
    _validate_feature(df, 'Transaction_Size', expected_type='category', check_nulls=True)
    return df

def create_transaction_risk(df: pd.DataFrame) -> pd.DataFrame:
    """
    Purpose:
        Assigns hard risk categories based on the transaction mechanism.
    Parameters:
        df (pd.DataFrame): Dataset with 'type'.
    Returns:
        pd.DataFrame: Dataset with 'Transaction_Risk'.
    Business significance:
        Historically, 100% of fraud in this ecosystem occurs in TRANSFER and CASH_OUT.
        Segmenting by risk type heavily reduces the investigation search space.
    """
    logging.info("Creating Transaction Risk Categories...")
    
    risk_mapping = {
        'TRANSFER': 'High',
        'CASH_OUT': 'High',
        'CASH_IN': 'Low',
        'PAYMENT': 'Low',
        'DEBIT': 'Low'
    }
    
    df['Transaction_Risk'] = df['type'].map(risk_mapping).fillna('Low').astype('category')
    
    # Validation
    _validate_feature(df, 'Transaction_Risk', expected_type='category', check_nulls=True)
    return df

def create_balance_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Purpose:
        Calculates balance changes and detects account takeovers.
    Parameters:
        df (pd.DataFrame): Dataset with balance and amount columns.
    Returns:
        pd.DataFrame: Dataset with 'Balance_Change' and 'Account_Drained'.
    Business significance:
        Balance_Change shows the actual net movement of the sender's funds.
        Account_Drained is a boolean flag explicitly capturing Account Takeover (ATO) behavior
        where a fraudster empties a compromised account in one sweep.
    """
    logging.info("Creating Balance Features...")
    
    # Balance Change: The actual difference in the sender's account.
    # A negative change implies money left the account.
    df['Balance_Change'] = df['newbalanceOrig'] - df['oldbalanceOrg']
    
    # Account Drained: Did the account have money, and did the transaction empty it (nearly)?
    # Specifically looking at outgoing transactions (CASH_OUT, TRANSFER)
    outgoing_mask = df['type'].isin(['CASH_OUT', 'TRANSFER'])
    
    # Using np.where for speed. True if old balance > 0 and new balance is exactly 0.
    df['Account_Drained'] = np.where(
        outgoing_mask & (df['oldbalanceOrg'] > 0) & (df['newbalanceOrig'] == 0),
        True, 
        False
    )
    
    # Validation
    _validate_feature(df, 'Balance_Change', check_nulls=True)
    _validate_feature(df, 'Account_Drained', expected_type='bool', check_nulls=True)
    return df

def calculate_risk_score(df: pd.DataFrame) -> pd.DataFrame:
    """
    Purpose:
        Creates a rule-based 0-100 score evaluating the holistic risk of a transaction.
    Parameters:
        df (pd.DataFrame): Engineered dataset.
    Returns:
        pd.DataFrame: Dataset with 'Risk_Score'.
    Business significance:
        Provides a transparent heuristic for analysts to sort and prioritize work queues.
        No ML is used to guarantee 100% regulatory explainability (FCRA, ECOA compliance).
    """
    logging.info("Calculating Risk Score...")
    
    # Initialize base score
    score = np.zeros(len(df), dtype=np.int16)
    
    # Rule 1: Highest indicator of Account Takeover
    score += np.where(df['Account_Drained'] == True, 40, 0)
    
    # Rule 2: Mechanism Risk
    score += np.where(df['Transaction_Risk'] == 'High', 20, 0)
    
    # Rule 3: Extreme Amounts
    score += np.where(df['Transaction_Size'] == 'Extreme', 25, 0)
    score += np.where(df['Transaction_Size'] == 'High-Value', 10, 0)
    
    # Rule 4: System Flagged (Using legacy system flags if they fired)
    score += np.where(df['isFlaggedFraud'] == 1, 15, 0)
    
    # Ensure score is bound between 0 and 100
    df['Risk_Score'] = np.clip(score, 0, 100).astype(np.int8)
    
    # Validation
    _validate_feature(df, 'Risk_Score', min_val=0, max_val=100, check_nulls=True)
    return df

def assign_priority(df: pd.DataFrame) -> pd.DataFrame:
    """
    Purpose:
        Maps the quantitative risk score to categorical investigation queues.
    Parameters:
        df (pd.DataFrame): Dataset with 'Risk_Score'.
    Returns:
        pd.DataFrame: Dataset with 'Priority'.
    Business significance:
        SLA enforcement. Operations teams require predefined queues ('Critical', 'High') 
        to ensure massive losses are reviewed within an hour, while 'Low' risks are bulk-approved.
    """
    logging.info("Assigning Investigation Priority...")
    
    conditions = [
        df['Risk_Score'] >= 80,
        df['Risk_Score'] >= 60,
        df['Risk_Score'] >= 40
    ]
    choices = ['Critical', 'High', 'Medium']
    
    df['Priority'] = np.select(conditions, choices, default='Low')
    df['Priority'] = pd.Categorical(df['Priority'], categories=['Low', 'Medium', 'High', 'Critical'], ordered=True)
    
    # Validation
    _validate_feature(df, 'Priority', expected_type='category', check_nulls=True)
    return df

def _validate_feature(df: pd.DataFrame, column: str, expected_type=None, min_val=None, max_val=None, check_nulls=False):
    """Internal helper to validate a single feature."""
    if check_nulls and df[column].isnull().any():
        null_count = df[column].isnull().sum()
        logging.warning(f"Validation Warning: {column} contains {null_count} null values.")
        
    if expected_type:
        actual_type = df[column].dtype.name
        if expected_type == 'category' and not isinstance(df[column].dtype, pd.CategoricalDtype):
            logging.warning(f"Validation Warning: {column} expected category type but got {actual_type}.")
        elif expected_type == 'bool' and actual_type != 'bool':
            logging.warning(f"Validation Warning: {column} expected bool type but got {actual_type}.")
        elif expected_type == 'object' and actual_type != 'object':
            logging.warning(f"Validation Warning: {column} expected object type but got {actual_type}.")
            
    if min_val is not None:
        if df[column].min() < min_val:
            logging.warning(f"Validation Warning: {column} minimum value ({df[column].min()}) is below expected ({min_val}).")
            
    if max_val is not None:
        if df[column].max() > max_val:
            logging.warning(f"Validation Warning: {column} maximum value ({df[column].max()}) is above expected ({max_val}).")

def validate_dataset(df: pd.DataFrame):
    """
    Purpose:
        Final comprehensive validation of the entire dataset before saving.
    Parameters:
        df (pd.DataFrame): Fully engineered dataset.
    Business significance:
        Prevents corrupt data from entering the enterprise data warehouse.
    """
    logging.info("Validating Final Dataset...")
    
    # 1. Missing Values
    total_missing = df.isnull().sum().sum()
    if total_missing > 0:
        logging.warning(f"Dataset contains {total_missing} missing values across all columns.")
        
    # 2. Unexpected ranges on numeric columns
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    for col in numeric_cols:
        if np.isinf(df[col]).any():
            logging.warning(f"Column {col} contains infinite values.")
            
    # 3. Required Columns check
    required_cols = ['Transaction_ID', 'Hour', 'Day', 'Transaction_Size', 
                     'Transaction_Risk', 'Balance_Change', 'Account_Drained', 
                     'Risk_Score', 'Priority']
    
    missing_cols = [c for c in required_cols if c not in df.columns]
    if missing_cols:
        logging.error(f"Missing critical engineered columns: {missing_cols}")

def save_dataset(df: pd.DataFrame, output_path: str):
    """
    Purpose:
        Saves the engineered dataset to disk.
    Parameters:
        df (pd.DataFrame): Fully engineered dataset.
        output_path (str): The destination path.
    Business significance:
        Persists data for Power BI ingestion and GenAI prompt embedding.
    """
    logging.info(f"Saving Dataset to {output_path}...")
    
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    # Reorder columns for readability (Metadata -> Features -> Original)
    metadata_cols = ['Transaction_ID', 'Hour', 'Day', 'Priority', 'Risk_Score', 'Account_Drained', 'Transaction_Size', 'Transaction_Risk', 'Balance_Change']
    other_cols = [c for c in df.columns if c not in metadata_cols]
    final_cols = metadata_cols + other_cols
    
    df[final_cols].to_csv(output_path, index=False)

def main():
    start_time = time.time()
    
    INPUT_PATH = "data/raw/PS_20174392719_1491204439457_log.csv"
    OUTPUT_PATH = "data/processed/engineered_transactions.csv"
    
    # Pipeline Execution
    try:
        df = load_data(INPUT_PATH)
        original_shape = df.shape
        original_memory = df.memory_usage(deep=True).sum() / (1024 * 1024)
        
        df = generate_transaction_id(df)
        df = create_time_features(df)
        df = create_transaction_size(df)
        df = create_transaction_risk(df)
        df = create_balance_features(df)
        df = calculate_risk_score(df)
        df = assign_priority(df)
        
        validate_dataset(df)
        save_dataset(df, OUTPUT_PATH)
        
        end_time = time.time()
        
        # Display Final Output Statistics
        final_shape = df.shape
        final_memory = df.memory_usage(deep=True).sum() / (1024 * 1024)
        new_columns = set(df.columns) - set(['step', 'type', 'amount', 'nameOrig', 'oldbalanceOrg', 
                                             'newbalanceOrig', 'nameDest', 'oldbalanceDest', 
                                             'newbalanceDest', 'isFraud', 'isFlaggedFraud'])
        
        print("\n" + "="*50)
        print("FEATURE ENGINEERING PIPELINE REPORT")
        print("="*50)
        print(f"Execution Time:      {end_time - start_time:.2f} seconds")
        print(f"Original Shape:      {original_shape}")
        print(f"Final Shape:         {final_shape}")
        print(f"Original Memory:     {original_memory:.2f} MB")
        print(f"Final Memory Usage:  {final_memory:.2f} MB")
        print(f"New Columns Added:   {len(new_columns)}")
        print("\n--- New Engineered Features ---")
        for col in sorted(new_columns):
            print(f" - {col} ({df[col].dtype})")
            
        print("\n--- Summary Statistics of New Features ---")
        print("\nRisk Score Distribution:")
        print(df['Risk_Score'].describe()[['mean', 'min', '50%', '75%', 'max']])
        
        print("\nPriority Distribution:")
        print(df['Priority'].value_counts(normalize=True).mul(100).round(2).astype(str) + '%')
        
        print("\n--- Sample Records (First 3) ---")
        display_cols = ['Transaction_ID', 'type', 'amount', 'Transaction_Size', 
                        'Account_Drained', 'Risk_Score', 'Priority']
        print(df[display_cols].head(3).to_string(index=False))
        
        print("\n" + "="*50)
        logging.info("Feature Engineering Completed Successfully")
        
    except Exception as e:
        logging.error(f"Pipeline Failed: {e}", exc_info=True)

if __name__ == "__main__":
    main()
