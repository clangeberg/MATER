# MATER for macOS

<img src="Assets/AppIcon-master.png" alt="MATER RNA hairpin icon" width="128">

**MATER — Manual Alignment Tool for Evolutionary RNA** is a native, structure-aware Stockholm alignment editor designed for fast manual RNA alignment curation on macOS.

## Install

1. Download `MATER-0.6.1-macOS-universal.zip` from the [latest release](https://github.com/clangeberg/MATER/releases/latest).
2. Unzip it and drag `MATER.app` into Applications.
3. On first launch, right-click the app and choose **Open**. If macOS still blocks it, allow MATER under **System Settings → Privacy & Security** and open it again.

MATER supports macOS 13 or newer on Apple-silicon and Intel Macs. The release is ad-hoc signed but not Apple-notarized.

## Current features

- Native macOS document GUI for `.sto`, `.stk`, and `.stockholm` files
- Lossless preservation of Stockholm metadata and comments
- Editable sequence, `#=GC`, and `#=GR` alignment rows
- Live stem coloring across every `SS_cons*` layer, with non-repeating deterministic colors and noncanonical pairs left uncolored
- WUSS/Rfam pairs: `<>`, `()`, `[]`, `{}`, and `A/a` through `Z/z`
- Descriptive pair-variation coloring for same-pair, one-sided, two-sided, invalid, and gapped observations
- Residue coloring
- User-configurable, persistent colors for A, C, G, and U/T
- Automatic highlighting of the selected nucleotide's structural partner
- Double-click pair selection and triple-click full-stem selection
- Rectangular multi-sequence editing, shifting, clearing, copying, and pasting
- Single-sequence gap opening and closing without changing alignment width
- Optional pinned reference sequence
- R2R-compatible, GSC-weighted consensus (`A/C/G/U`, `R/Y`, lowercase `n`, or `-`) in a compact row directly above the analysis plots
- Strong whole-column highlighting when selecting the calculated consensus or a `#=GC SS_cons*`, `RF`, or `cons` cell
- Enabled-by-default Alignment Integrity mode that protects ordered ungapped sequence data during editing and verifies it again before saving
- Explicit sequence-editing unlock for intentional residue corrections, with persistent comparison against the opened file
- Collapsible Structural Quality Inspector with per-stem support metrics, residue-pair counts, pair-by-pair summaries, and clickable observations
- Gap-only suggested stem fixes with before/after arm previews and canonical/noncanonical/gap deltas
- Display-only sequence filtering and sorting by selected-stem pairing violations, name, violation count, or alignment-wide gap fraction
- Column-aligned structure overview with matching colored blocks for each stem arm and dashed outlines for pseudoknots
- Combined structure/entropy/gap/pair-violation overview for direct comparison and rapid navigation across large alignments
- Pair-violation rates calculated only from occupied, unambiguous pairs; gapped and ambiguous observations are excluded rather than treated as structural failures
- `#=GR … PP` and `#=GC PP_cons` rows hidden by default without changing the file
- Live per-column Shannon entropy bar plot (0–2 bits), shown by default
- Live gap-frequency plot, interactive plot columns, and adjustable analysis thresholds
- Search by sequence name, motif, or alignment column
- Navigation among noncanonical pairs, high-entropy columns, gap-rich columns, and validation problems
- Rolling recovery snapshots, changed-cell highlighting, and baseline region/row reversion
- Full-alignment vector export to PDF or SVG using the current colors and display options, including the R2R consensus row when visible
- Export titles, legends, numbering intervals, adjustable name width, selected rows/columns, and tiled multi-page PDF
- Shift selected residues left/right into adjacent gaps, automatically expanding a single structural base to its complete stem arm
- Optionally shift both paired stem arms together in opposite directions to keep the helix in register
- Jump between paired columns
- Create and remove primary or pseudoknot pairs
- Insert alignment-wide gap columns, delete one all-gap column, or remove every all-gap column at once
- Revision-based rendering caches for responsive navigation and coloring
- Undo/redo, copy/paste, validation, and round-trip saving

## Build

Run:

```bash
./scripts/build-app.sh
```

The double-clickable universal app is created at `dist/MATER.app`, supports both Apple-silicon and Intel Macs, and is ad-hoc signed for local use.

Run the regression suite with:

```bash
./scripts/run-core-tests.sh
```

## Core editing controls

- Click or drag to select cells; Shift-click or Shift–arrows extends a rectangular selection.
- Double-click a paired cell to select both partners; triple-click it to select its entire stem.
- Click or drag in `SS_cons*`, `RF`, `cons`, or the calculated R2R consensus row to highlight complete alignment columns.
- Keep **Alignment locked** for normal curation. Gap movement and annotations remain editable, while residue replacement, insertion, deletion, and sequence reordering are protected.
- Select a stem to populate the **Quality Inspector**; click a reported problem to jump to that sequence and pair.
- Use **Suggest fixes** to preview adjacent, width-preserving gap transfers that improve the selected sequence's stem without changing its ungapped residues.
- Click or drag in the combined structure and analysis overview to navigate long alignments; matching block colors identify paired stem arms.
- Type an IUPAC nucleotide to replace selected sequence cells.
- Delete replaces sequence cells with `-` and annotation cells with `.`.
- Option–Left/Right shifts the selected block into adjacent gaps. On a single paired base, it automatically shifts that complete stem arm.
- Keep **Link stem arms** enabled to move the paired arm one column in the opposite direction during a stem-arm shift; turn it off to move only the selected arm.
- Control-G opens a gap before the cursor; Control-Shift-G closes the selected gap.
- Command-C/V copies or overwrites an alignment segment.
- Command-F focuses search; enter a sequence name, motif, number, or `col:123`.
- Select two or more columns and use **Set pair** to annotate the endpoints in the chosen structure layer.
- Use **Navigate** to jump directly among analysis and structural problems.
- Use **Changes** to compare against the opened file, revert a region or row, and manage recovery snapshots.
- Use **Export** to save the complete or selected colored alignment as vector PDF or SVG.
- Use **View & columns** to insert or remove gap columns, show PP rows, toggle the R2R consensus, combined overview or inspector, configure plots, and adjust thresholds.

The original file is not modified until you save. Keep versioned copies of important alignments while this early build is being validated.

## Feedback

Bug reports and focused feature requests are welcome through [GitHub Issues](https://github.com/clangeberg/MATER/issues). When possible, include a minimal Stockholm example that reproduces the behavior; remove unpublished biological data first.
