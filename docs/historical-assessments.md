# Historical assessments

Runs retain project, terminal state, source identity, policy fingerprint, toolchain fingerprint, results, typed measurements, findings, executions, and events. Queries return stable ID order. Running/interrupted/invalid records remain visible but cannot serve as successful baselines. One typed history selection operation supplies both CLI and archive comparison decisions. A missing completed baseline, changed toolchain, or incomplete current assessment is exported as an unavailable comparison and is never rendered as “no regressions.”
