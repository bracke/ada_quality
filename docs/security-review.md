# Security review

Threats reviewed: argument injection, shell interpolation, output flooding, process hangs, orphan cleanup, source-tree
escape, cyclic links, embedded secret reporting, hostile policy values, stale evidence, ANSI in JSON, and partial DB
publication.

Controls:

- every assessed tool receives an explicit argument vector; the adapter does not invoke a shell;
- executable lookup occurs before spawn and evidence records program paths plus redacted option/argument shapes,
  never positional or attached option values;
- GNAT Expect enforces the monotonic deadline and escalates from TERM to KILL after five seconds;
- stdout and stderr are merged into a streaming byte-bounded buffer;
- a protected process-wide gate serializes the GNAT Expect spawn, monitor, and close boundary;
- symbolic links are identified before `Kind` and are never followed by assessment traversal or cleanup;
- coverage is rejected unless its source fingerprint equals the current assessment fingerprint;
- Git cleanliness is checked before and after tools when policy requires it;
- JSON is created through jsonlib with no terminal styling;
- all write paths use dependency transactions and terminal assessments are immutable.

SEC-01 is a conservative source-pattern detector, not a credential vault scanner. Evidence summaries do not persist
captured tool output, reducing secret-retention risk. Operators must still protect the database and local project
directories with filesystem permissions.
