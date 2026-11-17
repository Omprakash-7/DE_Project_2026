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
