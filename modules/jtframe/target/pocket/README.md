# Analogue Pocket Target

This directory contains the public JTFRAME Analogue Pocket target used by the
APC build flow. It is no longer just a bare scaffold: multiple arcade cores now
build, package, and run on real Pocket hardware through this target. The target
still is not full JTFRAME target parity, so keep build success, package
correctness, SD asset completeness, and hardware validation as separate gates.

Core bring-up results are tracked in `CORE_MATRIX.md`. Treat that matrix as the
source of truth for which cores are hardware-tested, merely buildable, or
blocked by missing metadata, dependencies, fit, timing, ROM payloads, or
hardware symptoms.

`CORE_MATRIX.json` is the generated machine-readable form of the matrix. Regenerate
and check it with `pocket_matrix.py` after batch work.

## Included Pieces

- `pocket.qpf` and `pocket.qsf` so the normal JTFRAME target build flow
  resolves.
- `cfg/files.yaml` and `cfg/sim.yaml` so synthesis and simulation file
  generation work for the Pocket target.
- `hdl/pocket_top.sv`, `hdl/jtframe_pocket.sv`,
  `hdl/jtframe_pocket_bridge.v`, `hdl/jtframe_pocket_data_loader.v`, and
  `hdl/jtframe_pocket_sound_i2s.v` as the public APF-facing wrapper.
- `pocket.go` so `jtframe mra` emits Pocket JSON metadata, instance JSONs,
  video metadata, input metadata, DIP/interact metadata, per-asset
  `Presets/.../{Input,Interact}` JSON, and minimal platform package files under
  `release/pocket/raw/Cores/jotego.<shortname>/`.
- `overrides.yaml` for auditable Pocket-only metadata policy learned from
  hardware bring-up.
- `export_apc_project.sh` and `build_with_apc.sh` for isolated APC project
  export/build packaging.

## Public Release Gates

- The shell is APF-shaped and hardware-proven on several cores, but it is still
  a public replacement. Any core marked only `Build OK / Needs HW test` still
  needs SD copy, asset validation, and real Pocket smoke testing.
- Save states remain disabled at the bridge contract.
- Some cores need bespoke Pocket wrappers or generated `cfg/mem.yaml` before
  export can proceed; older JTFRAME cores that already use
  `jtframe_game_ports.inc` can instead build through the target's legacy-top
  path. CPS1/CPS1.5/CPS2 now use a generated `cfg/mem.yaml` boundary for
  Pocket release builds. CPS2 is timing-clean after the latest download
  handshake fix; CPS1/CPS1.5 still need a tiny PLL hold/removal cleanup before
  they should be treated as release-clean. All three need SD copy and hardware
  retest on the `prog_rdy` handshake package.
- Some buildable cores still need ROM/cart payloads copied into the generated
  `Assets/jt*` folders before hardware behavior can be judged.
- Some large systems exceed Pocket fit limits and need a target-specific memory
  or feature strategy before they can become release candidates.

## Export Hardening

`export_apc_project.sh` validates the common public-target breakages before
APC or Quartus report opaque failures:

- rejects export paths outside the repo root;
- runs `jtframe mem` first, then verifies the generated Pocket wrapper and
  `mem_ports.inc`;
- allows legacy JTFRAME tops without `cfg/mem.yaml` when the source top already
  includes `jtframe_game_ports.inc`, and verifies that `files.qip` contains the
  real `cores/<core>/hdl/<GAMETOP>.v` source instead of requiring a duplicate
  Pocket wrapper;
- blocks CPS1/CPS1.5/CPS2 legacy-top exports by default with an actionable
  error. Set `JTFRAME_POCKET_ALLOW_LEGACY_CPS=1` only for local diagnostic
  comparisons against the old internal `jtcps1_sdram` topology; release builds
  use the generated `mem.yaml` boundary;
- fails explicitly when `cfg/mem.yaml` is missing and neither a legacy
  `jtframe_game_ports.inc` top nor a bespoke `cores/<core>/pocket` wrapper
  exists;
- validates required Pocket metadata files such as `core.json`, `data.json`,
  `input.json`, `interact.json`, `variants.json`, `video.json`, `audio.json`,
  and `info.txt`;
- validates every `core.metadata.platform_ids[]` entry and fails if the
  matching `dist/Platforms/<id>.json` file is missing;
- validates generated per-asset Input/Interact preset JSON before copying
  `Presets/` into the package root;
