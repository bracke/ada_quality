# Execution environment

Children start under `env -i`. Only PATH, HOME, TMPDIR, locale variables, user/shell identity, XDG data/cache/config, and Alire settings are copied when present. A dedicated test proves an unlisted secret variable cannot reach the child.
