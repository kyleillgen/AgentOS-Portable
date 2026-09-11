# File handoff protocol — version 1

The coordinator alone creates task directories and updates task.md. Keep a single active coordinator session. Do not rely on a sync service to arbitrate concurrent writers.

| State | Required evidence before transition |
|---|---|
| intake | Objective, criteria, scope, authorization and participants filled in |
| assigned | Coordinator names one producer and one reviewer; increments revision |
| accepted | Producer acceptance.md cites the assigned revision and confirms ability and scope |
| executing | Coordinator acknowledges acceptance and records execution start |
| review | Producer has finished results and recorded evidence plus limitations |
| delivered | Reviewer passes all criteria; coordinator actually delivers and records destination/time |
| closed | Coordinator verifies delivery and records closure rationale |
| blocked | A participant reports missing access, permission, budget, failed review, or uncertain outcome |

Each coordinator update increments revision and appends a history row in task.md. Never remove previous rows. Acceptance cites the assigned revision; review cites that same assignment revision and the current revision at review start. Results must still match the original scope. A change to scope, producer, or criteria after assignment requires a new linked task ID, not an edit to the agreed assignment.

Producer writes acceptance.md and results/ only. Put a completion note at results/completion.md identifying artifacts, checks, limitations, author, and assigned revision. Reviewer writes review.md only and identifies the exact artifact version reviewed (hash or immutable snapshot path). Once submitted for review, results are frozen. Coordinator writes delivery.md and task.md only. A human saving an agent's returned content acts as its scribe and records attribution.

Notify the coordinator after each handoff; the coordinator verifies files and records the state transition before handing off to the next participant. Status changes are not automatic. A review fail becomes blocked, with evidence preserved. An authorized correction uses a new linked task. Never mark a failed or unreviewed result delivered or closed.

If a session stops unexpectedly, record blocked and inspect existing artifacts and external effects before authorizing any new attempt. If files conflict or the assignment revision does not match, stop and reconcile with the coordinator. Do not guess which copy is authoritative.

Delivery means the artifact was actually presented at the agreed destination. For a local task that can mean showing the principal a file link; record it. Closure means the coordinator has checked the delivery evidence and acceptance result. These are distinct from the producer finishing its work.

For tasks explicitly assigned to the local dispatcher, runners/README.md extends this protocol: the coordinator records acceptance before publishing an immutable JSON order, the dispatcher owns runtime status/receipts, and stage outputs live in work/results/<order-id>/. Link that evidence into the Markdown packet; do not run a second manual producer concurrently. Delivery and closure remain coordinator actions.
