# End-to-end testing

The instrumented coverage driver invokes help/version, database init/check/recover, policy validate/show, all project
mutations, two full assessments, history/status/findings/regressions, JSON archive, release checker, empty registry,
missing records/policy, unknown commands/options, missing values, and conflicting selectors. A three-project batch
fixture makes the middle project fail during staging and verifies that its run is interrupted while the final project
still receives a completed assessment. Expected aggregate exit classes are asserted at process level.
