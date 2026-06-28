import pandas as pd

# Load Dataset
df = pd.read_csv("data/raw/PS_20174392719_1491204439457_log.csv")

print("="*50)
print("DATASET OVERVIEW")
print("="*50)

print(f"\nRows, Columns: {df.shape}")

print("\nColumn Names:")
print(df.columns.tolist())

print("\nData Types:")
print(df.dtypes)

print("\nMissing Values:")
print(df.isnull().sum())

print("\nDuplicate Rows:")
print(df.duplicated().sum())

print("\nFraud Distribution:")
print(df["isFraud"].value_counts())

print("\nFraud Percentage:")
print(df["isFraud"].value_counts(normalize=True) * 100)

print("\nTransaction Types:")
print(df["type"].value_counts())

print("\nSummary Statistics:")
print(df.describe())