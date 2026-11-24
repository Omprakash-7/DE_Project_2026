# Phase 4 Optimization Report: WhatsApp Messaging Database (CP3)
**Team:** T0004 | **Section:** D | **Mentor:** Omkar  
**Repository:** [DE_Project_2026](https://github.com/Omprakash-7/DE_Project_2026)  
**Database:** PostgreSQL 18.4 (Postgres.app) | **Workload:** 5 consecutive runs per query (`sql/06_optimized_queries.sql`)  

---

## 1. Executive Summary
* **Total Baseline Time (30 queries):** `17,265.649 ms` (~17.27 seconds)
* **Total Optimized Time (30 queries):** `129.899 ms` (~0.13 seconds)
* **Overall Improvement:** **99.25% reduction (`132.9×` faster overall)**
* **Biggest Single Improvement:** Query **R19** dropped from **17,003.794 ms → 14.083 ms** (`99.92%` / `1,207.4×` faster).
* **Correctness Bug Fixed:** Query **R13** previously returned **0 rows** due to a SQL three-valued logic `NULL` trap in `NOT IN`; rewriting to `NOT EXISTS` recovers all **7 real unanswered questions** while running `240×` faster (`19.205 ms → 0.080 ms`).

---

## 2. Optimization Summary Table (All 30 Queries)

> Note: `Improvement % = (Before - After) / Before × 100`. Negative percentages on write queries (`W01`, `W03`, `W04`, `W05`) reflect expected index-maintenance overhead.

| Query | Before (ms) | Problem Found in Baseline Plan | Optimization Applied | After (ms) | Improvement | Same Result? |
|---|---:|---|---|---:|---:|:---:|
| **R01** | 18.377 | `chat_members_pkey` scanned 295 pages (`user_id` trailing); 4× `Seq Scan on messages` | `idx_chat_members_user_chat` + `idx_messages_chat_sent` (Index Only Scans) | 0.098 | 99.5% (187.5×) | ✅ |
| **R02** | 3.506 | `Seq Scan on messages` (120k rows) + sort | `idx_messages_chat_sent` (`chat_id, sent_at DESC`) | 0.083 | 97.6% (42.2×) | ✅ |
| **R03** | 7.705 | `Parallel Seq Scan` across all 501,590 `message_receipts` | Partial covering index `idx_receipts_unread_user (user_id, message_id) WHERE read_at IS NULL` | 0.100 | 98.7% (77.0×) | ✅ |
| **R04** | 33.006 | `Seq Scan on messages` checking `ILIKE` on 120k rows before join | `idx_chat_members_user_chat` + `idx_messages_chat_sent` (`INCLUDE body`, Index Only Scan) | 0.063 | 99.8% (523.9×) | ✅ |
| **R05** | 0.022 | Already optimal (`Index Scan using users_phone_e164_key`) | No change (already uses automatic `UNIQUE` index) | 0.021 | 4.5% (1.0×) | ✅ |
| **R06** | 0.981 | `chat_members_pkey` scanned 295 pages (`user_id` trailing) | `idx_chat_members_user_chat` (Index Only Scan on leading `user_id`) | 0.104 | 89.4% (9.4×) | ✅ |
| **R07** | 0.117 | Already optimal (`chat_members_pkey` leading `chat_id` + `users_pkey`) | No change | 0.111 | 5.1% (1.1×) | ✅ |
| **R08** | 13.536 | `Parallel Seq Scan` on 501k receipts + `Parallel Seq Scan` on 120k messages | `idx_receipts_undelivered` (1% partial index) + `MATERIALIZED` pending CTE driving join | 2.956 | 78.2% (4.6×) | ✅ |
| **R09** | 8.076 | Must read and sum `size_bytes` across 100% of `media` (27,634 rows) | None kept (`Seq Scan` + `HashAggregate` beats index walk; see §7) | 8.212 | -1.7% (1.0×) | ✅ |
| **R10** | 7.571 | Non-sargable `sent_at::date` predicate + `Seq Scan on messages` | Rewritten to sargable timestamp range + `idx_messages_sent_at_cover` (Index Only Scan) | 1.576 | 79.2% (4.8×) | ✅ |
| **R11** | 3.065 | Non-sargable `EXTRACT(YEAR ...)` + `Seq Scan on calls` | Sargable range `started_at >= '2025-01-01+05:30'` + `idx_calls_missed_chat` + `idx_chat_members_user_chat` | 0.063 | 97.9% (48.7×) | ✅ |
| **R12** | 5.358 | `Seq Scan` on 120k messages to read 5,998 forwarded rows (5%) | Partial index `idx_messages_forwarded (sender_id, sent_at) WHERE is_forwarded = true` | 1.144 | 78.6% (4.7×) | ✅ |
| **R13** | 19.205 | **Wrong result (0 rows)** due to `NOT IN` NULL trap + 2× `Seq Scan` (120k rows) | Fixed to `NOT EXISTS` + `idx_messages_chat_sent` + partial `idx_messages_reply_to` | 0.080 | 99.6% (240.1×) | Fixed (0→7) ✅ |
| **R14** | 6.118 | `Seq Scan on messages` + `Seq Scan on chats` (23k rows) | `idx_messages_sent_at_cover` + partial `idx_chats_group` (Index Only Scans) | 1.924 | 68.6% (3.2×) | ✅ |
| **R15** | 0.025 | Already optimal (`Index Only Scan using blocked_users_pkey`) | No change | 0.024 | 4.0% (1.0×) | ✅ |
| **R16** | 0.061 | Already optimal (`message_receipts_pkey` leading `message_id` + `users_pkey`) | No change | 0.060 | 1.6% (1.0×) | ✅ |
| **R17** | 15.929 | `Parallel Seq Scan` on 501k receipts + 120k messages | `idx_messages_sent_at_cover` narrows `messages` side to 6,593 June rows (receipts still `Seq Scan`) | 15.021 | 5.7% (1.1×) | ✅ |
| **R18** | 14.484 | `Seq Scan` on `users`, `chats`, and `chat_members` | `idx_users_last_seen` + `idx_chats_group` (Index Only Scans; eliminates `Sort` on `users`) | 12.261 | 15.3% (1.2×) | ✅ |
| **R19** | 17003.794 | 2 correlated scalar subqueries × 3,000 groups = 6,000× `Seq Scan on messages` | Rewritten to single-pass `LEFT JOIN` aggregation + `idx_chats_group` | 14.083 | 99.9% (1207.4×) | ✅ |
| **R20** | 43.136 | `Sort Method: external merge Disk: 2392kB` (bad `n_distinct` estimate on `EXTRACT`) | `AT TIME ZONE 'Asia/Kolkata'` rewrite + `idx_messages_hour_type` stats → in-memory `HashAggregate` | 20.781 | 51.8% (2.1×) | ✅ |
| **R21** | 12.254 | Must aggregate edit/delete shares across 100% of `messages` (120k rows) | None kept (`Seq Scan` + `HashAggregate`; see §7) | 11.679 | 4.7% (1.0×) | ✅ |
| **R22** | 8.942 | `Index Scan Backward using messages_pkey` reads & discards 100,000 `OFFSET` rows | Rewritten to keyset pagination (`WHERE message_id < 20001 LIMIT 25`) | 0.026 | 99.7% (343.9×) | ✅ |
| **R23** | 3.216 | `Seq Scan on devices` (42k rows) + in-memory `Sort` (464 kB) | Partial covering index `idx_devices_linked_active` (pre-sorted Index Only Scan) | 0.395 | 87.7% (8.1×) | ✅ |
| **R24** | 6.659 | Must hash-group 100% of `media` (27,634 rows) to detect duplicate `sha256` | None kept (`Seq Scan` + `HashAggregate`; see §7) | 6.415 | 3.7% (1.0×) | ✅ |
| **R25** | 0.060 | Already optimal (recursive PK lookups on `messages_pkey`) | No change | 0.058 | 3.3% (1.0×) | ✅ |
| **W01** | 0.625 | Single-row `INSERT` + FK checks | Maintained 5 indexes on `messages` (`pg_trgm` omitted to keep overhead tiny) | 0.633 | -1.3% (1.0×) | ✅ |
| **W02** | 3.468 | `Seq Scan on messages` (120k rows) to find 34 messages of chat 22556 | `idx_messages_chat_sent` + `idx_receipts_unread_user` (Bitmap Index Scans) | 0.267 | 92.3% (13.0×) | ✅ |
| **W03** | 0.150 | Single-row `UPDATE` by `messages_pkey` | Updates `idx_messages_chat_sent` (`INCLUDE body`) when `body` cleared to `NULL` | 0.181 | -20.7% (0.8×) | ✅ |
| **W04** | 26.061 | Bulk 5,000-row `INSERT` into `message_receipts` + 10k FK checks | Maintains 2 new partial indexes (`idx_receipts_unread_user`, `idx_receipts_undelivered`) | 31.319 | -20.2% (0.8×) | ✅ |
| **W05** | 0.142 | Single-row `UPDATE` by `chat_members_pkey` | Updates `idx_chat_members_user_chat` (`INCLUDE left_at`) | 0.161 | -13.4% (0.9×) | ✅ |
| **Total** | **17265.649** | | | **129.899** | **99.25% (132.9×)** | ✅ |

---

## 3. The Wrong-Result Query: R13 (SQL Three-Valued Logic `NULL` Trap)

### What happened in the original `R13`?
Original query (`queries/workload_30.sql`, solving Problem P6: *"Group admins asked for a list of unanswered questions; the report always comes back empty."*):
```sql
SELECT m.message_id, m.sender_id, m.sent_at, m.body
FROM messages m
WHERE m.chat_id = 20501
  AND m.body LIKE '%?%'
  AND m.message_id NOT IN (SELECT r.reply_to_message_id FROM messages r);
```
* **Baseline Output:** **0 rows** (empty report!).
* **Why SQL returned 0 rows:** In `messages`, **105,090 out of 120,000 rows** (87.6%) are standalone messages where `reply_to_message_id IS NULL`. Because the subquery returns `NULL` alongside real parent IDs, SQL evaluates:
  $$m.\text{message\_id} \neq r_1 \;\land\; m.\text{message\_id} \neq r_2 \;\land\; \dots \;\land\; (m.\text{message\_id} \neq \text{NULL})$$
  In SQL **Three-Valued Logic** (`TRUE`, `FALSE`, `UNKNOWN`), comparing any value to `NULL` with `<>` yields `UNKNOWN`. Since `TRUE AND UNKNOWN` is `UNKNOWN`, and `WHERE` discards `UNKNOWN` rows, `NOT IN` **always returns 0 rows** whenever even a single `NULL` exists in the subquery.

### Fix & Recovered Output
Rewritten query in `sql/06_optimized_queries.sql`:
```sql
SELECT m.message_id, m.sender_id, m.sent_at, m.body
FROM messages m
WHERE m.chat_id = 20501
  AND m.body LIKE '%?%'
  AND NOT EXISTS (
      SELECT 1
      FROM messages r
      WHERE r.reply_to_message_id = m.message_id
  );
```
`NOT EXISTS` tests correlation cleanly (`NULL = m.message_id` is simply `UNKNOWN`, not matching `EXISTS`, so `NOT EXISTS` becomes `TRUE` as intended) and allows PostgreSQL to execute a `Nested Loop Anti Join` using partial index `idx_messages_reply_to`. It recovers all **7 real unanswered questions** in group `20501` (`7523`, `17808`, `49869`, `50134`, `61225`, `102101`, `114900`).

---

## 4. Proof of Result Equivalence

Every query whose SQL changed (and every unchanged read query whose scan order/plan changed) was verified against the baseline `queries/workload_30.sql` using bidirectional `EXCEPT ALL` multiset comparison inside `psql`:

```sql
SELECT
  (SELECT count(*) FROM ((SELECT * FROM (<original>) x) EXCEPT ALL (SELECT * FROM (<optimized>) y)) d1) AS missing_rows,
  (SELECT count(*) FROM ((SELECT * FROM (<optimized>) y) EXCEPT ALL (SELECT * FROM (<original>) x)) d2) AS extra_rows;
```

* **Read Queries (`R01`–`R12`, `R14`–`R25`):** All **24 queries** returned `missing_rows = 0` and `extra_rows = 0` (100% identical rows and multiplicities), plus identical MD5 checksums on all ordered outputs (`R10: 30|a0df3488...`, `R11: 1|f5b0b2c6...`, `R19: 3000|bd258ff2...`, `R20: 144|f2413b87...`, `R22: 25|c95f20ba...`).
* **Query `R13`:** Intentionally fixed from `0` rows (buggy `NOT IN` NULL trap) to `7` rows (`5025b60f83f29cf05fac753ce9bda360`).
* **Write Queries (`W01`–`W05`):** Identical affected row counts verified inside `BEGIN ... ROLLBACK` (`W01: INSERT 0 1`, `W02: UPDATE 14`, `W03: UPDATE 1`, `W04: INSERT 0 5000`, `W05: UPDATE 1`).

---

## 5. Before / After `EXPLAIN (ANALYZE, BUFFERS)` Plans (5 Biggest Improvements)

### 5.1 Query R19 — Group Health Report (`17,003.794 ms` → `14.083 ms`, 1,207.4× faster)
* **Before (Run 1, `17,728.744 ms`, `8,208,179` buffer hits):**
```text
Sort  (cost=18108764.26..18108771.76 rows=3000 width=36) (actual time=17728.140..17728.220 rows=3000.00 loops=1)
  Buffers: shared hit=8208179
  ->  Seq Scan on chats c  (actual time=7.274..17726.961 rows=3000.00 loops=1)
        Filter: ((chat_type)::text = 'GROUP'::text)
        SubPlan 1 -> Aggregate -> Seq Scan on messages m (actual time=0.118..2.800 rows=24.04 loops=3000)
        SubPlan 2 -> Aggregate -> Seq Scan on messages m_1 (actual time=3.017..3.103 rows=1.33 loops=3000)
Execution Time: 17728.744 ms
```
* **After (Run 1, `14.066 ms`, `1,389` buffer hits — 5,909× less buffer I/O):**
```text
Sort  (cost=4419.50..4427.00 rows=3000 width=36) (actual time=13.922..13.972 rows=3000.00 loops=1)
  Buffers: shared hit=1389
  ->  Hash Right Join  (actual time=11.952..13.648 rows=3000.00 loops=1)
        ->  HashAggregate  (actual time=11.672..12.494 rows=21164.00 loops=1)
              ->  Seq Scan on messages m  (actual time=0.004..2.931 rows=120000.00 loops=1)
        ->  Hash  (actual time=0.275..0.275 rows=3000.00 loops=1)
              ->  Index Only Scan using idx_chats_group on chats c  (actual time=0.027..0.136 rows=3000.00 loops=1)
Execution Time: 14.066 ms
```

### 5.2 Query R04 — Message Search (`33.006 ms` → `0.063 ms`, 523.9× faster)
* **Before (Run 1, `33.011 ms`, `1,666` buffer hits):**
```text
Limit  (actual time=32.991..32.992 rows=6.00 loops=1)
  ->  Sort  (actual time=32.990..32.991 rows=6.00 loops=1)
        ->  Hash Join  (actual time=8.263..32.981 rows=6.00 loops=1)
              ->  Seq Scan on messages m  (actual time=0.005..31.599 rows=12935.00 loops=1)
                    Filter: (body ~~* '%meeting%'::text)
              ->  Hash -> Index Only Scan using chat_members_pkey on chat_members cm (actual time=0.337..0.907 rows=4.00 loops=1)
Execution Time: 33.011 ms
```
* **After (Run 1, `0.064 ms`, `20` buffer hits, `Heap Fetches: 0`):**
```text
Limit  (actual time=0.049..0.050 rows=6.00 loops=1)
  Buffers: shared hit=20
  ->  Sort  (actual time=0.049..0.049 rows=6.00 loops=1)
        ->  Nested Loop  (actual time=0.017..0.042 rows=6.00 loops=1)
              ->  Index Only Scan using idx_chat_members_user_chat on chat_members cm  (actual time=0.005..0.005 rows=4.00 loops=1)
                    Heap Fetches: 0
              ->  Index Only Scan using idx_messages_chat_sent on messages m  (actual time=0.005..0.009 rows=1.50 loops=4)
                    Filter: (body ~~* '%meeting%'::text)
                    Heap Fetches: 0
Execution Time: 0.064 ms
```

### 5.3 Query R20 — Hourly Capacity Planning (`43.136 ms` → `20.781 ms`, 2.1× faster)
* **Before (Run 1, `42.786 ms`, `temp read=299 written=300` disk spill):**
```text
GroupAggregate  (actual time=28.443..42.063 rows=144.00 loops=1)
  Buffers: shared hit=1374, temp read=299 written=300
  ->  Sort  (actual time=28.405..35.581 rows=120000.00 loops=1)
        Sort Method: external merge  Disk: 2392kB
        ->  Seq Scan on messages  (actual time=0.011..10.266 rows=120000.00 loops=1)
Execution Time: 42.786 ms
```
* **After (Run 1, `19.946 ms`, `0` disk spill, 40 kB in-memory Parallel HashAggregate):**
```text
Finalize GroupAggregate  (actual time=19.030..19.888 rows=144.00 loops=1)
  Buffers: shared hit=1383
  ->  Gather Merge -> Sort -> Partial HashAggregate (Batches: 1  Memory Usage: 40kB)
        ->  Parallel Seq Scan on messages  (actual time=0.013..12.590 rows=60000.00 loops=2)
Execution Time: 19.946 ms
```

### 5.4 Query R13 — Unanswered Questions (`19.205 ms` → `0.080 ms`, 240.1× faster + Fixed NULL bug)
* **Before (Run 1, `19.104 ms`, `2,736` buffer hits, `rows=0.00`):**
```text
Seq Scan on messages m  (actual time=19.074..19.074 rows=0.00 loops=1)
  Filter: ((body ~~ '%?%'::text) AND (NOT (ANY (message_id = (hashed SubPlan 1).col1))) AND (chat_id = 20501))
  Buffers: shared hit=2736
  SubPlan 1 -> Seq Scan on messages r  (actual time=0.002..4.912 rows=120000.00 loops=1)
Execution Time: 19.104 ms
```
* **After (Run 1, `0.082 ms`, `49` buffer hits, `rows=7.00`):**
```text
Nested Loop Anti Join  (actual time=0.018..0.059 rows=7.00 loops=1)
  Buffers: shared hit=49
  ->  Bitmap Heap Scan on messages m  (actual time=0.014..0.045 rows=9.00 loops=1)
        ->  Bitmap Index Scan on idx_messages_chat_sent  (Index Cond: (chat_id = 20501))
  ->  Index Only Scan using idx_messages_reply_to on messages r  (Heap Fetches: 0, Index Searches: 9)
Execution Time: 0.082 ms
```

### 5.5 Query R01 — Chats Screen (`18.377 ms` → `0.098 ms`, 187.5× faster)
* **Before (Run 1, `22.571 ms`, `5,782` buffer hits):**
```text
Sort -> Nested Loop -> Nested Loop
  -> Index Scan using chat_members_pkey on chat_members cm (Buffers: shared hit=295)
  -> Index Scan using chats_pkey on chats c (Buffers: shared hit=12)
  -> Limit -> Sort -> Seq Scan on messages m (loops=4, Buffers: shared hit=5472)
Execution Time: 22.571 ms
```
* **After (Run 1, `0.092 ms`, `32` buffer hits, `Heap Fetches: 0`):**
```text
Sort -> Nested Loop -> Nested Loop
  -> Index Only Scan using idx_chat_members_user_chat on chat_members cm (Heap Fetches: 0, Buffers: shared hit=4)
  -> Index Scan using chats_pkey on chats c (Buffers: shared hit=12)
  -> Limit -> Index Only Scan using idx_messages_chat_sent on messages m (Heap Fetches: 0, Buffers: shared hit=13)
Execution Time: 0.092 ms
```

*(Also notable: **R22** dropped `8.942 ms → 0.026 ms` [`343.9×`] via keyset pagination, and **R08** dropped `13.536 ms → 2.956 ms` while cutting buffer hits from `35,924` to `3,568` via `MATERIALIZED` CTE + `Memoize`.)*

---

## 6. Write Overhead & Index Storage Analysis

### 6.1 Write Overhead (`W01`–`W05`)
| Write Query | Before (ms) | After (ms) | Delta (ms) | Change | Acceptability Verdict |
|---|---:|---:|---:|---:|---|
| **W01** (Send text message) | 0.625 | 0.633 | +0.008 | +1.3% | **Acceptable:** Only 8 µs extra across 5 `messages` indexes (omitting `pg_trgm` GIN saved ~0.43 ms). |
| **W02** (Mark group read) | 3.468 | 0.267 | -3.201 | **-92.3% (13× faster)** | **Net Win:** Finding messages in group `22556` and unread receipts via indexes dominates update cost. |
| **W03** (Delete for everyone) | 0.150 | 0.181 | +0.031 | +20.7% | **Acceptable:** `0.181 ms` stays 27× faster than the `5 ms` real-time target; updates `idx_messages_chat_sent`. |
| **W04** (Broadcast 5k receipts) | 26.061 | 31.319 | +5.258 | +20.2% | **Acceptable:** ~1 µs per inserted receipt to update `idx_receipts_unread_user` & `idx_receipts_undelivered`; well under `2,000 ms` batch target. |
| **W05** (Leave group) | 0.142 | 0.161 | +0.019 | +13.4% | **Acceptable:** Updating `left_at` updates `idx_chat_members_user_chat`; `0.161 ms` is 31× under `5 ms` target. |

### 6.2 Index Storage (`pg_relation_size`)
Total across all 9 base tables: **59 MB** (`61,440 kB`).  
Total PK/UNIQUE indexes (CP1): **24 MB** · Total new CP3 indexes (12 indexes): **28 MB** · Combined all indexes: **52 MB**.

| Table | Table Size | Index Name | Kind | Index Size | % of Table |
|---|---:|---|---|---:|---:|
| `blocked_users` | 176 kB | `blocked_users_pkey` | PK | 104 kB | 59.1% |
| `calls` | 2,120 kB | `calls_pkey` | PK | 568 kB | 26.8% |
| `calls` | 2,120 kB | `idx_calls_missed_chat` | CP3 | 328 kB | 15.5% |
| `chat_members` | 6,208 kB | `chat_members_pkey` | PK | 2,312 kB | 37.2% |
| `chat_members` | 6,208 kB | `idx_chat_members_user_chat` | CP3 | 3,240 kB | 52.2% |
| `chats` | 1,232 kB | `chats_pkey` | PK | 520 kB | 42.2% |
| `chats` | 1,232 kB | `idx_chats_group` | CP3 | 144 kB | 11.7% |
| `devices` | 2,800 kB | `devices_pkey` | PK | 936 kB | 33.4% |
| `devices` | 2,800 kB | `idx_devices_linked_active` | CP3 | 496 kB | 17.7% |
| `media` | 3,976 kB | `media_pkey` | PK | 624 kB | 15.7% |
| `message_receipts` | 29 MB | `message_receipts_pkey` | PK | 15 MB | 52.9% |
| `message_receipts` | 29 MB | `idx_receipts_unread_user` | CP3 | 4,672 kB | 15.7% |
| `message_receipts` | 29 MB | `idx_receipts_undelivered` | CP3 | 640 kB | 2.1% |
| `messages` | 11 MB | `messages_pkey` | PK | 2,640 kB | 24.1% |
| `messages` | 11 MB | `idx_messages_chat_sent` | CP3 | 7,504 kB | 68.6% |
| `messages` | 11 MB | `idx_messages_sent_at_cover` | CP3 | 5,880 kB | 53.7% |
| `messages` | 11 MB | `idx_messages_hour_type` | CP3 | 3,688 kB | 33.7% |
| `messages` | 11 MB | `idx_messages_reply_to` | CP3 | 344 kB | 3.1% |
| `messages` | 11 MB | `idx_messages_forwarded` | CP3 | 200 kB | 1.8% |
| `users` | 2,736 kB | `users_pkey` | PK | 672 kB | 24.6% |
| `users` | 2,736 kB | `users_phone_e164_key` | UNIQUE | 936 kB | 34.2% |
| `users` | 2,736 kB | `idx_users_last_seen` | CP3 | 1,272 kB | 46.5% |

*(Note: During iterative tuning, we also tested and dropped 4 candidate indexes—`idx_receipts_msg_read` [11 MB], `idx_messages_body_trgm` [3.5 MB], `idx_media_sha256_size` [2.8 MB], and `idx_media_uploader_size` [864 kB]—after `pg_stat_user_indexes` confirmed `idx_scan = 0` on all 4, reclaiming ~18.4 MB and cutting `W01` write penalty from `+71%` to `+1.3%`.)*

---

## 7. Queries We Could Not Speed Up (and Why)

1. **R09 (`8.076 ms` → `8.212 ms`), R24 (`6.659 ms` → `6.415 ms`), R21 (`12.254 ms` → `11.679 ms`):**
   * All three queries compute full-table aggregations (`GROUP BY uploader_id`, `GROUP BY sha256`, `GROUP BY message_type`) touching **100% of rows** in `media` (27,634 rows) or `messages` (120,000 rows).
   * Even with covering indexes (`idx_media_uploader_size`, `idx_media_sha256_size`), PostgreSQL's cost model rightly selects sequential `Seq Scan` + `HashAggregate` rather than walking 100% of an index. Since all three already finish in 6–12 ms (vs. the 5,000 ms reporting target), avoiding extra indexes saves storage and write overhead.
2. **R17 (`15.929 ms` → `15.021 ms`) & R18 (`14.484 ms` → `12.261 ms`):**
   * `R17` joins June messages (~6,593 rows) to ~27,600 read receipts (~5.5% of `message_receipts`). Reading `message_receipts` via `Parallel Seq Scan` (3 workers) still beats 6,593 random index probes on `message_receipts`, even though `idx_messages_sent_at_cover` sped up the `messages` side.
   * `R18` tests `left_at IS NULL` in `chat_members`, which matches **94% of rows** (`98,213 / 104,514`). Because selectivity is 94%, a sequential scan on `chat_members` is optimal; the speedup came from `idx_chats_group` and pre-sorted `idx_users_last_seen`.
3. **R05, R07, R15, R16, R25 (`0.02–0.11 ms`):**
   * Already optimal at baseline via automatic `PRIMARY KEY` and `UNIQUE` B-tree indexes.