- copies HDL-local `.hex`, `.mif`, and `.bin` collateral from both core HDL
  folders and QIP source folders;
- disables JTFRAME credits/logo overlay generation for Pocket packages, so
  per-core `cfg/msg` Patreon/JT splash assets are not emitted or copied;
- filters any `MiSTer specific` section from imported core `syn/*.sdc` files so
  reusable timing constraints survive without stale DE10/HDMI paths;
- appends optional core-local `cores/<core>/syn/pocket.qsf` settings for
  Pocket-only fitter overrides that should be reproducible without shell
  environment overrides;
- falls back to `NOSOUND` for `jt539` users only if the public `jt539` module is
  unavailable.

`pocket.go` now derives the primary video orientation from the main
instance/coremod metadata when available, while keeping scaler width tied to
the APF-facing active stream width (`JTFRAME_WIDTH`). Coremod horizontal-frame
bits describe visible crop in the ROM header; they must not shrink
`video.json` width because the Pocket scaler still receives the full active
line including border pixels. The target also honors the `COREMOD_XORFLIP`
orientation bit and emits additional unique scaler modes for mixed-orientation
instance sets, which keeps cores such as System 16 and Namco System 1 from
being locked to a single horizontal or clockwise-vertical `video.json` mode.

`pocket.go` also emits per-asset Pocket presets that mirror each slot-0
instance JSON path. For an instance at
`Assets/<platform>/jotego.<shortname>/Game.json`, the target emits matching
`Presets/jotego.<shortname>/Input/<platform>/jotego.<shortname>/Game.json` and
`Presets/jotego.<shortname>/Interact/<platform>/jotego.<shortname>/Game.json`.
This keeps button labels and DIP defaults tied to the selected MRA instead of
leaking the first game's controls/settings across every clone or alternative.
Instances also include the optional `.sav` data-slot reference when the core
declares `JTFRAME_IOCTL_RD`, matching the public data-slot contract.

## SDRAM Programming

The Pocket QSF defines `JTFRAME_POCKET_PROG_SINGLE_BEAT` so ROM downloads use
single-beat SDRAM programming writes even when the normal ROM read path keeps a
burst length above one beat for JTFRAME's small read caches. The controller
masks unused programming burst beats under that macro. This prevents the second
beat of a download write from corrupting the next SDRAM word, which shows up
most clearly on cores with swizzled graphics ROM regions such as `btiger`.

Use `pocket_sim` memory ROM diagnostics to validate this path after SDRAM
changes. A healthy run should have matching SDRAM physical write and ROM
preload counts, with zero ROM mismatch, unwritten-read, coverage-gap, and
byte-enable errors for the loaded ROM window.

The CPS family is the first larger user of this generated-memory path. Its
Pocket wrapper now posts the CPS ROM-download remap outputs back into the
JTFRAME generated downloader, feeds the SDRAM programmer `prog_rdy` signal back
into `jtcps1_prom_we`, and registers CPU-visible SDRAM return data/ok and
controls on `clk48`. The `prog_rdy` feedback is required because the legacy CPS
loader holds each remapped byte until the SDRAM programming path is ready; a
single-cycle remapped `post_we` pulse can silently drop ROM writes and boot to a
black screen. The clock-domain registers close the old `clk96` download-remap
setup failure and the subsequent Fast-corner `clk96` to `clk48` hold failures
without waiving real timing paths.

## Target Overrides

Use `overrides.yaml` for Pocket-specific packaging or scaler policy learned
during hardware bring-up. This keeps avoidable one-off metadata fixes out of
`cores/*/cfg` and makes the target's assumptions reviewable in one place. Each
override must include a reason.

Good fits for `overrides.yaml`:

- Pocket-only aspect/scaler metadata that should not affect MiSTer, MiST, or
  other JTFRAME targets;
- documented hardware bring-up quirks that the generator can apply without HDL
  changes;
- repeated family behavior that should later become a target-wide rule.

Do not use `overrides.yaml` for real portable core facts, synthesis source
lists, or hardware implementation changes. Put those in the normal core cfg,
`cores/<core>/pocket`, or `cores/<core>/syn/pocket.qsf` as appropriate.

## Module Policy

`modules/jt539` is vendored as normal source in this repository because the
historical submodule URL is unavailable publicly and affected public builds
need a K054539-compatible module. The vendored implementation is a clean
JTCORES-style behavioral HDL module; it does not import Furrtek's pin-level
SiliconRE HDL.

