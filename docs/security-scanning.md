# Security scanning

Bounded `regexp` expressions detect credential assignments and shell-wrapper identifiers after comment/string normalization. Findings never retain secret values; messages state only rule, path, and line. Tree links and generated artifacts are separate findings. Comments and arbitrary string text do not trigger credential or shell rules.
