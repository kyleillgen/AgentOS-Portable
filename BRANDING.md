# IAF Protocol rename and compatibility

**IAF Protocol** means **It's All Files**. It is the new project name for AgentOS. The protocol defines shared records and task rules; the runner, operations, desk, and storage packages implement or support it.

| Before | Current identity |
|---|---|
| AgentOS / AgentOS Portable public foundation | IAF Protocol — `kyleillgen/IAF-Protocol` |
| AgentOS Drive | IAF Protocol Drive — `kyleillgen/IAF-Protocol-Drive` |

## Entry points and releases

- Deployment source: `Install-IAF.ps1` and `IAF.ps1` delegate to the existing `Install-AgentOS.ps1` and `AgentOS.ps1` implementations with the same parameters.
- Portable source: `Install-IAF.ps1` delegates to the original installer; `iaf-init` and legacy `agentos-init` invoke the same scaffolder.
- Fresh deployment builds use `iaf-profiles-0.3.0.zip`.
- Published 0.2.1 archives keep their original `agentos-*.zip` names, contents, hashes, and version. Their legacy installer names still apply. The portable builder retains compatible archive filenames; new source builds do not replace historical release assets.

## Stored identifiers

Existing `agentos-*` contract/schema identifiers, installation receipts, management locks, internal function names, configured task names, and example legacy installation paths remain compatible. The release's `AgentOS Portable Dispatcher` task name is unchanged. These identify existing records and integrations, not alternate public branding.

Do not rename a live installation folder, ledger, queue, task ID, or Windows task to match the brand. Do not initialize a replacement ledger. Host migration requires state reconciliation, backup, and verification.

Deployment 0.3.0 is a source preview. The underlying protocol/foundation remain v1/0.2.1. Private-host features are not automatically part of the public package.
