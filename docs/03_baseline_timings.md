# Baseline Timings: Phase 3

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Chats screen: user 965's chats with the time and text of the latest message, newest first | READ | 22.571 | 18.166 | 14.393 | 18.377 |
| R02: Open a chat: the latest 50 messages of group 22556 | READ | 3.727 | 3.585 | 3.206 | 3.506 |
| R03: Badge counts: unread messages per chat for user 965 | READ | 7.924 | 7.498 | 7.692 | 7.705 |
| R04: Search: messages containing "meeting" in any chat user 965 belongs to | READ | 33.011 | 32.827 | 33.181 | 33.006 |
| R05: Registration: is this phone number already on WhatsApp? | READ | 0.022 | 0.022 | 0.021 | 0.022 |
| R06: Contact info: "last seen" of everyone user 965 chats with directly | READ | 1.026 | 0.954 | 0.963 | 0.981 |
| R07: Group info screen: current members of group 22556 with their role | READ | 0.120 | 0.119 | 0.112 | 0.117 |
| R08: Delivery service: receipts still not delivered for messages sent before 23:00 on 30 Jun 2026 | READ | 13.648 | 13.581 | 13.378 | 13.536 |
| R09: Storage team: top 20 users by total media uploaded (GB) | READ | 8.067 | 8.101 | 8.060 | 8.076 |
| R10: Growth: daily active senders in June 2026 | READ | 7.660 | 7.513 | 7.539 | 7.571 |
| R11: Calls tab: missed calls received by user 965 since 1 Jan 2025 | READ | 3.154 | 2.936 | 3.105 | 3.065 |
| R12: Spam detection: users who forwarded 2+ messages on the same day | READ | 5.545 | 5.266 | 5.262 | 5.358 |
| R13: Group admins: questions asked in group 20501 that nobody has replied to | READ | 19.104 | 20.822 | 17.689 | 19.205 |
| R14: Engagement: 10 groups with the most distinct senders in June 2026 | READ | 6.247 | 5.983 | 6.125 | 6.118 |
| R15: Before delivering: has user 3064 blocked user 17793? | READ | 0.029 | 0.020 | 0.025 | 0.025 |
| R16: Message info screen: who has read message 119989 and when | READ | 0.067 | 0.059 | 0.057 | 0.061 |
| R17: Product analytics: average minutes from sending to reading, per message type (June 2026) | READ | 15.828 | 15.854 | 16.105 | 15.929 |
| R18: Clean-up: users not seen since April 2026 who are still in at least one group | READ | 14.076 | 14.324 | 15.052 | 14.484 |
| R19: Group health report: for every group, the last message time and messages in June 2026 | READ | 17728.744 | 17632.714 | 15649.924 | 17003.794 |
| R20: Capacity planning: messages per hour of the day, by message type | READ | 42.786 | 43.694 | 42.929 | 43.136 |
| R21: Product analytics: share of messages edited or deleted, per message type | READ | 12.754 | 11.999 | 12.008 | 12.254 |
| R22: Trust & safety console: all messages, newest first, page 4,001 (25 per page) | READ | 8.840 | 8.814 | 9.171 | 8.942 |
| R23: Security: linked WEB/DESKTOP devices unused since 1 June 2026 (to auto log out) | READ | 3.244 | 3.232 | 3.171 | 3.216 |
| R24: Storage dedup: media files uploaded more than once (same SHA-256) | READ | 6.708 | 6.520 | 6.749 | 6.659 |
| R25: Reply thread: walk up the chain of replies starting at message 119989 | READ | 0.060 | 0.060 | 0.059 | 0.060 |
| W01: Send a text message in group 22556 | WRITE | 0.797 | 0.563 | 0.516 | 0.625 |
| W02: Open chat: mark all of user 965's unread messages in group 22556 as read | WRITE | 3.716 | 3.350 | 3.337 | 3.468 |
| W03: "Delete for everyone" on message 119989 | WRITE | 0.164 | 0.142 | 0.144 | 0.150 |
| W04: Broadcast: create delivery receipts for 5,000 recipients of a business announcement | WRITE | 25.672 | 26.248 | 26.262 | 26.061 |
| W05: User 965 leaves group 20898 | WRITE | 0.160 | 0.135 | 0.132 | 0.142 |
| **Total (sum of all 30)** | | **17995.471** | **17895.101** | **15906.367** | **17265.649** |

---

## Scan Types and Plan Reasons (All 30 Queries)

