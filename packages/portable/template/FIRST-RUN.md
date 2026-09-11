# First install: start here

**Early preview 0.2.1.** Start in a new local folder on Windows. Foreground use is the first milestone; boot-start operation is optional and has separate compatibility limits.

## Before you start

- Extract the whole ZIP. Do not run scripts from inside the ZIP viewer.
- Choose a simple folder such as `C:\AgentOS`. Spaces work; brackets and junctions do not. Keep the ledger in a different local folder. Do not relocate a configured installation.
- Automated execution needs native Windows Codex and Claude CLIs, your own supported sign-ins, Git for Windows, and Windows PowerShell 5.1. Installation makes no model calls and needs no Node.js.
- Without both clients you can still use the manual file workflow in README.md and examples/hello/. Automatic independent review needs both.

## Set up and check

Follow [runners/README.md](runners/README.md), sections 1–3, to locate the CLIs, sign in, configure and run mechanical tests. Use ordinary PowerShell for foreground setup; administrator access is not normally needed. If Windows blocks downloaded scripts, review the download source and use the process-scoped `-ExecutionPolicy Bypass` commands in that guide; do not change the machine-wide execution policy.

Edit TEAM.md to name the principal, coordinator and participants and record their access and boundaries. Then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\runners\doctor.ps1
```

PASS means the named mechanical check passed. NOT_TESTED for account access is expected; the doctor does not log you in or start models. Address FAIL entries before proceeding.

## One harmless real task

Substitute the principal name you put in TEAM.md. This prepares one local greeting task and records your authorization and acceptance on behalf of the producer. It does not publish or run it.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\runners\prepare-smoke.ps1 `
  -Principal 'Your name' -AuthorizeLocalGreeting
```

Read the generated task packet, run the publish command it prints, then start:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\runners\monitor.ps1
```

Keep that window open. Allow at least 30 seconds for the order to settle; each model attempt can take up to 20 minutes. In a second PowerShell window, run the doctor again. Inspect `work/status/<printed-id>.json`: success means `state: completed` and `stage: review`. Read the greeting, execute and review summaries under `work/results/<printed-id>/` and the handoff under `work/handoffs/`.

After seeing the reviewed greeting, use templates/delivery.md to record delivery in the task folder and append closure to task.md. No automatic system can establish that you actually received it merely by producing a file.

## Stop and report back

From the workspace in the second window:

```powershell
New-Item -ItemType File -Path .\state\monitor.stop -Force
```

The monitor finishes its active dispatcher scan and stops. It does not cancel an active model. To resume later, remove only that marker and run the monitor again. Closing the window can interrupt a run; interrupted work needs inspection and will not replay automatically.

Tell the maintainer:

1. Package version, Windows version, and manual or agent-assisted path.
2. Whether setup and mechanical tests passed.
3. Whether the real greeting reached review/completed and you saw it.
4. The first failed step and exact error, if any.

The doctor output avoids configured paths and usernames and can be shared after review. Do not upload your ledger, TEAM.md, entire workspace, authentication files, prompts or raw logs. Share a redacted error excerpt only. A fresh folder test is not a clean-machine or signed-out test.

## If something fails

| Symptom | Next step |
|---|---|
| No CLI executable found | Install the CLI, reopen PowerShell and resolve its real .exe path; npm shims are not executable paths for this runner. |
| Setup refuses a folder | Use a new destination and a new ledger; existing work is preserved. Do not delete an existing ledger. |
| Setup interrupted after creating files | Preserve the partial workspace and ledger for inspection. For this unused first install, choose new folder names and rerun; never reinitialize history. |
| No activity | Check the doctor, stop marker, designated computer, and 30-second settle period. Monitor output is intentionally quiet; state/monitor-heartbeat.json records its last update. |
| blocked or needs_attention | Read the stage summary. Fix the stated cause and prepare a new authorized smoke ID; do not edit or reuse a published ID. |
| Login or unsupported flag error | Check the exact installed CLI's version/help and sign in interactively. CLI upgrades can change compatibility. |
| Native sandbox or scheduled-session failure | Keep foreground operation if it works. Do not disable the sandbox. This preview includes no WSL adapter. |

Background scheduling, account access and signed-out operation must be validated on each receiving computer. See the full runner guide for recovery and removal.
