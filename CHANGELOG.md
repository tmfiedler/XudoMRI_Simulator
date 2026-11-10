# Changelog

Versions use `YYYY.X`: the year and a release number starting at zero each year
(for example, `2026.0`, `2026.1`, then `2027.0`). Root `VERSION` is authoritative;
builds do not increment it. Pending changes go under `Unreleased`. Release tags
use `vYYYY.X` and are lightweight.

File-format versions are independent: new formats start at V1 and increment
when their stored contract changes.

## Unreleased

- Parse protocol transmit weights as finite numeric data without evaluating
  MATLAB expressions. Reject malformed numeric CLI values before narrowing.
- Reject nonfinite active B1/E-field and geometry inputs, invalid geometry
  tissue-ID casts, and nonfinite computed signal, trajectory or noise outputs;
  failed runs return nonzero status. Add native/parser and MATLAB regression
  checks while retaining valid input conventions and MRI calculations.

- Recorded a public research-preview readiness review, including clean Windows
  builds, CPU/CUDA and noise checks, history screening, confirmed input-handling
  defects, licensing clarification, and remaining manual validation work.

## 2026.0

- Initial public source baseline: MATLAB experiment setup and reconstruction,
  native CPU/CUDA signal simulation, and correlated receive-noise generation.
- Proton and phenomenological sodium models, with shared nucleus configuration.
- V1 sequence and tissue formats and one self-contained proton GRE example.
- SNR maps in the reconstruction viewer.
- Basic format/noise checks and a standalone MATLAB signal test with analytic
  proton/sodium references, CPU/CUDA checks, and a GRE reconstruction smoke check.
- Scientific methods and known limitations are described in `docs/SCIENTIFIC_METHODS.md`.
