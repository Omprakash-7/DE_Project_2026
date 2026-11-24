# CP5 Individual Analysis: R08 Undelivered Messages

## Access path

R08 asks for a bounded list of messages with at least one undelivered receipt.
The optimized query drives from recent messages, probes the partial index of
undelivered receipts, and stops after collecting 500 rows. The limit is central
to the plan: it avoids materializing the entire undelivered set before sorting
and returning a page.

## Scale behavior

The scalability report records that a materialized CTE over all pending
receipts performed poorly at 20x scale: it spilled temporary data and led to a
large scan of `messages`. The current plain join avoids that forced
intermediate result. The report's measured improvement depends on the tested
distribution and index selectivity, so it should not be generalized to a
workload where most receipts are undelivered or the requested ordering changes.

## Correctness boundary

The receipt index only answers whether a matching undelivered receipt exists;
the query must still select the intended message fields and avoid duplicate
messages when several recipients have not received one message. Verify output
uniqueness and ordering as well as latency when changing the join shape.

## Evidence

See `sql/06_optimized_queries.sql` R08, `docs/04_optimization_report.md`, and
the scale comparison in `docs/05_scalability_report.md`.
