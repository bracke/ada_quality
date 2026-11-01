# Source inventory

Traversal is sorted, capped by depth, file count, individual size, and aggregate fingerprint bytes, and never follows symbolic links. Production, test, and generated config sources are counted separately. Build, coverage, object, library, VCS, proof, and Alire working trees are excluded. Link paths, but not external target contents, participate in source identity.
