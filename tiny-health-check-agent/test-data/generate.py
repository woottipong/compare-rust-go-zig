#!/usr/bin/env python3
"""Generate targets.csv with 5000 health-check targets."""
import random
import os

random.seed(42)

script_dir = os.path.dirname(os.path.abspath(__file__))
out_path = os.path.join(script_dir, "targets.csv")

SERVICE_PREFIXES = [
    "auth", "api", "payment", "order", "user", "product", "cart",
    "inventory", "search", "recommend", "notify", "email", "sms",
    "upload", "download", "stream", "cache", "queue", "worker",
    "scheduler", "monitor", "logger", "metrics", "config", "gateway",
]
SERVICE_SUFFIXES = [
    "service", "svc", "api", "backend", "server", "handler",
    "proxy", "worker", "agent", "daemon", "node",
]

rows = []
for i in range(1, 5001):
    prefix = random.choice(SERVICE_PREFIXES)
    suffix = random.choice(SERVICE_SUFFIXES)
    name = f"{prefix}-{suffix}-{i:04d}"
    expected_up = "true" if random.random() < 0.88 else "false"
    base_ms = random.randint(5, 200)
    jitter_ms = random.randint(1, 50)
    rows.append(f"{i},{name},{expected_up},{base_ms},{jitter_ms}")

with open(out_path, "w") as f:
    f.write("# id,name,expected_up,base_ms,jitter_ms\n")
    f.write("\n".join(rows) + "\n")

up_count = sum(1 for r in rows if ",true," in r)
print(f"Generated {out_path}")
print(f"  Rows: {len(rows):,}")
print(f"  Expected up: {up_count:,} ({up_count/len(rows)*100:.1f}%)")
print(f"  Expected down: {len(rows)-up_count:,}")
size_kb = os.path.getsize(out_path) / 1024
print(f"  File size: {size_kb:.1f} KB")
