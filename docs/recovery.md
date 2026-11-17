# Recovery

Startup or explicit `database recover` scans running assessments. Each is atomically changed to interrupted with one
separately allocated recovery event; recovering multiple runs keeps the session's event allocator synchronized.
Repeating recovery makes no further changes or identifier reservations. Controller failures can interrupt a known
run immediately. Injected commit failure proves state and event roll back together. The integrated recovery fixture
publishes three completed numerical assessments, abandons a fourth run, reopens and recovers the database, and
verifies that chronological trends and completed baseline selection remain intact while comparison against the
interrupted latest run is explicitly unavailable.
