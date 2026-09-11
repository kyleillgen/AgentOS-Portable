# AgentOS

**Portable 0.2.1 — early preview.** A local file workspace and Windows PowerShell dispatcher for coordinating AI agents. Codex and Claude execute and independently review assignments through their existing CLIs. Other clients can use the same file contract with manual handoffs.

## Start here

**[Read the short setup guide](packages/portable/START-HERE.md)** or [open the versioned release](https://github.com/kyleillgen/AgentOS-Portable/releases/tag/v0.2.1).

| Setup path | Download | First step |
|---|---|---|
| Manual | [Manual ZIP](https://github.com/kyleillgen/AgentOS-Portable/releases/download/v0.2.1/agentos-manual-0.2.1.zip) | Extract to a new folder; open START-HERE.md |
| Agent-assisted | [Agent setup ZIP](https://github.com/kyleillgen/AgentOS-Portable/releases/download/v0.2.1/agentos-agent-setup-0.2.1.zip) | Extract and give a locally connected agent AGENT-SETUP.md |

Both downloads contain the same workspace. No Git knowledge, source compilation, Node.js, Drive connection or custom model API integration is needed to use the Windows package. The optional source scaffolder uses Node.js.

For agent-assisted setup:

> Read AGENT-SETUP.md and set up AgentOS on my laptop. Inspect what is installed, guide me through logins and permissions, run the mechanical checks and greeting workflow, and report what actually works.

The agent needs authorized local file and execution access. Uploading a ZIP to a cloud-only chat does not grant laptop access; that session can prepare a handoff instead.

## What works in this foundation

- Shared instructions, explicit ownership, task/review/delivery templates and a worked example.
- Windows inbox monitor and serialized Codex/Claude execution with alternate-provider review.
- Durable local ledger, run-specific completion signals, timeouts and no automatic replay after failure.
- Two installation paths, a read-only doctor, a prepared first-run greeting and optional boot-start instructions.

The lifecycle is intake → assignment → acceptance → execution → independent review → delivery → closure. A completed dispatcher run creates a delivery handoff; the coordinator records actual delivery and closure.

## Requirements and limits

For automation: Windows PowerShell 5.1, Git for Windows, both native Codex and Claude executables, and your own supported sign-ins. The file workflow alone can be used on other platforms. New local folders are required; setup preserves existing installations. Use simple paths without brackets or junctions.

This is an early preview for technical testers. Automated checks cover fresh-folder installation from both ZIPs and synthetic CLI execution, review, recovery, timeouts and monitoring. They do **not** establish real account access, a clean-machine installation, or scheduled/signed-out compatibility. Validate the real greeting on the receiving computer before assigning important work. Native Windows Codex has version/session-specific sandbox limitations; foreground operation is the initial target.

Google Drive, WSL adapters and Ollama are optional future integrations. The base does not install, sync or configure them. See [extension boundaries](EXTENSIONS.md).

## Build, contribute and verify

- [First real greeting and troubleshooting](packages/portable/template/FIRST-RUN.md)
- [Full Windows setup and operation](packages/portable/template/runners/README.md)
- [Architecture](packages/portable/ARCHITECTURE.md)
- [Source and test commands](packages/portable/README.md)
- [Changelog](packages/portable/CHANGELOG.md)
- [SHA-256 checksums](packages/portable/downloads/SHA256SUMS.txt)
- [Contributing and bug reports](CONTRIBUTING.md)

Licensed under [MIT](LICENSE). Forks and focused contributions are welcome. Keep private task data, credentials and installed configurations out of contributions.
