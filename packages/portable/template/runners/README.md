# Windows dispatcher setup and operation

This is the local PowerShell component of AgentOS. It monitors JSON work orders, invokes installed Codex/Claude CLIs, runs the other provider as reviewer, and retains evidence. These are scripts, not a custom model API server. There is no compilation/build step for users.

New testers: start with [FIRST-RUN.md](../FIRST-RUN.md) for the short checklist, doctor and uniquely named greeting task. This guide is the full operational reference.

## 1. Prerequisites and login

Use Windows PowerShell 5.1 (included with Windows). Install Git for Windows and both model CLIs. Use the official [Codex CLI installation guide](https://learn.chatgpt.com/docs/codex/cli) and [Claude Code installation guide](https://code.claude.com/docs/en/installation). Claude offers `winget install Anthropic.ClaudeCode`. Open each CLI interactively in the new workspace and complete its own sign-in flow. For this subscription-based edition, choose your supported subscription login; do not configure model API keys. Account access and subscription limits still apply.

Verify versions and binary locations:

```powershell
codex --version
claude --version
Get-Command codex,claude | Select-Object Name,Source
```

The dispatcher requires absolute paths to actual .exe files, not .cmd/.ps1 npm shims. Prefer native CLI installations. If Codex was installed through npm, `npm root -g` locates global packages; inspect its @openai directory recursively for codex.exe and use the binary matching your Windows architecture. Run that exact executable with --version before configuring it. Do not pick an arbitrary old app-bundled version. Keep the resolved paths current after upgrades.

No provider source build is required. AgentOS calls Codex's `exec` mode and Claude's print/JSON mode. See [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode) and [Claude CLI reference](https://code.claude.com/docs/en/cli-reference). CLI flags can change: run the supplied tests and a real smoke task after upgrades. No paid model calls are made by installation or fake-CLI tests.

## 2. Configure the workspace

Extract the manual ZIP into a new folder. Set the principal, coordinator, access and limits in TEAM.md. Open PowerShell in that folder and substitute actual executable locations below. Choose a NEW ledger directory outside the workspace, on local storage, with an existing parent.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\runners\setup.ps1 `
  -CodexPath 'C:\Path\To\codex.exe' `
  -ClaudePath 'C:\Path\To\claude.exe' `
  -LedgerDirectory "$env:LOCALAPPDATA\AgentOS-Ledger"
```

The agent-assisted bundle performs the same operation through Install-AgentOS.ps1, adding a -Destination argument to copy the same template first. Setup refuses existing configuration, ledger directories, and runtime history. It never installs a task or launches a model. Keep the ledger private and backed up. It is outside the normal shared context, not an OS security boundary against programs with the same Windows permissions. Avoid junctions/symlinks and cloud-synced ledger locations.

Generated runners/dispatcher.json records the designated hostname, both executable paths and the ledger location. Model selection remains in each client configuration/default; this release does not automatically choose a model by task size. Defaults are a 30-second settle period, 20 minutes per model attempt, and a Claude ceiling of 25 turns. Task budgets can tighten that ceiling. Source/search limits and Codex turn limits are advisory. Edit settings only while the monitor and dispatcher are stopped.

## 3. Run the mechanical checks

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\runners\test-all.ps1
```

Tests run in disposable temporary folders, including fake CLI processes. They do not use your subscriptions, touch your live queue, or install a scheduled task. They verify state transitions, verdicts, ledger recovery, process timeouts, and monitoring. TestMode is for isolated fixtures only: never run it against real work because it writes simulated success records.

## 4. Run a real smoke task

The coordinator creates tasks/dispatcher-smoke/task.md from templates/task.md, using the objective and criteria in runners/smoke-order.example.json. Assign revision 2, name Codex as producer and Claude as reviewer, and authorize only the local greeting. Record producer acceptance of that scope (a human coordinator may record acceptance on the configured producer's behalf). Fill the rest of the task packet and TEAM.md first.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\runners\publish-order.ps1 `
  -OrderPath .\runners\smoke-order.example.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\runners\monitor.ps1
```

Allow the 30-second settling period. The monitor starts execution and then independent review. Check work/status/dispatcher-smoke-001.json, work/results/dispatcher-smoke-001/, and work/handoffs/dispatcher-smoke-001.json. Only completed at the review stage establishes dispatcher success. The handoff still says delivery and closure are pending. Show the greeting to the principal and record delivery/closure in tasks/dispatcher-smoke/ using the supplied templates.

The monitor calls no model while idle. For one scan instead, run runners/dispatcher.ps1; execution and review need separate scans. Publish supporting files first, then publish the complete JSON through publish-order.ps1. Never edit published order bytes or reuse an ID. For a failed smoke, inspect evidence and use a new linked ID and updated output path after authorizing the correction.

## 5. Understand ownership and state

| Record | Writer | Meaning |
|---|---|---|
| tasks/<task_id>/task.md and acceptance.md | Coordinator; acceptance on producer's behalf if recorded explicitly | Human-facing scope, revision and authorization before publishing |
| work/inbox/<id>.json | Coordinator via publish-order.ps1, then immutable | Automated assignment referring to task_id and assigned_revision |
| work/results/<id>/ | Producer, then reviewer in separate stage files | Artifacts, output, verdicts and runtime evidence |
| work/status/, work/receipts/, external ledger | Dispatcher only | Per-attempt execution/review state |
| work/handoffs/<id>.json | Dispatcher creates; coordinator records delivery if needed | Pending delivery acknowledgment, not proof of delivery |
| tasks/<task_id>/review.md and delivery.md | Reviewer/coordinator as appropriate | Link exact reviewed runtime artifacts; record delivery and closure |

For automated tasks this table extends the manual PROTOCOL.md ownership map: output is under work/results/<order-id>, not tasks/<task-id>/results. The coordinator links those paths and appends state history; the dispatcher does not update Markdown tasks automatically. Acceptance is explicit before publication; the dispatcher validates the order, not the truth of a claimed human authorization. Do not operate a manual producer on the same assignment concurrently. Runtime completed does not mean project closed.

Reviewers must leave producer artifacts unchanged and write their review evidence and review-verdict.json. This is a cooperative file contract, not per-file OS isolation. Codex uses workspace-write sandboxing. Claude uses acceptEdits with the explicit built-in tool list in dispatcher.ps1 and no MCP configuration; Bash/Web tools are permitted for authorized tasks. Configure the workspace with that capability in mind. No permission-bypass flag is used. The nonce binds a verdict to a stage/run; it is not a cryptographic signature or protection against a malicious participant.

## 6. Start at boot (optional, after real foreground success)

From local PowerShell, use the account that owns the CLI logins. Get-Credential is a LOCAL Windows dialog; never put its password in a prompt or a file. Windows account policy may require elevation to register this task.

```powershell
.\runners\install-dispatcher.ps1 -Credential (Get-Credential)
Start-ScheduledTask -TaskName 'AgentOS Portable Dispatcher'
Get-ScheduledTaskInfo -TaskName 'AgentOS Portable Dispatcher'
```

The installer preserves any existing task with that name. A new task uses Password logon, a boot trigger, limited privileges, restart on failure, and no scheduler lifetime limit. Test with a NEW smoke ID in the scheduled context. A foreground run does not prove scheduled or signed-out behavior. The native Codex sandbox may fail in a noninteractive Windows session on some versions/hosts. This portable edition does not include the private installation's WSL wrapper; do not disable the sandbox to work around that. Retain foreground operation if scheduled validation fails. Sleep, shutdown, connectivity, account access and quota still affect availability.

## 7. Stop, recover and remove

For a graceful stop, create state/monitor.stop from a second PowerShell window. The monitor waits for its active child to finish. Remove that marker only when you intend to resume. Disable the scheduled task to prevent future boot starts; do not force-stop an active model merely to pause new work. The stop marker does not cancel a dispatcher scan already in progress.

Interrupted or failed runs are retained as needs_attention/blocked and are not automatically replayed. Unconfirmed process cleanup creates state/runtime-quarantine.json and suspends further model launches. Inspect the owned processes and effects, preserve evidence, and clear quarantine only after cleanup is established. Restore a missing/corrupt ledger from a verified backup; never initialize an empty replacement. The ledger can reconstruct status/receipts/handoffs, not deleted deliverables. Runtime cleanup must preserve results and pending delivery evidence. Prefer a new linked order over RetryId; retry controls are operator recovery tools, not routine scheduling.

To remove the installation, stop gracefully, disable the newly created task, preserve workspace and ledger evidence, then remove the task and folders only when desired. Provider CLI installations and their sign-ins are separate and need not be removed.

## Scope and provenance

Adapted from this repository's working local dispatcher on 2026-09-11. The portable copy retains the monitor, process helper, telemetry and durable ledger; replaces machine-specific configuration; and excludes relay, Git checkpoint observers, Ollama and the private WSL integration. Drive is unnecessary. Cross-platform agents can use the file protocol manually; this dispatcher edition supports native Windows Codex and Claude only.
