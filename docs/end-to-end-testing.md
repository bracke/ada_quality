# End-to-end testing

The instrumented coverage driver invokes help/version, database init/check/recover, policy validate/show, all project mutations, two full assessments, history/status/findings/regressions, JSON archive, release checker, empty registry, missing records/policy, unknown commands/options, missing values, and conflicting selectors. Expected exit classes are asserted at process level.
