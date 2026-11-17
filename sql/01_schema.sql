-- =====================================================================
-- WhatsApp Messaging Database: Production Schema (Checkpoint 1)
-- Team: T0004 | Section: D | Mentor: Omkar
-- Database: PostgreSQL 15+
--
-- DESIGN RULES & CONSTRAINTS ENFORCEMENT:
-- 1. All entities exist within schema 'whatsapp'.
-- 2. Strictly constrained types: INTEGER/BIGINT IDs, VARCHAR(16) phone,
--    TIMESTAMPTZ for timestamps with timezone offsets, DATE for joined_on,
--    CHAR(64) for SHA-256 hashes, BIGINT for byte sizes, TEXT for free-form bodies.
-- 3. Constraints ONLY: PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL, CHECK.
--    No manual indexes are created here to ensure clean Phase 3 baseline timings.
-- 4. media.sha256 is explicitly NOT UNIQUE (seed data contains 3,215 duplicates;
--    Query R24 explicitly groups by sha256 to find duplicate media).
-- 5. Foreign Key ON DELETE policies are carefully chosen and commented for viva defense.
-- 6. All CHECK constraints are validated against 100% of real production seed rows.
-- =====================================================================

DROP SCHEMA IF EXISTS whatsapp CASCADE;
CREATE SCHEMA whatsapp;
SET search_path TO whatsapp;

-- =====================================================================
-- TABLE 1: users
-- Core registered WhatsApp identity table.
-- =====================================================================
CREATE TABLE users (
    user_id      INTEGER PRIMARY KEY,
    phone_e164   VARCHAR(16) NOT NULL UNIQUE,
    display_name VARCHAR(100) NOT NULL,
    about        TEXT,
    is_business  BOOLEAN NOT NULL DEFAULT false,
    joined_on    DATE NOT NULL,
    last_seen_at TIMESTAMPTZ,
    status       VARCHAR(10) NOT NULL,

    -- CONSTRAINT 1: Valid E.164 international phone number format (+ followed by 8 to 15 digits)
    CONSTRAINT chk_users_phone_format
        CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),

    -- CONSTRAINT 2: User account lifecycle status domain
    CONSTRAINT chk_users_status_enum
        CHECK (status IN ('ACTIVE', 'BANNED', 'DELETED')),

    -- CONSTRAINT 3: Temporal logic - user cannot be last seen before the account was created
    CONSTRAINT chk_users_last_seen_after_join
        CHECK (last_seen_at IS NULL OR last_seen_at >= joined_on::timestamptz)
);

-- =====================================================================
-- TABLE 2: devices
-- Multi-device linked endpoints (Android, iOS, WhatsApp Web, Desktop).
-- =====================================================================
CREATE TABLE devices (
    device_id      INTEGER PRIMARY KEY,
    user_id        INTEGER NOT NULL,
    device_type    VARCHAR(10) NOT NULL,
    app_version    VARCHAR(20) NOT NULL,
    registered_at  TIMESTAMPTZ NOT NULL,
    last_active_at TIMESTAMPTZ NOT NULL,

    -- FK DELETE RULE: When a user account is deleted, all their linked device sessions
    -- have no owner and must be automatically purged (CASCADE).
    CONSTRAINT fk_devices_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE,

    -- CONSTRAINT 4: Supported client device types
    CONSTRAINT chk_devices_type_enum
        CHECK (device_type IN ('ANDROID', 'IOS', 'WEB', 'DESKTOP')),

    -- CONSTRAINT 5: Semantic versioning pattern (e.g. 2.24.8, 2.25.12)
    CONSTRAINT chk_devices_app_version_format
        CHECK (app_version ~ '^[0-9]+(\.[0-9]+)+$'),

    -- CONSTRAINT 6: Device cannot show activity before it was registered
    CONSTRAINT chk_devices_last_active_after_reg
        CHECK (last_active_at >= registered_at)
);

