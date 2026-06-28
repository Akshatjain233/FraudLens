import pandas as pd

# Load cleaned dataset (or raw dataset if not cleaned yet)
df = pd.read_csv("data/raw/PS_20174392719_1491204439457_log.csv")

print("=" * 60)
print("BUSINESS VALIDATION")
print("=" * 60)

# 1. Negative Amounts
print("\n1. Negative Amount Transactions")
print((df["amount"] < 0).sum())

# 2. Zero Amount Transactions
print("\n2. Zero Amount Transactions")
print((df["amount"] == 0).sum())

# 3. Fraud by Transaction Type
print("\n3. Fraud by Transaction Type")
print(pd.crosstab(df["type"], df["isFraud"]))

# 4. Fraud Amount Statistics
print("\n4. Fraud Amount Statistics")
print(df[df["isFraud"] == 1]["amount"].describe())

# 5. Flagged Fraud Distribution
print("\n5. Flagged Fraud Distribution")
print(df["isFlaggedFraud"].value_counts())