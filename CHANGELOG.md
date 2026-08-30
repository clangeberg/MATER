# Changelog

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
