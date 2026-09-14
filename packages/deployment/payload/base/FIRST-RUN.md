# First run

## Manual

Open TEAM.md and name your coordinator, producer and independent reviewer. Copy the templates into tasks/<new-id>/ and use examples/hello as a worked example. Follow PROTOCOL.md for acceptance, evidence, review, delivery and closure. No model executable, Python, Git, account setup, administrator access or background process is required for the file workflow.

On Windows, check installation integrity with:

```powershell
.\IAF.ps1 Doctor
```

## Automated

This preview's runner uses the Codex/Claude pair, each reviewing the other. Follow runners/README.md to sign in locally and perform the greeting workflow in the foreground. Git for Windows and both native provider executables are prerequisites for that workflow. Setup does not verify login or launch a model.

Use `IAF.ps1 Run` for the foreground event-driven monitor. It runs until stopped; run `IAF.ps1 Disable` in another terminal to request graceful retirement. To resume later, inspect incomplete work and remove state/monitor.stop explicitly. Unknown outcomes must not be replayed.

## Unattended

After the foreground workflow passes, open Windows PowerShell under the intended account with the Windows rights needed to register startup tasks:

```powershell
.\IAF.ps1 Enable -Credential (Get-Credential)
.\IAF.ps1 Doctor
```

Windows stores the scheduled-task credential. IAF Protocol does not save it in files. All three startup tasks use that same account: runner, deterministic checker and independent watchdog. Their names include this installation's ID. A registration failure is an error, not successful activation. The profile is only configured until activation succeeds, and Doctor checks actual health separately.

The runner requests that Windows stay awake while it runs. Manual sleep, shutdown, power loss, account policy, credential expiry and host failure still interrupt service. Windows restarts failed tasks after one minute. The checker watches filesystem changes with five-minute reconciliation; the separate watchdog checks health every ten seconds. No browser or agent app owns either process.

## Reports and recovery

With operations installed, use `IAF.ps1 Check` for one reconciliation or `IAF.ps1 Snapshot` for current cases and reports. Case updates require the current fingerprint and revision; worker claims expire. Use extensions/operations/README.md for the claim and resolution commands. The checker never launches a model or republishes an order. A compatible worker inspects evidence and prepares an explicitly authorized, linked new attempt when needed.

With the optional Desk installed, run `IAF.ps1 Desk -Port 8765` and open the local URL it prints. Closing or removing the desk does not stop the checker or watchdog. The desk is a foreground, loopback-only interface in this preview; desktop tray notifications are not bundled.

## Stop and remove

`IAF.ps1 Disable` requests a graceful stop and removes only this installation's background registrations. If a worker is still finishing, the command reports that it must be run again later; it never kills that worker to finish removal.

`IAF.ps1 RemoveDesk` gracefully closes and removes only the optional interface. `IAF.ps1 Uninstall` stops background operation and removes unchanged automation package files. Both preserve modified files. The base workflow, tasks, reports, local recovery records, runner configuration and protected ledger remain. No recursive workspace deletion is performed.

For a later upgrade or profile change, use a fresh installation and an explicit migration. This preview refuses in-place installation and never initializes a new ledger over prior work. Do not copy an old inbox into a fresh ledger. Back up the workspace and external local state together while stopped; restore the matching pair to the same host and paths, then run Doctor.

The software checks do not prove live provider access, reboot recovery, signed-out execution or remote file delivery. Verify those in the intended receiving environment before relying on unattended operation.
