# 🗄️ Lab 3b — Query, GSI & Pagination

*Hands-On Lab · 45 min · Module 8 — Databases*

## Objectives (3 min)

- Bulk-load a table from a JSON file
- Query by partition + sort key with a filter expression
- Paginate through results with `LastEvaluatedKey`
- Query the `byCategory` GSI

## Prerequisites (3 min)

- Lab 3a complete — table `Items-$USER_ID` active, 2 items present
- Cloud9 terminal in `~/environment/dev-on-aws/lab3`
```bash
export AWS_DEFAULT_REGION=us-east-1
```

- Set the default region in your shell — the Python scripts do **not** pass `region_name`, so boto3 reads it from the environment:
 
 Add it to `~/.bashrc` if you want it to persist across terminal sessions.

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 3b` exports `$USER_ID`. You can create the table yourself via `seed.py` or by running the Step 1 console flow.

## Step 1 — Review seed.py (6 min)

> Open `~/environment/dev-on-aws/lab3/seed.py` in the Cloud9 editor. It builds 30 items in memory with seeded randomness:

- Each row gets the same `pk = f"USER#{os.environ['USER_ID']}"` — no hand-editing needed
- `sk` ranges `ITEM#003`..`ITEM#032` to avoid colliding with Lab 3a's `ITEM#001`, `ITEM#002`
- `price` is a `Decimal` — required by DynamoDB (no `float`)
- `random.seed(42)` means everyone gets identical rows

## Step 2 — Run bulk_load.py (6 min)

> Open `~/environment/dev-on-aws/lab3/bulk_load.py` to see the batch writer. Then run it:

```bash
cd ~/environment/dev-on-aws/lab3
python3 bulk_load.py
# loaded 30 rows
```

> The resource API's batch writer chunks to 25 items/call and retries `UnprocessedItems`.

## Step 3 — Query + Filter + Paginate (6 min)

> Open `lab3/query_filter.py` in the editor. It runs a `KeyConditionExpression` narrowed to your `USER#$USER_ID` rows, layers a `FilterExpression` for `price < 20`, and walks `LastEvaluatedKey` until the table ends. Then run:

```bash
cd ~/environment/dev-on-aws/lab3
python3 query_filter.py
# items under $20: <count>
```

## Step 4 — Query the GSI (6 min)

> Open `lab3/query_gsi.py`. It targets the `byCategory` GSI and mixes a HASH (`category`) with a RANGE (`price`) condition.

```bash
python3 query_gsi.py
```

- GSI query doesn't require the table's primary key
- GSI reads are eventually consistent
- Only projected attributes come back (your GSI projects ALL)

## Step 5 — Conditional Update (6 min)

> Open `lab3/update_conditional.py`. It updates ITEM#003's `price` and `ADDs` 1 to `views`, guarded by `price <> :new`.

```bash
python3 update_conditional.py    # succeeds — price is now 9.99
python3 update_conditional.py    # ConditionalCheckFailedException — price already 9.99
```

> This is how you prevent lost updates: the database enforces the precondition in the same atomic write.

## Step 6 — Scan (Just Once, to Feel It) (6 min)

> Open `lab3/scan_demo.py`. It scans the full table, then filters for `category == widgets` client-side.

```bash
python3 scan_demo.py
# <n> items in <time>s
```

> Scan reads the whole table, then filters. On 30 rows it's instant; on 30M it's painful. Design for Query.

## Success Criteria (3 min)

- ✅ 30+ items loaded
- ✅ Filtered Query returns items priced under $20, paginated
- ✅ GSI query returns widgets under $15 without touching `pk`
- ✅ You've seen Scan's cost first-hand and chosen not to use it again
