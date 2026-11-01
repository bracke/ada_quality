# Dependency indicators

DEP-01 reuses the staged Alire build as dependency-resolution evidence. DEP-03 requires the resolved solution to build consistently. DEP-02 is a native release-policy check and remains a violation when the development manifest contains local paths, even though the isolation layer safely stages them.
