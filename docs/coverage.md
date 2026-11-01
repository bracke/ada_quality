# Coverage

TST-03 accepts only complete, source-bound `gcov-production-lines-v1` evidence. It requires nonzero eligible production executable lines and compares exact integers against the policy basis points. The bundled coverage driver performs a clean instrumented build, runs unit and CLI E2E paths, inventories production bodies, writes the evidence file, and fails below policy.
