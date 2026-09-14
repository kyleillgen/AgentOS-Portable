# IAF Protocol deployment profiles — 0.3.0 source preview

One installer, three choices. The base stays usable without background processes. This preview is separate from the published Portable 0.2.1 downloads and does not migrate existing installations.

| Choice | Includes | Requirements |
|---|---|---|
| Manual (default) | File protocol, templates, examples, role instructions, diagnostics | Windows PowerShell 5.1 for installer; the resulting file workflow is platform independent |
| Automated | Manual plus foreground runner, immutable orders, ledger, bounded processes, independent review | Windows, Git for Windows, native Codex and Claude executables and the user's own local sign-ins |
| Unattended | Automated plus headless case checker, independent health observer and startup-task management | Python 3.10+, a local state folder outside sync, and an account able to register password-backed Windows startup tasks |
| Optional Desk | Loopback reports and case interface; depends on operations code | Automated or Unattended, Python; no background task required for the interface |

## Install

Extract the profiles ZIP into a folder, then open PowerShell there. Create the parent folders first.

```powershell
# No provider paths, Python or local ledger needed.
.\Install-IAF.ps1 -Destination C:\AgentOS -Profile Manual

# The executable paths are examples: supply your own installed native binaries.
.\Install-IAF.ps1 -Destination C:\AgentOS -Profile Automated -CodexPath C:\Tools\codex.exe -ClaudePath C:\Tools\claude.exe -LocalStateDirectory C:\AgentOSLocal

.\Install-IAF.ps1 -Destination C:\AgentOS -Profile Unattended -CodexPath C:\Tools\codex.exe -ClaudePath C:\Tools\claude.exe -LocalStateDirectory C:\AgentOSLocal -PythonPath C:\Python312\python.exe -Desk
```

Choose one command and a new destination. The local state folder must also be new, separate from the workspace, and outside any synchronization service. Setup verifies packaged bytes and prerequisites before creating folders. It does not launch models or register tasks. Failed installations leave an explicit failure receipt and preserve partial state for inspection; no empty-ledger reset is attempted.

In the installed workspace, read FIRST-RUN.md and run `IAF.ps1 Doctor`. After the foreground greeting workflow passes, activate an Unattended installation with `IAF.ps1 Enable -Credential (Get-Credential)`. Windows, not an agent or browser, then owns the runner, checker and watchdog. Never pass a password in command text or save it in a script.

## Understand and maintain

`IAF.ps1` provides Doctor, Run, Check, Snapshot, Desk, Enable, Disable, RemoveDesk and Uninstall. The installed FIRST-RUN.md explains each action. Installed file ownership, configured paths and selected components are recorded in `agentos-installation.json`. That receipt contains no passwords.

`VERSION` identifies the underlying file foundation (0.2.1); the installation receipt identifies this deployment package (0.3.0).

Operations is usable through its CLI without the Desk. Recovery cases have fingerprints, revision checks, finite worker claims and evidence-backed resolution. Detection does not authorize replay. The portable checker creates cases; workers inspect partial output and coordinate a linked new attempt when authorized. It does not contain the private installation's automatic review-only publishing policy or its project-event database. The base task protocol stays manual and authoritative for delivery/closure.

Removing Desk does not remove monitoring. Uninstall removes unchanged automation files and this installation's Windows tasks after graceful retirement; it preserves the base, modified files, tasks, reports, recovery history, configuration and protected ledger. Profile changes and upgrades currently require a fresh installation and explicit migration, not copying old work into an empty ledger.

## Scope and release gate

This is a source packaging preview, not a claim of verified clean-machine or signed-out deployment. The initial runner supports the existing native Codex/Claude pair as a built-in integration. Provider selection beyond that pair, Ollama, WSL, Astra, desktop tray notifications and Drive are not bundled. See [CONTRACTS.md](CONTRACTS.md) for extension boundaries.

The private host remains on its existing, working installation. A host migration is a separate task with state reconciliation and rollback. The published 0.2.1 bundles remain unchanged.

Before promoting this preview, run the package tests, install on a clean Windows machine, authenticate both providers locally, complete a real greeting and review, activate under the intended account, then verify reboot, signed-out behavior and removal. Provider login and Windows credentials cannot be inferred from synthetic tests.

## Build and verify (maintainers)

From the repository root, build with Windows PowerShell:

```powershell
.\packages\deployment\build.ps1 -OutputDirectory C:\AgentOSBuild
.\packages\deployment\test\profiles.test.ps1 -PythonPath C:\Python312\python.exe
```

The builder composes an allowlisted, unconfigured 0.2.1 foundation with separately owned operations and desk payloads. It excludes runtime tests from installed workspaces, scans for private paths/credentials, and emits an integrity inventory plus ZIP SHA-256. Building needs neither access to the private installation nor Git or Node at runtime. The source extraction provenance is in CONTRACTS.md; the extracted sources are checked in and built directly.

The build emits `iaf-profiles-0.3.0.zip` and `SHA256SUMS.txt` in the chosen output folder. Extract that ZIP into a new folder before running `Install-IAF.ps1`. The legacy entry points and stored `agentos-*` identifiers remain compatible; this rename does not migrate an existing host.
