# Database transactions

Project updates, assessment start plus start event, terminal publication of all dependent rows plus publish event, interruption, recovery, migration, and schema metadata creation use write transactions. Queries and next-ID scans use read transactions. Every exceptional write path rolls back; no transaction remains open while a tool executes.
