"""Lab 3b Step 1 — generate items.json: 30 catalog rows for YOUR partition.

    python3 seed.py          # writes ./items.json

Plain JSON objects (not DynamoDB-typed), the same shape you'd get from an
export or another system. bulk_load.py reads this file into the table.
"""
import json
import os
import random

USER = os.environ["USER_ID"]   # set in Lab 1b — keeps your rows in your own partition

random.seed(42)                # everyone gets identical rows
CATEGORIES = ["widgets", "gadgets", "tools", "parts"]
COLORS = ["Blue", "Red", "Green", "Yellow", "Orange", "Black"]
NOUNS  = ["widget", "gadget", "gizmo", "thing", "tool", "bracket"]

rows = []
for i in range(3, 33):          # ITEM#003..ITEM#032 — no clash with Lab 3a's 001/002
    rows.append({
        "pk":       f"USER#{USER}",
        "sk":       f"ITEM#{i:03d}",
        "title":    f"{random.choice(COLORS)} {random.choice(NOUNS)}",
        "category": random.choice(CATEGORIES),
        "price":    round(random.uniform(2, 50), 2),
        "inStock":  random.choice([True, False]),
    })

with open("items.json", "w") as f:
    json.dump(rows, f, indent=2)
print(f"wrote {len(rows)} rows to items.json")
