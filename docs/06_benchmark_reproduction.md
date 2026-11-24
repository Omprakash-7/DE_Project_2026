# CP3/CP4 Benchmark Reproduction

This runbook records the commands and assumptions needed to reproduce the DE
measurements. Use PostgreSQL 15 or newer and run commands from the repository
root so the `\copy` paths in `sql/02_load_data.sql` resolve.

## Seed benchmark and optimized workload

1. Unzip the committed `seed_data.zip` into `seed_data/` (do not commit the CSVs).
2. Create a clean database, then load and benchmark:

   ```sh
   createdb whatsapp_seed
   psql -v ON_ERROR_STOP=1 -d whatsapp_seed -f sql/01_schema.sql
   psql -v ON_ERROR_STOP=1 -d whatsapp_seed -f sql/02_load_data.sql
   ./benchmarks/run_benchmark.sh whatsapp_seed baseline 3
   psql -v ON_ERROR_STOP=1 -d whatsapp_seed -f sql/05_indexes.sql
   ./benchmarks/run_benchmark.sh whatsapp_seed optimized 5 sql/06_optimized_queries.sql
   ```

3. For date/hour comparisons, set and record the intended session time zone. The
   optimized reporting bounds assume India Standard Time (`Asia/Kolkata`).

## Large-data benchmark

Download and unzip the official [`large_data.zip`](https://github.com/edusatyaki/DBMS-WhatsApp-Messaging/releases/download/large-data/large_data.zip)
release locally; do not add its CSVs to Git. Put the nine large CSVs in
`seed_data/` for this run (replace the seed CSVs; do not mix datasets), then
load them with the same schema and loader, apply `sql/05_indexes.sql`, and run:

```sh
./benchmarks/run_benchmark.sh whatsapp_large large 3 sql/06_optimized_queries.sql
```

Record PostgreSQL version, host/session time zone, dataset row counts, and run
count with every new result. Baseline uses three runs while the committed CP3
optimized benchmark uses five; those averages are not matched-run comparisons.
