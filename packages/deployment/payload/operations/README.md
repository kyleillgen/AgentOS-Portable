# Headless operations

The checker runs without the desk or any model client. Windows starts it separately from the runner and watchdog in the Unattended profile. `IAF.ps1 Check` performs one pass; `IAF.ps1 Snapshot` displays current cases, report hashes and health. Persistent alerts live in the external operations directory even when no interface is open.

## Worker recovery

Use the Python executable and local-state location in agentos-installation.json. Never paste a claim token into a public report. In PowerShell from the workspace:

```powershell
$installation=Get-Content .\agentos-installation.json -Raw|ConvertFrom-Json
$registry=Join-Path $installation.local_state 'operations'
$service=Join-Path $installation.root 'extensions/operations/operations_service.py'
& $installation.python -E -s $service --root $installation.root --registry $registry --snapshot
```

Select a case from `unresolved`. Use its recovery fingerprint and current revision:

```powershell
& $installation.python -E -s $service --root $installation.root --registry $registry --claim example-id --fingerprint CURRENT_FINGERPRINT --expected-revision 2 --owner worker-name --lease-seconds 1800
```

The response supplies a new revision and lease token. Inspect existing output and runtime evidence. A claim grants no additional authority. Record findings in work/results/<id>/ and use the current revision and token to update the case:

```powershell
& $installation.python -E -s $service --root $installation.root --registry $registry --update example-id --fingerprint CURRENT_FINGERPRINT --expected-revision 3 --state resolved --note 'Evidence establishes the disposition.' --evidence work/results/example-id/recovery-review.md --lease-token CURRENT_TOKEN
```

Resolution requires evidence hashes. Changing or removing evidence reopens the case. An expired claim returns to needs_decision; the previous task is never automatically rerun. A linked new attempt requires explicit authorization and a new immutable ID published through runners/publish-order.ps1. Do not edit status, receipts or the protected ledger.

The service detects failed attempts, running/pending attempts overdue by more than two configured stage timeouts plus two minutes (at least five minutes), and expired recovery claims. Overdue attempts receive an inspection case; the checker never kills a process or changes runner status. It does not automatically interpret every manually coordinated task.md, run private project-event workflows, or reproduce the private host's review-only auto-recovery policy. Case disposition does not deliver or close the original task.
