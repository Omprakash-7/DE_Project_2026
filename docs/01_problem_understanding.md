# Problem Understanding: WhatsApp Messaging Database (CP1)
**Team:** T0004 | **Section:** D | **Mentor:** Omkar  
**Repository:** [DE_Project_2026](https://github.com/Omprakash-7/DE_Project_2026)  

---

## 1. Problem Statements Analysis (P1 – P10)

| # | Problem Reported & Business Need | Stakeholder Affected | Workload Classification | Related Queries |
|---|----------------------------------|----------------------|-------------------------|-----------------|
| **P1** | **Chats Screen:** Mobile app must instantly render active chat lists, showing the snippet and timestamp of the latest message and unread count badges. High-frequency screen opened on app launch. | End User / Mobile App Client | **Customer-Facing / Real-Time** (Target: < 50ms) | R01, R03 |
| **P2** | **Busy Group History:** Users scrolling active group conversations experience lag fetching message batches. The server must fetch paginated messages (latest 50) and handle concurrent message posting without locking. | End User / Mobile App Client | **Customer-Facing / Real-Time** (Target: < 30ms) | R02, R07, W01 |
| **P3** | **Search & Message Info:** In-chat text search (e.g. searching "meeting") and inspecting message info (per-recipient delivery/read receipts) must respond promptly to user interactions. | End User / Mobile App Client | **Customer-Facing / Real-Time** (Target: < 100ms) | R04, R16, R25 |
| **P4** | **Identity, Privacy & Registration:** Verifying whether a phone number is registered, fetching contact "last seen", and checking blocking state before sending must be instantaneous. | Identity & Privacy Services | **Customer-Facing / Real-Time** (Target: < 10ms) | R05, R06, R15 |
| **P5** | **Delivery & Read Acknowledgment:** The delivery pipeline scans pending receipts (undelivered messages) and performs batch updates to mark receipts as delivered/read under heavy concurrent load. | Delivery Service | **Customer-Facing / Real-Time** (Target: < 50ms) | R08, W02, W04 |
| **P6** | **Unanswered Group Questions:** Group admins require a report of questions asked with zero replies. Currently returns empty due to SQL Three-Valued Logic (`NOT IN (..., NULL)`). | Group Administrators | **Reporting / Analytics** (Target: < 200ms) | R13 |
| **P7** | **Spam & Forwarding Surveillance:** Trust & Safety console flags accounts forwarding messages excessively across contacts on the same day, requiring rapid message offset pagination. | Trust & Safety Operations | **Reporting / Analytics** (Target: < 500ms) | R12, R22, W03 |
| **P8** | **Storage Optimization & Media Deduplication:** Infrastructure storage team needs to identify top uploaders and duplicate media assets sharing the same SHA-256 hash to reclaim storage space. | Storage & Infrastructure Team | **Reporting / Analytics** (Target: < 1s) | R09, R24 |
| **P9** | **Product & Growth Analytics:** Daily Active Senders (DAU), read latency metrics, edit/delete rates, and hourly capacity planning scans fail or time out under 20× projected traffic growth. | Product & Growth Analytics | **Reporting / Analytics** (Target: < 2s) | R10, R14, R17, R19, R20, R21 |
| **P10**| **Security & Stale Resource Clean-Up:** Background maintenance jobs detecting stale linked web/desktop sessions (to auto log out), inactive users in groups, and leaving groups lag significantly. | Platform & Security Team | **Reporting / Analytics** (Target: < 500ms) | R11, R18, R23, W05 |

---

## 2. Key Architectural Assumptions
1. **Concurrency Isolation:** Real-time customer queries (P1–P5) prioritize low-latency point lookups and range scans, while analytic queries (P6–P10) execute as read-only queries that must not acquire heavy table-level write locks.
2. **Delete-for-Everyone Semantics:** When a user deletes a message for everyone, `messages.is_deleted` is updated to `true`, and both `body` and `media_id` are cleared (`NULL`). The physical media record is retained in `media` for audit/dedup purposes.
3. **Receipt Lifecycle:** Every recipient in a chat receives an independent delivery receipt row. Delivery (`delivered_at`) strictly precedes or equals read time (`read_at`).
4. **Timezone Standardization:** All timestamps are ingested and processed using explicit timezone offsets (`TIMESTAMPTZ` with `+05:30` IST standard).

---
*Team Notes / Customization Placeholder:* `[Team T0004: All members reviewed and agreed on problem classification]`.
