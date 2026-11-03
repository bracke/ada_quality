# Test indicators

TST-01 runs the AUnit child-crate action after a successful build. The tests crate's `tests/alire.toml` names the suite: its first `project-files` entry, or `<name>.gpr`, is built, and its first `executables` entry, or its `name`, is run from `tests/bin` (`Ada_Quality.Checks.Test_Project_File` and `Test_Suite_Executable`). TST-02 requires actual registration tokens in test sources. TST-04 repeats the action and requires both successful results and identical bounded output. Coverage is deliberately deferred to TST-03 and its stronger evidence contract.
