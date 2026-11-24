# Phase 4 Optimization Report: WhatsApp Messaging Database (CP3)
**Team:** T0004 | **Section:** D | **Mentor:** Omkar
**Repository:** [DE_Project_2026](https://github.com/Omprakash-7/DE_Project_2026)
**Database:** PostgreSQL 18.4 (Postgres.app) | **Workload:** baseline values are from the CP2 three-run benchmark; optimized values are averages of five runs (`sql/06_optimized_queries.sql`).

> **Run-count note:** the baseline and optimized averages use different sample counts (3 vs. 5), because the CP2 baseline artifacts were retained and the CP3 workload was measured for five runs. Compare the reported averages as indicative timings; the run counts are not matched.

---

## 1. Executive Summary
* **Total Baseline Time (30 queries):** `17,265.649 ms` (~17.27 seconds)
* **Total Optimized Time (30 queries):** `148.001 ms` (~0.15 seconds)
* **Overall Improvement:** **99.14% reduction (`116.7×` faster overall)**
* **Biggest Single Improvement:** Query **R19** dropped from **17,003.794 ms → 14.740 ms** (`99.91%` / `1,153.6×` faster).
* **Correctness Bug Fixed:** Query **R13** previously returned **0 rows** due to a SQL three-valued logic `NULL` trap in `NOT IN`; rewriting to `NOT EXISTS` recovers all **7 real unanswered questions** while running `34.6×` faster (`19.205 ms → 0.555 ms`, and `< 0.1 ms` warm).

---

## 2. Optimization Summary Table (All 30 Queries)

> Note: `Improvement % = (Before - After) / Before × 100`. Negative percentages on fast PK lookups or write queries reflect minor cold-cache variance and expected index-maintenance overhead. Baseline values use three runs; optimized values use five.

| Query | Before (ms) | Problem Found in Baseline Plan | Optimization Applied | After (ms) | Improvement | Same Result? |
|---|---:|---|---|---:|---:|:---:|
| **R01** | 18.377 | `chat_members_pkey` scanned 295 pages (`user_id` trailing); 4× `Seq Scan on messages` | `idx_chat_members_user_chat` + `idx_messages_chat_sent` (Index Only Scans) | 0.570 | 96.9% (32.2×) | ✅ |
| **R02** | 3.506 | `Seq Scan on messages` (120k rows) + sort | `idx_messages_chat_sent` (`chat_id, sent_at DESC`) | 0.665 | 81.0% (5.3×) | ✅ |
| **R03** | 7.705 | `Parallel Seq Scan` across all 501,590 `message_receipts` | Partial covering index `idx_receipts_unread_user (user_id, message_id) WHERE read_at IS NULL` | 0.816 | 89.4% (9.4×) | ✅ |
| **R04** | 33.006 | `Seq Scan on messages` checking `ILIKE` on 120k rows before join | `idx_chat_members_user_chat` + `idx_messages_chat_sent` (`INCLUDE body`, Index Only Scan) | 0.077 | 99.8% (428.6×) | ✅ |
| **R05** | 0.022 | Already optimal (`Index Scan using users_phone_e164_key`) | No change (already uses automatic `UNIQUE` index) | 0.114 | -418.2% (0.2×) | ✅ |
| **R06** | 0.981 | `chat_members_pkey` scanned 295 pages (`user_id` trailing) | `idx_chat_members_user_chat` (Index Only Scan on leading `user_id`) | 0.283 | 71.2% (3.5×) | ✅ |
| **R07** | 0.117 | Already optimal (`chat_members_pkey` leading `chat_id` + `users_pkey`) | No change | 0.740 | -532.5% (0.2×) | ✅ |
| **R08** | 13.536 | `Parallel Seq Scan` on 501k receipts + `Parallel Seq Scan` on 120k messages | `idx_messages_sent_at_cover` (`LIMIT 500` early exit) + 1% partial `idx_receipts_undelivered` | 6.680 | 50.7% (2.0×) | ✅ |
| **R09** | 8.076 | Must read and sum `size_bytes` across 100% of `media` (27,634 rows) | None kept (`Seq Scan` + `HashAggregate` beats index walk; see §7) | 10.444 | -29.3% (0.8×) | ✅ |
| **R10** | 7.571 | Non-sargable `sent_at::date` predicate + `Seq Scan on messages` | Rewritten to sargable timestamp range + `idx_messages_sent_at_cover` (Index Only Scan) | 1.672 | 77.9% (4.5×) | ✅ |
| **R11** | 3.065 | Non-sargable `EXTRACT(YEAR ...)` + `Seq Scan on calls` | Sargable range `started_at >= '2025-01-01+05:30'` + `idx_calls_missed_chat` + `idx_chat_members_user_chat` | 0.163 | 94.7% (18.8×) | ✅ |
| **R12** | 5.358 | `Seq Scan` on 120k messages to read 5,998 forwarded rows (5%) | Partial index `idx_messages_forwarded (sender_id, sent_at) WHERE is_forwarded = true` | 1.245 | 76.8% (4.3×) | ✅ |
| **R13** | 19.205 | **Wrong result (0 rows)** due to `NOT IN` NULL trap + 2× `Seq Scan` (120k rows) | Fixed to `NOT EXISTS` + `idx_messages_chat_sent` + partial `idx_messages_reply_to` | 0.555 | 97.1% (34.6×) | Fixed (0→7) ✅ |
| **R14** | 6.118 | `Seq Scan on messages` + `Seq Scan on chats` (23k rows) | `idx_messages_sent_at_cover` + partial `idx_chats_group` (Index Only Scans) | 2.189 | 64.2% (2.8×) | ✅ |
| **R15** | 0.025 | Already optimal (`Index Only Scan using blocked_users_pkey`) | No change | 0.051 | -104.0% (0.5×) | ✅ |
| **R16** | 0.061 | Already optimal (`message_receipts_pkey` leading `message_id` + `users_pkey`) | No change | 0.330 | -441.0% (0.2×) | ✅ |
| **R17** | 15.929 | `Parallel Seq Scan` on 501k receipts + 120k messages | `idx_messages_sent_at_cover` narrows `messages` side to 6,593 June rows (receipts still `Seq Scan`) | 18.498 | -16.1% (0.9×) | ✅ |
| **R18** | 14.484 | `Seq Scan` on `users`, `chats`, and `chat_members` | `idx_users_last_seen` + `idx_chats_group` (Index Only Scans; eliminates `Sort` on `users`) | 13.436 | 7.2% (1.1×) | ✅ |
| **R19** | 17003.794 | 2 correlated scalar subqueries × 3,000 groups = 6,000× `Seq Scan on messages` | Rewritten to single-pass `LEFT JOIN` aggregation + `idx_chats_group` | 14.740 | 99.9% (1153.6×) | ✅ |
| **R20** | 43.136 | `Sort Method: external merge Disk: 2392kB` (bad `n_distinct` estimate on `EXTRACT`) | `AT TIME ZONE 'Asia/Kolkata'` rewrite + `idx_messages_hour_type` stats → in-memory `HashAggregate` | 20.205 | 53.2% (2.1×) | ✅ |
| **R21** | 12.254 | Must aggregate edit/delete shares across 100% of `messages` (120k rows) | None kept (`Seq Scan` + `HashAggregate`; see §7) | 12.128 | 1.0% (1.0×) | ✅ |
| **R22** | 8.942 | `Index Scan Backward using messages_pkey` reads & discards 100,000 `OFFSET` rows | Rewritten to keyset pagination (`WHERE message_id < 20001 LIMIT 25`) | 0.062 | 99.3% (144.2×) | ✅ |
| **R23** | 3.216 | `Seq Scan on devices` (42k rows) + in-memory `Sort` (464 kB) | Partial covering index `idx_devices_linked_active` (pre-sorted Index Only Scan) | 0.512 | 84.1% (6.3×) | ✅ |
| **R24** | 6.659 | Must hash-group 100% of `media` (27,634 rows) to detect duplicate `sha256` | None kept (`Seq Scan` + `HashAggregate`; see §7) | 6.453 | 3.1% (1.0×) | ✅ |
| **R25** | 0.060 | Already optimal (recursive PK lookups on `messages_pkey`) | No change | 0.107 | -78.3% (0.6×) | ✅ |
| **W01** | 0.625 | Single-row `INSERT` + FK checks | Maintained 5 indexes on `messages` (`pg_trgm` omitted to keep overhead low) | 0.837 | -33.9% (0.7×) | ✅ |
| **W02** | 3.468 | `Seq Scan on messages` (120k rows) to find 34 messages of chat 22556 | `idx_messages_chat_sent` + `idx_receipts_unread_user` (Bitmap Index Scans) | 0.866 | 75.0% (4.0×) | ✅ |
| **W03** | 0.150 | Single-row `UPDATE` by `messages_pkey` | Updates `idx_messages_chat_sent` (`INCLUDE body`) when `body` cleared to `NULL` | 0.298 | -98.7% (0.5×) | ✅ |
| **W04** | 26.061 | Bulk 5,000-row `INSERT` into `message_receipts` + 10k FK checks | Maintains 2 new partial indexes (`idx_receipts_unread_user`, `idx_receipts_undelivered`) | 33.041 | -26.8% (0.8×) | ✅ |
| **W05** | 0.142 | Single-row `UPDATE` by `chat_members_pkey` | Updates `idx_chat_members_user_chat` (`INCLUDE left_at`) | 0.224 | -57.7% (0.6×) | ✅ |
| **Total** | **17265.649** | | | **148.001** | **99.14% (116.7×)** | ✅ |

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

**Time-zone assumption for R10/R11/R20:** the seed timestamps carry `+05:30` offsets, while the baseline `sent_at::date` and `EXTRACT(YEAR FROM started_at)` depend on the PostgreSQL session time zone. The optimized R10/R11 bounds encode `+05:30`, and R20 groups by the explicit `Asia/Kolkata` wall-clock hour. Their equivalence to the baseline date/year buckets therefore assumes an `Asia/Kolkata` baseline session. The captured benchmark files do not record `SET TIME ZONE`, so future comparisons should set it explicitly; production queries should follow the product's documented time-zone contract.

Every query whose SQL changed (and every unchanged read query) was verified against the baseline `queries/workload_30.sql` using bidirectional `EXCEPT ALL` multiset comparison inside `psql`:

```sql
SELECT
  (SELECT count(*) FROM ((SELECT * FROM (<original>) x) EXCEPT ALL (SELECT * FROM (<optimized>) y)) d1) AS missing_rows,
  (SELECT count(*) FROM ((SELECT * FROM (<optimized>) y) EXCEPT ALL (SELECT * FROM (<original>) x)) d2) AS extra_rows;
```

* **Read Queries (`R01`–`R12`, `R14`–`R25`):** All **24 queries** returned `missing_rows = 0` and `extra_rows = 0` (100% identical rows and multiplicities), plus identical MD5 checksums on ordered outputs (`R10: 30|a0df3488...`, `R11: 1|f5b0b2c6...`, `R19: 3000|bd258ff2...`, `R20: 144|f2413b87...`, `R22: 25|c95f20ba...`).
* **Query `R13`:** Intentionally fixed from `0` rows (buggy `NOT IN` NULL trap) to `7` rows (`5025b60f83f29cf05fac753ce9bda360`).
* **Write Queries (`W01`–`W05`):** Identical affected row counts verified inside `BEGIN ... ROLLBACK` (`W01: INSERT 0 1`, `W02: UPDATE 14`, `W03: UPDATE 1`, `W04: INSERT 0 5000`, `W05: UPDATE 1`).

---

## 5. Before / After `EXPLAIN (ANALYZE, BUFFERS)` Plans (5 Biggest Improvements)

### 5.1 Query R19 — Group Health Report (`17,003.794 ms` → `14.740 ms`, 1,153.6× faster)
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
* **After (Run 1, `16.091 ms`, `1,389` total buffers — 5,909× less buffer I/O):**
```text
Sort  (cost=4419.50..4427.00 rows=3000 width=36) (actual time=16.010..16.061 rows=3000.00 loops=1)
  Buffers: shared hit=83 read=1306
  ->  Hash Right Join  (actual time=13.914..15.728 rows=3000.00 loops=1)
        ->  HashAggregate -> Seq Scan on messages m  (rows=120000.00)
        ->  Hash -> Index Only Scan using idx_chats_group on chats c  (rows=3000.00)
Execution Time: 16.091 ms
```

### 5.2 Query R04 — Message Search (`33.006 ms` → `0.077 ms`, 428.6× faster)
* **Before (Run 1, `33.011 ms`, `1,666` buffer hits):**
```text
Limit -> Sort -> Hash Join  (actual time=8.263..32.981 rows=6.00 loops=1)
  ->  Seq Scan on messages m  (actual time=0.005..31.599 rows=12935.00 loops=1)
        Filter: (body ~~* '%meeting%'::text)
  ->  Hash -> Index Only Scan using chat_members_pkey on chat_members cm (actual time=0.337..0.907 rows=4.00 loops=1)
Execution Time: 33.011 ms
```
* **After (Run 1, `0.131 ms`, `21` buffer hits):**
```text
Limit -> Sort -> Nested Loop  (actual time=0.044..0.102 rows=6.00 loops=1)
  Buffers: shared hit=21
  ->  Index Only Scan using idx_chat_members_user_chat on chat_members cm  (rows=4.00)
  ->  Index Only Scan using idx_messages_chat_sent on messages m  (Filter: body ~~* '%meeting%', Heap Fetches: 0)
Execution Time: 0.131 ms
```

### 5.3 Query R20 — Hourly Capacity Planning (`43.136 ms` → `20.205 ms`, 2.1× faster)
* **Before (Run 1, `42.786 ms`, `temp read=299 written=300` disk spill):**
```text
GroupAggregate  (actual time=28.443..42.063 rows=144.00 loops=1)
  Buffers: shared hit=1374, temp read=299 written=300
  ->  Sort  (Sort Method: external merge  Disk: 2392kB)
        ->  Seq Scan on messages  (actual time=0.011..10.266 rows=120000.00 loops=1)
Execution Time: 42.786 ms
```
* **After (Run 1, `19.876 ms`, `0` disk spill, 40 kB in-memory Parallel HashAggregate):**
```text
Finalize GroupAggregate  (actual time=19.010..19.830 rows=144.00 loops=1)
  Buffers: shared hit=1383
  ->  Gather Merge -> Sort -> Partial HashAggregate (Batches: 1  Memory Usage: 40kB)
        ->  Parallel Seq Scan on messages  (actual time=0.013..12.744 rows=60000.00 loops=2)
Execution Time: 19.876 ms
```

### 5.4 Query R13 — Unanswered Questions (`19.205 ms` → `0.555 ms`, 34.6× faster + Fixed NULL bug)
* **Before (Run 1, `19.104 ms`, `2,736` buffer hits, `rows=0.00`):**
```text
Seq Scan on messages m  (actual time=19.074..19.074 rows=0.00 loops=1)
  Filter: ((body ~~ '%?%'::text) AND (NOT (ANY (message_id = (hashed SubPlan 1).col1))) AND (chat_id = 20501))
  SubPlan 1 -> Seq Scan on messages r  (actual time=0.002..4.912 rows=120000.00 loops=1)
Execution Time: 19.104 ms
```
* **After (Run 1, `2.480 ms` cold / `~0.08 ms` warm, `49` buffer hits, `rows=7.00`):**
```text
Nested Loop Anti Join  (actual time=0.847..2.455 rows=7.00 loops=1)
  Buffers: shared hit=14 read=35
  ->  Bitmap Heap Scan on messages m -> Bitmap Index Scan on idx_messages_chat_sent (Index Cond: (chat_id = 20501))
  ->  Index Only Scan using idx_messages_reply_to on messages r (Heap Fetches: 0, Index Searches: 9)
Execution Time: 2.480 ms
```

### 5.5 Query R01 — Chats Screen (`18.377 ms` → `0.570 ms`, 32.2× faster)
* **Before (Run 1, `22.571 ms`, `5,782` buffer hits):**
```text
Sort -> Nested Loop -> Nested Loop
  -> Index Scan using chat_members_pkey on chat_members cm (Buffers: shared hit=295)
  -> Index Scan using chats_pkey on chats c (Buffers: shared hit=12)
  -> Limit -> Sort -> Seq Scan on messages m (loops=4, Buffers: shared hit=5472)
Execution Time: 22.571 ms
```
* **After (Run 1, `2.410 ms` cold / `~0.1 ms` warm, `35` buffers):**
```text
Sort -> Nested Loop -> Nested Loop
  -> Index Only Scan using idx_chat_members_user_chat on chat_members cm (Buffers: shared hit=2 read=4)
  -> Index Scan using chats_pkey on chats c (Buffers: shared hit=4 read=8)
  -> Limit -> Index Only Scan using idx_messages_chat_sent on messages m (Buffers: shared hit=6 read=8)
Execution Time: 2.410 ms
```

*(Also notable: **R22** dropped `8.942 ms → 0.062 ms` [`144.2×`] via keyset pagination, and **R08** dropped `13.536 ms → 6.680 ms` via `idx_messages_sent_at_cover` + `idx_receipts_undelivered` while keeping `O(1)` latency at 20× scale.)*

---

## 6. Write Overhead & Index Storage Analysis

### 6.1 Write Overhead (`W01`–`W05`)
| Write Query | Before (ms) | After (ms) | Delta (ms) | Change | Acceptability Verdict |
|---|---:|---:|---:|---:|---|
| **W01** (Send text message) | 0.625 | 0.837 | +0.212 | +33.9% | **Acceptable:** `0.837 ms` stays 6× under the `5 ms` real-time target across 5 `messages` indexes. |
| **W02** (Mark group read) | 3.468 | 0.866 | -2.602 | **-75.0% (4× faster)** | **Net Win:** Finding messages in group `22556` and unread receipts via indexes dominates update cost. |
| **W03** (Delete for everyone) | 0.150 | 0.298 | +0.148 | +98.7% | **Acceptable:** `0.298 ms` stays 16× under the `5 ms` real-time target; updates `idx_messages_chat_sent`. |
| **W04** (Broadcast 5k receipts) | 26.061 | 33.041 | +6.980 | +26.8% | **Acceptable:** ~1.4 µs per inserted receipt to update `idx_receipts_unread_user` & `idx_receipts_undelivered`; well under `2,000 ms` batch target. |
| **W05** (Leave group) | 0.142 | 0.224 | +0.082 | +57.7% | **Acceptable:** Updating `left_at` updates `idx_chat_members_user_chat`; `0.224 ms` is 22× under `5 ms` target. |

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

*(Note: During iterative tuning, we also tested and dropped 4 candidate indexes—`idx_receipts_msg_read` [11 MB], `idx_messages_body_trgm` [3.5 MB], `idx_media_sha256_size` [2.8 MB], and `idx_media_uploader_size` [864 kB]—after `pg_stat_user_indexes` confirmed `idx_scan = 0` on all 4, reclaiming ~18.4 MB and protecting write speed on `W01`/`W03`.)*

---

## 7. Queries We Could Not Speed Up (and Why)

1. **R09 (`8.076 ms` → `10.444 ms`), R24 (`6.659 ms` → `6.453 ms`), R21 (`12.254 ms` → `12.128 ms`):**
   * All three queries compute full-table aggregations (`GROUP BY uploader_id`, `GROUP BY sha256`, `GROUP BY message_type`) touching **100% of rows** in `media` (27,634 rows) or `messages` (120,000 rows).
   * Even with covering indexes (`idx_media_uploader_size`, `idx_media_sha256_size`), PostgreSQL's cost model rightly selects sequential `Seq Scan` + `HashAggregate` rather than walking 100% of an index. Since all three already finish in 6–12 ms (vs. the 5,000 ms reporting target), avoiding extra indexes saves storage and write overhead.
2. **R17 (`15.929 ms` → `18.498 ms`) & R18 (`14.484 ms` → `13.436 ms`):**
   * `R17` joins June messages (~6,593 rows) to ~27,600 read receipts (~5.5% of `message_receipts`). Reading `message_receipts` via `Parallel Seq Scan` (3 workers) beats 6,593 random index probes on `message_receipts`, even though `idx_messages_sent_at_cover` sped up the `messages` side.
   * `R18` tests `left_at IS NULL` in `chat_members`, which matches **94% of rows** (`98,213 / 104,514`). Because selectivity is 94%, a sequential scan on `chat_members` is optimal; `idx_chats_group` and `idx_users_last_seen` trimmed the join and sort sides.
3. **R05, R07, R15, R16, R25 (`0.02–0.11 ms` baseline):**
   * Already optimal at baseline via automatic `PRIMARY KEY` and `UNIQUE` B-tree indexes (5-run averages reflect minor first-run cold buffer reads after loading `large_data`).
