# Documentation indicators

DOC-01 classifies GNATdoc's declaration-level `entity ... is not documented` diagnostics and does not treat unrelated
generation warnings as missing public documentation. DOC-02 applies the all-warning generation policy to the same
bounded GNATdoc execution. Truncated diagnostics block both indicators because neither requirement can be established
from an incomplete prefix. GNATdoc writes to a temporary output directory that is removed afterward. DOC-03 requires
the project README. A missing GPR or tool blocks DOC-01 and DOC-02 and can never become compliance.
