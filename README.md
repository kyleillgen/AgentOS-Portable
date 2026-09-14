# IAF Protocol

**It's All Files.** A file-based protocol for coordinating work between AI agents.

I got tired of shuttling information between my LLM services, but didn't want to wire everything into a custom harness. So I built a file-based task system: a shared place to leave assignments, pick up results, and pass work between the tools I already use.

The core is ordinary files and a clear task process. Optional tools add local execution, monitoring, and an interface. Formerly **AgentOS**; existing installations and the published 0.2.1 archives retain compatible filenames and state formats. See [rename compatibility](BRANDING.md).

## How it works

1. A coordinator records the objective, criteria, producer, reviewer, and allowed actions in a task packet.
2. The producer accepts the assignment and leaves its output and evidence in files.
3. A separate reviewer checks the exact output against the criteria.
4. The coordinator delivers the result and records closure. Interrupted or uncertain attempts remain visible for inspection.

The files preserve the assignment and evidence between sessions. They do not grant a chat-only service access to your computer. Manual handoffs are explicit coordinator actions. The optional Windows runner invokes the supported Codex/Claude pair automatically and serially.

## Start with the amount of machinery you need

| Layer | What it adds | Current status |
|---|---|---|
| **Protocol and workspace** | Roles, task packets, ownership, acceptance, review, delivery, closure | File protocol v1; explicit manual handoffs |
| **Runner** | Codex/Claude execution and alternate-provider review, protected history, timeouts, no blind replay | Included in Portable 0.2.1 |
| **Operations** | Headless recovery cases, finite case claims, independent health observation | Deployment 0.3.0 source preview |
| **Operations Desk** | Optional local reports and recovery interface | Deployment 0.3.0 source preview; monitoring is independent of the desk |
| **Drive exchange** | Selected-file export and staged import through Drive for desktop | [Separate development preview](https://github.com/kyleillgen/IAF-Protocol-Drive); live sync unverified |

[Architecture and authority](ARCHITECTURE.md) explains the boundaries. One configured host owns automated dispatch; file sync is not distributed locking.

## Try it

**New architecture:** [Deployment 0.3.0 source preview](packages/deployment/README.md) contains one installer with Manual, Automated, and Unattended profiles and an optional Desk. Build it using that guide, then use `Install-IAF.ps1` and `IAF.ps1`. It has not been promoted to a verified receiving-machine release.

**Existing downloads:** [Portable 0.2.1 early preview](https://github.com/kyleillgen/IAF-Protocol/releases/tag/v0.2.1) remains available under its original AgentOS archive names. It predates the separate deployment profiles. Follow the instructions inside the ZIP; its agent-assisted installer is named `Install-AgentOS.ps1`.

| Download | First step |
|---|---|
| [Manual ZIP](https://github.com/kyleillgen/IAF-Protocol/releases/download/v0.2.1/agentos-manual-0.2.1.zip) | Extract to a new folder and read START-HERE.md |
| [Agent-assisted ZIP](https://github.com/kyleillgen/IAF-Protocol/releases/download/v0.2.1/agentos-agent-setup-0.2.1.zip) | Give a locally connected agent AGENT-SETUP.md |

Neither Windows download requires Git knowledge, source compilation, Node.js, Drive, or a custom model API integration. Automation requires Windows PowerShell 5.1, Git for Windows, both native Codex and Claude executables, and your own supported sign-ins. Provider usage limits still apply. Uploading a ZIP to a cloud-only chat does not grant laptop access.

For manual use, start with the [workspace guide](packages/portable/template/README.md), fill in TEAM.md, and follow the [file contract](packages/portable/template/PROTOCOL.md). Participants need verified file access or an explicitly attributed human handoff.

## Safeguards and limits

The runner preserves execution and review evidence, binds completion signals to their run, and keeps its protected ledger outside shared storage. Failed or ambiguous work is not automatically replayed. Operations observes failures and manages recovery cases; it does not authorize retries or close tasks. A reviewed execution creates a pending delivery handoff, not proof that the principal received it.

Independent review is a separate check, not a correctness guarantee. File ownership is a cooperative contract, not an operating-system security boundary. Local files do not make configured model-provider calls local or offline.

This is an early preview for technical testers. Tests cover scaffolding, Windows installation/runtime, deployment profiles, recovery, removal, and scheduling contracts. Synthetic clients and isolated process checks do not establish real account access, receiving-machine installation, reboot, or signed-out compatibility. Complete a real foreground greeting and review before testing unattended operation.

Automation currently supports the native Codex/Claude pair. Arbitrary provider adapters, WSL, Ollama, and private-host policies are not bundled. Storage transport is optional and grants no additional dispatcher authority.

## Read, build, and contribute

- [Architecture](ARCHITECTURE.md) and [extension boundaries](EXTENSIONS.md)
- [Deployment setup, build, and tests](packages/deployment/README.md) and [package contracts](packages/deployment/CONTRACTS.md)
- [Portable source and tests](packages/portable/README.md)
- [First real greeting](packages/portable/template/FIRST-RUN.md) and [runner operation](packages/portable/template/runners/README.md)
- [Rename compatibility](BRANDING.md) and [contribution guidance](CONTRIBUTING.md)

Licensed under [MIT](LICENSE). Keep credentials, private task data, installed configurations, and run ledgers out of contributions.
