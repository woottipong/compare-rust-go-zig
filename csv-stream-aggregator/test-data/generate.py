#!/usr/bin/env python3
"""Generate CSV test data for streaming aggregation benchmark."""
import csv
import random
from pathlib import Path

random.seed(42)

CATEGORIES = [
    "books", "electronics", "fashion", "groceries", "home", "sports", "toys", "beauty",
]

ROWS = 200_000

root = Path(__file__).resolve().parent
out = root / "sales.csv"

with out.open("w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["category", "amount"])
    for _ in range(ROWS):
        category = random.choice(CATEGORIES)
        amount = round(random.uniform(1.0, 500.0), 2)
        w.writerow([category, amount])

size_mb = out.stat().st_size / (1024 * 1024)
print(f"Generated {out}")
print(f"Rows: {ROWS:,}")
print(f"Size: {size_mb:.2f} MB")
