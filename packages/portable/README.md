# IAF Protocol portable package 0.2.1 — early preview

A shared file workspace with a local Windows PowerShell dispatcher for Codex and Claude. Other agents can participate through the same file contract with manual handoffs. Drive and model API integrations are not required.

## Two ways to start

- **Manual:** download [agentos-manual.zip](https://github.com/kyleillgen/IAF-Protocol/releases/download/v0.2.1/agentos-manual-0.2.1.zip), extract into a new folder, and open START-HERE.md.
- **Agent-assisted:** download [agentos-agent-setup.zip](https://github.com/kyleillgen/IAF-Protocol/releases/download/v0.2.1/agentos-agent-setup-0.2.1.zip), upload it to a locally connected agent, and ask it to read AGENT-SETUP.md. It inspects the laptop, guides logins, configures and tests the same dispatcher.

See [START-HERE.md](START-HERE.md) for choosing a path. Both downloads contain the identical template; both use runners/setup.ps1. A cloud-only session can prepare a local handoff but cannot install on a laptop without local tools.

## Included

Shared agent instructions and role definitions; task, acceptance, review and delivery templates; a worked example; PowerShell dispatcher, continuous monitor, durable ledger, timeout/process helpers, telemetry, fresh-install setup, atomic work-order publisher, scheduled-task installer, and isolated tests.

Read [the manual CLI and dispatcher guide](template/runners/README.md) for installation, sign-in, executable paths, permissions, foreground and scheduled smoke tests, starting/stopping, recovery and removal. No source compilation is needed. This release routes native Windows Codex and Claude; the private installation's WSL, Ollama, relay and checkpoint integrations are not included.

## Create from source

Copy template/ into a new folder (include dotfiles). Or use Node.js 18+ only for the optional scaffolding command:

```sh
node bin/init.mjs /path/to/new-workspace
```

The destination must be new and its parent must exist. This command does not configure logins or start the dispatcher. The agent bundle's Install-IAF.ps1 copies the same template and runs setup.ps1 with the supplied executable and ledger paths.

## Development and validation

`npm test` checks scaffolding and overwrite protection. Run template/runners/test-all.ps1 with Windows PowerShell 5.1 for runtime/setup tests using fake CLIs and temporary folders. Real subscription and scheduled-context tests are separate and required on each installation.

Run test/release.test.ps1 with Windows PowerShell 5.1 to build and extract both ZIPs, exercise both setup paths, and run the installed runtime tests without real model calls or scheduled tasks. The build refuses unexpected template files using release-files.txt and checks for configured or private content. This is a guardrail, not a substitute for reviewing a release.

Run build-bundles.ps1 -OutputDirectory <new-output-folder> to build both ZIPs and their SHA-256 manifest; it verifies matching workspace contents. Run `npm pack` for a local npm-format archive. The package remains private to prevent accidental registry publication; GitHub downloads work independently of that flag.

See [ARCHITECTURE.md](ARCHITECTURE.md) for interoperability and ownership limits. Installation does not change an existing IAF Protocol environment, schedule, or account configuration.

See CHANGELOG.md, template/FIRST-RUN.md and the MIT LICENSE. Live account access and clean-machine/scheduled operation remain receiving-machine checks.
