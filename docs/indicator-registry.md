# Indicator registry

`Ada_Quality.Indicators` is a static descriptor array keyed by the strong indicator enumeration. Each descriptor has ID, version, category, name, and prerequisite set. Count is exactly 33, parsing round-trips canonical names, and depth-first validation rejects dependency cycles.
