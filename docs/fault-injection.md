# Fault injection

| Injection point | Fixture | Expected and observed invariant |
|---|---|---|
| Schema metadata commit | injected creation fault | incomplete handle closes; fixture is safely removable |
| Migration commit | version 1 plus injected fault | database remains version 1 and migrates on retry |
| Assessment start commit | injected fault | neither running row nor start event leaks |
| After running record commit | close/reopen before publication | recovery marks exactly one interrupted run |
| During publication | invalid UTF-8 source identity | transaction rolls back; zero result rows leak |
| Publication commit | injected fault after dependent inserts | running row remains; results/events roll back |
| Republication | publish the same completed ID twice | second publication is rejected; 33 rows remain |
| Recovery commit | injected fault after state/event writes | state remains running and no recovery event leaks |
| Recovery repeat | call recovery twice | first call records state/event; second reports zero |
| Tool spawn | nonexistent executable | structured `Spawn_Error`, never pass |
| Tool deadline | two-second child with one-second limit | timeout status and child cleanup |
| Output pressure | ten-byte output with five-byte ceiling | exact five bytes retained and truncation recorded |
| Link/pin escape/cycle | external/ancestor links and `../../../` pin | no traversal, no hang, external content ignored |
| Policy corruption | missing, duplicate, and excessive values | structured load failure and exit class 2 |

The database dependency supplies lower-level WAL, commit, and crash machinery. This crate injects failures at its own
transaction boundary and verifies only public dependency APIs; it does not reach into database internals.
