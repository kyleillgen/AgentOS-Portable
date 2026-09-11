# Task: hello

Fictional walkthrough; these records are illustrative, not an actual agent run.

Protocol: 1
ID: hello
Project: onboarding
State: closed
Revision: 8
Assigned revision: 2
Created at (UTC): 2026-01-01T10:00:00Z
Coordinator: person-a
Producer: session-b
Reviewer: person-c
Previous task: none

## Objective
Write a greeting to demonstrate a file handoff.

## Acceptance criteria
- results/greeting.txt contains exactly Hello, team! followed by one newline.

## Authorization
Authorized by: person-a (fictional principal)
Allowed actions and outcome: create the greeting within this task only.
Excluded actions: external actions and changes outside this task.
Budget/limits: one manual attempt; no purchases.

## Context and inputs
The greeting specified above is the entire input.

## Expected artifacts and delivery destination
results/greeting.txt; show its contents to person-a in the coordinating session.

## History (coordinator appends)
| Revision | UTC time | State | Actor | Evidence and rationale |
|---|---|---|---|---|
| 1 | 2026-01-01T10:00:00Z | intake | person-a | Criteria recorded |
| 2 | 2026-01-01T10:01:00Z | assigned | person-a | session-b assigned, person-c reviews |
| 3 | 2026-01-01T10:02:00Z | accepted | person-a | acceptance.md cites revision 2 |
| 4 | 2026-01-01T10:03:00Z | executing | person-a | Acceptance checked; producer starts |
| 5 | 2026-01-01T10:04:00Z | review | person-a | results/completion.md; results frozen |
| 6 | 2026-01-01T10:05:00Z | review | person-a | review.md passes |
| 7 | 2026-01-01T10:06:00Z | delivered | person-a | delivery.md records presentation |
| 8 | 2026-01-01T10:07:00Z | closed | person-a | Review and delivery verified |
