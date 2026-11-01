# Coverage and proof

Coverage evidence must contain covered and eligible totals, `complete=true`, inventory kind `gcov-production-lines-v2`, the explicit coverage-driver exclusion, and the exact assessed source fingerprint. The gate uses overflow-safe integer arithmetic. PRF-01 scans exact `SPARK_Mode` tokens outside comments and strings in Ada sources, configuration-pragmas files, and project files. When applicable, GNATprove runs in proof mode; a failed, missing, or timed-out tool cannot pass.
