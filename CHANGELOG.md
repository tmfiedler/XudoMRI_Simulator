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

### Features

- Support gzip-compressed geometry and coil maps in Setup, the field viewer,
  and the signal and noise engines. The MATLAB compression helper reports
  disk savings and includes unassigned CST E-field maps in the protocol folder.

- Reco has a resizable viewer with scrollable controls and protocol details.
  It infers receive channels from the selected signal files.
- Reco pairs the 2D Cartesian image with its acquired k-space plane and the
  three 3D radial views with central k-space sections. Image views support
  rotation, a shared volume-wide display scale and pane export.

- Enlarged Setup and its square geometry previews, reorganized Imaging Setup
  into five rows, and grouped action buttons below it. Refined Study and
  Geometry Editor spacing and aligned the larger header logos with the headings.

- Scanner profiles support RAD_3D with per-axis limits, ramp compensation
  before ADC and balanced rewinders after each spoke.

- Scanner profiles support GRE_EPI with slew-limited readout reversals and
  phase blips between flat-top readouts.

- Scanner profiles also support spin echo, with ramped slice compensation
  around refocusing and balanced readout and phase-encode rewinders.

- Reco displays saved Cartesian readout trajectories and individual samples
  in the radial trajectory plots.

- Plot Seq. displays the nominal in-plane k-space path and individual ADC
  samples for GRE, SE and GRE_EPI, including the path through GRE gradient ramps.

- Setup supports named scanner gradient profiles for GRE. The Generic profile
  uses 22 mT/m and 120 T/m/s per axis with 10 µs ramp steps. Protocols save the
  limits used for generation. Selecting None uses the existing rectangular GRE.

- The three Setup geometry previews support independent zoom and pan and keep
  their views when slices change. Scroll and drag are handled by the Setup
  window on classic MATLAB figures. Panning stays within the image bounds.
- `RAD_3D` supports a nominal acquisition resolution independent of samples per
  spoke. The reconstruction viewer uses the saved resolution for its default
  matrix and supports an override for radial data. Deapodization operates on
  the output volume after extracting it from the internal FFT grid.
- Setup tooltips show the selected nucleus's Larmor frequency, readout duration
  and dwell time, and sequence timing limits. The B1+ tooltip explains its link
  to flip angle and RF pulse duration. Removed the GPU, Run, and Jobs tooltips.

### Fixes

- Widened the Geometry Editor coordinate and slice-position fields and aligned
  the FOV dropdown with the adjacent inputs. The FOV controls leave more
  clearance beside the axial preview.
- Removed Setup tooltips from the version badge, noise loading button, radial
  acquisition resolution field and job details line.


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
