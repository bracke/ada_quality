# Database design

One Ada-native database owns eight logical tables: projects, assessment runs, indicator results, measurements, findings, tool executions, events, and schema metadata. Every table is registered through an explicit typed row mapping. External tools run outside write transactions; start, terminal publication, migration, interruption, and recovery use bounded write transactions. Schema version 2 has an explicit version-1 migration.
