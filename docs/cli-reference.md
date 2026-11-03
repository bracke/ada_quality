# CLI reference

Commands are `project add/list/show/enable/disable/remove`, `check --all|--project ID [--json]`, `status`, `findings`,
`regressions`, `history`, `report --format json`, `policy validate/show`, and `database init/check/recover`. During
`check --all`, a project-local source or assessment exception interrupts that project's run, contributes exit class 3,
and does not prevent later enabled projects from running. Database start, publication, interruption, and integrity
failures remain batch-fatal. `regressions` reports one of three distinct outcomes per project: concrete regressions,
no regressions in comparable completed assessments, or comparison unavailable with the reason. Global options are
`--database`, `--policy`, `--color`, and `--no-color`. Unknown options, missing values, and conflicting selectors are
rejected.
