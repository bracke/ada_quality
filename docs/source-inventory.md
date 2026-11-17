# Source inventory

Traversal is sorted, capped by depth, file count, individual size, and aggregate fingerprint bytes, and never follows
symbolic links. `Ada_Quality.Project_Inventory` is the canonical classification shared by source fingerprints,
artifact fingerprints, coverage inventory, and isolated workspace staging. Production, test, and generated config
sources are counted separately. Compiler intermediates, test output, local assessment databases, build, coverage,
object, library, VCS, proof, and Alire working trees are excluded. Staging retains only the generated Alire lock and
the two canonical coverage evidence files that release checks require. `.gitignore` mirrors the same generated-state
categories. Link paths, but not external target contents, participate in source identity.
