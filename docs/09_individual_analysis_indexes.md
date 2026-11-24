# CP5 Individual Analysis: Indexes and Write Cost

## Observation

An index is useful when it avoids reading many rows or supplies rows in the needed order. It is not automatically beneficial for every report. Queries such as R09 and R24 aggregate or group most of a relation; their optimized plans retain sequential scans because reading the table once and aggregating is cheaper than walking an index and fetching many heap pages.

The workload also includes writes. W01 and W04 became slower in the measured optimized phase while additional indexes were maintained. That is an expected cost: inserts and updates must keep every applicable index entry consistent. A design judged only by read latency can therefore make the overall workload worse.

## Decision rule

Before adding an index, check the query predicate, selectivity, sort order, and actual plan. Then measure both the target read and representative writes. Keep an index when its read benefit matters to the workload and outweighs its write, storage, and maintenance costs. Recheck after data growth because selectivity and planner choices can change.

## Measurement caveat

The baseline summary is based on three runs and the optimized summary on five. Individual fast queries also show cache and timing noise, so small regressions should not be treated as conclusive without matched repeated measurements. The reproduction steps in `docs/06_benchmark_reproduction.md` describe how to rerun the phases.
