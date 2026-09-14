# Contributing

IAF Protocol Portable is an early preview. Small fixes, clearer onboarding and reproducible bug reports are especially useful. Propose larger adapters or features in an issue before implementation; keep the shared file contract and the Windows runner separable.

Fork the repository and open a pull request with the problem, resulting behavior, tests and limitations. Never include personal workspaces, prompts, provider credentials, installed dispatcher configurations or run ledgers. Keep synthetic test fixtures clearly labeled.

On Windows, from packages/portable run `npm test` (Node 18+) and `powershell -NoProfile -ExecutionPolicy Bypass -File test/release.test.ps1`. The latter creates temporary packages and installs with fake executables; it launches no provider models and registers no scheduled tasks. Runtime tests exercise real child processes, including timeout cases. Receiving-machine login and foreground/scheduled tests remain separate.

For the deployment profiles, also run `packages/deployment/test/profiles.test.ps1 -PythonPath <absolute-python.exe>` from the repository root. This builds and extracts a ZIP, installs all profiles into fresh folders, tests removal/preservation and scheduling failures, and exercises the checker independently from the HTTP interface. No real startup task or provider account is used by these tests. New extensions must satisfy [the package contracts](packages/deployment/CONTRACTS.md). Keep feature expansion paused until the clean-machine and signed-out release gates are established.

Bug reports should include package version, Windows/PowerShell and CLI versions, setup path, exact failed step, expected behavior and a redacted error. The doctor report deliberately omits configured paths and usernames. Do not attach whole run folders. Please report a potential secret exposure privately through the repository owner's GitHub profile contact options instead of posting the secret in an issue.

The first release goal is a dependable foundation: explicit ownership, preservation of existing work, independently reviewed results and honest evidence. Avoid new automatic retries, silent provider switches or global machine changes.
