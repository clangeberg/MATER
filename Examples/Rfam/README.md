# Rfam example alignments

These focused Rfam SEED alignments are included as realistic MATER exercises. They were downloaded from the official Rfam family-alignment API on 30 August 2026. Rfam data are released under CC0; see the [Rfam terms](https://rfam.org/about#terms) and [Rfam API documentation](https://docs.rfam.org/en/latest/api.html#alignments).

All four files are unmodified copies of the complete Rfam SEED alignments. The riboswitches contain 40–43 sequences. The selenocysteine tRNA SEED contains 109 sequences and is still compact enough for an interactive test.

| File | Rfam family | Depth × width | Pseudoknot | Useful tests |
|---|---|---:|---|---|
| `RF00522-PreQ1.sto` | [RF00522](https://rfam.org/family/RF00522), PreQ1 riboswitch | 43 × 70 | Yes (`A/a`) | Compact H-type pseudoknot, pair variation, linked-arm editing |
| `RF01763-Guanidine-III.sto` | [RF01763](https://rfam.org/family/RF01763), guanidine-III riboswitch | 41 × 85 | Yes (`A/a`) | Crossing stems, multiple structure elements, inspector navigation |
| `RF00521-SAM-alpha.sto` | [RF00521](https://rfam.org/family/RF00521), SAM-alpha riboswitch | 40 × 85 | No | Ordinary nested stem, entropy/gap tracks, consensus comparison |
| `RF01852-tRNA-Sec.sto` | [RF01852](https://rfam.org/family/RF01852), selenocysteine tRNA | 109 × 119 | Additional `()` WUSS class; no lettered layer | Extended tRNA multi-stem alignment, large-alignment navigation, overview and export |

For a first exercise, duplicate one of these files in Finder and edit the copy. They are examples, not claims that the underlying Rfam alignments need correction.
