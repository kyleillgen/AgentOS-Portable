# Agent installation instructions

You are setting up AgentOS for the person who provided this bundle. Read START-HERE.md, template/FIRST-RUN.md, template/runners/README.md and template/TEAM.md. Use the same setup scripts as the manual path; do not invent a second dispatcher or silently replace installed infrastructure.

## 1. Establish where you can act

Determine the actual operating system and whether your tools can read and execute on the user's laptop. A container, cloud VM, uploaded folder or application workspace is not evidence of laptop access. Record the actual hostname and location. Never claim a laptop installation from a remote environment.

If local execution is unavailable, prepare the extracted workspace and a short handoff with the exact local commands from the manual guide. State "Prepared for local installation; not installed on the laptop." The user can open the bundle in a locally connected agent or run those commands. Do not request credentials in chat.

## 2. Inspect before modifying

Check existing AgentOS folders, relevant scheduled tasks, PowerShell, Git, and installed Codex and Claude CLI versions/paths. Confirm or obtain a new destination and a separate local ledger location. Prefer a new folder in the user's Documents folder and a new ledger folder under their local application data. Do not merge into an existing installation. Do not change existing scheduled tasks, global model configuration, or other agent systems.

Configure the user as principal. Ask only for missing material choices: destination if uncertain, permissions for this workspace, accounts to use, and whether background boot-start operation is wanted. The installation request authorizes ordinary setup within the agreed scope, not email, purchases, sharing private data with new providers, or bypassing security controls.

## 3. Install prerequisites and hand off logins

Use official provider instructions linked in the manual guide. Existing valid installations should be reused. Help the user install missing CLIs using the normal local approval flow. Resolve actual .exe paths; npm shims cannot be passed as the dispatcher executable.

Ask the user to complete each interactive sign-in in the provider's own interface. Never read, upload, copy into the workspace, or print authentication files, tokens or passwords. CLI installation, account login, and permission to work on files are separate checks. If login requires user interaction, pause that step while completing independent preparation.

## 4. Use the shared installation path

From the extracted agent bundle, run Install-AgentOS.ps1 with the agreed new destination, resolved Codex/Claude executables, and new external ledger directory. This copies template/ and calls the same runners/setup.ps1 that a manual user runs. It does not start models or install a scheduled task.

Fill TEAM.md with the principal, designated coordinator, producer/reviewer sessions, verified access, limits, and handoff method. Use the supplied scripts unchanged unless a concrete defect prevents setup. If a fix is required, preserve the original and report it. Use paths without brackets or junctions, keep workspace and ledger separate, and preserve a partially failed installation for inspection; never initialize over runtime history.

## 5. Verify in stages

Run runners/test-all.ps1 in the new workspace. It uses temporary fixtures and fake CLIs; this is mechanical validation, not proof of real model access. Run runners/doctor.ps1 and resolve failures. Use runners/prepare-smoke.ps1 with the configured principal and -AuthorizeLocalGreeting only when that scope is authorized. It creates a unique draft packet and acceptance record; review it and publish its order.json as FIRST-RUN.md describes. Start the monitor in the foreground, using a hidden background process only when needed and supported by your tools. Verify real execution, alternate-provider review, and pending delivery handoff. Show the greeting to the user and record delivery/closure separately.

A timeout, failed review, missing login or interrupted run is not permission to retry. Preserve evidence. Inspect the result, resolve the cause, and use a newly authorized linked ID. Do not reset the ledger or delete runtime records to make the check look successful.

## 6. Optional background operation

Only after the real foreground smoke passes, and only if the user requested boot-start operation, use runners/install-dispatcher.ps1. The user enters Windows credentials locally through Get-Credential. Never obtain a password in conversation. Preserve existing scheduled tasks. Test the new task in its actual scheduled context; interactive success does not prove signed-out operation. Native Codex can have session-specific sandbox limitations; do not remove its sandbox to make a test pass. If scheduled execution fails, leave it disabled and retain the foreground workflow.

## 7. Deliver an honest setup report

Create SETUP-REPORT.md in the new workspace (or the prepared handoff directory if laptop access is unavailable). Include destination, host, CLI versions, configuration/ledger paths without secrets, checks and evidence, foreground/scheduled/signed-out status separately, unresolved blockers, how to start/stop, and how to reverse setup. Use installed / verified / not tested / blocked accurately. Do not mark a simulated test as live verification.

Completion requires a usable local workspace and verified real producer/reviewer handoff, or an explicit blocked handoff explaining exactly what the user must do. Do not claim unsupported cross-platform dispatcher compatibility. Never send email.