| Query | Scan Type(s) from Baseline Plan | Why It Is Fast or Slow |
|---|---|---|
| **R01** | `Index Scan using chat_members_pkey` · `Index Scan using chats_pkey` · `Seq Scan on messages` | Slow (18.377 ms): `chat_members_pkey` scans 295 pages because `user_id` is trailing, and lateral `LIMIT 1` performs 4 separate full `Seq Scan`s of 120k `messages`. |
| **R02** | `Seq Scan on messages` | Slow (3.506 ms): No index on `messages(chat_id, sent_at DESC)`, forcing a full scan of 120,000 rows to return 34 rows for group 22556. |
| **R03** | `Seq Scan on message_receipts` · `Index Scan using messages_pkey` | Slow (7.705 ms): `Parallel Seq Scan` reads all 501,590 receipts (3,584 pages) because no index exists on `message_receipts(user_id)`. |
| **R04** | `Seq Scan on messages` · `Index Only Scan using chat_members_pkey` | Slow (33.006 ms): No index on `messages(chat_id)` or `body`, forcing a full scan evaluating `ILIKE '%meeting%'` across 120k rows before hash joining 4 chats. |
| **R05** | `Index Scan using users_phone_e164_key` | Fast (0.022 ms): Point lookup directly uses the automatic `UNIQUE` B-tree index on `users(phone_e164)`. |
| **R06** | `Index Only Scan using chat_members_pkey` · `Index Scan using chats_pkey` · `Index Scan using users_pkey` | Moderate (0.981 ms): Uses PKs on `chats`/`users`, but `me.user_id = 965` reads 295 pages of `chat_members_pkey` because `user_id` is the second key column. |
| **R07** | `Index Scan using chat_members_pkey` · `Index Scan using users_pkey` | Fast (0.117 ms): Filters on leading PK column `chat_id = 22556` in `chat_members_pkey` (22 rows) plus PK lookups into `users`. |
| **R08** | `Seq Scan on messages` · `Seq Scan on message_receipts` | Slow (13.536 ms): `Parallel Seq Scan` reads all 501,590 receipts to find 5,076 NULLs and `Parallel Seq Scan` reads all 120k messages before a Parallel Hash Join. |
| **R09** | `Seq Scan on media` | Moderate (8.076 ms): Must aggregate `size_bytes` across all 27,634 rows of `media` with a full `Seq Scan` + `HashAggregate`. |
| **R10** | `Seq Scan on messages` | Slow (7.571 ms): Non-sargable `sent_at::date` filter plus no `sent_at` index forces a full 120k-row `Seq Scan` to retrieve 6,593 June rows. |
| **R11** | `Index Only Scan using chat_members_pkey` · `Seq Scan on calls` | Slow (3.065 ms): No index on `calls(chat_id)` and non-sargable `EXTRACT(YEAR FROM started_at)` force a full scan of all 25,000 calls. |
| **R12** | `Seq Scan on messages` | Slow (5.358 ms): Full scan of 120,000 messages even though `is_forwarded = true` matches only 5,998 rows (~5%). |
| **R13** | `Seq Scan on messages` (twice) | Slow & Buggy (19.205 ms): Scans all 120k messages twice; `NOT IN` over `reply_to_message_id` (105,090 NULLs) evaluates to `UNKNOWN` and returns 0 rows. |
| **R14** | `Seq Scan on messages` · `Seq Scan on chats` | Slow (6.118 ms): Full scans of 120k messages (no `sent_at` index) and 23k chats (no partial `GROUP` index). |
| **R15** | `Index Only Scan using blocked_users_pkey` | Fast (0.025 ms): Direct B-tree lookup on composite PK `(blocker_id, blocked_id)` with zero heap fetches. |
| **R16** | `Index Scan using message_receipts_pkey` · `Index Scan using users_pkey` | Fast (0.061 ms): Filters on leading PK column `message_id = 119989` in `message_receipts_pkey` (6 rows) plus `users_pkey` lookups. |
| **R17** | `Seq Scan on message_receipts` · `Seq Scan on messages` | Slow (15.929 ms): Full parallel scans of both 501,590 receipts and 120,000 messages before a Hash Join. |
| **R18** | `Seq Scan on chat_members` · `Seq Scan on chats` · `Seq Scan on users` | Slow (14.484 ms): Full scans on all three tables due to missing indexes on `users(last_seen_at)` and `chats(chat_type)` plus active-member join. |
| **R19** | `Seq Scan on chats` · `Seq Scan on messages` (×6,000) | Extremely Slow (17,003.794 ms): Evaluates two correlated subqueries per `GROUP` chat (3,000 groups), executing 6,000 full sequential scans of 120k `messages` (8,208,179 buffer hits). |
| **R20** | `Seq Scan on messages` | Slow (43.136 ms): Full scan of 120k messages plus an external disk merge sort (`Disk: 2392kB`) because `EXTRACT(HOUR FROM sent_at)` has no distinct-value stats. |
| **R21** | `Seq Scan on messages` | Moderate (12.254 ms): Aggregates edit/delete counts across all 120,000 rows via a single `Seq Scan` + `HashAggregate`. |
| **R22** | `Index Scan using messages_pkey` (Backward) | Slow (8.942 ms): Backward scan on `messages_pkey` still reads and discards 100,000 rows (`OFFSET 100000`) before returning 25 rows. |
| **R23** | `Seq Scan on devices` | Slow (3.216 ms): Scans all 42,000 devices and sorts 6,945 stale WEB/DESKTOP rows in memory (`464kB`) due to no partial index on `(last_active_at)`. |
| **R24** | `Seq Scan on media` | Moderate (6.659 ms): Full scan of 27,634 rows + `HashAggregate` (5,393 kB) to group every `sha256` and keep duplicates. |
| **R25** | `Index Scan using messages_pkey` | Fast (0.060 ms): Recursive CTE follows `reply_to_message_id` up 3 hops using direct PK lookups on `messages_pkey`. |
| **W01** | `(no scan)` + FK trigger lookups | Fast (0.625 ms): Single-row `INSERT` with 4 FK validation lookups (`chats_pkey`, `users_pkey`, etc.). |
| **W02** | `Seq Scan on messages` · `Index Scan using message_receipts_pkey` | Slow (3.468 ms): Full scan of 120,000 messages to find the 34 messages of group 22556 before updating 14 unread receipts via PK. |
| **W03** | `Index Scan using messages_pkey` | Fast (0.150 ms): Single-row `UPDATE` located directly via `messages_pkey`. |
| **W04** | `(no scan)` + 5,000×2 FK trigger checks | Moderate (26.061 ms): Bulk `INSERT` of 5,000 rows into `message_receipts`, incurring 5,000 PK conflict checks and 10,000 FK trigger checks. |
| **W05** | `Index Scan using chat_members_pkey` | Fast (0.142 ms): Single-row `UPDATE` located directly via composite PK `(chat_id, user_id)`. |

