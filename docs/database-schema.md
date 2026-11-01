# Database schema

Schema version 3 contains exactly eight logical tables. The normalized typed row envelope has an integer key and
parent key plus kind, state, payload, and active fields; domain-specific mapping code encodes and decodes each
logical table. Measurement kind/value and assessment source/policy/toolchain fields are retained explicitly. New
assessment rows record UTC start and finish timestamps and identify lossless, escaped child evidence. Queries sort
by stable IDs.
