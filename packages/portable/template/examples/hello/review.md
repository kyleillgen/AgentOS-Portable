# Independent review (fictional)
Task ID: hello
Assigned revision: 2
Revision at review start: 5
Reviewer/session: person-c
Model/client or deterministic tool: manual byte comparison
Saved by: person-c
UTC time: 2026-01-01T10:05:00Z
Independence from producer: separate person; did not author the output.
Artifact: results/greeting.txt
SHA-256: 34eb79f7f3c959b1a840d91603c38f3efdd6694c5ff50c31a5f8a4e063484542

| Criterion | Check performed | Evidence | Pass/fail |
|---|---|---|---|
| Exact greeting and one newline | Compare UTF-8 bytes to specified text | 13 bytes, last byte 0a, hash above | pass |

Decision: pass
Limitations and required corrections: illustrative review; not a live multi-model validation.
