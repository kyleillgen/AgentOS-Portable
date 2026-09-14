# Start here — IAF Protocol Portable 0.2.1

**Early preview for Windows testers.** This is a local shared folder plus a PowerShell dispatcher. It uses your installed Codex and Claude CLIs for execution and independent review. No Drive connection or model API setup is required.

## Pick a setup path

- **Manual ZIP:** extract it to a new local folder and open its START-HERE.md. That file is the first-run checklist, including setup, diagnostics, a greeting task and reporting a problem.
- **Agent-assisted ZIP:** extract it and ask your locally connected agent to read AGENT-SETUP.md. It must inspect the computer, guide sign-ins, configure a new workspace and run the same checks. If the session has no laptop access, it must say so and prepare a local handoff.

Download both options from the [0.2.1 release](https://github.com/kyleillgen/IAF-Protocol/releases/tag/v0.2.1). Check SHA256SUMS.txt from the same release with PowerShell's Get-FileHash if you want to verify the downloaded bytes.

## What you need

Windows PowerShell 5.1, Git for Windows, native Codex and Claude executables, and supported sign-ins for both clients. No Node.js or build tools are needed for installation. Both clients are required for automatic cross-provider review. Without them, the manual file workflow remains available.

Choose a new local workspace and a separate new local ledger folder. Use simple folder names; spaces are supported, brackets and junctions are not. Complete the real greeting in the foreground before considering boot-start operation. Credentials stay in each provider's own login interface.

## Reading this from source or the agent bundle?

The [first-run checklist](template/FIRST-RUN.md) and [full CLI setup guide](template/runners/README.md) are under template/. The agent bundle's Install-IAF.ps1 copies that folder into a new destination and uses the same setup.ps1 as the manual path.

Mechanical tests use fake CLIs. Real logins, clean-machine installation and scheduled/signed-out behavior are still checks for the receiving computer. The [MIT license](LICENSE) permits forks and reuse; contributions should contain no private workspace data.
