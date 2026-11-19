# Database design

One Ada-native database owns eight logical tables: projects, assessment runs, indicator results, measurements,
findings, tool executions, events, and schema metadata. Every table is registered through an explicit typed row
mapping. External tools run outside write transactions; start, terminal publication, migration, interruption, and
recovery use bounded write transactions. Schema version 4 has explicit migrations from versions 1 through 3, retains
the version-3 run timestamps and lossless payloads, and adds append-only assessment aliases without changing the
catalog shape.