`modules/jtdsp16` and `modules/jttms` were checked during this pass. Their
worktrees had accidental missing-file dirtiness only; they were restored to
their checked-in submodule contents and are not vendored or changed by this
target work.

## APC Build Flow

Use `build_with_apc.sh` when building with `apc`. The APC tool walks package
`core.json` files in the shared workspace and can copy one build's
`bitstream.rbf_r` into sibling exports under `.apc/`. The wrapper exports a
fresh project, runs `apc` from an isolated temporary workspace that exposes only
that package, and copies the verified `bitstream.rbf_r` back into the real
export. This avoids mutating sibling package descriptors and keeps parallel
Pocket builds from overwriting each other's packaged bitstreams.

When a build is copied to SD or tested on hardware, update `CORE_MATRIX.md` with
the exact artifact hash, SD asset state, hardware result, and next action.

## Matrix Tooling

Use `pocket_matrix.py` to keep the markdown matrix honest:

- `./pocket_matrix.py check` verifies that every `cores/*` directory has exactly
  one matrix row and that the coverage summary matches the rows.
- `./pocket_matrix.py check --sd-root /Volumes/Untitled` also checks SD-card
  bitstream hashes against the matrix and reports cores with no detected ROM or
  cartridge payloads.
- `POCKET_ASSET_ROOT=/path/to/Assets ./pocket_matrix.py check --asset-root "$POCKET_ASSET_ROOT"`
  scans an asset cache for available ROM/cart payloads.
- `./pocket_matrix.py generate-json` refreshes `CORE_MATRIX.json`.
- `./pocket_matrix.py copy-assets --dest-root /Volumes/Untitled <core...>`
  copies ROM/cart payloads from the configured asset cache into an SD-card or
  package root. It intentionally does not copy cached JSON metadata, so generated
  instance and preset files remain the public target's source of truth.
- `./pocket_matrix.py run --stage export <core...>` runs Pocket export into
  `.apc/<core>-matrix-export`.
- `./pocket_matrix.py run --stage build <core...>` runs the isolated APC build
  wrapper into `.apc/<core>-matrix-build` and reports the resulting bitstream
  hash when the build succeeds.
- `./pocket_matrix.py run --stage sim --package-only <core...>` exports a fresh
  package, stages ROM/cart payloads from the configured asset cache, reuses an
  existing built `bitstream.rbf_r` from `.apc/<core>-*/dist` when available,
  and runs `apfsim package-check --strict`.
- `./pocket_matrix.py run --stage sim <core...>` then continues into
  `apfsim bringup`. The runner generates a profile from the fresh export,
  preserves pocket_sim's generated JTFRAME logical APF wrapper when present,
  and only patches the profile top to the QSF `TOP_LEVEL_ENTITY` as a fallback.
  It also stages safe `$readmem` runtime collateral such as CPU microcode,
  fonts, filter coefficients, and small lookup tables into a generated runtime
  directory. The runner intentionally does not expose generated `msg.bin` or
  `msg.hex` directly because some cores emit message files larger than the
  Verilator-side debug/message RAM. Scenario repair now chooses an instance JSON
  whose referenced payload exists, then patches the ROM/cart slot and checksum
  from that same instance. Use `--instance-match "Road Fighter"` for targeted
  multi-game package validation when the generated setup JSON selects a sibling
  game. The patch details are recorded in
  `profile_runtime_cwd` and `scenario_instance_binding`; this catches missing
  runtime collateral and setup-JSON/ROM mismatches before they become misleading
  black-screen or silent-audio failures. Use `--timeout-cycles` for the
  simulated cycle budget; the default is intentionally larger than
  `pocket_sim`'s generated scenario default so large ROM loads still leave
  post-load time for frame and audio validation.
- Add `--input-video-gate` to sim runs when triaging black, frozen, or
  warning-screen failures. The runner patches the generated scenario with
  coin/start inputs and asks `pocket_sim` to require visible video movement
  after input. Treat this as a targeted diagnostic gate, not as a universal
  release requirement for every attract-mode core.
- Add `--input-audio-gate` to the same targeted runs when audio behavior matters.
  This asks `pocket_sim` to require nonzero post-input audio samples and records
  the gate patch in `input_audio_gate`. Use failures such as
  `AUDIO_NO_POST_INPUT_ACTIVITY` to separate "input/gameplay never advanced"
  from "video advanced, but the APF DAC path is still silent".
  This is the intended gate before SD copy, but it still depends on buildable
  pocket_sim models for mixed HDL, vendor IP, and external memories used by the
  generated package.
