# CP5 Individual Analysis: Partitioning Boundaries

## What the demonstration proves

The partitioning script creates a separate `messages_partitioned` table,
copies rows into it, and runs a time-bounded query that can prune unrelated
monthly partitions. This demonstrates partition creation and pruning. It does
not switch the application's `messages` table to the partitioned design.

## Key and foreign-key constraint

The current message identity is `message_id`, while PostgreSQL requires a
partitioned unique key to include the partition key `sent_at`. Changing the
primary key therefore affects receipts and reply references. The partitioned
demo uses `(message_id, sent_at)` while the existing relationships refer to
`message_id` alone, so a production migration needs an explicit referential
integrity design before cutover.

## Operational work still needed

A real migration would need to backfill, reconcile counts and references,
handle writes during the copy, and test rollback and retention behavior. The
script is a useful plan experiment, but partition pruning alone does not
establish a safe migration or demonstrate that all workload queries improve.

## Evidence

See `sql/08_partitioning.sql` and `docs/07_partitioning_rollout_notes.md`.
This analysis clarifies the scope of the current experiment and makes no
changes to the checkpoint SQL.
