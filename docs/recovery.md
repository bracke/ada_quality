# Recovery

Startup or explicit `database recover` scans running assessments. Each is atomically changed to interrupted with one recovery event. Repeating recovery makes no further changes. Controller failures can interrupt a known run immediately. Injected commit failure proves state and event roll back together.
