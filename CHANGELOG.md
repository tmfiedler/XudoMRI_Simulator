# Changelog

Versions use `YYYY.X`: the year and a release number starting at zero each year
(for example, `2026.0`, `2026.1`, then `2027.0`). Root `VERSION` is authoritative;
builds do not increment it. Pending changes go under `Unreleased`. Release tags
use `vYYYY.X` and are lightweight.

File-format versions are independent: new formats start at V1 and increment
when their stored contract changes.

## Unreleased

- Keep Matrix Size edits in the selected FE or PE dimension regardless of orientation.
- Offer to match the signal sample box when starting a run with a disjoint FOV.
- Align the displayed FOV, RF slice, Match bounds and reconstructed image center for nonzero FOV offsets.
- Allow `.prop` tissue properties files anywhere under `protocols/` to be tracked in Git.

## 2026.0

- Initial public source baseline: MATLAB experiment setup and reconstruction,
  native CPU/CUDA signal simulation, and correlated receive-noise generation.
- Proton and phenomenological sodium models, with shared nucleus configuration.
- V1 sequence and tissue formats and one self-contained proton GRE example.
- SNR maps in the reconstruction viewer.
- Basic format/noise checks and a standalone MATLAB signal test with analytic
  proton/sodium references, CPU/CUDA checks, and a GRE reconstruction smoke check.
- Scientific methods and known limitations are described in `docs/SCIENTIFIC_METHODS.md`.
