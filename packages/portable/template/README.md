# Your IAF Protocol workspace

Start here. This folder coordinates people and AI agents using ordinary files.

1. Configure `TEAM.md`: name your principal, coordinator, producer and reviewer; record actual access and boundaries.
2. Read `AGENTS.md` and `PROTOCOL.md` with each participating session.
3. The coordinator creates `tasks/<unique-id>/` and copies `templates/task.md` into it as `task.md`. Fill every required field before assigning work.
4. The producer copies `templates/acceptance.md` into the task folder, accepts the exact revision, and writes artifacts in `tasks/<unique-id>/results/`.
5. A separate reviewer copies `templates/review.md` into the task folder and checks the artifacts.
6. The coordinator uses `templates/delivery.md` to record actual delivery and close the task after review passes.

If an agent cannot open this folder, provide the needed files in its chat and save the returned artifacts yourself. Merely adding files does not trigger another agent. Explicitly notify the next participant through your chosen application or manually start their session.

First try the fictional completed packet in `examples/hello/`. Real work belongs in `tasks/`. Selected reusable context belongs in `knowledge/`; do not load that whole folder into every session.

Suggested starting instruction:

> Read AGENTS.md, TEAM.md, PROTOCOL.md, and tasks/<id>/task.md. Act only as the assigned role. Confirm the task revision and your actual file access. Follow the protocol and write only your assigned files. If you cannot write files, return their exact relative paths and complete content for the coordinator to save.

## Use the local dispatcher

For automated Codex/Claude execution and independent review on Windows, follow runners/README.md. It includes CLI installation/sign-in, configuration, smoke tests and optional boot-start setup. The dispatcher uses work/inbox and work/results with links back to the same task packet. Read its ownership table before publishing. No Node.js is required for manual extraction or the PowerShell runtime.
