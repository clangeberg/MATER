# Changelog

## 1.0.0 — 2026-09-10

- **First public release:** the structure-aware Stockholm editor, full user guide, Rfam teaching files, and universal macOS app are ready for general use.
- **Manual RNA curation:** linked stem-arm gap movement, partner highlighting, pseudoknot-aware structure editing, residue colors, and stem/element color modes.
- **Alignment safeguards:** locked ungapped-sequence integrity, registered `#=GR` movement, stable undo/redo, validation before save, and rolling local recovery.
- **Structural context:** R2R-style consensus, entropy, gap-frequency, occupied-pair problem tracks, a Structural Quality Inspector, and large-alignment navigation.
- **Refinement:** previewed helix-neighborhood suggestions, cancellable whole-alignment Wiggle-refine, and optional CaCoFold-refine.
- **External analysis:** optional R-scape evaluate-given-structure runs with pairwise tables and an in-window R2R drawing.
- **Release checks:** deterministic edit properties, Rfam corpus compatibility, large GUI/render/export stress tests, and native Apple-silicon/Intel packaging.
- **Public project files:** BSD 3-Clause license, citation metadata, privacy policy, contribution notes, issue forms, and stable-tag release automation.

## 0.9.1 — 2026-09-09

- **Randomized integrity suite:** 10,000 deterministic safe edits plus malformed-input fuzzing, checking width, ungapped sequences, `#=GR` attachment, WUSS, stable validation, and save/reopen invariants.
- **Undo/redo integrity suite:** randomized exact restoration of sequence-plus-`#=GR` gap movement.
- **Rfam corpus audit:** an on-demand audit of 100–500 evenly sampled families from the current official SEED archive; the release audit passed 250 of 4,227 families, including `#=GR` and pseudoknot cases.
- **GUI stress matrix:** quick and full offscreen tests from 100 × 1,000 through 5,000 × 1,000 and 200 × 10,000, covering rendering, linked edits, undo/redo, reopen, and bounded PDF/SVG export.
- **Deep-alignment consensus scaling:** exact duplicate aligned patterns are represented as equivalent zero-length GSC subtrees, preserving relative R2R/GSC weights while keeping redundant alignments responsive.
- **Stable tiled PDF export:** one-page PDFKit source documents remain alive until the combined PDF finishes rendering, preventing the large-export warning and stall found by the stress matrix.
- **R-scape compatibility coverage:** paths with spaces, ordinary and pseudoknotted input, absent/non-executable/incomplete installs, missing R2R output, retained failure diagnostics, and cancellation.
- **CaCoFold-refine compatibility coverage:** successful, missing, malformed, and failed output with disposable temporary products.
- **Invalid-Stockholm save protection:** a prominent safety banner and an explicit per-document warning override before malformed output can be saved.
- **Support and privacy tools:** privacy-safe **Copy Diagnostics**, structured bug/feature issue forms, and a documented no-analytics/local-data privacy policy.
- **Continuous integration:** Node 24 releases of GitHub's official checkout and artifact actions, randomized properties and quick GUI stress on every push, and monthly/manual full GUI and Rfam audits.
- **Distribution:** ad-hoc signed and unnotarized, with no paid Apple developer tooling or Zenodo setup.

## 0.9.0 — 2026-09-08

- Move every matching `#=GR` row through the same full-column permutation as its sequence during shifts, gap opening/closing, suggested edits, paste/reversion, and Wiggle-refine; preserve the user's mixed `.`/`-` gap symbols.
- Add residue-annotation attachment verification and regression coverage so PP/SS characters cannot silently fall out of register during gap-only sequence movement.
- Distinguish wrapped Stockholm block continuations from duplicate identifiers; retain same-block duplicates as separate rows and report a specific validation error.
- Give validation issues stable identities to eliminate unnecessary SwiftUI list churn.
- Add cancellable Wiggle-refine with pass, sequence, and accepted-edit progress; cancellation never changes the source or writes a partial result.
- Replace repeated UI structure parsing with cached pairs and batch multi-character edits; add a reproducible 5,000 × 1,000 synthetic performance benchmark.
- Isolate recovery by canonical file path, expire snapshots after 30 days, and add a confirmed **Clear all recovery data** setting.
- Add native About, Settings, and Help commands, including persistent residue-color and R-scape-path controls and an offline bundled guide.
- Migrate the bundle/type identifiers to `io.github.clangeberg.mater` while copying existing residue-color and R-scape preferences from the former defaults domain.
- Add a BSD 3-Clause license, `CITATION.cff`, a real application screenshot, portable SDK selection, universal release packaging, and macOS GitHub Actions testing/tag artifacts.
- Keep release builds ad-hoc signed and unnotarized; no paid Apple developer tooling is required.

