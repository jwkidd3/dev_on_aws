# 🗄️ Lab 3a — DynamoDB in the Console

*Hands-On Lab · 45 min · Console · Module 8 — Databases*

## Objectives (2 min)

- Create the `Items-userN` table and its `byCategory` GSI
- Add items through the console's item editor
- Run a Query using the table's Explore view
- Run a Scan with a filter and observe the capacity cost
- Use PartiQL from the console's query editor

## Prerequisites (2 min)

- Day 1 labs complete (Cloud9 + LabRole + repo cloned + env file set up)
- AWS Console tab open

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 3a` exports `$USER_ID`/`$ACCT`.

## ☀️ Resume from Day 1 (3 min)

> Run this before anything else on Day 2. It confirms Cloud9 came back up clean and your session variables are still in place. If any check fails, fix it before continuing.

```bash
# 1. LabRole is still attached, AMTC still off
aws sts get-caller-identity --query Arn --output text
#   → arn:aws:sts::ACCT:assumed-role/LabRole/i-…

# 2. Session variables auto-sourced from ~/.dev-on-aws.env
echo "USER_ID=$USER_ID  ACCT=$ACCT  BUCKET=$BUCKET"
#   → all three non-empty

# 3. Repo + files still on disk
ls ~/environment/dev-on-aws/lab3/
#   → bulk_load.py  query_filter.py  query_gsi.py  scan_demo.py  seed.py  update_conditional.py
```

> If check 1 shows `user/user1` or an AMTC session, redo Lab 1a Step 4. If check 2 shows blanks, `source ~/.dev-on-aws.env`. If check 3 is missing, re-clone per Lab 1a Step 6.

## Step 1 — Create the Table (5 min)

1. Console search: **DynamoDB** → **Tables** → **Create table**
2. Table name: `Items-user1` (replace with your user)
3. Partition key: `pk` (String)
4. Sort key: `sk` (String)
5. Table settings: **Default settings** (on-demand billing)
6. **Create table** — wait ~20 s for status *Active*
7. Open the table → **Indexes** tab → **Create index**
8. Index name: `byCategory`; partition `category` (String); sort `price` (Number); projection **All**

## Step 2 — Add an Item (Form) (5 min)

1. **Explore table items** → **Create item**
2. Form view — fill in `pk = USER#user1`, `sk = ITEM#001`
3. Click **Add new attribute** → String → `title = Blue widget`
4. Add: `category` (String, `widgets`), `price` (Number, `19.95`), `inStock` (Boolean, true)
5. **Create item**

## Step 3 — Add an Item (JSON) (8 min)

1. **Create item** → toggle **JSON view** (turn **View DynamoDB JSON** on)
2. Paste the JSON below — **replace `user1` with your user id first**; the Console does not expand shell variables
3. **Create item**
4. Click the new `ITEM#002` row to confirm the typed attributes (`S`, `N`, `BOOL`, `SS`)

```json
{
  "pk":       { "S": "USER#user1" },
  "sk":       { "S": "ITEM#002" },
  "title":    { "S": "Red gadget" },
  "category": { "S": "gadgets" },
  "price":    { "N": "29.00" },
  "inStock":  { "BOOL": false },
  "tags":     { "SS": ["red", "gadget"] }
}
```

## Step 4 — Run a Query (4 min)

1. Explore view → switch from *Scan* to **Query**
2. Partition key: `pk = USER#<your-user-id>` (e.g., `USER#user1`)
3. Sort key: `begins_with ITEM#`
4. **Run**
5. Scroll right — the returned *Read capacity units* tells you what the query cost

## Step 5 — Scan + Filter (4 min)

1. Switch to **Scan**
2. Add filter: `category = widgets`
3. **Run**
4. Note the time taken and RCU used compared to the Query
5. This is the "scan cost" lesson you'll remember every time you design a table

## Step 6 — PartiQL in the Console (7 min)

1. Left nav → **PartiQL editor**
2. Paste the SELECT below — **replace `user1` in both places** with your user id — and **Run**

```sql
SELECT sk, title, price
FROM   "Items-user1"
WHERE  pk = 'USER#user1'
  AND  begins_with(sk, 'ITEM#')
```

3. Run an UPDATE to change ITEM#001's price to 17.50 (again, your user id):

```sql
UPDATE "Items-user1"
SET    price = 17.50
WHERE  pk = 'USER#user1' AND sk = 'ITEM#001'
```

4. Re-run the SELECT — ITEM#001 now shows `17.5`

## Success Criteria (2 min)

- ✅ Table schema + `byCategory` GSI understood
- ✅ ITEM#001 and ITEM#002 created through the console (form + JSON)
- ✅ Query returns both items; Scan + filter returns a subset
- ✅ Difference in RCU between Query and Scan noted
- ✅ PartiQL SELECT + UPDATE executed from the console
