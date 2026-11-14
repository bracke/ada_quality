# Metric trends

`Metric_Trend` selects the newest completed assessment as its reference and returns compatible numeric points in
run-ID order. A later running, invalid, or interrupted assessment therefore cannot hide earlier valid history. Trend
points must match the reference measurement's indicator-contract version, evidence-method version, value kind,
policy, and toolchain. Ordinary source revisions remain comparable when those semantics are unchanged. Legacy
measurement rows are explicitly interpreted as indicator v1/method v1; malformed semantic identities, unavailable,
text, and Boolean values are ignored. Fixtures cover interrupted-latest history, independent version changes,
recovery integration, and deterministic ordering across 1,000 runs.
