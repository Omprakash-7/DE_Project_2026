-- =====================================================================
-- WhatsApp Messaging Database: Data Loading Script (Checkpoint 1)
-- Team: T0004 | Section: D | Mentor: Omkar
-- Database: PostgreSQL 15+
--
-- TOPOLOGICAL LOAD ORDER (satisfying all foreign key dependencies):
--  1. users            (Independent root table)
--  2. devices          (Depends on users)
--  3. chats            (Depends on users via created_by)
--  4. chat_members     (Depends on chats and users)
--  5. media            (Depends on users via uploader_id)
--  6. messages         (Depends on chats, users, media, and self-referencing messages)
--  7. message_receipts (Depends on messages and users)
--  8. calls            (Depends on chats and users via caller_id)
--  9. blocked_users    (Depends on users via blocker_id and blocked_id)
-- =====================================================================

SET search_path TO whatsapp;

-- Step 1: Ingest seed data via psql client \copy
\echo 'Loading users...'
\copy users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading devices...'
\copy devices FROM 'seed_data/devices.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading chats...'
\copy chats FROM 'seed_data/chats.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading chat_members...'
\copy chat_members FROM 'seed_data/chat_members.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading media...'
\copy media FROM 'seed_data/media.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading messages...'
\copy messages FROM 'seed_data/messages.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading message_receipts...'
\copy message_receipts FROM 'seed_data/message_receipts.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading calls...'
\copy calls FROM 'seed_data/calls.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading blocked_users...'
\copy blocked_users FROM 'seed_data/blocked_users.csv' WITH (FORMAT csv, HEADER true);

-- Step 2: Refresh database optimizer statistics
\echo 'Analyzing database statistics...'
ANALYZE;

-- Step 3: Automated Row Count Verification
\echo '=================================================='
\echo 'Verifying Loaded Row Counts vs Expected Row Counts'
\echo '=================================================='

WITH expected(table_name, expected_count) AS (
    VALUES
        ('users',            30000::bigint),
        ('devices',          42000::bigint),
        ('chats',            23000::bigint),
        ('chat_members',     104514::bigint),
        ('media',            27634::bigint),
        ('messages',         120000::bigint),
        ('message_receipts', 501590::bigint),
        ('calls',            25000::bigint),
        ('blocked_users',    4000::bigint)
),
actual(table_name, actual_count) AS (
    SELECT 'users', count(*) FROM users UNION ALL
    SELECT 'devices', count(*) FROM devices UNION ALL
    SELECT 'chats', count(*) FROM chats UNION ALL
    SELECT 'chat_members', count(*) FROM chat_members UNION ALL
    SELECT 'media', count(*) FROM media UNION ALL
    SELECT 'messages', count(*) FROM messages UNION ALL
    SELECT 'message_receipts', count(*) FROM message_receipts UNION ALL
    SELECT 'calls', count(*) FROM calls UNION ALL
    SELECT 'blocked_users', count(*) FROM blocked_users
)
SELECT
    e.table_name,
    e.expected_count,
    a.actual_count,
    CASE WHEN e.expected_count = a.actual_count THEN 'PASS (Exact Match)' ELSE 'FAIL (Mismatch)' END AS status
FROM expected e
JOIN actual a ON a.table_name = e.table_name
ORDER BY e.table_name;
