# Architecture

## Files are the common interface

Models do not need to call one another. Each session reads a bounded packet, performs its assigned role, and writes a durable artifact that the next session can understand. The shared contract outlives context windows and provider sessions.

```text
Person / coordinator
        |
        v
Task packet -> producer acceptance -> result -> independent review
     ^                                  |               |
     |                                  v               v
     +-- new linked attempt          evidence       delivery -> closure
```

| Layer | Files | Responsibility |
|---|---|---|
| Governance | AGENTS.md, TEAM.md | Authority, boundaries, participants and access |
| Coordination | PROTOCOL.md, tasks/<id>/task.md | Objective, assignment, acceptance and state |
| Execution | tasks/<id>/acceptance.md, results/ | Producer acknowledgment and artifacts |
| Verification | tasks/<id>/review.md | Independent checks against acceptance criteria |
| Delivery | tasks/<id>/delivery.md | What was delivered, to whom, and closure evidence |
| Reuse | templates/, knowledge/ | Blank packets and selected reusable context |

## Ownership instead of a distributed lock service

One designated coordinator session owns task creation, assignment, and `task.md` updates. One producer owns that task's acceptance and results. One reviewer owns its review. The coordinator records delivery. Different tasks can run concurrently; writers must never share ownership of the same file. A role can be performed by a human.

Before switching coordinator sessions, stop the old writer and explicitly transfer ownership in TEAM.md. This is a cooperative protocol, not an enforced lock. If exclusive ownership cannot be established, stop writes and reconcile with the person coordinating the work. Sync conflicts, stale copies, or an offline owner invalidate any assumption that the latest file has arrived. Never resolve them by last-write-wins automation.

The task revision increases with each coordinator state update. Producer and reviewer records cite the assigned revision, so stale results can be detected. This is a manual check, not an atomic compare-and-swap guarantee. The coordinator verifies the current revision before accepting a handoff.

## Portability contract

- Use UTF-8 Markdown and relative paths with `/` in records.
- Use lowercase ASCII task IDs with letters, numbers and hyphens; no spaces, reserved device names, or case-only differences. Keep IDs short.
- Use ISO 8601 UTC timestamps and explicit participant identifiers.
- Include protocol version `1` in each task packet. Stop and ask the coordinator to translate an unsupported version.
- Record the actual model/client if known; use `unknown` otherwise. Do not invent provenance.
- Keep context task-specific. Link evidence and distinguish observed facts, assumptions, and unresolved questions.
- An output filename is not proof of success. Review must check content against the prewritten criteria.

## What this does and does not establish

The templates standardize meaning and ownership across providers; they do not guarantee that a model follows instructions. The scaffold is mechanically testable. Cross-client behavior still requires a local smoke task with the chosen participants. The file contract does not provision authentication, pool model quotas, grant filesystem access, or provide exactly-once execution. The included Windows dispatcher can be scheduled after explicit setup and validation.

Interrupted work has an unknown outcome until inspected. Do not repeat external actions automatically. Preserve failed attempts and create a linked task for authorized corrections. Substantive review should use a separate session and preferably a different model/provider; mechanical acceptance can be checked by deterministic tools with recorded evidence.

Additional storage adapters and runners may be added later without changing the core task semantics. They must preserve ownership, revision checks, acceptance evidence, and the distinction between completion, delivery, and closure.

## Included local dispatcher

The shared protocol also has an optional Windows execution layer in template/runners/. The coordinator publishes an immutable JSON order linked to the Markdown task ID and accepted revision. The monitor wakes the dispatcher; it runs Codex or Claude and swaps providers for review. The ledger records attempt state before shared projections. A passed review creates a pending handoff, leaving actual delivery/closure to the coordinator.

Automated results live in work/results/<order-id>/ and manual results in tasks/<task-id>/results/. The task packet links the appropriate evidence; these are two execution paths for the same lifecycle, not competing status authorities. See template/runners/README.md for the precise ownership map. Only one host writes runtime state. Other providers retain manual participation; this edition does not promise cross-platform PowerShell execution or native signed-out Codex success on every host.

Manual and agent-assisted downloads are built from this exact template and call the same setup.ps1. AGENT-SETUP.md supplies environment detection, login handoff, evidence checks and explicit local-access limitations around those scripts.
