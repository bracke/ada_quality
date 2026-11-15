# Security scanning

Bounded `regexp` expressions detect credential assignments after comment/string normalization. A dedicated Ada lexical
scan detects shell APIs (`run_shell`, `spawn_shell`, `shell_execute`, `system`, `popen`, and `execlp`) and shell
executables used in process arguments or commands. It distinguishes identifiers, decoded string literals, and comments,
so comments and unrelated string text do not trigger the shell rule. Findings never retain secret values; messages
state only rule, path, and line. Tree links and generated artifacts are separate findings.
