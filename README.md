# MATER for macOS

<img src="Assets/AppIcon-master.png" alt="MATER RNA hairpin icon" width="128">

**MATER — Manual Alignment Tool for Evolutionary RNA** is a native, structure-aware Stockholm alignment editor designed for fast manual RNA alignment curation on macOS.

## Install

1. Download `MATER-0.4.1-macOS-universal.zip` from the [latest release](https://github.com/clangeberg/MATER/releases/latest).
2. Unzip it and drag `MATER.app` into Applications.
3. On first launch, right-click the app and choose **Open**. If macOS still blocks it, allow MATER under **System Settings → Privacy & Security** and open it again.

MATER supports macOS 13 or newer on Apple-silicon and Intel Macs. The release is ad-hoc signed but not Apple-notarized.

## Current features

- Native macOS document GUI for `.sto`, `.stk`, and `.stockholm` files
- Lossless preservation of Stockholm metadata and comments
- Editable sequence, `#=GC`, and `#=GR` alignment rows
- Live stem coloring across every `SS_cons*` layer, with non-repeating deterministic colors and noncanonical pairs left uncolored
- WUSS/Rfam pairs: `<>`, `()`, `[]`, `{}`, and `A/a` through `Z/z`
- Covariation coloring for conserved, one-sided, compensatory, invalid, and gapped pairs
- Residue coloring
- User-configurable, persistent colors for A, C, G, and U/T
- Automatic highlighting of the selected nucleotide's structural partner
- Double-click pair selection and triple-click full-stem selection
- Rectangular multi-sequence editing, shifting, clearing, copying, and pasting
- Single-sequence gap opening and closing without changing alignment width
- Pinned reference sequence and calculated RNA consensus rows
- `#=GR … PP` and `#=GC PP_cons` rows hidden by default without changing the file
- Live per-column Shannon entropy bar plot (0–2 bits), shown by default
- Live gap-frequency plot, interactive plot columns, and adjustable analysis thresholds
- Search by sequence name, motif, or alignment column
- Navigation among noncanonical pairs, high-entropy columns, gap-rich columns, and validation problems
- Rolling recovery snapshots, changed-cell highlighting, and baseline region/row reversion
- Full-alignment vector export to PDF or SVG using the current colors and display options
- Export titles, legends, numbering intervals, adjustable name width, selected rows/columns, and tiled multi-page PDF
- Shift selected residues left/right into adjacent gaps
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
- Type an IUPAC nucleotide to replace selected sequence cells.
- Delete replaces sequence cells with `-` and annotation cells with `.`.
- Option–Left/Right shifts the selected block or discontinuous pair/stem selection into adjacent gaps.
- Control-G opens a gap before the cursor; Control-Shift-G closes the selected gap.
- Command-C/V copies or overwrites an alignment segment.
- Command-F focuses search; enter a sequence name, motif, number, or `col:123`.
- Select two or more columns and use **Set pair** to annotate the endpoints in the chosen structure layer.
- Use **Navigate** to jump directly among analysis and structural problems.
- Use **Changes** to compare against the opened file, revert a region or row, and manage recovery snapshots.
- Use **Export** to save the complete or selected colored alignment as vector PDF or SVG.
- Use **View & columns** to insert or remove gap columns, show PP rows, configure plots, and adjust thresholds.

The original file is not modified until you save. Keep versioned copies of important alignments while this early build is being validated.

## Feedback

Bug reports and focused feature requests are welcome through [GitHub Issues](https://github.com/clangeberg/MATER/issues). When possible, include a minimal Stockholm example that reproduces the behavior; remove unpublished biological data first.
