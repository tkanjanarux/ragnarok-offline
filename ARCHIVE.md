# Stopped companion experiments — not a deployment baseline

Preserved for source recovery only. No runtime is started and no policy is enabled by this tag.
The active baseline is main, server/profiles/production or playable, matching the deployed release.

The patch is the normalized source delta from main server production profile (2026-11-25) to the private companion-dev snapshot 9912035ca1d3144ed04953c3bd388ea7868df55a. It also removes later closeout fixes absent from that old experimental tree: do not deploy it. Normalize reconstructed source CRLF to LF before inspecting/applying this archival patch in a separate directory. Test tools may require old private fixtures; account evidence and credentials are intentionally not published.

Exact original bytes, full local history, excluded evidence and all untracked files are retained in the owner's private verified bundle/tar backup. This archive is not a replacement for that backup. rAthena-derived source remains GPL-3.0; see LICENSE.
