# benchScale — Cross-Architecture Build Validation

Automated build, inspection, and runtime validation for ecoPrimals primal binaries
across target architectures.

**Owner**: primalSpring (ecoPrimals ecosystem infra)
**License**: AGPL-3.0-or-later

## Purpose

Every primal ships as a musl-static binary via plasmidBin. benchScale validates that
those binaries are correct before they reach production gates:

- **Build verification**: compile for each target triple, catch linker/CRT issues
- **Binary inspection**: ELF type, architecture, static linkage, no dynamic deps
- **Runtime smoke test**: execute under QEMU (aarch64, armv7) or native (x86_64)
- **Regression tracking**: compare binary sizes, startup behavior across sessions

## Supported Targets

| Target | Linker | Validation |
|--------|--------|------------|
| `x86_64-unknown-linux-musl` | self-contained (rust-lld) | native run |
| `aarch64-unknown-linux-musl` | `ld.lld` | QEMU `qemu-aarch64-static` |
| `aarch64-linux-android` | NDK clang | `adb` (when available) |

## Usage

```bash
# Validate a single primal
./validate-binary.sh nestgate aarch64-unknown-linux-musl

# Validate all plasmidBin targets for a primal
./validate-binary.sh nestgate --all-targets

# Full ecosystem validation
./validate-all.sh
```

## Prerequisites

```bash
# Rust targets
rustup target add x86_64-unknown-linux-musl aarch64-unknown-linux-musl

# Cross-architecture tools
sudo apt install lld qemu-user-static

# Inspection tools (usually pre-installed)
# file, readelf
```

## Structure

```
benchScale/
├── README.md
├── validate-binary.sh      # single-primal binary validation
├── validate-all.sh          # ecosystem-wide validation
├── lib/
│   ├── inspect.sh           # ELF inspection helpers
│   └── qemu.sh              # QEMU runner helpers
└── results/                 # validation results (gitignored)
```

## Integration with plasmidBin

benchScale runs after `build-primal.sh` and before `harvest.sh` in the
plasmidBin pipeline. A binary that fails benchScale validation is not harvested.

## See Also

- `infra/plasmidBin/` — binary distribution
- `infra/agentReagents/` — agent automation reagents
- `infra/wateringHole/` — ecosystem documentation
