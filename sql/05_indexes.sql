-- =====================================================================
-- WhatsApp Messaging Database: Phase 4 Optimization Indexes (CP3)
-- Team: T0004 | Section: D | Mentor: Omkar
-- Database: PostgreSQL 15+
--
-- DESIGN PRINCIPLES:
-- 1. Column order in composite B-trees: equality predicates first,
--    range/sort columns second, non-filtered SELECT columns in INCLUDE
--    to enable Index Only Scans without bloating B-tree search keys.
-- 2. Partial indexes (WHERE ...) shrink index size and write overhead
--    when queries consistently filter a selective subset of rows.
-- 3. Every index is verified active (idx_scan > 0). Unused indexes
--    (e.g. GIN on body or covering indexes on full-table scans R09/R24)
--    were dropped after empirical profiling to avoid wasted storage and
--    write amplification on W01/W03/W04.
-- =====================================================================

SET search_path TO whatsapp;

-- ---------------------------------------------------------------------
-- 1. chat_members: Covering index keyed on user_id first
--    Serves: R01, R04, R06, R11, R18
--    Why: PK is (chat_id, user_id), so lookups by user_id had to scan
--    many index pages (~295 buffers). Putting (user_id, chat_id) first
--    with INCLUDE (left_at) gives single-probe Index Only Scans.
-- ---------------------------------------------------------------------
CREATE INDEX idx_chat_members_user_chat
    ON chat_members (user_id, chat_id)
    INCLUDE (left_at);

-- ---------------------------------------------------------------------
-- 2. chats: Partial covering index for GROUP chats only
--    Serves: R14, R18, R19
--    Why: Only 3,000 of 23,000 chats (13%) are GROUP chats. Filtering
--    on chat_type = 'GROUP' avoids scanning the 20,000 DIRECT chats
--    and INCLUDE (group_name) enables Index Only Scans.
-- ---------------------------------------------------------------------
CREATE INDEX idx_chats_group
    ON chats (chat_id)
    INCLUDE (group_name)
    WHERE chat_type = 'GROUP';

-- ---------------------------------------------------------------------
-- 3. messages: Composite covering index by (chat_id, sent_at DESC)
--    Serves: R01, R02, R04, R13, W02
--    Why: Equality on chat_id followed by DESC sort on sent_at lets R01
--    (LIMIT 1) and R02 (LIMIT 50) stop immediately via Index Only /
--    Bitmap Index Scan without sorting 120k rows. INCLUDE (message_id,
--    body) makes R01 and R04 Index Only Scans.
-- ---------------------------------------------------------------------
CREATE INDEX idx_messages_chat_sent
    ON messages (chat_id, sent_at DESC)
    INCLUDE (message_id, body);

-- ---------------------------------------------------------------------
-- 4. messages: Covering B-tree index on sent_at for time-range analytics
--    Serves: R10, R14, R17
--    Why: Supports sargable range queries on June 2026 (5.5% of rows)
--    with INCLUDE (message_id, chat_id, sender_id, message_type) so
--    analytics avoid reading wide heap rows.
-- ---------------------------------------------------------------------
CREATE INDEX idx_messages_sent_at_cover
    ON messages (sent_at)
    INCLUDE (message_id, chat_id, sender_id, message_type);

-- ---------------------------------------------------------------------
-- 5. messages: Partial covering index for forwarded messages
--    Serves: R12 (Spam detection)
--    Why: Only ~5% of messages (5,998 / 120,000) have is_forwarded = true.
--    Keying on (sender_id, sent_at) lets R12 Index Only Scan 5% of rows.
-- ---------------------------------------------------------------------
CREATE INDEX idx_messages_forwarded
    ON messages (sender_id, sent_at)
    WHERE is_forwarded = true;

-- ---------------------------------------------------------------------
-- 6. messages: Partial index on reply_to_message_id
--    Serves: R13 (Unanswered questions anti-join), FK delete checks
--    Why: 87.6% of messages are NOT replies (reply_to_message_id IS NULL).
--    Indexing only non-NULL pointers cuts index size by ~88% and speeds
--    up NOT EXISTS anti-joins.
-- ---------------------------------------------------------------------
CREATE INDEX idx_messages_reply_to
    ON messages (reply_to_message_id)
    WHERE reply_to_message_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- 7. messages: Expression index for hourly capacity planning
--    Serves: R20
--    Why: EXTRACT(HOUR FROM sent_at AT TIME ZONE 'Asia/Kolkata') is
--    immutable and gives the planner exact distinct-hour statistics (24
--    buckets instead of 120k estimate), switching R20 from an external
--    2.4 MB disk sort to an in-memory 40 kB HashAggregate.
-- ---------------------------------------------------------------------
CREATE INDEX idx_messages_hour_type
    ON messages ((EXTRACT(HOUR FROM sent_at AT TIME ZONE 'Asia/Kolkata')), message_type);

-- ---------------------------------------------------------------------
-- 8. message_receipts: Partial index for unread receipts per user
--    Serves: R03 (Badge counts), W02 (Mark chat read)
--    Why: Only ~25.8% of receipts have read_at IS NULL. Keying by
--    (user_id, message_id) turns R03 from a 501k-row Parallel Seq Scan
--    into a tiny Index Only Scan for user 965's unread receipts.
-- ---------------------------------------------------------------------
CREATE INDEX idx_receipts_unread_user
    ON message_receipts (user_id, message_id)
    WHERE read_at IS NULL;

-- ---------------------------------------------------------------------
-- 9. message_receipts: Partial index for undelivered receipts
--    Serves: R08 (Pending delivery queue)
--    Why: Only ~1.0% of receipts (5,076 / 501,590) have delivered_at
--    IS NULL. Allows R08 to inspect only pending rows via Index Only Scan.
-- ---------------------------------------------------------------------
CREATE INDEX idx_receipts_undelivered
    ON message_receipts (message_id, user_id)
    WHERE delivered_at IS NULL;

-- ---------------------------------------------------------------------
-- 10. calls: Partial covering index for missed calls by chat
--     Serves: R11 (Calls tab)
--     Why: Only ~25.3% of calls have status = 'MISSED'. Equality on
--     chat_id + DESC sort on started_at with INCLUDE columns delivers
--     an Index Only Scan already in sorted order.
-- ---------------------------------------------------------------------
CREATE INDEX idx_calls_missed_chat
    ON calls (chat_id, started_at DESC)
    INCLUDE (call_id, caller_id, call_type)
    WHERE status = 'MISSED';

-- ---------------------------------------------------------------------
-- 11. devices: Partial covering index for stale linked sessions
--     Serves: R23 (Security cleanup)
--     Why: Only 28.6% of devices are WEB/DESKTOP. Ordering by
--     last_active_at lets R23 read stale sessions via Index Only Scan
--     with zero sort overhead.
-- ---------------------------------------------------------------------
CREATE INDEX idx_devices_linked_active
    ON devices (last_active_at)
    INCLUDE (device_id, user_id, device_type)
    WHERE device_type IN ('WEB', 'DESKTOP');

-- ---------------------------------------------------------------------
-- 12. users: Partial covering index on last_seen_at
--     Serves: R18 (Inactive users cleanup)
--     Why: Pre-sorts non-NULL last_seen_at values and includes
--     (user_id, display_name) for an Index Only Scan without sorting.
-- ---------------------------------------------------------------------
CREATE INDEX idx_users_last_seen
    ON users (last_seen_at)
    INCLUDE (user_id, display_name)
    WHERE last_seen_at IS NOT NULL;

-- Populate visibility maps (for Index Only Scans) and planner statistics
VACUUM ANALYZE;
