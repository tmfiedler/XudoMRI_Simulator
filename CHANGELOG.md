# Changelog

Versions use `YYYY.X`, where `X` is the release number starting at zero each
year (for example, `2026.0`, `2026.1`, then `2027.0`). The root `VERSION` file is
authoritative, and builds leave it unchanged.

Develop each release on a branch named for its target version, such as `2026.1`.
Set `VERSION` to the target at the start and record changes under `Unreleased`.
`main` carries the current release until the next one is ready. At release time,
move the pending entries into a dated section, merge the branch into `main`,
and add a lightweight `vYYYY.X` tag to the release commit.

File-format versions are independent: new formats start at V1 and increment
when their stored contract changes.

## Unreleased

- The radial trajectory viewer marks the individual samples in its 3D and
  radius plots. The reconstruction viewer pairs the Rx and display controls
  with their labels and gives the lower controls more vertical space.

## 2026.0

- Initial public source baseline: MATLAB experiment setup and reconstruction,
  native CPU/CUDA signal simulation, and correlated receive-noise generation.
- Proton and phenomenological sodium models, with shared nucleus configuration.
- V1 sequence and tissue formats and one self-contained proton GRE example.
- SNR maps in the reconstruction viewer.
- Basic format/noise checks and a standalone MATLAB signal test with analytic
  proton/sodium references, CPU/CUDA checks, and a GRE reconstruction smoke check.
- Scientific methods and known limitations are described in `docs/SCIENTIFIC_METHODS.md`.

### Fixes

- Load protocol files selected through the All Files filter.
- Show the selected FE or PE field of view when loading a protocol.
- Keep Matrix Size edits in the selected FE or PE dimension regardless of orientation.
- Offer to match the signal sample box when starting a run with a disjoint FOV.
- Align the displayed FOV, RF slice, Match bounds and reconstructed image center for nonzero FOV offsets.
- Allow `.prop` tissue properties files anywhere under `protocols/` to be tracked in Git.