-- =====================================================================
-- TABLE 3: chats
-- Container for conversation streams (1-on-1 DIRECT chats and GROUP chats).
-- =====================================================================
CREATE TABLE chats (
    chat_id    INTEGER PRIMARY KEY,
    chat_type  VARCHAR(10) NOT NULL,
    group_name VARCHAR(100),
    created_by INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,

    -- FK DELETE RULE: We RESTRICT deleting a user who created active chats/groups
    -- to prevent accidental orphan groups and maintain organizational audit trails.
    CONSTRAINT fk_chats_creator
        FOREIGN KEY (created_by) REFERENCES users(user_id)
        ON DELETE RESTRICT,

    -- CONSTRAINT 7: Chat classification domain
    CONSTRAINT chk_chats_type_enum
        CHECK (chat_type IN ('DIRECT', 'GROUP')),

    -- CONSTRAINT 8: Structural invariant verified from data:
    -- DIRECT chats must have NULL group_name; GROUP chats must have a non-NULL name.
    CONSTRAINT chk_chats_group_name_logic
        CHECK (
            (chat_type = 'DIRECT' AND group_name IS NULL) OR
            (chat_type = 'GROUP' AND group_name IS NOT NULL)
        )
);

-- =====================================================================
-- TABLE 4: chat_members
-- Associative relationship tracking participant membership, roles, and muting.
-- =====================================================================
CREATE TABLE chat_members (
    chat_id   INTEGER NOT NULL,
    user_id   INTEGER NOT NULL,
    role      VARCHAR(10) NOT NULL DEFAULT 'MEMBER',
    joined_at TIMESTAMPTZ NOT NULL,
    left_at   TIMESTAMPTZ,
    is_muted  BOOLEAN NOT NULL DEFAULT false,

    PRIMARY KEY (chat_id, user_id),

    -- FK DELETE RULE: When a chat is deleted, its membership roster entries must be removed (CASCADE).
    CONSTRAINT fk_chat_members_chat
        FOREIGN KEY (chat_id) REFERENCES chats(chat_id)
        ON DELETE CASCADE,

    -- FK DELETE RULE: When a user is deleted, their memberships in chats must be cleaned up (CASCADE).
    CONSTRAINT fk_chat_members_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE,

    -- CONSTRAINT 9: Group membership permission levels
    CONSTRAINT chk_chat_members_role_enum
        CHECK (role IN ('ADMIN', 'MEMBER')),

    -- CONSTRAINT 10: Participant cannot leave before they joined
    CONSTRAINT chk_chat_members_leave_after_join
        CHECK (left_at IS NULL OR left_at >= joined_at)
);

-- =====================================================================
-- TABLE 5: media
-- Immutable binary media metadata stored in blob storage.
-- =====================================================================
CREATE TABLE media (
    media_id    INTEGER PRIMARY KEY,
    uploader_id INTEGER NOT NULL,
    media_type  VARCHAR(10) NOT NULL,
    mime_type   VARCHAR(50) NOT NULL,
    size_bytes  BIGINT NOT NULL,
    sha256      CHAR(64) NOT NULL, -- NOTE: NOT UNIQUE; duplicates exist and are required by R24!
    uploaded_at TIMESTAMPTZ NOT NULL,

    -- FK DELETE RULE: We RESTRICT deleting an uploader while their shared media files
    -- are referenced across active chats, preserving media evidence and chat integrity.
    CONSTRAINT fk_media_uploader
        FOREIGN KEY (uploader_id) REFERENCES users(user_id)
        ON DELETE RESTRICT,

    -- CONSTRAINT 11: File size must be strictly positive
    CONSTRAINT chk_media_size_positive
        CHECK (size_bytes > 0),

    -- CONSTRAINT 12: Permitted multimedia payload categories
    CONSTRAINT chk_media_type_enum
        CHECK (media_type IN ('IMAGE', 'AUDIO', 'VIDEO', 'DOCUMENT')),

    -- CONSTRAINT 13: Cryptographic SHA-256 integrity hash format (exactly 64 hex characters)
    CONSTRAINT chk_media_sha256_format
        CHECK (sha256 ~ '^[0-9a-f]{64}$'),

    -- CONSTRAINT 14: Strict 1-to-1 consistency between media category and MIME format
    CONSTRAINT chk_media_mime_type_consistency
        CHECK (
            (media_type = 'IMAGE' AND mime_type = 'image/jpeg') OR
            (media_type = 'AUDIO' AND mime_type = 'audio/ogg') OR
            (media_type = 'VIDEO' AND mime_type = 'video/mp4') OR
            (media_type = 'DOCUMENT' AND mime_type = 'application/pdf')
        )
);

