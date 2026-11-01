# JSON reporting

`check --json` emits one versioned assessment object. `report --format json` emits the persistent archive, including removed projects and derived regressions. Both use jsonlib, sorted members, UTF-8 strings, explicit typed measurement objects, and no terminal markers or ANSI sequences.
