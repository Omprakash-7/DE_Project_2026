-- =====================================================================
-- WhatsApp Messaging Database: Phase 5 Table Partitioning (CP4)
-- Team: T0004 | Section: D | Mentor: Omkar
-- Database: PostgreSQL 15+
--
-- DESIGN DECISIONS:
-- 1. Table Chosen: `messages` (grows unboundedly at 20x -> 2.4M rows and
--    100x -> 12M+ rows; `sent_at` physical correlation is ~1.0).
-- 2. Partitioning Strategy: RANGE partitioning by `sent_at` (monthly).
--    - Supports time-window analytics (R10, R14, R17, R19 June filter)
--      via compile-time & runtime partition pruning.
--    - Enables O(1) instant retention/archival (`DETACH` / `DROP TABLE`
--      on expired month partitions) without VACUUM bloat.
-- 3. Primary-Key Rule for Partitioned Tables in PostgreSQL:
--    - Every PRIMARY KEY / UNIQUE constraint on a partitioned table MUST
--      include all partition key columns. Therefore, the PK is
--      `PRIMARY KEY (message_id, sent_at)` rather than `(message_id)` alone.
--    - Note: Because `message_receipts(message_id)` and self-referential
--      `reply_to_message_id` only carry `message_id` (not `sent_at`),
--      this script builds `messages_partitioned` alongside `messages`
--      for safe, non-destructive verification and EXPLAIN pruning proofs.
-- =====================================================================

SET search_path TO whatsapp;

DROP TABLE IF EXISTS messages_partitioned CASCADE;

CREATE TABLE messages_partitioned (
    message_id          BIGINT NOT NULL,
    chat_id             INTEGER NOT NULL REFERENCES chats(chat_id) ON DELETE CASCADE,
    sender_id           INTEGER NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    sent_at             TIMESTAMPTZ NOT NULL,
    message_type        VARCHAR(10) NOT NULL CHECK (message_type IN ('TEXT', 'IMAGE', 'AUDIO', 'VIDEO', 'DOCUMENT', 'LOCATION')),
    body                TEXT,
    media_id            INTEGER REFERENCES media(media_id) ON DELETE SET NULL,
    reply_to_message_id BIGINT,
    is_forwarded        BOOLEAN NOT NULL DEFAULT false,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,
    edited_at           TIMESTAMPTZ,

    PRIMARY KEY (message_id, sent_at),

    CONSTRAINT chk_msg_part_edit_after_sent
        CHECK (edited_at IS NULL OR edited_at >= sent_at),
    CONSTRAINT chk_msg_part_content_deletion
        CHECK (
            (is_deleted = true AND body IS NULL AND media_id IS NULL)
            OR
            (is_deleted = false AND (
                (message_type IN ('TEXT', 'LOCATION') AND media_id IS NULL AND body IS NOT NULL)
                OR
                (message_type IN ('IMAGE', 'AUDIO', 'VIDEO', 'DOCUMENT') AND media_id IS NOT NULL)
            ))
        )
) PARTITION BY RANGE (sent_at);

-- ---------------------------------------------------------------------
-- Monthly Partitions: Jan 2025 through Jul 2026 + DEFAULT safety net
-- ---------------------------------------------------------------------
CREATE TABLE messages_p2025_01 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-02-01 00:00:00+05:30');
CREATE TABLE messages_p2025_02 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-02-01 00:00:00+05:30') TO ('2025-03-01 00:00:00+05:30');
CREATE TABLE messages_p2025_03 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-03-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');
CREATE TABLE messages_p2025_04 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-05-01 00:00:00+05:30');
CREATE TABLE messages_p2025_05 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-05-01 00:00:00+05:30') TO ('2025-06-01 00:00:00+05:30');
CREATE TABLE messages_p2025_06 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-06-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');
CREATE TABLE messages_p2025_07 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-08-01 00:00:00+05:30');
CREATE TABLE messages_p2025_08 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-08-01 00:00:00+05:30') TO ('2025-09-01 00:00:00+05:30');
CREATE TABLE messages_p2025_09 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-09-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');
CREATE TABLE messages_p2025_10 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2025-11-01 00:00:00+05:30');
CREATE TABLE messages_p2025_11 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-11-01 00:00:00+05:30') TO ('2025-12-01 00:00:00+05:30');
CREATE TABLE messages_p2025_12 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-12-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');
CREATE TABLE messages_p2026_01 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-02-01 00:00:00+05:30');
CREATE TABLE messages_p2026_02 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-02-01 00:00:00+05:30') TO ('2026-03-01 00:00:00+05:30');
CREATE TABLE messages_p2026_03 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-03-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');
CREATE TABLE messages_p2026_04 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-05-01 00:00:00+05:30');
CREATE TABLE messages_p2026_05 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-05-01 00:00:00+05:30') TO ('2026-06-01 00:00:00+05:30');
CREATE TABLE messages_p2026_06 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-06-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');
CREATE TABLE messages_p2026_07 PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-08-01 00:00:00+05:30');
CREATE TABLE messages_p_default PARTITION OF messages_partitioned DEFAULT;

-- Local partitioned indexes (automatically propagated to every child partition)
CREATE INDEX idx_msg_part_chat_sent
    ON messages_partitioned (chat_id, sent_at DESC)
    INCLUDE (message_id, body);

CREATE INDEX idx_msg_part_forwarded
    ON messages_partitioned (sender_id, sent_at)
    WHERE is_forwarded = true;

-- Populate partitioned table from messages and refresh statistics
INSERT INTO messages_partitioned
SELECT * FROM messages;

VACUUM ANALYZE messages_partitioned;

-- Verify row counts per partition
SELECT tableoid::regclass AS partition_name, count(*) AS rows_in_partition
FROM messages_partitioned
GROUP BY 1
ORDER BY 1;

-- Demonstrate Partition Pruning (June 2026 daily active senders - R10 style)
-- Only messages_p2026_06 is scanned; the other 19 partitions are pruned at plan time!
EXPLAIN (ANALYZE, BUFFERS)
SELECT sent_at::date AS day, count(DISTINCT sender_id) AS active_senders, count(*) AS messages
FROM messages_partitioned
WHERE sent_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND sent_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
GROUP BY 1
ORDER BY 1;