## 0.8.1 — 2026-09-01

> Safety advisory: versions through 0.8.1 can leave `#=GR` per-residue annotations at their old columns after a sequence gap shift. Upgrade to 0.9.0 before editing alignments containing `#=GR` rows.

- Rename **Auto-refine copy** to **Wiggle-refine** and write results as unique `*-MATER-wiggle-refined.sto` files.
- Add **CaCoFold-refine**, which runs a separately installed R-scape with `-s --cacofold`, retains only its improved Stockholm alignment, and deletes all temporary analysis products.
- Disable CaCoFold figure generation because this focused workflow does not retain drawings, tables, or logs; the full **Run R-scape** analysis remains available separately.
- Open both refinement results explicitly through MATER's document interface instead of the macOS default plain-text application.
- Add nonfatal R-scape discovery and executable-selection handling to CaCoFold-refine.
- Validate the generated CaCoFold Stockholm result before saving and opening it.
- Add automated disposable-output coverage and an opt-in integration test exercised against R-scape 2.6.16.

## 0.8.0-alpha.1 — 2026-08-31

- Extend previewed refinement across both complete helix arms and up to three neighboring unpaired columns, using bounded gap redistribution and a leave-one-out GSC-weighted sequence profile.
- Extend **Auto-refine copy** with coordinated helix-arm window moves that iterate to a local structural fixed point while preserving alignment width and every ungapped sequence.
- Treat gapped or missing stems as possible structural variants: gaps remain descriptive and never count as pairing violations or an automatic-refinement objective.
- Add optional R-scape integration in evaluate-given-structure (`-s`) mode, including safe PATH discovery, a remembered manual executable location, and clear non-crashing errors when R-scape is unavailable.
- Retain the exact analyzed Stockholm snapshot, pairwise `.cov` table, `.power` table, R2R PDF/SVG drawing, and run log in a uniquely named results folder.
- Add a closable in-window PDFKit panel with a zoomable R2R drawing, run summary, power guidance, cancellation, and direct access to result files.
- Normalize interleaved/wrapped Stockholm blocks into complete logical sequence, `#=GC`, and `#=GR` rows on open, preserving raw metadata/comments and preventing duplicate-row crashes.
- Keep immediately nested pairs in one stem across up to two total bulged columns, while retaining large internal loops, branches, disjoint helices, and different WUSS classes as distinct stems.
- Add toggleable **Element** coloring for high-level continuous helices: arbitrarily large bulges and internal loops retain one color, while true branch junctions, disjoint roots, different structure rows, and different WUSS pairing classes begin new elements.
- Resolve remembered `src/R-scape` selections and selected `bin`/installation folders to the installed `bin/R-scape` beside R2R; explain Finder-versus-Terminal PATH behavior.
- Run R-scape inside MATER's private writable temporary directory so its internal FastTree alignment/tree files work when MATER is launched from Finder; retain combined standard-output/error diagnostics on failure.
- Open R-scape `.cov` pair tables and `.power` tables explicitly in TextEdit instead of asking macOS to locate an application for those scientific file extensions.
- Keep the compact structural-problem heatmap editor-only and intentionally exclude it from alignment PDF/SVG export.

## 0.7.0-alpha.1 — 2026-08-30

