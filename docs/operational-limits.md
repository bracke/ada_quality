# Operational limits

Policy bounds timeout to 1..3600 seconds and captured output to 1 KiB..16 MiB. Source traversal allows depth 128, 100,000 files, 64 MiB per file, and 1 GiB aggregate fingerprint input. Regexp matching is bounded by the library defaults. Child capture uses a 4 KiB internal buffer and stores only the configured prefix plus digest/length metadata.