-- =====================================================================
-- TABLE 6: messages
-- Central transaction store of messages, replies, forwards, and deletes.
-- =====================================================================
CREATE TABLE messages (
    message_id          BIGINT PRIMARY KEY,
    chat_id             INTEGER NOT NULL,
    sender_id           INTEGER NOT NULL,
    sent_at             TIMESTAMPTZ NOT NULL,
    message_type        VARCHAR(10) NOT NULL,
    body                TEXT,
    media_id            INTEGER,
    reply_to_message_id BIGINT,
    is_forwarded        BOOLEAN NOT NULL DEFAULT false,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,
    edited_at           TIMESTAMPTZ,

    -- FK DELETE RULE: Deleting a chat cascades down to delete its constituent message history.
    CONSTRAINT fk_messages_chat
        FOREIGN KEY (chat_id) REFERENCES chats(chat_id)
        ON DELETE CASCADE,

    -- FK DELETE RULE: Sender accounts cannot be purged while messages exist (RESTRICT)
    -- to guarantee audit logs and non-repudiation in chat histories.
    CONSTRAINT fk_messages_sender
        FOREIGN KEY (sender_id) REFERENCES users(user_id)
        ON DELETE RESTRICT,

    -- FK DELETE RULE: If a media file is purged from storage, retain the message metadata
    -- and text context while disassociating the media pointer (SET NULL).
    CONSTRAINT fk_messages_media
        FOREIGN KEY (media_id) REFERENCES media(media_id)
        ON DELETE SET NULL,

    -- FK DELETE RULE: If a parent message in a thread is deleted, preserve child replies
    -- while unlinking the parent pointer (SET NULL).
    CONSTRAINT fk_messages_reply
        FOREIGN KEY (reply_to_message_id) REFERENCES messages(message_id)
        ON DELETE SET NULL,

    -- CONSTRAINT 15: Supported message payloads
    CONSTRAINT chk_messages_type_enum
        CHECK (message_type IN ('TEXT', 'IMAGE', 'AUDIO', 'VIDEO', 'DOCUMENT', 'LOCATION')),

    -- CONSTRAINT 16: Edit timestamp cannot precede original send time
    CONSTRAINT chk_messages_edit_after_sent
        CHECK (edited_at IS NULL OR edited_at >= sent_at),

    -- CONSTRAINT 17: Content consistency with Delete-For-Everyone and Media Rules:
    -- - If is_deleted = true: both body and media_id must be NULL (W03).
    -- - If is_deleted = false:
    --     * TEXT / LOCATION messages must have non-null body and NULL media_id.
    --     * Media messages (IMAGE, AUDIO, VIDEO, DOCUMENT) must have non-null media_id (and optional caption).
    CONSTRAINT chk_messages_content_and_deletion_rules
        CHECK (
            (is_deleted = true AND body IS NULL AND media_id IS NULL)
            OR
            (is_deleted = false AND (
                (message_type IN ('TEXT', 'LOCATION') AND media_id IS NULL AND body IS NOT NULL)
                OR
                (message_type IN ('IMAGE', 'AUDIO', 'VIDEO', 'DOCUMENT') AND media_id IS NOT NULL)
            ))
        )
);

-- =====================================================================
-- TABLE 7: message_receipts
-- Per-recipient message delivery and read acknowledgment logs.
-- =====================================================================
CREATE TABLE message_receipts (
    message_id   BIGINT NOT NULL,
    user_id      INTEGER NOT NULL,
    delivered_at TIMESTAMPTZ,
    read_at      TIMESTAMPTZ,

    PRIMARY KEY (message_id, user_id),

    -- FK DELETE RULE: Deleting a message deletes its receipt tracking records (CASCADE).
    CONSTRAINT fk_receipts_message
        FOREIGN KEY (message_id) REFERENCES messages(message_id)
        ON DELETE CASCADE,

    -- FK DELETE RULE: Deleting a user deletes receipt records tracking their acknowledgments (CASCADE).
    CONSTRAINT fk_receipts_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE,

    -- CONSTRAINT 18: Receipt state machine time order:
    -- A message cannot be read before it is delivered, and delivered_at cannot be NULL if read_at is populated.
    CONSTRAINT chk_receipts_delivery_read_flow
        CHECK (read_at IS NULL OR (delivered_at IS NOT NULL AND read_at >= delivered_at))
);

