# Persistence invariants

Foreign parent IDs are checked at publication boundaries, completed evidence cannot be rewritten, all 33 results and measurements publish together, and failed publication leaves the running row with only its start event. Persistent lock conflicts fail opening a second handle. Recovery changes only running records and is idempotent.
