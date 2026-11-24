# Partitioning Rollout Notes

`sql/08_partitioning.sql` creates and fills `whatsapp.messages_partitioned` as
a non-destructive partitioning demonstration. It does **not** replace the
production-shaped `whatsapp.messages` table or redirect application queries.
That distinction matters because `message_receipts` and the reply pointer refer
to `message_id` alone, while PostgreSQL requires a partitioned table's unique
key to include its partition key (`sent_at`).

Before a production cutover, the team would need to choose and verify one
referential-integrity design:

1. Carry `sent_at` into receipt/reply relationships and use composite foreign
   keys; or
2. Keep a non-partitioned `message_id` registry with a unique constraint and
   reference that registry from receipts/replies; or
3. Define and test a trigger/application validation strategy with explicit
   behavior for deletes, retention, and late-arriving messages.

The migration should then backfill in bounded batches, reconcile row counts and
foreign-key relationships, dual-write during cutover, and compare the full
read/write workload before routing production traffic. The current script
proves partition creation and pruning only; it is not a zero-downtime migration
procedure.
