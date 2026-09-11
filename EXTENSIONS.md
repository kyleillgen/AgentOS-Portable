# Extensions to the base

The base release must remain usable with local files and manual handoffs, plus the optional Windows dispatcher. Integrations should depend on a specific released base version and keep their setup, configuration and tests separate.

A future Google Drive package should add transport to the base rather than duplicate the whole tree. It must define which files sync, keep provider credentials and the local run ledger outside shared storage, designate one dispatcher host, and preserve the ownership and immutable-order contract. File sync is not a distributed lock or proof that another host has received a complete task packet.

Proposed layout: packages/portable for the base, and an independently installable packages/drive extension with its own version, prerequisites, setup, rollback and end-to-end sync tests. Do not enable it during base installation. A separate repository can follow if its maintenance or release cycle needs to diverge.

Extensions must preserve independent review, distinguish execution from delivery, and avoid silently adding external access, retries, account changes or new model costs. They must state what is verified locally, remotely, and while signed out. Google Drive integration is not included in this release.