-- =====================================================================
-- TABLE 8: calls
-- Peer-to-peer and group voice/video communication call records.
-- =====================================================================
CREATE TABLE calls (
    call_id     INTEGER PRIMARY KEY,
    chat_id     INTEGER NOT NULL,
    caller_id   INTEGER NOT NULL,
    call_type   VARCHAR(10) NOT NULL,
    started_at  TIMESTAMPTZ NOT NULL,
    answered_at TIMESTAMPTZ,
    ended_at    TIMESTAMPTZ,
    status      VARCHAR(15) NOT NULL,

    -- FK DELETE RULE: Purging a chat purges its call log history (CASCADE).
    CONSTRAINT fk_calls_chat
        FOREIGN KEY (chat_id) REFERENCES chats(chat_id)
        ON DELETE CASCADE,

    -- FK DELETE RULE: Caller identity must be retained for billing/telecom audit (RESTRICT).
    CONSTRAINT fk_calls_caller
        FOREIGN KEY (caller_id) REFERENCES users(user_id)
        ON DELETE RESTRICT,

    -- CONSTRAINT 19: Supported call media types
    CONSTRAINT chk_calls_type_enum
        CHECK (call_type IN ('VOICE', 'VIDEO')),

    -- CONSTRAINT 20: Call termination state machine
    CONSTRAINT chk_calls_status_enum
        CHECK (status IN ('COMPLETED', 'MISSED', 'REJECTED', 'FAILED')),

    -- CONSTRAINT 21: Call lifecycle temporal consistency:
    -- - COMPLETED calls have answered_at and ended_at, with started_at <= answered_at <= ended_at.
    -- - MISSED/REJECTED calls have ended_at (ringing ended) but NULL answered_at, with started_at <= ended_at.
    -- - FAILED calls (connection drops) have NULL answered_at and NULL ended_at.
    CONSTRAINT chk_calls_lifecycle_timestamps
        CHECK (
            (status = 'COMPLETED' AND answered_at IS NOT NULL AND ended_at IS NOT NULL
                AND answered_at >= started_at AND ended_at >= answered_at)
            OR
            (status IN ('MISSED', 'REJECTED') AND answered_at IS NULL AND ended_at IS NOT NULL
                AND ended_at >= started_at)
            OR
            (status = 'FAILED' AND answered_at IS NULL AND ended_at IS NULL)
        )
);

-- =====================================================================
-- TABLE 9: blocked_users
-- Directed user-to-user blocking privacy relationships.
-- =====================================================================
CREATE TABLE blocked_users (
    blocker_id INTEGER NOT NULL,
    blocked_id INTEGER NOT NULL,
    blocked_at TIMESTAMPTZ NOT NULL,

    PRIMARY KEY (blocker_id, blocked_id),

    -- FK DELETE RULE: When a blocker deletes their account, their active blocks are lifted (CASCADE).
    CONSTRAINT fk_blocked_blocker
        FOREIGN KEY (blocker_id) REFERENCES users(user_id)
        ON DELETE CASCADE,

    -- FK DELETE RULE: When a blocked user deletes their account, blocks on that ID are purged (CASCADE).
    CONSTRAINT fk_blocked_blocked
        FOREIGN KEY (blocked_id) REFERENCES users(user_id)
        ON DELETE CASCADE,

    -- CONSTRAINT 22: Business rule - A user cannot block themselves
    CONSTRAINT chk_blocked_no_self_block
        CHECK (blocker_id <> blocked_id)
);

-- =====================================================================
-- AUTOMATIC POSTGRESQL INDEXES IN THIS SCHEMA
-- Note: As specified in Checkpoint 1, NO manual secondary indexes are added.
-- PostgreSQL creates unique B-Tree indexes automatically for:
--  1. users: users_pkey (user_id), users_phone_e164_key (phone_e164)
--  2. devices: devices_pkey (device_id)
--  3. chats: chats_pkey (chat_id)
--  4. chat_members: chat_members_pkey (chat_id, user_id)
--  5. media: media_pkey (media_id)
--  6. messages: messages_pkey (message_id)
--  7. message_receipts: message_receipts_pkey (message_id, user_id)
--  8. calls: calls_pkey (call_id)
--  9. blocked_users: blocked_users_pkey (blocker_id, blocked_id)
-- =====================================================================
