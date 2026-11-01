# Baseline selection

A compatible baseline belongs to the same project, is completed, has nonempty source identities, and has the same nonempty policy and toolchain fingerprints. Selection walks backward from the current run to the newest compatible predecessor. Policy changes may be compared separately as policy-induced change; toolchain changes are not quality regressions.
