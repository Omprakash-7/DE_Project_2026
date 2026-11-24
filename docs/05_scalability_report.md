# Phase 5 Scalability Report: 20× Large Dataset & 100× Architecture (CP4)
**Team:** T0004 | **Section:** D | **Mentor:** Omkar  
**Repository:** [DE_Project_2026](https://github.com/Omprakash-7/DE_Project_2026)  
**Database:** PostgreSQL 18.4 (Postgres.app) | **Scale Test:** `large_data.zip` (20× dataset: 17,543,347 total rows)  

---

## 1. 20× Large Dataset Benchmark Results

We loaded all 9 CSVs from the official `large_data.zip` release into a fresh database `whatsapp_large` using `sql/01_schema.sql` (0 constraint failures across **17.54M rows**: `600,000` users, `840,000` devices, `460,000` chats, `2,090,014` chat_members, `551,121` media, `2,400,000` messages, `10,022,212` message_receipts, `500,000` calls, `80,000` blocked_users), applied `sql/05_indexes.sql`, and ran `sql/06_optimized_queries.sql` for 3 runs per query (`benchmarks/results/large/summary.csv`).

### 1.1 Results Table (All 30 Queries vs. Phase 5 Targets)

| Query | Target (ms) | Optimized on Seed (ms) | Optimized on Large (ms) | Growth (Large ÷ Seed) | Meets Target? | Notes / Fix Applied at Scale |
|---|---:|---:|---:|---:|:---:|---|
| **R01** | < 5 | 0.570 | 0.208 | 0.4× | ✅ | Warm index cache; $O(\log N)$ Index Only Scans (`chat_members`, `messages`) |
| **R02** | < 5 | 0.665 | 0.043 | 0.1× | ✅ | `idx_messages_chat_sent` reads only 50 messages of group `22556` |
| **R03** | < 5 | 0.816 | 0.073 | 0.1× | ✅ | `idx_receipts_unread_user` isolates user 965's unread rows |
| **R04** | < 250 | 0.077 | 0.056 | 0.7× | ✅ | User 965's 4 chats scanned via `idx_messages_chat_sent` |
| **R05** | < 5 | 0.114 | 0.155 | 1.4× | ✅ | Unique B-tree point lookup `users_phone_e164_key` |
| **R06** | < 5 | 0.283 | 0.132 | 0.5× | ✅ | Direct chat partner lookup via `idx_chat_members_user_chat` |
| **R07** | < 5 | 0.740 | 0.244 | 0.3× | ✅ | PK lookup on `chat_members_pkey` + `users_pkey` |
| **R08** | < 250 | 6.680 | 7.340 | 1.1× | ✅ | **Fixed scale regression:** removed `MATERIALIZED` CTE (was 191.1 ms / 64.7×; see §3) |
| **R09** | < 5,000 | 10.444 | 225.346 | 21.6× | ✅ | Full `Seq Scan on media` (551k rows) + `HashAggregate` |
| **R10** | < 5,000 | 1.672 | 40.354 | 24.1× | ✅ | `Index Only Scan` on `idx_messages_sent_at_cover` (131k June rows) |
| **R11** | < 250 | 0.163 | 0.073 | 0.4× | ✅ | `idx_chat_members_user_chat` + `idx_calls_missed_chat` |
| **R12** | < 5,000 | 1.245 | 29.511 | 23.7× | ✅ | Partial `Index Only Scan` on `idx_messages_forwarded` (120k rows) |
| **R13** | < 250 | 0.555 | 0.049 | 0.1× | ✅ | `idx_messages_chat_sent` + `idx_messages_reply_to` anti-join |
| **R14** | < 5,000 | 2.189 | 48.050 | 22.0× | ✅ | `idx_messages_sent_at_cover` + partial `idx_chats_group` |
| **R15** | < 5 | 0.051 | 0.024 | 0.5× | ✅ | `blocked_users_pkey` point check |
| **R16** | < 5 | 0.330 | 0.166 | 0.5× | ✅ | `message_receipts_pkey` leading `message_id` |
| **R17** | < 5,000 | 18.498 | 257.769 | 13.9× | ✅ | Parallel `Seq Scan` on 10M receipts + `idx_messages_sent_at_cover` |
| **R18** | < 5,000 | 13.436 | 138.409 | 10.3× | ✅ | `idx_users_last_seen` + `idx_chats_group` + `Seq Scan on chat_members` |
| **R19** | < 5,000 | 14.740 | 258.433 | 17.5× | ✅ | **Plan upgrade at scale:** switched to streaming `Index Only Scan` Merge Join |
| **R20** | < 5,000 | 20.205 | 242.431 | 12.0× | ✅ | Parallel `Seq Scan` + in-memory `HashAggregate` (0 disk sort) |
| **R21** | < 5,000 | 12.128 | 89.542 | 7.4× | ✅ | Parallel `Seq Scan on messages` + `HashAggregate` |
| **R22** | < 250 | 0.062 | 0.025 | 0.4× | ✅ | Keyset pagination (`0.036 ms` verified at large page 4,001 `message_id < 2300001`; see §1.2) |
| **R23** | < 250 | 0.512 | 9.075 | 17.7× | ✅ | Pre-sorted `Index Only Scan` on `idx_devices_linked_active` |
| **R24** | < 5,000 | 6.453 | 290.919 | 45.1× | ✅ | Hash table (~485k SHA-256s) exceeded `work_mem` → external merge sort (see §2.3) |
| **R25** | < 5 | 0.107 | 0.057 | 0.5× | ✅ | Recursive PK lookups on `messages_pkey` |
| **W01** | < 5 | 0.837 | 1.310 | 1.6× | ✅ | Single `INSERT` + 5 B-tree updates ($O(\log N)$ depth) |
| **W02** | < 5 | 0.866 | 0.256 | 0.3× | ✅ | Indexed lookup on `idx_messages_chat_sent` + `idx_receipts_unread_user` |
| **W03** | < 5 | 0.298 | 0.239 | 0.8× | ✅ | Single-row PK `UPDATE` |
| **W04** | < 2,000 | 33.041 | 33.918 | 1.0× | ✅ | 5,000-row batch `INSERT` scales $O(5000 \log N)$ |
| **W05** | < 5 | 0.224 | 0.297 | 1.3× | ✅ | Single-row composite PK `UPDATE` |
| **Total** | — | **148.001** | **1,674.504** | **11.3×** | **30 / 30 ✅** | **Total 20× workload finishes in 1.67 seconds** |

### 1.2 Note on R22 Keyset Cursor for Large Data
In `sql/06_optimized_queries.sql`, `R22` uses keyset pagination `WHERE message_id < 20001 ORDER BY message_id DESC LIMIT 25` (which corresponds to page 4,001 after `OFFSET 100000` on the 120,000-row seed data). On the 2,400,000-row `large_data`, page 4,000 ends at:
```sql
SELECT message_id FROM messages ORDER BY message_id DESC OFFSET 99999 LIMIT 1;
-- Returns: 2300001
```
Testing `WHERE message_id < 2300001 ORDER BY message_id DESC LIMIT 25` directly against `whatsapp_large` executed `Index Scan Backward using messages_pkey` in **`0.036 ms`** (`Buffers: shared hit=6 read=1`). In production, the Trust & Safety console passes the last `message_id` rendered on page 4,000 (`2300001`) as the cursor parameter, giving constant $O(\log N)$ performance regardless of page depth.

---

## 2. Growth Analysis (When Data Grew 20×)

### 2.1 Stayed About the Same (`~0.1× – 1.6×` growth)
* **Queries:** `R01`, `R02`, `R03`, `R04`, `R05`, `R06`, `R07`, `R08`, `R11`, `R13`, `R15`, `R16`, `R22`, `R25`, `W01`, `W02`, `W03`, `W04`, `W05`.
* **Why:**
  1. B-tree depth only increases from ~3 levels (120k rows) to ~4 levels (2.4M–10M rows), so point lookups and single-user/single-chat queries scale at $O(\log N)$ (< 1 ms).
  2. `R08` (`1.1×`) and `R02`/`R22` stop immediately via `LIMIT 500` / `LIMIT 50` / `LIMIT 25` rather than reading a percentage of the table.
  3. `W04` (`1.0×`, `33.04 ms → 33.92 ms`) inserts a fixed batch of 5,000 receipts; B-tree descent cost stays nearly identical.
  4. *(Note: On seed data, several 0.05–0.8 ms queries incurred minor Run 1 cold-buffer reads right after large-DB creation, making warm `large` averages slightly lower than `seed`.)*

### 2.2 Grew Roughly `~7× – 24×` (Linear with Fixed Table Share)
* **Queries:** `R09` (`21.6×`), `R10` (`24.1×`), `R12` (`23.7×`), `R14` (`22.0×`), `R17` (`13.9×`), `R18` (`10.3×`), `R19` (`17.5×`), `R20` (`12.0×`), `R21` (`7.4×`), `R23` (`17.7×`).
* **Why:** Each of these queries reads either 100% of a table (`R09`, `R20`, `R21`) or a fixed percentage of rows (`R10`/`R14`/`R17`: ~5.5% June messages; `R12`: 5% forwarded; `R23`: ~29% linked devices; `R19`: all 60,000 groups). When rows grow 20×, I/O and aggregation work grow proportionally (`~10–24×`), with parallel workers amortizing full-table scans (`R21` `7.4×`, `R20` `12.0×`).
* **Notable Optimizer Plan Upgrade (`R19`):** On seed data, `R19` ran `Seq Scan on messages` + `HashAggregate`. On `whatsapp_large` (2.4M messages), the planner automatically upgraded to **`Merge Left Join` + `GroupAggregate` over `Index Only Scan using idx_messages_chat_sent` (`Heap Fetches: 0`)** joined to `Index Only Scan using idx_chats_group`, keeping growth sublinear (`17.5×`).

### 2.3 Grew More Than `20×`
1. **Query `R24` (`6.453 ms → 290.919 ms`, `45.1×` growth):**
   * **Why:** On seed data (`27,634` media rows), grouping by `sha256` fit inside PostgreSQL's `HashAggregate` memory budget (`5,393 kB` RAM). On `large_data` (`551,121` rows, ~485,000 distinct 64-byte hashes), the hash table exceeded `work_mem * hash_mem_multiplier`, forcing PostgreSQL to switch to `Sort` + **`external merge Disk` (~48.6 MB temp disk across 3 workers, `temp read=6074 written=6090`)**.
   * **Verdict:** At `290.9 ms`, it still meets its `< 5,000 ms` reporting target with a **17× safety margin**. At 100× scale, an incremental daily dedup summary table/replica avoids repeated 500k+ hash sorts.
2. **Query `R08` (`2.956 ms → 191.117 ms`, `64.7×` growth BEFORE Scale Fix — Fixed!):**
   * See Section 3 below!

---

## 3. What Broke at Scale & How We Fixed It (`R08`)

During Phase 4 on seed data, we initially rewrote `R08` with `WITH pending AS MATERIALIZED (SELECT message_id, user_id FROM message_receipts WHERE delivered_at IS NULL)`. On seed data (`5,076` undelivered rows), that ran in `2.956 ms` (263 kB RAM). **At 20× scale (`large_data`), that optimization broke badly:**
* `pending` grew to `99,600` rows, exceeding `4,096 kB` (`Storage: Disk, temp written=267`).
* Because the planner saw 100k rows in `pending`, it abandoned `Nested Loop` + `messages_pkey` and fell back to a **`Hash Join` with a full `Seq Scan` of all 2,400,000 rows in `messages`** (`26,632` buffers), jumping **`64.7×` to `191.117 ms`** (which would fail `< 250 ms` at 30×+!).

### Before Fix (`large/R08` with `MATERIALIZED` CTE — `195.307 ms` Run 1 / `191.117 ms` avg):
```text
Limit  (cost=78022.30..78023.55 rows=500 width=20) (actual time=194.492..194.519 rows=500.00 loops=1)
  Buffers: shared hit=1226 read=25796, temp written=267
  CTE pending -> Index Only Scan using idx_receipts_undelivered (rows=99600.00)
  ->  Sort -> Hash Join  (actual time=14.634..191.006 rows=99176.00 loops=1)
        ->  Seq Scan on messages m  (actual time=0.027..79.945 rows=2399817.00 loops=1)
        ->  Hash -> CTE Scan on pending r (Storage: Disk Maximum Storage: 4096kB)
Execution Time: 195.307 ms
```

### After Fix (`large/R08` plain `JOIN` driving from `idx_messages_sent_at_cover` `LIMIT 500` — `7.340 ms` avg, `26×` faster at scale!):
```text
Limit  (cost=1000.87..3714.30 rows=500 width=20) (actual time=6.296..7.143 rows=500.00 loops=1)
  Buffers: shared hit=53406
  ->  Gather Merge -> Nested Loop (actual time=0.124..2.956 rows=247.00 loops=3)
        ->  Parallel Index Only Scan using idx_messages_sent_at_cover on messages m (rows=5916.33 loops=3, Heap Fetches: 0)
        ->  Index Only Scan using idx_receipts_undelivered on message_receipts r (Index Searches: 17749, Heap Fetches: 0)
Execution Time: 7.174 ms
```
**Result:** Removing `MATERIALIZED` eliminated the disk spill and 2.4M-row sequential scan, fixing `R08` to **`7.340 ms`** (`1.1×` growth from seed to 20× large!).

---

## 4. Storage Comparison: Seed vs. Large Data

| Metric | Seed Data (1×) | Large Data (20×) | Scale Ratio |
|---|---:|---:|---:|
| **Total PostgreSQL DB Size (`pg_database_size`)** | **119 MB** | **2,157 MB** (~2.11 GB) | **18.1×** |
| **Base Tables (`pg_relation_size` sum)** | **59 MB** | **1,141 MB** | **19.3×** |
| **All Indexes (`pg_indexes_size` sum)** | **52 MB** | **1,009 MB** | **19.4×** |
| **Schema Total (`tables + indexes`)** | **111 MB** | **2,151 MB** | **19.4×** |

### Per-Table Storage Breakdown on `whatsapp_large` (20×):
| Table | Rows | Table Size | Indexes Size | Total Size |
|---|---:|---:|---:|---:|
| `message_receipts` | 10,022,212 | 557 MB | 382 MB | **939 MB** |
| `messages` | 2,400,000 | 208 MB | 393 MB | **602 MB** |
| `chat_members` | 2,090,014 | 121 MB | 108 MB | **229 MB** |
| `users` | 600,000 | 53 MB | 55 MB | **109 MB** |
| `media` | 551,121 | 77 MB | 12 MB | **89 MB** |
| `devices` | 840,000 | 55 MB | 27 MB | **82 MB** |
| `calls` | 500,000 | 42 MB | 17 MB | **58 MB** |
| `chats` | 460,000 | 24 MB | 12 MB | **36 MB** |
| `blocked_users` | 80,000 | 3,464 kB | 1,768 kB | **5.1 MB** |

**100× Projection:** At 100× seed volume (~12M messages, ~50M receipts), the total database will reach **~10.8 GB** (`~5.7 GB` tables + `~5.1 GB` indexes). A single server with **16–32 GB RAM** (`shared_buffers = 8 GB`) still holds the entire hot working set in memory, though `messages` and `message_receipts` (`~7.7 GB` combined) require partitioning and autovacuum tuning to prevent bloat.

---

## 5. Architecture for 100× Scale

### 5.1 Table Partitioning (`sql/08_partitioning.sql`)
* **Table & Strategy:** **`messages` partitioned by `RANGE (sent_at)` (monthly)** (`messages_p2025_01` through `messages_p2026_07` + `messages_p_default`).
  * *Why `messages` and `RANGE (sent_at)`:* `messages` grows monotonically with physical correlation `~1.0` on `sent_at`. Monthly partitions keep each active month at ~133k rows / ~12 MB at 20× (~665k rows / ~60 MB at 100×). Time-bounded queries (`R10`, `R14`, `R17`, `R19` June count) prune 18 of 19 historical partitions, and archiving old months becomes an instant `ALTER TABLE ... DETACH PARTITION` / `DROP TABLE` metadata operation with zero `VACUUM` overhead.
* **PostgreSQL Primary-Key Rule:** PostgreSQL requires every `PRIMARY KEY` / `UNIQUE` constraint on a partitioned table to include **all partition key columns**. Therefore, the partitioned `messages` PK must become **`PRIMARY KEY (message_id, sent_at)`** instead of `(message_id)` alone. *(Caveat: child tables like `message_receipts` and self-referential `reply_to_message_id` must either carry `sent_at` in composite FKs or validate referential integrity in the application/trigger layer.)*
* **Verified Partition Pruning on `whatsapp_large` (2,400,000 rows via `sql/08_partitioning.sql`):**
  ```text
  GroupAggregate  (actual time=31.101..39.266 rows=30.00 loops=1)
    Buffers: shared hit=1471, temp read=291 written=292
    ->  Sort -> Seq Scan on messages_p2026_06 messages_partitioned  (actual time=0.005..9.513 rows=131868.00 loops=1)
          Filter: ((sent_at >= '2026-06-01 00:00:00+05:30') AND (sent_at < '2026-07-01 00:00:00+05:30'))
  Execution Time: 39.733 ms
  ```
  19 of 20 partitions were pruned at plan time; only `messages_p2026_06` (`131,868` rows, `1,468` pages) was scanned.

### 5.2 Sharding Strategy (`chat_id` vs. `sender_id` vs. `recipient_id`)
* **Recommended Shard Key:** **`chat_id` (Hash-sharded across $K$ nodes)** for `chats`, `chat_members`, `messages`, `message_receipts`, and `calls` (co-located by `chat_id`!). Note `users`, `devices`, and `blocked_users` shard naturally by `user_id` (or replicate `users` small lookup / route via `user_id`).
* **Impact on `R01` (User's Chat List) vs. `R02` (One Chat's History):**
  * **`R02` (Open chat 22556), `R07`, `R13`, `W01`, `W02`, `W03`:** Become **100% single-shard queries** — opening a busy group, sending a message, and marking unread receipts in that group touch **exactly one shard**.
  * **`R01` (User 965's chats screen) & `R03` (Unread badges):** Become **cross-shard** if `chat_members` is sharded solely by `chat_id` (since user 965 belongs to multiple chats living on different shards).
  * **Handling Cross-Shard Queries (`R01`, `R03`, `R04`, `R06`):** Maintain a lightweight **user-to-chats directory/inbox table** co-located by `user_id` (or Redis cached list of `(user_id -> chat_ids, last_msg_preview, unread_count)` updated asynchronously on message delivery), or use Citus/application-level parallel scatter-gather restricted to just the user's ~4–50 active chat shards instead of all shards. Global analytics (`R09`, `R10`, `R14`, `R19`, `R20`, `R21`, `R24`) run via parallel map-reduce scatter-gather on an analytical replica / warehouse.

### 5.3 Read Replicas & Application Caching
| Tier | Queries Routed | Consistency / TTL Rationale |
|---|---|---|
| **Primary (Read-Write)** | `W01`–`W05`, `R05` (registration), `R15` (before delivery block check), `R08` (delivery worker) | Strong ACID consistency; delivery/registration cannot tolerate replication lag. |
| **Sync/Low-Lag Read Replicas** | `R01`, `R02`, `R03`, `R04`, `R06`, `R07`, `R11`, `R16`, `R25` | Offloads 90%+ of customer read traffic (`< 0.25 ms` on replica). |
| **Dedicated Analytics Replica** | `R09`, `R10`, `R12`, `R14`, `R17`, `R18`, `R19`, `R20`, `R21`, `R22`, `R23`, `R24` | Heavy multi-hundred-ms scans (`R17`, `R19`, `R24`) isolated from customer OLTP buffers. |
| **Redis / Edge Cache** | `R05` (phone→user_id, invalidate on join/ban), `R15` (block pairs, invalidate on block/unblock), `R06` (`last_seen`, 30s TTL) | Absorbs point lookups for contact info and delivery block gates (`< 1 ms`). |

### 5.4 Maintenance Strategy at 100×
1. **Aggressive Autovacuum on Hot Tables:** Lower `autovacuum_vacuum_scale_factor = 0.02` and `autovacuum_analyze_scale_factor = 0.01` on `messages` and `message_receipts` (`W02` updates `read_at`, `W03` updates `is_deleted`) so visibility maps stay clean and `Index Only Scans` avoid falling back to heap fetches.
2. **Zero-Bloat Partition Archiving:** Monthly `DROP` or `DETACH PARTITION` + archive to S3/Parquet for messages older than 12–18 months keeps hot working indexes within RAM.
3. **Summary Tables / Materialized Views:** At 100×, refresh `mv_hourly_message_stats` (`R20`), `mv_group_health` (`R19`), and `mv_media_dedup` (`R24`) hourly via `REFRESH MATERIALIZED VIEW CONCURRENTLY` on the analytics replica.

---

## 6. Conclusion & Remaining Risks
* **Readiness Verdict:** **Ready for 20× scale today.** All **30/30 queries** meet their Phase 5 performance targets (`1,674.5 ms` total across all 30 queries on `2,157 MB` data — **11.3× total growth for 20× data**).
* **Remaining Risks at 100×:**
  1. **`R24` External Merge Sort (`290.9 ms` at 20×):** Will spill several hundred MB at 100× unless moved to a scheduled dedup job / analytical replica or higher maintenance `work_mem` on the reporting node.
  2. **`message_receipts` Size (`939 MB` at 20× → `~4.7 GB` at 100×):** Without partitioning `message_receipts` (e.g., by `message_id` range aligned with `messages` monthly ID watermarks), `R17` and `message_receipts_pkey` B-tree depth/RAM footprint will be the #1 storage pressure point.
  3. **`W04` Broadcast Fan-out:** A single large business announcement to 500k+ recipients must be chunked into async batches (e.g., 5,000 rows per batch, `33.9 ms` each) via a queue to avoid holding long locks.
