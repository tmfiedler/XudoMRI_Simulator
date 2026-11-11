# Working on XudoMRI

XudoMRI is research MRI simulation software. Physical correctness,
reproducibility, traceability and readable implementation take priority.
These instructions apply to the whole repository.

## Start here

- Read [README](README.md) for installation and supported tools,
  [architecture](docs/ARCHITECTURE.md) for source ownership and extension points,
  [file formats](docs/FILE_FORMATS.md) for data contracts, and
  [scientific methods](docs/SCIENTIFIC_METHODS.md) for equations and limitations.
- Check the current branch, working-tree changes and task scope before editing.
  Preserve unrelated changes and user data. Do not reset, stash, delete or commit
  someone else's work to obtain a clean baseline.
- Keep changes focused. Separate scientific corrections from refactoring;
  explain intentional behavior changes. Resolve unclear equations or scientific
  intent with the contributor or maintainer before implementing assumptions.
- Prefer a small current-format implementation. Do not add compatibility layers,
  fallback formats, dependencies or frameworks without a concrete requirement.

## Source and build boundaries

- Active signal sources are `engine/signal/src/` and `include/`, shared by the
  host and CUDA implementations. Shared nucleus/tissue code is in `engine/common/`;
  noise is in `engine/noise/`; the interface and reconstruction are in `matlab/`.
- `engine/bin/` is generated deployment output, not source. Build directories,
  local archives and generated study results must not become runtime source
  dependencies or be included in a source distribution.
- Use the native Windows build scripts `engine/signal/build_windows.cmd` and
  `engine/noise/build_windows.cmd`, with MSVC/developer tools. Signal host code
  uses C++14; CUDA and noise use C++17. Preserve CUDA `/Zc:preprocessor` and
  architectures `75;80;86;89` unless changing toolchain support is the task.
- CPU execution must use and identify the host implementation. GPU execution
  must use and identify CUDA, or fail clearly; do not silently substitute CPU.
- MATLAB R2026a on Windows is the primary environment. Other platforms and
  releases require testing before support is claimed.

## Scientific conventions

Consult the methods guide before changing physical calculations. In particular:

- Preserve the independent sodium short/long-T2 Bloch pools, 60/40 weights and
  shared T1/RF rotations. This is a phenomenological model, not a quadrupolar or
  multiple-quantum model. Nucleus constants, relaxation models and sample
  temperature come from `config/nuclei.yaml`; tissue concentration counts
  isotope nuclei in mol/L.
- Cao et al. (2014), equations 11–12, is the noise-method baseline. Changes to
  receive phase, complex covariance, factorization or noise normalization need
  an explicit derivation and independent checks.
- Preserve the positive engine spatial phase. Radial TE is RF center to ADC
  onset; samples occur at original-window midpoints, with first k half a step
  from zero. `RAD_3D` FE/PE/SS are logical radial axes.
- Tx magnitude is complex amplitude, not power in watts. Absolute RF uses
  Tx/B1 scaling; SE refocusing flip angle is relative. Keep TI disabled until a
  sequence generator actually implements inversion preparation.
- Preserve plain RSS and the documented SNR formulas unless their replacement
  is explicitly in scope. Noise cropping and SNR-estimator validity are separate
  questions; a crop comparison does not validate an estimator or coil ranking.
- Preserve z-only `NumIso=[1,1,NumIso]`, derivative/state evolution, ideal
  missing-map fallbacks and the disabled x-gradient-error setter unless a
  specifically justified scientific change covers them. Do not casually remove
  apparently redundant host/CUDA behavior.

## Input, output and MATLAB integration

- Release versions come only from root `VERSION`, using `YYYY.X`; see
  [changelog](CHANGELOG.md) for the scheme. Sequence and tissue **format** versions are
  separate from release versions. Update readers, writers, examples and docs
  together when changing a format contract.
- Preserve exact-case CLI keys such as `TissueTypeFile`, `GeometryFile` and
  `SequenceFile`, ordered multi-coil arguments, numbered receiver outputs,
  float32 layouts and payload-size checks. Preserve tissue metadata and the
  unit-bearing header row. Supply a trailing newline when scripting console
  programs that pause for input.
