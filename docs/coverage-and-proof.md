# Coverage and proof

Coverage evidence must contain covered and eligible totals, `complete=true`, inventory kind `gcov-production-lines-v1`, and the exact assessed source fingerprint. The gate uses overflow-safe integer arithmetic. PRF-01 is not applicable when no Ada code declares `SPARK_Mode`; otherwise GNATprove runs in proof mode and a failed, missing, or timed-out tool cannot pass.
