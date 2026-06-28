import pandas as pd
import numpy as np

# ==========================================================
# Load Dataset
# ==========================================================

df = pd.read_csv("data/raw/PS_20174392719_1491204439457_log.csv")

print("=" * 60)
print("FEATURE ENGINEERING")
print("=" * 60)

print(f"\nOriginal Shape: {df.shape}")

# ==========================================================
# Feature 1 : Transaction ID
# ==========================================================

df.insert(
    0,
    "Transaction_ID",
    ["TXN" + str(i).zfill(8) for i in range(1, len(df) + 1)]
)

# ==========================================================
# Feature 2 : Hour
# ==========================================================

df["Hour"] = df["step"] % 24

# ==========================================================
# Feature 3 : Day
# ==========================================================

df["Day"] = (df["step"] // 24) + 1

# ==========================================================
# Preview
# ==========================================================

print("\nPreview of Engineered Features:\n")

print(
    df[
        [
            "Transaction_ID",
            "step",
            "Hour",
            "Day"
        ]
    ].head(20)
)

print("\nCurrent Shape:")
print(df.shape)