# SPARK verification

Ada code is scanned with comments and strings removed for `SPARK_Mode`. No declaration yields an evidenced not-applicable result. Otherwise GNATprove runs through Alire against the staged GPR with `--mode=prove --level=2`. Missing, timed-out, legality-only, failed, or incomplete proof execution cannot pass.
