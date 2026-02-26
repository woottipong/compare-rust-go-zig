#!/usr/bin/env python3
"""Generate metrics.db with 100,000 rows for SQLite query engine benchmark."""
import sqlite3
import random
import os

random.seed(42)

script_dir = os.path.dirname(os.path.abspath(__file__))
db_path = os.path.join(script_dir, "metrics.db")

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("DROP TABLE IF EXISTS metrics")
c.execute("""
CREATE TABLE metrics (
    id      INTEGER PRIMARY KEY,
    hostname TEXT    NOT NULL,
    cpu_pct  REAL    NOT NULL,
    mem_mb   INTEGER NOT NULL,
    status   TEXT    NOT NULL
)
""")

rows = []
for i in range(100_000):
    hostname = f"host-{i:05d}"
    cpu_pct = round(random.uniform(20.0, 99.9), 2)
    mem_mb = random.randint(512, 16383)   # fits in 2-byte int (≤32767)
    status = "warn" if cpu_pct > 80.0 else "ok"
    rows.append((hostname, cpu_pct, mem_mb, status))

c.executemany(
    "INSERT INTO metrics (hostname, cpu_pct, mem_mb, status) VALUES (?,?,?,?)",
    rows
)
conn.commit()

# Verify
c.execute("SELECT COUNT(*) FROM metrics")
total = c.fetchone()[0]
c.execute("SELECT COUNT(*) FROM metrics WHERE cpu_pct > 80.0")
matching = c.fetchone()[0]

conn.close()

size_mb = os.path.getsize(db_path) / 1024 / 1024
print(f"Generated {db_path}")
print(f"  Rows: {total:,}")
print(f"  Matching (cpu_pct > 80.0): {matching:,} ({matching/total*100:.1f}%)")
print(f"  File size: {size_mb:.2f} MB")
