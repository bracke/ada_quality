# Source analysis

Ada comments and strings are lexically removed where rules require code
tokens. SRC-03 is a defined lexical Ada decision-complexity metric, not an AST
claim: each subprogram starts at one; `if` (excluding `end if` and `elsif`),
`elsif`, `when`, non-terminating `case` and `loop` tokens, `and then`, and
`or else` each add one. The maximum segment between subprogram declarations is
reported. Representative conditionals, alternatives, loops, short-circuit
expressions, nested declarations, and expression functions are fixture-tested.
Library unit names are compared canonically with source filenames.

Broad handlers use `project_tools` Ada source scanning; an audited cleanup,
translation, or process-boundary handler may carry the explicit `AQ: audited
exception boundary` suppression on its handler line.

SRC-03 and SRC-06 exceptions use exact, standalone structured comments:

```ada
--  AQ-WAIVER: SRC-03 target=<measured-subprogram> owner=<owner> expires=YYYY-MM-DD justification=<reason>
--  AQ-WAIVER: SRC-06 target=file owner=<owner> expires=YYYY-MM-DD justification=<reason>
```

The rule, target, owner, canonical expiry date, and nonempty justification are mandatory. SRC-03 applies
only when its target equals the subprogram name associated with that file's
maximum measured segment; SRC-06 accepts only `target=file`. Legacy broad
markers, mismatched targets, and markers embedded in strings do not suppress a
violation. Every accepted waiver remains in assessment evidence as a
low-severity `review-waiver` finding even when the indicator passes. Expired or malformed applicable waivers remain
visible as `expired-waiver` or `invalid-waiver` findings and do not suppress the underlying violation. `waiver audit
--project ID` reports the active and rejected waiver evidence for a project.

DOC-01 uses GNATdoc's declaration-level warning audit rather than accepting one
file-level package comment as evidence for every declaration.
