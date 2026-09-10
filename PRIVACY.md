# MATER privacy

MATER is a local macOS application. It does not contain analytics, telemetry, advertising, account sign-in, automatic crash submission, or a service that uploads alignments. Opening, editing, analysis, export, and recovery operate on the Mac.

## Data stored locally

- MATER reads and writes files only when the user opens, saves, exports, or creates a refinement/result file.
- Recovery snapshots are stored in the user's Application Support area, limited to 30 snapshots per document identity, and removed automatically after 30 days. They can be deleted at any time in **MATER → Settings → Recovery**.
- Residue-color preferences and an optional R-scape executable path are stored in macOS user defaults.

## External programs and network access

MATER itself does not send alignment data over the network. If the user runs R-scape or CaCoFold-refine, MATER passes a local temporary Stockholm snapshot to the separately installed R-scape process. R-scape behavior and its dependencies are governed by that installation. MATER's R-scape analysis retains the user-requested local result files; CaCoFold-refine removes its temporary working directory after collecting the refined alignment.

Links in Help, documentation, or the issue tracker open in the user's web browser. The optional developer corpus-audit script downloads the public current Rfam SEED archive only when a developer explicitly runs it; this is not part of normal app operation.

## Diagnostics and bug reports

**Changes → Copy Diagnostics** copies the MATER version, macOS version, CPU architecture, alignment dimensions, structure counts, validation messages, integrity status, document filename, and detected R-scape executable path. It deliberately excludes sequence strings and annotation-row contents. The user should still review filenames, validation messages, and paths before sharing the report.

MATER never submits diagnostics automatically. Bug reports, screenshots, logs, and example alignments are shared only when the user deliberately sends them. Do not attach unpublished or sensitive biological data to a public issue; use a minimal synthetic or sanitized example whenever possible.
