# Extensions to the base

The base release must remain usable with local files and manual handoffs, plus the optional Windows dispatcher. Integrations should depend on a specific released base version and keep their setup, configuration and tests separate.

The [0.3.0 deployment preview](packages/deployment/README.md) implements Manual, Automated and Unattended profiles plus an optional desk. Its [package contracts](packages/deployment/CONTRACTS.md) define ownership, dependency direction, state locations, installation/removal and release gates. Safety remains mandatory within the runner. Unattended monitoring is independent of both the desk and agents. This uses explicit packages; no general plug-in framework is introduced. The initial automated provider integration remains the existing native Codex/Claude pair; arbitrary provider selection is not yet implemented.

The separate [IAF Protocol Drive preview](https://github.com/kyleillgen/IAF-Protocol-Drive) adds explicit selected-file exchange through Drive for desktop. Its implementation lives in `packages/google-drive` in that repository; it is not installed by the base or deployment profiles. It keeps credentials, the local run ledger, and locks out of transport, uses one dispatcher host, and stages imported files for review. Live sync remains a separate unverified boundary. File sync is not a distributed lock or proof of delivery.

Current layout: `packages/portable` for the file foundation and runner, `packages/deployment` for explicit profile composition and operations/desk payloads, and the separate Drive repository for transport. Future extensions should retain their own versions, prerequisites, configuration, diagnostics, removal, and meaningful tests.

Extensions must preserve independent review, distinguish execution from delivery, and avoid silently adding external access, retries, account changes or new model costs. They must state what is verified locally, remotely, and while signed out. Google Drive integration is not included in this release.
