# Build and test scripts

Run these commands from the repository root.

| Command | Purpose |
|---|---|
| `./scripts/build-app.sh` | Build the universal ad-hoc-signed `dist/MATER.app` |
| `./scripts/package-release.sh` | Build the app and make a versioned ZIP plus SHA-256 file |
| `./scripts/run-core-tests.sh` | Run parser, structure, document, editing, export, and optional input-file regressions |
| `./scripts/run-property-tests.sh` | Run deterministic randomized edits and malformed-input fuzzing |
| `./scripts/run-gui-stress-tests.sh --quick` | Run the smaller offscreen rendering/edit/export matrix used in CI |
| `./scripts/run-gui-stress-tests.sh` | Run the full large-alignment GUI matrix |
| `./scripts/audit-rfam-corpus.sh 250` | Download the current Rfam SEED archive into `.build` and audit an even sample |
| `./scripts/benchmark-performance.sh 5000 1000` | Run a reproducible large-alignment model benchmark |
| `./scripts/capture-screenshot.sh` | Build MATER's README screenshot from a local offscreen render |

The build scripts select the active macOS SDK with `xcrun`. Set `MATER_SDK_PATH` only when you deliberately need a different installed SDK.

The core suite can also exercise a real R-scape installation:

```bash
MATER_RSCAPE_EXECUTABLE=/path/to/bin/R-scape \
MATER_RSCAPE_INPUT=Examples/Rfam/RF00522-PreQ1.sto \
./scripts/run-core-tests.sh
```

Rfam downloads and build products stay in ignored local directories.