- Add one-click **Auto-refine copy** for iterative, alignment-wide gap-only structural refinement without per-edit approval.
- Preserve the original alignment, write and open a uniquely named refined Stockholm file, and retain exact ungapped sequence integrity.
- Require every automatic edit to maintain or improve alignment-wide canonical support without increasing definite noncanonical observations; gaps and ambiguity remain descriptive rather than optimization failures.

## 0.6.1

- Add a comprehensive user guide covering operation, calculations, workflows, limitations, and troubleshooting.
- Add focused Rfam SEED teaching alignments for two pseudoknotted riboswitches, one ordinary riboswitch, and selenocysteine tRNA.
- Replace the separate arc diagram with compact, column-aligned stem-arm blocks directly above the entropy, gap, and pairing-violation tracks.
- Use matching colors to associate the two arms of each stem and dashed block outlines to identify pseudoknots.
- Calculate pairing-violation heatmap values only among occupied, unambiguous base pairs; gaps and ambiguity codes no longer inflate the red problem track.
- Report canonical and noncanonical rates among evaluable observations while retaining gap and ambiguity frequencies as separate descriptive metrics.
- Restrict the inspector's problem filtering and sorting to definite noncanonical pair violations.

## 0.6.0

- Add enabled-by-default Alignment Integrity mode, which permits gap movement and annotation edits while blocking changes to ordered ungapped sequence data.
- Verify every ungapped sequence against the opened file before saving while integrity is locked, with an explicit protected sequence-editing unlock.
- Add a Structural Quality Inspector with per-stem canonical, noncanonical, gap, ambiguity, residue-pair, per-pair, and per-sequence problem summaries.
- Add display-only filtering and sorting for problem sequences, names, structural issue count, and whole-alignment gap fraction.
- Add gap-only suggested stem improvements with before/after previews, component metrics, sequence-integrity verification, and undoable acceptance.
- Add structure-linked navigation and an alignment overview for entropy, gaps, and structural quality.
- Rename the descriptive covariation color mode to **Pair variation** to distinguish observed pair changes from statistical covariation analysis.

## 0.5.0

- Replace the simple majority row with R2R's standard GSC-weighted sequence consensus rules and exact `A/C/G/U`, `R/Y`, lowercase `n`, and `-` output alphabet.
- Match R2R's 97%, 90%, and 75% identity and purine/pyrimidine thresholds; 97%, 90%, 75%, and 50% nucleotide-presence thresholds; fragment-end handling; gap treatment; and ambiguity-input exclusion.
- Move the calculated consensus into the synchronized alignment canvas directly above entropy and gap-frequency plots.
- Highlight the entire selected column from `SS_cons*`, `RF`, `cons`, and calculated-consensus rows.
- Keep the calculated consensus read-only while supporting selection, keyboard navigation, copying, and PDF/SVG export.

## 0.4.2

- Expand a single selected structural base to its complete stem arm when shifting.
- Add an enabled-by-default **Link stem arms** option that atomically shifts the paired arm in the opposite direction to keep the helix in register.
- Preserve manual block shifting for selections that are not a single stem arm.

## 0.4.1

- Generate a deterministic, non-repeating color for every structural stem.
- Preserve the same stem colors in the editor, pinned reference/consensus rows, PDF, and SVG exports.

## 0.4.0

- Add rectangular multi-sequence editing and discontinuous pair/stem selection.
- Add width-preserving gap opening and closing.
- Add pinned reference and RNA consensus rows.
- Add search and next-problem navigation.
- Add entropy and gap-frequency analysis with interactive thresholds.
- Add rolling recovery snapshots, changed-cell comparison, and regional reversion.
- Add configurable vector PDF/SVG export and tiled multi-page PDF.

## 0.3.0

- Add vector PDF and SVG export.
- Hide PP rows and show entropy by default.

## 0.2.0

- Add partner highlighting, gap-column tools, PP-row hiding, and entropy plotting.
- Improve canvas caching and interaction performance.

## 0.1.0

- Initial native macOS Stockholm alignment editor with structure, pseudoknot, covariation, and residue coloring.
