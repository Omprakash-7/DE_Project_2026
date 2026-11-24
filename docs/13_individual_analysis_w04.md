# CP5 Individual Analysis: W04 Receipt Batch Insert

## Batch behavior

W04 inserts 5,000 receipt rows in one statement. The measured optimized run is
slower than baseline (33.041 ms versus 26.061 ms), consistent with maintaining
the additional partial receipt indexes introduced for unread and undelivered
queries. The batch remains far below the report's 2,000 ms target.

## Trade-off

The write cost buys faster filtered reads when those predicates select a small
share of receipts. The trade-off depends on how often broadcasts occur, how
many receipts qualify for each partial index, and how frequently receipt
status changes. An index that includes nearly every row can approach the cost
of a full index while providing less filtering benefit.

## Measurement caveat

Compare repeated runs on the same database state and include both read and
write workloads. The optimized and baseline values in the report have different
run counts, so this measured difference is directional evidence rather than a
matched experiment. Preserve the transactional rollback procedure so each
trial inserts the same number of rows.

## Evidence

See W04 in `sql/06_optimized_queries.sql`, the W04 row and write-cost analysis
in `docs/04_optimization_report.md`, and the benchmark procedure in
`docs/06_benchmark_reproduction.md`.
