# Canonical main baseline — 2026-11-25

Repository: https://github.com/tkanjanarux/ragnarok-offline . `main` preserves shipped iOS source57c5a83 and merges server patch4793697. The upstream `origin` repository is not modified. This consolidation does not deploy or restart a server.

- iOS: application/package/project source and submodule pin match57c5a83; HP under party members, Party/minimap/coordinates/navigation, companions and RO foundation flows remain present. Existing unsigned IPA: https://76-13-19-77.sslip.io/downloads/RagOff-57c5a83.ipa . External signing is required.
- Native backend: `server/` reconstructs two distinct deployed profiles from the pinned dependency. It never substitutes the stale `/opt/ragoff-server/src` snapshot. Clone/build instructions are in `../../server/README.md`.
- Validation: portable27 tests and migration4 tests were rerun. Both profile sources reconstruct byte-for-byte against the deployed manifests; see `validation.json`. This is source reproducibility, not a claim that every compiler emits the same executable bytes. No Simulator/device visual verification was run.
- CI: `baseline.yml` checks portable tests, migration and both source profiles. `ro-foundations.yml` retains Xcode27.2 unsigned iPhone builds and manual dispatch without a Simulator job. Superseded workflows are preserved in archive tags.
- Archives: `archives.json` maps old client refs to readable archive tags. The stopped companion experiment archive is source-only and has no private parent history; it is not part of main's runtime source. Owner-puller UI drafts are preserved in the local-UI archive, not silently merged over the shipped UI.
- Private exclusions: raw workspaces/history bundles, account evidence, logs, player SQLite databases, credentials, binaries, build caches and GRF/assets remain outside public Git. The original companion-dev history and excluded evidence are retained privately; the clean local repository points to an archival snapshot.

Attendance remains without an active event. No schedule/reward/balance was invented. Deployment and account integration results are summarized without private account records in `deployed-versions.json`.
