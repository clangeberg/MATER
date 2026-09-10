# Contributing to MATER

Bug reports, careful test cases, documentation corrections, and focused pull requests are welcome.

Before opening an issue, check whether it already exists. For a bug, include the MATER build, macOS version, exact steps, and the smallest Stockholm file that reproduces the problem. **Changes → Copy Diagnostics** provides useful environment details without copying sequence or annotation contents.

Please do not post unpublished alignments, private sample names, or other data you are not allowed to share. A synthetic example is often easier to debug anyway.

## Code changes

MATER is a native Swift macOS application. Keep changes narrow and preserve these invariants:

- Gap-only edits must not change the ordered ungapped residues.
- A sequence's `#=GR` annotations must follow the same residue movement as the sequence.
- Existing Stockholm metadata and unknown lines should survive a save.
- Gaps and ambiguous bases must not be counted as definite pairing violations.
- Optional external tools must fail without crashing or changing the open document.

Run these before submitting a pull request:

```bash
./scripts/run-core-tests.sh
./scripts/run-property-tests.sh
./scripts/run-gui-stress-tests.sh --quick
```

For parser, performance, or rendering changes, also run the relevant Rfam audit, benchmark, or full GUI matrix described in [scripts/README.md](scripts/README.md).

Please explain the biological editing problem as well as the code change. That context makes it much easier to tell whether an interaction will work across different RNA families.
