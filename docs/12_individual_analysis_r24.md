# CP5 Individual Analysis: R24 Duplicate Media Detection

## Why an index may not help

R24 groups media rows by their content hash to find duplicates. The operation
must examine the hash value for every media row to establish groups, so a
sequential scan followed by aggregation can be cheaper than random index
lookups. The optimization report keeps that plan rather than adding an index
that would still visit most of the relation.

## Memory changes the plan

The scalability report describes the aggregate exceeding its in-memory budget
on the larger dataset and switching to an external sort with temporary disk
I/O. That is a meaningful change in resource use even though the query remains
within its reported target. Runtime alone can hide the disk spill and the
impact on concurrent workloads.

## Options at higher volume

For frequent duplicate checks, a maintained uniqueness/summary structure or
incremental grouping can avoid reprocessing all media rows. Such a design
shifts cost to writes and must define how duplicate groups change when media
rows are deleted or hashes are corrected.

## Evidence

See R24 in `sql/06_optimized_queries.sql`, the captured plans, and the storage
and scale discussion in `docs/05_scalability_report.md`.
