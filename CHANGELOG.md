# Changelog

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
