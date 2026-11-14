# Persistence invariants

Foreign parent IDs are checked at publication boundaries, completed evidence cannot be rewritten, all 33 results and measurements publish together, and failed publication leaves the running row with only its start event. Every new measurement row carries its indicator-contract and measurement-method versions; legacy rows have explicit v1/v1 trend semantics. Persistent lock conflicts fail opening a second handle. Recovery changes only running records and is idempotent.