- Resolve MATLAB setup paths from the source location, not `pwd`. Studies live
  in `protocols/<StudyName>/`; reconstruction needs the matching `.prot`, and
  radial reconstruction also needs `.ktrj`. Keep the bundled example
  self-contained and exclude private studies/generated results from distribution.
- The active reformatter writes binary directly in MATLAB; do not reintroduce
  a `txt2bin.exe` dependency. Preserve CST material matching and document any
  field-map normalization changes.
- Geometry rendering uses both Setup's `displayImages` call path and
  `Bin/gui/displayImagesCore.m`. Inspect both when changing display behavior.
  Keep GUIDE callbacks/tags aligned with their `.fig` files, and register new
  sequence interfaces in the GUI.

## Verification and review

- Build with the native scripts listed above. The noise build runs the
  `Essentials` and `NoiseMath` CTest checks. For signal checks, run
  `addpath('engine/tests'); testSignal` in MATLAB from the repository root.
  This checks both nuclei on CPU/CUDA against analytic references and exercises
  generated GRE simulation/reconstruction. `testSignal('CPU')` explicitly checks
  CPU only. Read the test source for tolerances and scope. These basic checks
  do not establish that every scientific path is validated.
- Before changing physics, units, timing, coordinates, defaults or reductions,
  establish independent expected results and explicit tolerances. A production
  helper generating its own expectations is not an independent reference.
  Refactors should preserve a known baseline; CPU/CUDA parity alone cannot
  establish physical correctness.
- Signal changes need native builds and affected CPU/CUDA checks, including
  nonzero gradients when spatial encoding is involved. Relevant scientific
  claims need independent references for both supported nuclei. Record tool
  versions, hardware/backend, settings, seeds, commands and observed errors.
- Run `NoiseMathTests` for covariance, factorization, statistical or
  reproducibility changes. Fixed seeds reproduce within the same build, not
  necessarily across standard libraries. Statistical evidence must state sample
  count, tolerance and uncertainty.
- After Setup changes, verify geometry import, all three panes and protocol
  load/save. Field-viewer changes need combined/per-channel maps, orientations,
  sliders, probes and overlays checked. Acquisition/reconstruction changes need
  generation, preview, simulation and reconstruction with matching sidecars.
- Sensitive scientific changes need review by someone who did not implement
  them: a human or a separate read-only review agent. Review the derivation
  before physics changes and the diff/results afterward. Report unavailable
  checks and unexplained failures; do not weaken tolerances to obtain a pass.
- Run existing tests relevant to the change. Add small, independent checks in
  `engine/tests/` when existing coverage is insufficient. Retain a regression
  test when it protects meaningful behavior; keep it understandable.
- Keep generated test inputs, outputs and logs temporary and ignored, and clean
  them afterward. Do not introduce temporary MATLAB path overrides or runtime
  dependencies on test artifacts. Never remove private data without authorization.

## Documentation and release boundaries

- After each requested task, run relevant checks, update affected guides, record
  meaningful changes in `CHANGELOG.md` under Unreleased. Keep detailed methods
  in the methods guide and extension advice in architecture.
- Create a commit only when the user explicitly asks you to commit. Otherwise,
  leave changes uncommitted for review. Before creating any commit, including a
  release commit, show the user the exact proposed commit message and wait for
  their approval. Include only the changes for that task.
- Preserve original attribution, license notices and third-party provenance.
- Spatial B0 maps/B0Solver, gradient-error maps, FOV offsets and SAR remain
  incomplete or known-defect paths. Radial reconstruction is quick-look
  gridding. Do not present these as validated scanner models or silently enable
  deferred features; see the methods guide and the [SAR task](TODO.md).
- Set `VERSION` to the target `YYYY.X` when starting development for that
  release on its own branch. Record changes under Unreleased during development.
  Keep `main` at the current release version until the next release is ready to
  merge.
- When explicitly asked to prepare a release, run relevant release checks,
  verify that `VERSION` matches the target `YYYY.X`, move pending changelog
  entries into a dated release section, leave an empty Unreleased section, and
  report the prepared changes. When the user also explicitly asks to commit the
  release, commit the release changes and create a lightweight `vYYYY.X` tag on
  the commit being released. Never push or publish without explicit instructions.
- Summarize what changed and why, checks performed and unresolved
  limitations. Include the commit SHA if a commit was requested and created. Do
  not claim release-wide scientific validation without explicit scope.
