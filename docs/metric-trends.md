# Metric trends

`Metric_Trend` selects the newest completed assessment as its reference and returns compatible numeric points in
run-ID order. A later running, invalid, or interrupted assessment therefore cannot hide earlier valid history. Trend
points must match the reference measurement's indicator-contract version, evidence-method version, value kind,
policy, and toolchain. Ordinary source revisions remain comparable when those semantics are unchanged. Legacy
measurement rows are explicitly interpreted as indicator v1/method v1; malformed semantic identities, unavailable,
text, and Boolean values are ignored. Fixtures cover interrupted-latest history, independent version changes,
recovery integration, and deterministic ordering across 1,000 runs.

The CLI exposes this series through `trend --project ID --indicator ID`; `--json` emits the versioned
metric-trend-v1 document with the registry's stable measurement unit.

`trend --project ID --all` emits every indicator whose registry direction is higher-is-better or lower-is-better.
`--from-run`/`--to-run` and `--since`/`--until` apply inclusive run-ID and completed-time bounds after semantic
compatibility selection. Single-series JSON remains metric-trend-v1; multi-series JSON is metric-trends-v1, and CSV
uses `project_id,indicator,unit,run_id,value` in registry and run order.
