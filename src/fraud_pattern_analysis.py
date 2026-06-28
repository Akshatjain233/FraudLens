import pandas as pd

df = pd.read_csv("data/raw/PS_20174392719_1491204439457_log.csv")

print("=" * 60)
print("FRAUD PATTERN ANALYSIS")
print("=" * 60)

# 1. Transaction Amount Comparison
print("\n1. Transaction Amount Comparison")
print(df.groupby("isFraud")["amount"].describe())

# 2. Average Sender Balance
print("\n2. Sender Balance Comparison")
print(df.groupby("isFraud")["oldbalanceOrg"].describe())

# 3. Average Receiver Balance
print("\n3. Receiver Balance Comparison")
print(df.groupby("isFraud")["oldbalanceDest"].describe())

# 4. Sender Balance After Transaction
print("\n4. Sender Balance After Transaction")
print(df.groupby("isFraud")["newbalanceOrig"].describe())

# 5. Receiver Balance After Transaction
print("\n5. Receiver Balance After Transaction")
print(df.groupby("isFraud")["newbalanceDest"].describe())

# 6. Fraud Percentage by Transaction Type
print("\n6. Fraud Percentage by Transaction Type")

fraud_rate = (
    df.groupby("type")["isFraud"]
      .mean()
      .mul(100)
      .round(2)
)

print(fraud_rate)