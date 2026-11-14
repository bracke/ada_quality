# Indicator registry

`Ada_Quality.Indicators` is a static descriptor array keyed by the strong indicator enumeration. Each descriptor has
ID, indicator-contract version, measurement-method version, category, name, and prerequisite set. Both versions are
persisted with numerical evidence so a future implementation change cannot silently mix incompatible trend points.
Count is exactly 33, parsing round-trips canonical names, and depth-first validation rejects dependency cycles.
