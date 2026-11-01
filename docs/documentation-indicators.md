# Documentation indicators

DOC-01 scans production specs for package documentation. DOC-02 runs GNATdoc against the mapped staged GPR file with a temporary output directory that is removed afterward. DOC-03 requires the project README. A missing GPR or tool blocks DOC-02 and can never become compliance.
