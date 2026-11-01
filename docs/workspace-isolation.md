# Workspace isolation

Every assessment copies the project into a unique temporary container, rejects symbolic links, omits generated trees, and runs build/test/doc/proof/release tools there. Relative dependency links from either the manifest or committed lockfile are recursively copied into the same container; escaping or absolute paths are rejected. Cleanup runs on success and exceptions. Original Git status, when required by policy, and the source fingerprint are checked before and after.
