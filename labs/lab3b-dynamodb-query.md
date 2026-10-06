# 🗄️ Lab 3b — Query, GSI & Pagination

*Hands-On Lab · 45 min · Module 8 — Databases*

## Objectives (2 min)

- Load a table by reading JSON objects from a file
- Compare the **low-level client** and the **resource (document)** APIs
- Query by partition + sort key with a filter expression, paginating with `LastEvaluatedKey`
- Query the `byCategory` GSI
- Update an item conditionally

> 🏷️ **Unique names — one shared account.** The whole class works in the same AWS account and region, and you're an admin: nothing stops you from overwriting or deleting a classmate's resource with the same name. Every name below uses `user1` — **replace it with your own user ID** (`$USER_ID` does this automatically in the terminal; in the Console you type it).
>
> - 30 rows in partition `USER#user1` of **your** table `Items-user1` (the scripts build both names from `$USER_ID`)

## Prerequisites (3 min)

- Lab 3a complete — table `Items-$USER_ID` active, 2 items present
- `$USER_ID` set (`echo $USER_ID`); the scripts read it to find **your** table and partition in the shared account
- The scripts don't pass `region_name`, so boto3 reads the region from the environment — set it once for this shell:

```bash
export AWS_DEFAULT_REGION=us-east-1
cd ~/environment/dev-on-aws/lab3
```

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 3b` creates `Items-$USER_ID` (with the `byCategory` GSI) if it doesn't exist. Lab 3a's two hand-made items will be missing — every step below still works.

## Step 1 — Generate the JSON File (5 min)

> Open `lab3/seed.py` in the Cloud9 editor. It writes 30 plain JSON objects to `items.json`:

- Every row's `pk` is `USER#<your USER_ID>` — your own partition, no hand-editing
- `sk` runs `ITEM#003`..`ITEM#032`, so it can't collide with Lab 3a's `ITEM#001`/`ITEM#002`
- `random.seed(42)` gives everyone identical rows

```bash
python3 seed.py
# wrote 30 rows to items.json
```

> Open the generated `items.json` in the editor — ordinary JSON, the way data arrives from an export or another system.

## Step 2 — Load the File with the Batch Writer (6 min)

> Open `lab3/bulk_load.py`. Two things to notice: `json.load(..., parse_float=Decimal)` (DynamoDB rejects Python `float`), and `table.batch_writer()`, which chunks writes to 25 per call and retries `UnprocessedItems` for you.

```bash
python3 bulk_load.py
# loaded 30 rows from items.json into Items-user1
```

## Step 3 — Low-Level Client vs Resource API (6 min)

> Open `lab3/get_item_client.py`. It fetches `ITEM#003` twice: through `boto3.client("dynamodb")` (every value typed — `{"S": "…"}`, `{"N": "…"}`) and through `boto3.resource("dynamodb")` (plain Python).

```bash
python3 get_item_client.py
# client   → {'pk': {'S': 'USER#user1'}, 'price': {'N': '…'}, …}
# decoded  → {'pk': 'USER#user1', 'price': Decimal('…'), …}
# resource → {'pk': 'USER#user1', 'price': Decimal('…'), …}
```

- **Client** maps 1:1 to the HTTP API — you build typed values yourself
- **Resource** wraps the same calls; `TypeDeserializer` is what converts between the two
- The rest of this lab uses the resource API

## Step 4 — Query + Filter + Paginate (6 min)

> Open `lab3/query_filter.py`. A `KeyConditionExpression` narrows the read to your `USER#…` rows, a `FilterExpression` keeps `price < 20`, and `Limit=10` forces several pages that the loop walks with `LastEvaluatedKey`.

```bash
python3 query_filter.py
# items under $20: <count>
```

> The filter runs **after** the read — you're charged for every row the key condition touched, not just the ones returned.

## Step 5 — Query the GSI (5 min)

> Open `lab3/query_gsi.py`. It targets the `byCategory` GSI: HASH `category = widgets`, RANGE `price < 15`.

```bash
python3 query_gsi.py
```

- A GSI query doesn't use the table's primary key
- GSI reads are eventually consistent
- Only projected attributes come back (this GSI projects ALL)
- The GSI spans the whole table — in this shared lab it's your table, so only your rows appear

## Step 6 — Conditional Update (6 min)

> Open `lab3/update_conditional.py`. It sets ITEM#003's `price` to 9.99 and `ADD`s 1 to `views`, guarded by `price <> :new`.

```bash
python3 update_conditional.py    # updated → {... 'price': Decimal('9.99'), 'views': Decimal('1')}
python3 update_conditional.py    # ConditionalCheckFailedException — nothing written
```

> This is how you prevent lost updates: the database checks the precondition and writes in one atomic step.

## Step 7 — Scan (Just Once, to Feel It) (3 min)

> Open `lab3/scan_demo.py`. It scans the full table with a `FilterExpression` for `category == widgets`.

```bash
python3 scan_demo.py
# <n> items in <time>s
```

> Scan reads every item, then filters. On 30 rows it's instant; on 30 million it's slow and expensive. Design for Query.

## Success Criteria (3 min)

- ✅ `items.json` generated and 30 rows loaded from it
- ✅ Same item read through the client (typed) and resource (plain) APIs
- ✅ Filtered Query returns items priced under $20 across several pages
- ✅ GSI query returns widgets under $15 without touching `pk`
- ✅ Second conditional update rejected with `ConditionalCheckFailedException`
