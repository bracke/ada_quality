# Dependency matrix

Ada Quality uses the inspected public APIs of `database` for typed tables and transactions, `project_tools` for files, TOML, processes, source handlers, coverage, and release checks, `regexp` for bounded security patterns, `messages` for human result formatting, `terminal_styles` for roles, and `jsonlib` for RFC 8259 output. The manifest has no local pins; Alire's generated workspace lock retains resolved sibling links for deterministic local development, and CI recreates the same layout from separate repositories.
