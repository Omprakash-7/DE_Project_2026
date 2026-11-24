# CP5 Individual Analysis: Deep Pagination in R22

## Offset cost

R22 returns a page of messages deep in the ordered history. With `OFFSET`, the
database still walks past earlier rows before it can return the requested
page. The baseline plan's backward primary-key scan discarded 100,000 rows.

## Keyset approach

The optimized query replaces the offset with a cursor predicate on
`message_id`, preserving descending order and limiting the result to 25 rows.
The benchmark reports 8.942 ms for the baseline and 0.062 ms for the optimized
query on the seed dataset. This is a strong example of avoiding work whose
size grows with page depth.

## Cursor contract

The cursor must be taken from the last row of the preceding page and used with
the same sort direction. A stable unique ordering key prevents ambiguous page
boundaries. If the product sorts by a non-unique timestamp, include a unique
tie-breaker such as `message_id` in both the ordering and cursor predicate.

## Evidence and limitation

See R22 in `sql/06_optimized_queries.sql` and its baseline/optimized plan
files. The fixed literal cursor is a reproducible benchmark example; an
application should bind the cursor parameter and validate pagination while
concurrent messages are arriving.
