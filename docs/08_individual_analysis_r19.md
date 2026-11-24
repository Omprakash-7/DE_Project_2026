# CP5 Individual Analysis: R19 Group Health Report

## Question

Why did R19 improve so much after optimization, and what did the change cost?

## Plan finding

The baseline plan for R19 ran two correlated aggregates for every group. With 3,000 groups, that caused 6,000 scans of `messages`; the captured baseline reported about 8.2 million shared-buffer hits and an average of 17,003.794 ms. The optimized query computes message statistics once, then joins that aggregate to the group rows. Its captured average was 14.740 ms, with 1,389 buffers in the representative plan.

The improvement comes from changing the amount of repeated work, not from making each individual lookup slightly faster. The old plan revisited the same message relation for each group, while the new plan pays for one sequential pass and a join. This is a good case where a sequential scan is the right access path: a report that needs statistics over most messages cannot avoid reading most of them.

## Trade-off and caveat

The aggregate still scans all messages, so its runtime will grow with message volume. The rewrite removes repeated scans but does not make the report constant-time. If the report becomes a frequent production query at much larger scale, a refreshed summary table or materialized view could reduce read latency at the cost of storage and refresh work.

The reported baseline used three runs and the optimized result used five. The ratio is therefore useful as an observed scale of improvement, but it is not a matched-run experiment. A strict comparison should run both query versions the same number of times against the same freshly loaded database, cache conditions, PostgreSQL version, and session settings.

## Evidence

- `benchmarks/results/baseline/R19.txt` and `benchmarks/results/optimized/R19.txt` contain the captured plans.
- `benchmarks/results/baseline/summary.csv` and `benchmarks/results/optimized/summary.csv` contain the phase summaries.
- `sql/06_optimized_queries.sql` contains the single-pass rewrite.

