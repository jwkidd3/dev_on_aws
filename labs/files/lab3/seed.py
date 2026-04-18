from decimal import Decimal
import os
import random

# Read your student user id from the session file set up in Lab 1b.
USER = os.environ.get("USER_ID", "user1")

random.seed(42)
CATEGORIES = ["widgets", "gadgets", "tools", "parts"]
COLORS = ["Blue", "Red", "Green", "Yellow", "Orange", "Black"]
NOUNS  = ["widget", "gadget", "gizmo", "thing", "tool", "bracket"]

ROWS = []
for i in range(3, 33):
    ROWS.append({
        "pk":       f"USER#{USER}",
        "sk":       f"ITEM#{i:03d}",
        "title":    f"{random.choice(COLORS)} {random.choice(NOUNS)}",
        "category": random.choice(CATEGORIES),
        "price":    Decimal(f"{random.uniform(2, 50):.2f}"),
        "inStock":  random.choice([True, False]),
    })
