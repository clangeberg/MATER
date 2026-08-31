# MATER User Guide

**Manual Alignment Tool for Evolutionary RNA**

**MATER version 0.8.0 alpha 1 • macOS 13 or newer**

Manual revision: 31 August 2026

MATER is a native macOS editor for manual curation of RNA multiple-sequence alignments in Stockholm format. It keeps aligned sequence, consensus secondary structure, pseudoknots, per-column annotations, and per-residue annotations in one editable view. Its central design rule is that ordinary alignment work should move gaps without silently changing the underlying biological sequences.

This manual is both a tutorial and a reference. New users should read Sections 1–4 and then work through Section 5. The remaining sections describe every control, calculation, and known limitation in version 0.8.0 alpha 1.

> **Alpha safety rule:** Work on a duplicate of an important alignment until MATER has been validated on your own files. Keep **Alignment locked** during normal curation.

## Contents

1. [Scope and terminology](#1-scope-and-terminology)
2. [Installation and first launch](#2-installation-and-first-launch)
3. [Supported files and Stockholm conventions](#3-supported-files-and-stockholm-conventions)
4. [Interface overview](#4-interface-overview)
5. [Ten-minute tutorial](#5-ten-minute-tutorial)
6. [Selection and navigation](#6-selection-and-navigation)
7. [Manual alignment editing](#7-manual-alignment-editing)
8. [Secondary structure and pseudoknots](#8-secondary-structure-and-pseudoknots)
9. [Color modes](#9-color-modes)
10. [Alignment Integrity mode](#10-alignment-integrity-mode)
11. [Calculated consensus and analysis tracks](#11-calculated-consensus-and-analysis-tracks)
12. [Structural Quality Inspector](#12-structural-quality-inspector)
13. [Suggested edits](#13-suggested-edits)
14. [Optional R-scape analysis](#14-optional-r-scape-analysis)
15. [Large-alignment overview, filters, and sorting](#15-large-alignment-overview-filters-and-sorting)
16. [Search and problem navigation](#16-search-and-problem-navigation)
17. [Change tracking and recovery](#17-change-tracking-and-recovery)
18. [PDF and SVG export](#18-pdf-and-svg-export)
19. [Validation and saving](#19-validation-and-saving)
20. [Keyboard and mouse reference](#20-keyboard-and-mouse-reference)
21. [Recommended workflows](#21-recommended-workflows)
22. [Rfam example alignments](#22-rfam-example-alignments)
23. [Troubleshooting and frequently asked questions](#23-troubleshooting-and-frequently-asked-questions)
24. [Current limitations](#24-current-limitations)
25. [Reporting a useful alpha issue](#25-reporting-a-useful-alpha-issue)
26. [Building from source](#26-building-from-source)
27. [Glossary](#27-glossary)
28. [Methods summary and references](#28-methods-summary-and-references)

## 1. Scope and terminology

MATER is intended for manual refinement of an existing RNA alignment. It is not a de novo aligner, structure predictor, or covariance-model builder. Statistical covariation analysis is available only by running a separately installed R-scape program; MATER does not reimplement R-scape's test.

In this guide:

- An **alignment row** is a sequence, a `#=GC` per-column annotation, or a `#=GR` per-residue annotation displayed by MATER.
- A **column** is a one-based alignment coordinate in the interface and this guide. Internally and in source code, columns are zero-based.
- A **pair** is two alignment columns connected by a recognized symbol pair in an `SS_cons*` row.
- A **stem** is a run of immediately nested adjacent pairs, such as columns 10–40, 11–39, and 12–38.
- An **occupied pair observation** has a nucleotide at both paired columns in one sequence.
- An **evaluable pair observation** is occupied and contains unambiguous A, C, G, or U/T at both positions.
- **Canonical** means one of AU, UA, GC, CG, GU, or UG after converting T to U.
- A **pseudoknot** is a pairing layer or bracket class outside MATER's primary `< >` layer. It may cross another set of pairs.

## 2. Installation and first launch

### 2.1 System requirements

- macOS 13 or newer
- Apple Silicon or Intel processor
- A plain-text Stockholm alignment with extension `.sto`, `.stk`, or `.stockholm`

### 2.2 Installing an alpha ZIP

1. Unzip `MATER-0.8.0-alpha.1-macOS-universal.zip`.
2. Drag `MATER.app` to **Applications**.
3. On first launch, right-click MATER and choose **Open**.
4. If macOS still blocks it, open **System Settings → Privacy & Security**, allow MATER, and try again.

Version 0.8.0 alpha 1 is ad-hoc signed and is not Apple-notarized. This is acceptable for a supervised alpha but produces more Gatekeeper friction than a Developer ID-signed, notarized release.

### 2.3 Opening an alignment

Use **File → Open**, double-click a supported file, or drag the file onto MATER. If macOS asks which application should open the file, select MATER.

For alpha testing, duplicate the alignment in Finder first. Save the edited copy under a new name until its round trip has been checked.

## 3. Supported files and Stockholm conventions

### 3.1 Minimum useful file

```text
# STOCKHOLM 1.0
sequence_1    GCGAAACGCUUC
sequence_2    GUGAAACGCAAC
#=GC SS_cons  <<......>>..
//
```

MATER expects one alignment and one aligned segment per displayed row. All sequence and aligned annotation strings should have the same width.

### 3.2 Rows MATER understands

| Stockholm record | Interpretation | Editable in the canvas |
|---|---|---|
| `name ALIGNED_SEQUENCE` | Sequence row | Yes |
| `#=GC TAG ALIGNED_ANNOTATION` | Per-column annotation | Yes |
| `#=GR NAME TAG ALIGNED_ANNOTATION` | Per-residue annotation | Yes |
| `#=GF`, `#=GS`, comments, blank lines | Metadata/raw text | Preserved, not displayed as alignment rows |
| `# STOCKHOLM 1.0` and `//` | Header and terminator | Preserved and validated |

For a single-block file, MATER preserves the original record order, spacing around parsed alignment values, comments, metadata, line-ending style, and unknown raw lines. Editing an aligned row changes its aligned value while retaining its parsed prefix and suffix.

Wrapped/interleaved Stockholm is normalized on open. Later segments with the same sequence name, `#=GC` tag, or `#=GR` sequence/tag identity are concatenated onto the first logical row. Raw metadata, comments, and blank lines are retained, but saving writes one complete aligned string per logical row rather than recreating the visual block wrapping. A validation warning reports how many later row segments were joined.

### 3.3 Input restrictions in the current alpha

- Use a single Stockholm alignment per file.
- Single-block and wrapped/interleaved sequence, `#=GC`, and `#=GR` rows are accepted. Interleaved files are written back in normalized single-block form.
- All displayed rows should have the same alignment length. MATER reports inconsistent widths as validation errors.
- Sequence names are not renamed, added, or deleted through the current GUI.
- UTF-8 and ISO Latin-1 input can be opened. Saved output is UTF-8.

### 3.4 Gaps and residue characters

In sequence rows, MATER recognizes `-`, `.`, and `~` as gap/missing-data symbols in general alignment operations. The integrity check also treats `_` and spaces as non-residues. Standard Rfam-style sequence alignments normally use `-` or `.` rather than `_`.

When sequence editing is explicitly unlocked, direct typing accepts:

```text
A C G U T N R Y S W K M B D H V X - . ~
```

T is treated as U by nucleotide coloring and base-pair calculations, but the literal T is preserved in the file.

### 3.5 Structure notation

Every `#=GC` tag beginning with `SS_cons` is parsed as a structure layer. MATER recognizes these opener/closer pairs:

| Open | Close | Typical use |
|---:|---:|---|
| `<` | `>` | Primary nested structure |
| `(` | `)` | Additional/pseudoknot class |
| `[` | `]` | Additional/pseudoknot class |
| `{` | `}` | Additional/pseudoknot class |
| `A`–`Z` | matching `a`–`z` | Up to 26 lettered WUSS pseudoknot classes |

Unpaired WUSS characters such as `.`, `_`, `-`, `:`, and `,` are retained but do not create pairs.

## 4. Interface overview

The editor window has six functional regions.

1. **Color and file controls:** color mode, base palette, pinned reference, vector export, and Alignment Integrity lock.
2. **View & columns:** gap-column operations, PP visibility, calculated rows and plots, thresholds, overview visibility, inspector visibility, and text size.
3. **Editing controls:** shifting, linked stem arms, gap opening/closing, pair navigation, stem selection, structure-layer editing, and suggestions.
4. **Alignment canvas:** names, sequences, `#=GC` rows, `#=GR` rows, the calculated R2R consensus, and optional full-height analysis plots.
5. **Structural Quality Inspector:** metrics and navigation for the stem containing the selected column.
6. **Bottom status and overview:** integrity and validation state, selection details, aligned stem blocks, entropy, gap frequency, and occupied-pair violations.

Hover over a control to see its short help description. The footer reports the current row, column, paired partner, entropy, gap frequency, dimensions, validation state, and most recent action.

## 5. Ten-minute tutorial

The repository includes focused teaching examples in `Examples/Rfam`.

### 5.1 Inspect several ordinary stems

1. Open `Examples/Rfam/RF01852-tRNA-Sec.sto`.
2. Leave **Alignment locked** and **Stem** coloring enabled.
3. Look at the colored blocks above the bottom heatmaps. Each matching color marks the two arms of one stem.
4. Click a block. The selected column moves there and the Quality Inspector displays that stem.
5. Click a pair in **Pairs in this stem** to select both paired columns.
6. Switch among **Stem**, **Element**, **Pair variation**, and **Residue** color modes.
7. Double-click a paired cell to select its pair, then triple-click it to select the complete stem.

### 5.2 Inspect a pseudoknot

1. Open `Examples/Rfam/RF00522-PreQ1.sto` or `RF01763-Guanidine-III.sto`.
2. Find the blocks with dashed outlines in the bottom overview. These correspond to the `A/a` pseudoknot in `SS_cons`.
3. Click an `A` or `a` structural column. Its partner is highlighted and the inspector identifies its stem.
4. Use **Jump pair** to move between partners.

### 5.3 Make a safe gap-only edit

1. Duplicate an example and open the copy.
2. Select one or more sequence cells.
3. Use **Option–Left Arrow** or **Option–Right Arrow** to move the selection into an adjacent gap.
4. Confirm that the footer still says **Integrity verified**.
5. Use **Command-Z** to undo.

Typing a different nucleotide while the alignment is locked is intentionally blocked. Gap movement remains available.

### 5.4 Export the view

1. Choose the desired color mode and PP/analysis visibility.
2. Open **Export** and choose PDF or SVG.
3. Set a title, numbering interval, name width, legend, and optional selection-only export.
4. For a wide PDF, enable tiled landscape Letter pages.

## 6. Selection and navigation

### 6.1 Mouse selection

- **Click:** select one cell.
- **Drag:** select a rectangular region.
- **Shift-click/Shift-drag:** extend from the existing anchor.
- **Double-click a paired column:** select that base and all recognized partners at the column.
- **Triple-click a paired column:** select every column in its stem.
- **Click an `SS_cons*`, `RF`, or `cons` cell:** highlight the complete alignment column.
- **Click the calculated R2R consensus:** highlight the complete column; the calculated row is read-only.
- **Click or drag an analysis plot:** move to its alignment column.
- **Click or drag the bottom overview:** navigate in the same coordinate system as the heatmaps.

When one base in a recognized pair is selected, its paired partner is shown with an orange outline in the same displayed row.

### 6.2 Keyboard navigation

- Arrow keys move one cell.
- Shift-arrow extends a rectangular selection.
- Home/End moves to the first/last column.
- Shift-Home/Shift-End extends to the first/last column.
- Command-A selects all sequence rows and all columns. On the calculated consensus, it selects all consensus columns.

Navigation follows the currently displayed order. If sequences are filtered or sorted, hidden rows are skipped.

### 6.3 Pair and stem navigation

- **Jump pair** moves the cursor to the partner of the selected structural column.
- **Select stem** selects both arms of the complete stem.
- Inspector pair rows select exactly the two reported columns.
- Inspector issue rows jump to the reported sequence and pair.

If a column participates in more than one structure layer, MATER can highlight multiple partners. Some single-stem inspector actions use the first recognized pair at that column.

## 7. Manual alignment editing

### 7.1 Undo and redo

Edits register with the standard macOS undo manager. Use **Command-Z** to undo and **Shift-Command-Z** to redo. Accepted suggestions and recovery restores are also undoable.

### 7.2 Typing and clearing cells

- Sequence residue typing requires sequence editing to be unlocked.
- Typing into a `#=GC` or `#=GR` row replaces the selected annotation cells without unlocking sequences.
- Backspace/Delete changes selected sequence cells to `-` and annotation cells to `.`.
- While locked, deleting an existing sequence residue is blocked; clearing cells that are already gaps is harmless.

When multiple rows are selected, direct sequence typing is applied only to sequence rows. Annotation rows are not mixed into a multi-sequence residue replacement.

### 7.3 Copy and paste

- **Command-C** copies selected aligned characters as one line per selected row.
- **Command-V** overwrites starting at the selected column.
- A single pasted line targets the active row.
- Multiple pasted lines map to the selected rows in order.
- A discontinuous pair/stem selection is honored when the pasted line fits the number of selected columns; otherwise MATER pastes continuously from the first selected column.

Paste is still subject to Alignment Integrity mode. A paste that changes an ungapped sequence is rejected while locked.

### 7.4 Shifting a selected block

Use **Shift left/right** or **Option–Left/Right Arrow**. For a normal selection:

- Every destination outside the selected columns must already be a gap.
- Every selected sequence row must be able to move.
- The edit is atomic: if one row cannot move, none of the selected rows move.
- Alignment width and ungapped sequence strings remain unchanged.

### 7.5 Automatic stem-arm shifting

If the selection is a single paired cell or exactly one complete stem arm, a shift automatically expands to the full arm. This prevents a stem from moving one base at a time.

With **Link stem arms** enabled, the paired arm moves one column in the opposite direction in the same atomic edit. For example, shifting the left arm right shifts the right arm left. Both sides require compatible gaps.

After a successful stem shift, the destination arm stays selected so repeated Option-arrow presses continue moving the same stem.

### 7.6 Opening a gap

**Control-G** or **Open gap** inserts `-` before the cursor while consuming the nearest downstream gap in the same sequence. Width and ungapped sequence remain unchanged.

Opening fails if:

- The active row is not a sequence.
- There is no downstream gap.
- The calculated consensus is selected.

### 7.7 Closing a gap

**Control-Shift-G** or **Close gap** removes the gap at the cursor, pulls the following residue block left, and moves a gap to the far edge of that block.

Closing fails unless the selected sequence cell is a gap and moving it changes the alignment.

### 7.8 Alignment-wide gap columns

The **View & columns** menu contains:

- **Insert empty gap column:** inserts `-` in every sequence row and `.` in every aligned annotation row before the selected column.
- **Delete selected all-gap column:** deletes one column only if every sequence contains a recognized gap there.
- **Remove all empty columns:** deletes every all-gap sequence column at once.

Column annotations are changed in lockstep. If deleting a column removes only one endpoint of a structural pair, MATER clears the surviving endpoint to avoid an orphaned WUSS symbol.

## 8. Secondary structure and pseudoknots

### 8.1 Reading structure

MATER parses all `#=GC SS_cons*` rows. Each opener is matched to the next valid closer using a separate stack for that bracket class. Immediately nested pairs of the same class and structure row are grouped into one stem. Up to two skipped columns in total across the two arms are tolerated, so a one-column bulge or small symmetric internal loop does not split an otherwise continuous helix.

Unmatched openers or closers produce validation errors.

### 8.2 Adding a pair

1. Select at least two columns.
2. Choose a **Pairing layer**.
3. Click **Set pair**.

MATER pairs the first and last selected columns. If either endpoint already participates in a pair in the target layer, that old pair is cleared first.

The editable layers are:

| UI layer | Stockholm tag created/used | Symbols |
|---|---|---|
| Primary | `SS_cons` | `< >` |
| Pseudoknot 1 | `SS_cons_2` | `( )` |
| Pseudoknot 2 | `SS_cons_3` | `[ ]` |
| Pseudoknot 3 | `SS_cons_4` | `{ }` |
| Pseudoknot 4 | `SS_cons_5` | `A a` |

If the selected `SS_cons*` row does not exist, MATER inserts it before `//` and fills unpaired columns with `.`.

### 8.3 Removing pairs

Select one or more columns and click **Unpair**. Every recognized pair touching the selection is cleared at both endpoints, including pairs in other `SS_cons*` rows.

### 8.4 Existing lettered pseudoknots

Existing `A/a` through `Z/z` classes are parsed even though the GUI creates only `A/a` in its fourth pseudoknot layer. They remain editable as annotation characters and participate in highlighting, scoring, stem coloring, and export.

### 8.5 How stems and major elements are inferred

WUSS/dot-bracket symbols encode base-pair relationships and pairing classes; they do not encode arbitrary biological domain names or requested colors. Infernal builds covariance-model pair and bifurcation states from the consensus pairing topology, while MATER derives two useful display levels from that same kind of topology:

- A **stem** is an insertion-tolerant stack within one `SS_cons*` row and opener class. A combined bulge of zero, one, or two skipped arm columns remains in the stack. A larger internal loop, a branch, a disjoint helix, a different opener class, or a different structure row begins another stem.
- A **major element** is one continuous high-level helix. A singly nested chain of pairs remains one element no matter how many unpaired columns occur on either arm. A true junction with two or more directly nested child helices ends that chain: the enclosing helix and each child helix receive separate elements. Disjoint roots, different `SS_cons*` rows, and different WUSS opener classes are also separate.

For example, these annotations both resolve to three stems—one outer stem and two internal stems—even though only the first uses different bracket classes:

```text
((((([[[[[.....]]]]]...{{{{{.....}}}}})))))
((((((((((.....)))))...(((((.....))))))))))
```

The large topological discontinuities prevent the ordinary-parentheses form from collapsing into one fine stem. In **Stem** mode the three stacks have different colors. In **Element** mode these examples also have three colors: the first has three explicit WUSS pairing classes, while the second has an enclosing helix and two child helices leaving a true branch junction.

A continuous nested chain behaves differently even when its arms contain large interruptions:

```text
((..(.(....(((.....)).)))....)..)
```

Every pair has only one directly nested child, so the whole chain is one color in **Element** mode. By contrast, `((...))((..))` has two disjoint roots and therefore two elements, while `((((((...)))(((...))))))` has an outer helix plus two child branches and therefore three.

A small insertion behaves differently:

```text
(((.....)).)
```

The outer pair skips one extra column on its right arm, but all three pairs remain one fine stem. Lettered K-, L-, M-, and more complex pseudoknot classes are parsed independently with their own stacks. Each pseudoknot class can remain one high-level Element across bulges and internal loops, but crossing classes are not merged merely because their spans overlap. This preserves distinct pseudoknot stems while treating interruptions within one matched opener/closer class consistently.

Because named domains such as “HCV IRES domain II” are not explicitly labeled by dot bracket alone, Element mode is a reproducible topology-based approximation. If a desired biological domain boundary differs from the topology, it cannot be inferred unambiguously from `SS_cons`; an explicit named-domain annotation would be required.

## 9. Color modes

### 9.1 Stem

Every insertion-tolerant stem receives a deterministic color. The same color is used for both arms in the alignment, overview, pinned reference, consensus where applicable, and vector export. Bulges totaling up to two skipped arm columns remain the same color; large loops, branches, and different WUSS classes remain distinct.

For sequence rows, a structural cell is colored only when that sequence forms AU, UA, GC, CG, GU, or UG at the complete pair. A defined pair that is gapped, ambiguous, or noncanonical is left uncolored. Structure annotation rows themselves retain the stem colors.

This makes violations conspicuous without assigning them a misleading stem color.

### 9.2 Element

Element mode uses the same canonical-pair rule as Stem mode but colors a continuous high-level helix identically across arbitrarily large bulges and internal loops. It follows the direct pair-containment tree: a single nested child continues the current element, while two or more direct children create a true branch and each child begins a new element. Disjoint helices, different structure rows, and different WUSS opener classes—including crossing pseudoknot classes—remain distinct. Switch back to Stem mode for the finer two-skipped-column stack boundary.

### 9.3 Pair variation

Pair variation is descriptive and is **not** a statistical covariation analysis.

For each structural pair, MATER finds the most frequent canonical occupied pair in the alignment and uses it as the reference. Each sequence is classified as:

| Color/label | Meaning |
|---|---|
| Green, **same pair** | Same canonical pair as the reference |
| Cyan, **one-sided** | Canonical pair with one partner changed |
| Blue, **two-sided change** | Canonical pair with both partners changed |
| Red, **noncanonical** | Occupied observation outside the six accepted pairs; ambiguous characters also fall here in this color mode |
| Gray, **gap** | At least one partner is gapped |

The classification uses observed counts, not GSC weights, a phylogenetic model, E-values, or R-scape statistics. “Two-sided change” is therefore not evidence by itself for statistically significant covariation.

### 9.4 Residue

A, C, G, and U/T receive user-defined colors. Open **Base colors** to customize them. Colors persist in macOS user preferences and are reused in later sessions and exports. Ambiguity symbols and gaps remain uncolored.

### 9.5 None

Disables biological cell coloring while retaining selection, change, threshold, and validation indicators.

## 10. Alignment Integrity mode

Alignment Integrity mode is enabled by default and is the main data-safety boundary.

### 10.1 What is protected

At open time, MATER records, in order:

- Every sequence-row name and its occurrence number
- The sequence row order
- The exact ungapped residue string for each sequence

For this comparison, `-`, `.`, `~`, `_`, and spaces are removed. Remaining characters are compared literally, including case and T versus U.

While locked, an edit is accepted only if those ordered ungapped strings remain unchanged. Gap movement, gap-column operations, and annotation edits are therefore allowed. Residue replacement, residue deletion, sequence addition/removal, or reordering is rejected.

### 10.2 Save-time check

When locked, MATER repeats the comparison against the originally opened file before saving. Saving is blocked if integrity differs, even if the change was made earlier while unlocked.

### 10.3 Intentionally changing a sequence

Click **Alignment locked**, read the warning, and choose **Unlock Sequence Editing**. The footer becomes orange. MATER continues comparing the document with the opened baseline and reports changed sequences.

When relocking a changed document, MATER warns that saving will remain blocked. Choose one of these routes:

- Revert the intended cells/rows to the baseline while locked.
- Unlock again and save the intentional sequence change.
- Undo the change.

Baseline-reversion commands are allowed while locked when they measurably restore integrity.

### 10.4 What integrity does not guarantee

Integrity protection proves that the ordered ungapped strings have not changed. It does not prove that gap placement, row annotations, secondary structure, biological interpretation, or the choice of sequence set is correct.

## 11. Calculated consensus and analysis tracks

### 11.1 Calculated R2R consensus

The **R2R consensus** row is calculated in memory and is not inserted into the Stockholm file. It follows R2R's standard GSC-weighted sequence-consensus convention and uses only:

```text
A C G U R Y n -
```

#### Sequence weighting

MATER derives GSC-style weights from a tree based on pairwise sequence identity. Closely redundant sequences share weight, reducing their ability to dominate the consensus. Weights are recomputed after every alignment revision.

#### Fragment handling

For each sequence, columns before its first alphabetic character and after its last alphabetic character do not contribute. Internal non-alphabetic characters contribute to the gap category. This prevents terminal fragment padding from acting like aligned internal deletions.

Alphabetic ambiguity symbols such as N or R are omitted from the nucleotide and gap counts; they are not divided among compatible nucleotides.

#### Consensus rule

Let weighted frequencies at a column be `fA`, `fC`, `fG`, `fU`, and `fgap`, normalized over the counted A/C/G/U/gap weight.

1. If A, C, G, or U reaches one of the standard identity thresholds 97%, 90%, or 75%, output that nucleotide.
2. Otherwise, if A+G reaches one of those thresholds, output `R`.
3. Otherwise, if C+U reaches one of those thresholds, output `Y`.
4. Otherwise, if nucleotide presence `1 − fgap` reaches 97%, 90%, 75%, or 50%, output lowercase `n`.
5. Otherwise output `-`.

Because the UI shows only the consensus symbol and not a separate conservation-level row, the visible distinctions are effectively nucleotide/R/Y at at least 75%, `n` at at least 50% presence, and `-` below 50% presence.

This calculated row may differ from an existing `#=GC RF` or `#=GC cons` line because those are file annotations with their own provenance.

### 11.2 Shannon entropy

For column `i`, MATER counts unweighted A, C, G, and U/T observations. Gaps and ambiguity symbols are omitted. If

```text
p(b,i) = count of base b at i / total canonical bases at i
```

then

```text
H(i) = - Σ p(b,i) log2 p(b,i),  b ∈ {A,C,G,U}
```

The range is 0–2 bits:

- 0 bits: one observed canonical base type, or no canonical observations
- 1 bit: two equally frequent base types
- 2 bits: A, C, G, and U equally frequent

Entropy is deliberately **not** GSC-weighted. A column containing one A and many gaps has entropy 0, not high entropy; use the gap track to interpret its occupancy.

### 11.3 Gap frequency

For column `i`:

```text
gap frequency(i) = sequence rows containing -, ., or ~ at i / number of sequence rows
```

Terminal and internal gaps both count. Ambiguity symbols do not count as gaps.

### 11.4 Occupied-pair violation fraction

The red structural-problem track is designed not to punish legitimate structural subtypes.

For a consensus pair `p`, a sequence contributes only when both paired positions contain unambiguous A, C, G, or U/T. Gapped pairs and ambiguity codes are excluded from both numerator and denominator.

```text
violation fraction(p) = definite noncanonical observations / evaluable occupied observations
```

AU, UA, GC, CG, GU, and UG are canonical. Every other evaluable A/C/G/U combination is a violation. The same value is assigned to both partner columns. If a column belongs to multiple recognized pairs, its displayed fraction aggregates the evaluable observations for those pairs.

Consequences:

- A subtype lacking the stem does not increase the red track.
- An N-containing pair does not increase the red track because its pairing state is unknown.
- Missing data remain visible in the separate teal gap track.
- A red value reports definite convention-breaking observations, not statistical significance.

### 11.5 Full-height plots and compact overview

**Show entropy bar plot** and **Show gap-frequency plot** add full-height interactive plots directly under the alignment. The compact bottom overview always aligns structure blocks, entropy, gap frequency, and pair violations when the overview is visible.

### 11.6 Analysis thresholds

The **View & columns** menu exposes entropy and gap thresholds. When **Highlight high-entropy/gap-rich columns** is enabled, columns meeting either threshold receive a light canvas highlight. The same thresholds define **Next high-entropy column** and **Next gap-rich column** navigation.

## 12. Structural Quality Inspector

Select a paired column to inspect its stem.

### 12.1 Observation classes

For every sequence and pair in the selected stem, MATER records one class:

- **Canonical:** occupied, unambiguous AU/UA/GC/CG/GU/UG
- **Noncanonical:** occupied, unambiguous, but outside the six accepted pairs
- **Gap:** at least one partner is a gap/missing-data character
- **Ambiguous:** both positions are occupied but at least one is not unambiguous A/C/G/U after T→U normalization

Let `C`, `N`, `G`, and `A` be those counts across all sequence-by-pair observations in the selected stem.

```text
evaluable = C + N
total     = C + N + G + A

canonical rate    = C / evaluable
noncanonical rate = N / evaluable
gap rate          = G / total
ambiguity rate    = A / total
```

If `evaluable = 0`, MATER reports that there are no occupied, unambiguous pairs rather than displaying a meaningful canonical percentage. Gaps and ambiguities are review categories, not violations.

### 12.2 Inspector sections

- **Stem summary:** structure tag, pair count, and the four metrics above.
- **Observed residue pairs:** counts occupied unambiguous pair types, canonical and noncanonical.
- **Pairs in this stem:** per-pair canonical rate among evaluable observations; click to select both columns.
- **Observations to review:** noncanonical, gapped, and ambiguous sequence/pair observations; click to jump.

The issue list displays at most the first 80 observations for responsiveness.

### 12.3 Filtering and sorting

Filters are display-only and never rewrite row order in the Stockholm file.

| Filter | Visible sequence rows |
|---|---|
| All sequences | Every sequence |
| Pair violations | Sequences with at least one definite noncanonical observation in the selected stem |
| Noncanonical only | Same definite noncanonical criterion |
| Gaps in stem | Sequences with at least one gapped pair observation in the selected stem |

Associated `#=GR` rows are hidden when their sequence is filtered out. `#=GC` rows remain visible.

Sort choices are file order, sequence name, most pair violations in the selected stem, and highest alignment-wide gap fraction. Sorting is also display-only. When a non-file sort is active, sequence rows are grouped above annotation rows in the display.

## 13. Suggested edits

**Suggest fixes** is a conservative local search, not an automatic realigner.

### 13.1 Requirements

- Select a sequence row.
- Place the cursor in a recognized pair.
- The sequence must have a nearby gap arrangement that permits a width-preserving candidate.

### 13.2 Candidates tested

For the selected sequence and stem, MATER tests:

- One-column shifts of the selected stem arm left and right
- Linked, opposite-direction shifts of both arms when enabled
- Opening or closing a gap at each stem endpoint and one column on either side
- Coordinated shifts of both complete helix-arm windows, including up to three neighboring unpaired columns on each side
- Bounded redistribution of the existing residues and gaps within those windows, while retaining residue order and limiting each residue to a three-column displacement

An arm window ends early if it encounters a paired column belonging to another stem. If the two expanded arm windows would overlap, MATER divides the intervening region between them. The broader window search is enabled only when each arm window contains at least half as many residues as the annotated helix has pairs, rounded up. This occupancy safeguard prevents a missing arm from being pulled into existence merely to satisfy `SS_cons`; a gapped stem may be a real structural subtype.

The redistribution search uses a bounded beam of at most 256 partial arrangements and retains at most 24 complete arrangements per window. These limits make the preview responsive while allowing multi-column changes that the original one-gap-at-a-time search could not find. Every candidate preserves alignment width, residue order, and the exact ungapped sequence.

### 13.3 Acceptance and ranking

A candidate is rejected if, over all annotated pairs in that sequence, it loses a canonical pair or creates an additional definite noncanonical pair. Gaps and ambiguity are neutral for this structural safety test. A surviving candidate is shown if it does either of the following:

1. Increases canonical observations or decreases definite noncanonical observations in the selected stem; or
2. Improves the neighboring unpaired-column profile by at least 0.20 natural-log units without worsening the structural safety measures.

The neighboring profile is leave-one-out: the sequence being edited is excluded, so it cannot vote for its own current placement. MATER uses the same GSC sequence weights used for calculated consensus. At each unpaired neighborhood column, A, C, G, U/T, and gap are the five modeled symbols; ambiguity characters are excluded. For symbol `b` at column `i`:

```text
profile contribution(b,i) = ln((weighted_count(b,i) + 0.25)
                               / (weighted_total(i) + 5 × 0.25))
```

The displayed profile change is the sum of those contributions after the candidate minus before it. Modeling a gap in this local sequence profile helps place insertions consistently; it does **not** make a gapped structural pair a violation or require a missing stem to become occupied.

Suggestions are ranked by canonical gain in the selected sequence, then canonical gain across that stem, fewer definite noncanonical observations, larger profile gain, and finally smaller total residue displacement. Linked candidates are preferred only after those comparisons.

### 13.4 Preview and apply

The preview shows left and right stem arms before/after, canonical/noncanonical changes for the selected sequence, the selected stem's canonical count over the whole alignment, the neighboring profile change, and total residue displacement.

Applying a suggestion:

- Rechecks that the sequence row has not changed since preview generation
- Rechecks integrity through the normal document mutation path
- Applies one undoable edit
- Never modifies the alignment width or ungapped sequence

Review every suggestion biologically. Local canonical-pair improvement does not prove homology, structural conservation, or a globally optimal alignment.

### 13.5 Automatic whole-alignment refinement

**Auto-refine copy** performs conservative width-preserving, gap-only operations without asking for approval after each proposal. It is intended for quickly generating a candidate alignment that can be compared with the original.

When the current document has a file location, one click:

1. Scans every sequence row, every stem in every `SS_cons*` layer, and both arms of each stem.
2. Tests one-column arm shifts, optional linked-arm shifts, nearby gap opening/closing operations, and coordinated complete-arm window shifts across each helix and its up-to-three-column flanks.
3. Applies the strongest safe edit, then immediately rescans that sequence so several necessary gap moves can accumulate in one pass rather than relying on stale proposals.
4. Repeats complete passes until no supported move can improve the structural objective, or until the 100-pass safety limit is reached.
5. Writes a new file beside the source as `NAME-MATER-refined.sto` and opens it. If that name exists, MATER adds `-2`, `-3`, and so on; it never overwrites the source or an earlier result.

For a new unsaved document, MATER asks where to write the refined copy.

Every automatically accepted edit must satisfy all of these conditions:

- The exact ordered ungapped sequence set is unchanged.
- The alignment-wide number of canonical AU/UA/GC/CG/GU/UG observations does not decrease.
- The alignment-wide number of definite noncanonical observations does not increase.
- At least one of those two structural measures improves.

Gap and ambiguity counts are descriptive only and are not optimization terms. Missing stems, fragments, ambiguity, and genuine structural subtypes may be biologically valid. The leave-one-out neighboring profile is used only to choose among structurally improving automatic candidates; profile gain alone cannot cause an automatic edit. `SS_cons*` annotations, alignment width, sequence names, and Stockholm metadata are not rewritten.

Here, **fully refined** means a local fixed point for MATER's supported one-column and coordinated helix-arm window moves under the stated safety rule. Automatic mode iterates one-column complete-arm shifts; the previewed manual search additionally considers the larger bounded residue/gap redistribution set described above. It does not mean a globally optimal multiple-sequence alignment, a newly inferred structure, or proof that every accepted register is biologically correct. The original file is deliberately retained so the two alignments can be compared.

## 14. Optional R-scape analysis

MATER can run an external R-scape installation to test the current annotated structure for statistically significant covariation. It uses R-scape's evaluate-given-structure mode; it does not run CaCoFold or replace the current `SS_cons*` annotations.

### 14.1 Requirements and executable discovery

Install R-scape separately, including the R2R and Perl components needed for schematic rendering. Click **Run R-scape** in MATER's main toolbar. MATER checks a previously selected location, its own process `PATH`, and common Homebrew/local binary folders for `R-scape` or `r-scape`.

An app opened from Finder does not normally inherit the customized `PATH` used by an interactive Terminal shell. Therefore, `R-scape -h` can work in Terminal even when automatic app discovery fails. This is expected macOS behavior, not evidence that the R-scape binary itself is broken.

If no executable is found, MATER opens a nonfatal results panel explaining the problem. Click **Locate R-scape…** and select any of these:

- The installed `bin/R-scape` executable
- The distribution's `bin` folder
- The top-level R-scape installation folder
- A development `src/R-scape` executable; MATER will prefer the sibling installed `bin/R-scape` when it exists

The installed `bin` copy is preferred when it sits beside an executable R2R companion. MATER remembers the resolved path for later sessions. The alignment remains open and editable if R-scape is absent, invalid, or fails.

### 14.2 What MATER runs

The current in-memory alignment—not merely the last saved version—is written to an exact input snapshot. Validation errors must be fixed and at least one recognized `SS_cons*` pair must exist. MATER then invokes the equivalent of:

```text
R-scape -s --onemsa --outdir TEMPORARY_DIRECTORY --outname NAME INPUT.sto
```

`-s` requests R-scape's two-set evaluation of the given structure. `--onemsa` limits the invocation to the one alignment MATER submitted. All current WUSS structure layers, including pseudoknots in `SS_cons*`, remain in the submitted Stockholm snapshot. MATER prepends the selected executable's directory to `PATH` so companion programs from the same installation can be found. It also makes the private temporary output folder R-scape's current working directory, because R-scape writes its internal FastTree input and tree there independently of `--outdir`. This prevents Finder launches from failing with `Failed to create external tree` merely because the inherited working directory is not writable.

### 14.3 Results panel and retained files

The R-scape panel is part of the MATER document window. Its PDFKit preview supports normal PDF scrolling, panning, and zooming. Close the panel at any time with its × button; closing it does not cancel a running analysis, and **R-scape results** reopens it. Use **Cancel** to terminate the active R-scape process.

For a saved alignment, MATER creates a unique sibling folder named `NAME-MATER-R-scape`, adding `-2`, `-3`, and so on when necessary. An unsaved document prompts for a parent folder. The retained files are:

| File | Meaning |
|---|---|
| `NAME-R-scape-input.sto` | Exact MATER snapshot supplied to R-scape |
| `NAME-R-scape.cov` | Pairwise statistically significant results at R-scape's selected target E-value; `*` marks a pair in the given structure |
| `NAME-R-scape.sorted.cov` | The same significant-pair table sorted by score, when produced |
| `NAME-R-scape.power` | Given-structure pairs, substitutions, estimated detection power, and expected/observed covarying-pair summary |
| `NAME-R-scape.R2R.sto.pdf` | R2R schematic shown in MATER's zoomable preview |
| `NAME-R-scape.R2R.sto.svg` | Editable vector version of the R2R schematic, when produced |
| `NAME-R-scape.original.sto` | R-scape's retained/normalized Stockholm input, when produced |
| `NAME-R-scape.log` | Exact command plus captured standard output and error |

Buttons below the preview open the full PDF, pair table, power table, or results folder. MATER accepts a run as usable when the `.cov` table and R2R PDF exist. Some R-scape installations report optional RFview or gnuplot warnings after producing those required outputs; MATER retains the results and surfaces a warning linked to the log rather than discarding valid files.

### 14.4 Summary values and interpretation

MATER counts a `.cov` data row as one significant pair and counts rows beginning with `*` as significant pairs belonging to the submitted structure. From `.power`, it reports the number of annotated pairs and R-scape's expected and observed numbers of covarying pairs. These values are parsed summaries of R-scape output, not statistics recalculated by MATER.

A lack of significant pairs is not evidence that a helix is false when the alignment has little detection power, too few substitutions, excessive redundancy, or incomplete occupancy. Consult `.power`, the R-scape user guide, and the phylogenetic context. Conversely, a significant pair supports covariation beyond R-scape's phylogenetic expectation but does not by itself validate every sequence register or every pair in the helix.

The in-editor **Pair variation** colors remain descriptive regardless of whether R-scape has been run; MATER does not currently overlay R-scape E-values on alignment cells.

## 15. Large-alignment overview, filters, and sorting

The bottom overview shares one horizontal coordinate system across four tracks:

1. **Stem blocks:** each stem arm is a colored block; matching colors associate the two arms.
2. **Entropy:** indigo intensity from 0 to 2 bits.
3. **Gaps:** teal intensity from 0 to 100% sequence gaps.
4. **Occupied-pair violations:** red intensity from 0 to 100% definite violations among evaluable observations.

Dashed stem-block outlines indicate pseudoknot classes. A yellow vertical marker indicates the selected column.

Click or drag to navigate. Clicking a paired block selects a structural column and populates the inspector. Block colors show membership; they do not encode support or quality.

For a very large alignment, combine the overview with inspector filtering, sequence sorting, the pinned reference, and search rather than repeatedly scrolling end to end.

## 16. Search and problem navigation

### 16.1 Search syntax

The search field accepts:

- A sequence or annotation label fragment, case-insensitive
- An exact aligned motif, with T normalized to U
- A one-based column number such as `123`
- Explicit column syntax such as `col:123`

Motif search examines the aligned character string, including any gap characters typed in the query. It is literal and does not interpret IUPAC symbols as wildcard patterns. Search continues after the current location and wraps.

Use **Command-F** to focus search and Return to find the next match.

### 16.2 Navigate menu

- **Next problem:** cycles through all generated navigation problems.
- **Next noncanonical pair:** occupied pair outside AU/UA/GC/CG/GU/UG. Gapped pairs are skipped; ambiguity is presently treated as noncanonical by this navigation command.
- **Next high-entropy column:** uses the configured entropy threshold.
- **Next gap-rich column:** uses the configured gap threshold.
- **Next validation problem:** inconsistent row length or malformed structure navigation target.

Navigation wraps to the first matching problem after reaching the end.

## 17. Change tracking and recovery

### 17.1 Baseline comparison

The opened file is the baseline for the document session. The **Changes** menu reports changed cells and rows, separated into sequence and annotation cells.

Enable **Highlight changes from opened file** to show an orange corner marker on changed cells.

### 17.2 Reverting

- **Revert selected region:** restores matching baseline cells within the selected rows and columns.
- **Revert selected rows:** restores complete matching baseline rows only when their original width equals the current alignment width.

Reversion is undoable. It can repair an integrity difference while Alignment Integrity mode remains locked.

### 17.3 Recovery snapshots

MATER keeps rolling snapshots under:

```text
~/Library/Application Support/MATER/Recovery/
```

Each opened baseline receives a content-derived recovery folder. Normal edits schedule a pre-edit snapshot after a short debounce; MATER retains up to 30 snapshots per baseline. **Create recovery snapshot** immediately stores the current document. **Restore latest recovery snapshot** restores the newest different snapshot and registers undo.

While locked, a recovery that would alter ungapped sequence data is rejected.

Recovery is a convenience, not a substitute for versioned source files or laboratory data management.

## 18. PDF and SVG export

MATER exports a vector rendering of the alignment using the current:

- Color mode and custom residue palette
- Grid visibility
- PP-row visibility
- R2R consensus visibility
- Entropy and gap-plot visibility
- Font size

Export options include:

- Optional title
- Color legend
- Column-number interval from 1–100
- Label/name width from 140–480 points
- Selected rows only
- Selected columns only
- Tiled landscape Letter pages for oversized PDFs

The structural inspector and compact bottom overview are not part of alignment exports. Entropy and gap plots can be exported. The compact occupied-pair violation heatmap is deliberately editor-only: it is a navigation diagnostic aggregated from the current `SS_cons*` layers, not an alignment annotation intended for a figure.

For a discontinuous pair/stem selection, **selected columns only** exports the continuous interval from the first through last selected column, including intervening columns.

SVG is convenient for Illustrator, Inkscape, Affinity Designer, and web figures. PDF is convenient for direct sharing and tiled printing.

## 19. Validation and saving

MATER continuously checks:

- At least one sequence row exists
- `# STOCKHOLM 1.0` header is present
- `//` terminator is present
- Every displayed aligned row has the modal sequence alignment width
- At least one `SS_cons*` row exists
- Every recognized structural opener and closer is matched

Missing header, terminator, or structure produces a warning. Missing sequences, inconsistent widths, and unmatched structure symbols produce errors in the footer.

The alignment width is the most common sequence-row length; ties favor the smaller length. This lets validation identify outlier rows, but users should fix width errors before editing or saving.

When Alignment Integrity mode is locked, save performs the additional baseline sequence check described in Section 10.

## 20. Keyboard and mouse reference

| Action | Shortcut/gesture |
|---|---|
| Move one cell | Arrow keys |
| Extend rectangular selection | Shift-arrow |
| First/last column | Home / End |
| Extend to first/last column | Shift-Home / Shift-End |
| Shift selected block/stem | Option-Left / Option-Right |
| Open a gap | Control-G |
| Close a gap | Control-Shift-G |
| Clear to gap/dot | Delete or Backspace |
| Copy/paste | Command-C / Command-V |
| Select all sequence cells | Command-A |
| Focus search | Command-F |
| Undo/redo | Command-Z / Shift-Command-Z |
| Single cell | Click |
| Rectangle | Drag |
| Extend from anchor | Shift-click or Shift-drag |
| Select pair | Double-click paired cell |
| Select complete stem | Triple-click paired cell |
| Highlight full annotation column | Click/drag `SS_cons*`, `RF`, `cons`, or calculated consensus |
| Navigate overview | Click/drag bottom overview |

## 21. Recommended workflows

### 21.1 Manually refine a stem

1. Duplicate and open the alignment.
2. Keep Alignment Integrity mode locked.
3. Select a stem in the overview or canvas.
4. Inspect canonical and noncanonical rates; interpret gaps separately.
5. Filter to pair violations or gaps depending on the biological question.
6. Select an outlier sequence and compare Stem, Element, Pair variation, and Residue modes.
7. Move its stem arm with Option-arrow, Open gap, or Close gap.
8. If appropriate, preview **Suggest fixes**.
9. Recheck neighboring columns, entropy, gap frequency, and subtype context.
10. Save under a versioned filename and reopen it once before adopting it.

### 21.2 Work with structural subtypes

1. Use the teal gap track to identify occupancy boundaries.
2. Remember that gapped pair observations do not contribute to red violations.
3. Use **Gaps in stem** to inspect sequences lacking part of a stem.
4. Do not interpret absence as misalignment without subtype or phylogenetic context.
5. Use **Pair violations** only for occupied, unambiguous convention-breaking observations.

### 21.3 Edit a pseudoknot

1. Confirm the existing WUSS class and crossing partners.
2. Select partner columns by double-click or inspector.
3. To add a new crossing pair, choose a pseudoknot layer rather than overwriting the primary layer.
4. Keep linked arm shifting enabled only when both arms should remain registered together.
5. Export a small SVG after editing and visually confirm the affected colored blocks and rows.

### 21.4 Prepare a figure

1. Hide PP rows if they distract from the sequence comparison.
2. Select Stem, Element, Pair variation, or Residue mode according to the message of the figure.
3. Set a readable font size and name width.
4. Decide whether consensus, entropy, gap frequency, and grid are needed.
5. Export SVG for editing or tiled PDF for direct review.
6. In a caption, describe Pair variation as descriptive unless a separate statistical covariation analysis was performed.

## 22. Rfam example alignments

MATER includes four focused Rfam teaching alignments in `Examples/Rfam`:

| File | Depth × width | Structure |
|---|---:|---|
| `RF00522-PreQ1.sto` | 43 × 70 | PreQ1 riboswitch with an `A/a` pseudoknot |
| `RF01763-Guanidine-III.sto` | 41 × 85 | Guanidine-III riboswitch with an `A/a` pseudoknot and multiple stems |
| `RF00521-SAM-alpha.sto` | 40 × 85 | SAM-alpha riboswitch without a lettered pseudoknot layer |
| `RF01852-tRNA-Sec.sto` | 109 × 119 | Selenocysteine tRNA with an extended multi-stem structure |

All four files are complete, unmodified Rfam SEED downloads. The selenocysteine tRNA example contains 109 sequences, slightly above the initial sub-100 target but compact enough for routine testing and preferable to a sampled general-tRNA alignment. See [`Examples/Rfam/README.md`](../Examples/Rfam/README.md) for provenance and family links. Rfam describes SEED alignments as hand-curated representative family alignments and distributes its data under CC0.

## 23. Troubleshooting and frequently asked questions

### Why are defined stem cells uncolored in Stem mode?

That sequence does not form one of the six accepted pairs at the complete structural pair, or one partner is gapped/ambiguous. Leaving it uncolored is intentional.

### What is the difference between green, cyan, and blue in Pair variation?

Green is the same canonical pair as the most common canonical reference; cyan changes one partner while staying canonical; blue changes both partners while staying canonical. These are descriptive categories, not statistical covariation significance.

### Why is a gapped stem not red in the problem overview?

Gaps may represent genuine structural subtypes or missing coverage. They are excluded from pairing-violation scoring and shown separately in teal and in the inspector's gap category.

### Why does a column have entropy 0 even though most sequences are gaps?

Entropy ignores gaps and ambiguity. If the only canonical observations are the same nucleotide, entropy is 0. Read it together with gap frequency.

### Why is the R2R consensus different from `RF` or `cons`?

MATER recalculates GSC-weighted sequence consensus from the current sequences. `RF` and `cons` are stored annotations that may have been generated by a different method or curated manually.

### Why did all or many sequences disappear?

A Quality Inspector filter is active. Choose **Show all sequences** or set Filter to **All sequences**. Filtering does not delete rows.

### Why is Suggest fixes disabled or empty?

Select a sequence cell in a recognized stem. An empty result means the one-column, linked-arm, and bounded helix-neighborhood search found no integrity-safe structural or profile improvement under its rules. A largely unoccupied arm is intentionally excluded from broad helix optimization because it may represent a structural subtype. An empty result does not mean the alignment is globally optimal.

### What does Auto-refine copy change?

Only gap placement in sequence rows. It can coordinate both complete arms of a helix and their up-to-three-column flanks, but it does not change ungapped residues, row order, structure annotations, alignment width, or metadata. Gapped structural variants are not penalized. The original document remains open and untouched; the refined result is written and opened as a separate file. A result with zero edits means no supported move satisfied the automatic safety rule, not that the alignment is biologically perfect.

### Why will a shift not move?

A destination outside the selected block is occupied in at least one selected sequence. Linked stem shifting requires compatible gaps beside both arms. Open a gap, reduce the row selection, or temporarily unlink the arms if biologically appropriate.

### Why will Open gap not work?

Open gap consumes the nearest downstream gap. If none exists, it cannot preserve width. Insert an alignment-wide gap column or rearrange a downstream gap first.

### Why is saving blocked?

Alignment Integrity mode is locked and an ungapped sequence differs from the opened baseline. Use Changes to revert, undo the residue edit, or explicitly unlock sequence editing before saving the intentional change.

### Why is macOS warning that MATER cannot be verified?

The alpha is ad-hoc signed and not notarized. Right-click the app and choose Open, then use Privacy & Security if needed. Do not bypass this warning for a copy received from an untrusted source.

### Why is a large alignment slow or showing a spinning wait cursor?

Prefer Rfam SEED rather than FULL alignments for interactive curation. Hide the inspector, compact overview, full-height plots, change highlighting, or PP rows when they are not needed. Filter to a selected stem's relevant sequences. If a reproducible alignment still hangs, report its dimensions and a sanitized example.

### Why did a wrapped Stockholm file previously duplicate rows or crash?

Version 0.8 joins repeated interleaved segments by sequence name, `#=GC` tag, or `#=GR` sequence/tag before the editor builds its row model. Saving intentionally writes the normalized single-block form. If a wrapped file still fails, check whether it actually contains more than one complete Stockholm alignment or reuses one sequence name for biologically distinct rows; those cases are outside the one-alignment/unique-name assumption.

### Why do two parts of a helix have different Stem colors?

Stem mode keeps immediately nested pairs together across at most two total bulged columns. A larger internal loop, branch, disjoint helix, different WUSS class, or different `SS_cons*` row defines another fine stem. Choose **Element** to keep a singly nested helix chain one color across any number of unpaired columns. Element mode still splits at true branches, disjoint roots, different structure rows, and different WUSS pairing classes. Dot bracket does not encode arbitrary named domains, so an exact laboratory-specific domain boundary cannot always be inferred.

### Does MATER alter metadata it does not display?

Recognized metadata and unknown raw lines are preserved. Alignment-wide column insertion/removal changes parsed aligned sequence/`#=GC`/`#=GR` rows of the current width but does not rewrite free-text metadata. Always inspect a saved diff during alpha use.

### Can MATER test statistically significant covariation?

Yes, through a separately installed R-scape. Click **Run R-scape** to use its evaluate-given-structure (`-s`) test and view the R2R PDF in MATER. If R-scape is not in `PATH`, use **Locate R-scape…**. MATER's Pair variation display remains an observed-pair comparison and must not be interpreted as a significance test.

### Why does Run R-scape say the program is missing?

MATER does not bundle R-scape, and Finder does not inherit Terminal's customized `PATH`. Install R-scape separately, then click **Locate R-scape…** and choose its installed executable, `bin` folder, or installation folder. If you choose `src/R-scape`, MATER searches the sibling `bin` folder and prefers that installed copy beside R2R. If the statistical table is produced but the drawing is missing, check that the installation's R2R and Perl components are executable. The run log in the results folder contains the exact command and diagnostics.

## 24. Current limitations

Version 0.8.0 alpha 1 intentionally has a bounded scope:

- macOS only; macOS 13 or newer
- Ad-hoc signed and not notarized
- One Stockholm alignment per file; wrapped/interleaved rows are accepted but saved in normalized single-block form
- No de novo multiple-sequence alignment or profile alignment
- No structure prediction or thermodynamic folding
- Statistical covariation analysis requires a separate compatible R-scape/R2R installation; MATER does not bundle, update, or reimplement it
- No covariance-model building/searching
- No automatic sequence addition, removal, renaming, or phylogenetic tree editor
- Suggested and automatic edits use bounded helix-plus-three-column gap rearrangements and iterative local moves rather than a global multiple-sequence realignment algorithm
- GUI pair creation provides four pseudoknot layers beyond primary, although more existing WUSS letter classes are parsed
- Major elements are inferred from continuous pair-containment chains and WUSS classes; arbitrary named biological-domain boundaries are not encoded by dot bracket and cannot be assigned explicitly in this release
- Compact structural-problem heatmap is intentionally editor-only and is not included in alignment PDF/SVG export
- No built-in automatic updater or crash-reporting service

These limitations should be considered when interpreting a “clean” inspector or accepting a suggestion.

## 25. Reporting a useful alpha issue

Report bugs in the private GitHub repository or through the agreed alpha channel. Include:

1. MATER version and build number
2. Mac model/processor and macOS version
3. Alignment dimensions and relevant annotation tags
4. Exact steps starting from opening the file
5. Expected and observed behavior
6. Whether Alignment Integrity was locked
7. Whether undo, save, reopen, and recovery worked
8. A screenshot or short screen recording if visual
9. A minimal sanitized `.sto` that reproduces the issue

Remove unpublished biological data, sample identifiers, and sensitive metadata before sharing. A synthetic two-to-ten-sequence reproduction is usually more useful than a large confidential alignment.

Treat these as highest priority:

- Any unintended ungapped-sequence change while locked
- Saved-file corruption or metadata loss
- A repeatable crash or hang
- Undo/redo producing a different alignment than expected
- Incorrect pair or pseudoknot interpretation

## 26. Building from source

Requirements are the current Xcode Command Line Tools and Swift 5.10-compatible tooling.

From the repository root:

```bash
./scripts/run-core-tests.sh
./scripts/build-app.sh
```

The test script covers parser round trips, structure and pseudoknot parsing, base-pair rules, pair variation, entropy, R2R consensus, gap frequency, integrity, quality metrics, suggestions, editing operations, search/navigation, PDF/SVG export, recovery, and document comparison.

To audit additional Stockholm files without modifying them:

```bash
./scripts/run-core-tests.sh path/to/example1.sto path/to/example2.sto
```

The universal ad-hoc-signed app is written to:

```text
dist/MATER.app
```

## 27. Glossary

**Alignment Integrity** — MATER's protection of ordered exact ungapped sequence strings relative to the opened file.

**Ambiguous observation** — An occupied pair containing at least one residue outside unambiguous A/C/G/U after T→U normalization.

**Canonical pair** — AU, UA, GC, CG, GU, or UG.

**Compensatory/two-sided change** — In Pair variation mode, both partners differ from the modal canonical reference while the observed pair remains canonical. This is descriptive, not a significance test.

**Entropy** — Unweighted Shannon entropy of canonical nucleotide identities at a column, excluding gaps and ambiguity.

**Element** — A topology-derived continuous helix chain: single-child nesting continues through any bulge/internal loop, while branches, disjoint roots, structure rows, and WUSS classes split elements. It is not an explicit biological-domain label.

**Evaluable pair** — Both partners are occupied and unambiguous A/C/G/U.

**GSC weighting** — A tree-based sequence-weighting approach that reduces the influence of closely redundant sequences.

**Interleaved Stockholm** — A Stockholm alignment wrapped into repeated row blocks. MATER joins repeated logical rows and saves normalized single-block form.

**Occupied pair** — Neither partner is a gap; it may still be ambiguous.

**Pair variation** — MATER's descriptive per-sequence classification relative to the most common canonical pair.

**Pseudoknot** — Base pairs that cross another pairing set or are encoded in a non-primary WUSS class/layer.

**RF** — A Stockholm reference-annotation row, usually `#=GC RF`; it is not the same thing as MATER's calculated consensus.

**SEED alignment** — Rfam's curated representative alignment used to construct a family covariance model.

**Stem** — An insertion-tolerant run of nested pairs in one structure row and WUSS opener class; MATER permits up to two total skipped arm columns before beginning a new stem.

**Stockholm** — A multiple-sequence alignment format supporting file-, sequence-, column-, and residue-level annotations.

**WUSS** — Washington University Secondary Structure notation, including bracket and letter pairs used in Stockholm structure annotations.

## 28. Methods summary and references

### 28.1 Reproducible methods description

A concise methods statement for work performed with this alpha is:

> RNA multiple-sequence alignments in Stockholm format were manually curated with MATER version 0.8.0-alpha.1. Ungapped sequence integrity was protected during gap editing. Consensus symbols used MATER's implementation of the standard R2R GSC-weighted sequence-consensus thresholds. Pair-variation colors were used descriptively and were not interpreted as a statistical covariation test.

If the optional integration was used, also report the independently installed R-scape version, its evaluate-given-structure mode, and the retained command/log and output files. If MATER materially contributed to a published analysis, state which external method was used to test covariation or structural support.

### 28.2 Software citation before a formal paper

Until a formal MATER citation is available, cite the software name, full expansion, version, repository URL, and access date. Preserve the exact version or release archive used for the analysis.

### 28.3 References

- Nawrocki EP and Eddy SR. Infernal 1.1: 100-fold faster RNA homology searches. *Bioinformatics* 29:2933–2935 (2013). See the [Infernal User's Guide](http://eddylab.org/infernal/Userguide.pdf) for Stockholm/WUSS and scientific-software manual conventions.
- Weinberg Z and Breaker RR. R2R—software to speed the depiction of aesthetic consensus RNA secondary structures. *BMC Bioinformatics* 12:3 (2011). [Article and supplementary manual](https://pmc.ncbi.nlm.nih.gov/articles/PMC3023696/).
- Rivas E, Clements J, and Eddy SR. A statistical test for conserved RNA structure shows lack of evidence for structure in lncRNAs. *Nature Methods* 14:45–48 (2017). See the [R-scape software and user guide](http://eddylab.org/R-scape/).
- R2R standard consensus command: `--GSC-weighted-consensus ... 3 0.97 0.9 0.75 4 0.97 0.9 0.75 0.5 0.1`. See the [R2R 1.0.7 downloads](https://sourceforge.net/projects/weinberg-r2r/files/).
- Rfam documentation: [SEED and FULL alignments](https://docs.rfam.org/en/latest/faq.html#what-are-seed-and-full-alignments), [family alignment API](https://docs.rfam.org/en/latest/api.html#alignments), and [building Rfam families](https://docs.rfam.org/en/latest/building-families.html).

MATER reuses scientific conventions from these resources but is an independent alignment editor. Rfam example data remain attributable to Rfam and their original curators.
