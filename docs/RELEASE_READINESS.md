# Research preview release review — 10 November 2026

**Recommendation: hold publication for licensing clarification and remaining
release checks.** R2–R4 below describe the original baseline and have now been
repaired on `codex/release-readiness-review`; R1 and R5 remain open.

## Input-validation follow-up — 10 November 2026

- **R2 fixed:** protocol weights use strict, finite decimal-token parsing with
  exactly two values and nonnegative magnitude. Expressions are not evaluated.
- **R3 fixed:** active selected B1+/B1-/E1- records reject nonfinite components
  with file/original-record diagnostics. Geometry headers and records are checked
  before integer casts, and both engines stop on invalid geometry. Shared host
  exports reject nonfinite signal, trajectory and noise values before opening
  the corresponding output files. The same signal guards cover CPU and CUDA.
- **R4 fixed:** signal/noise numeric CLI conversions require complete valid
  values before narrowing. Thread/NumIso are positive 16-bit whole counts,
  widths remain positive in metres, and crop indices fit their integer/float
  storage. Valid signed/zero B0, integral count notation, base-0 crop indices and
  ideal missing-map behavior remain available. MRI equations, defaults and file
  layouts are unchanged.

Both unchanged native Windows build scripts passed on a clean candidate copy,
using the environment recorded below. Noise CTest passed Essentials (including
new independent numeric-parser boundary checks) and NoiseMath, 2/2. In MATLAB:

```matlab
addpath('engine/tests'); testInputValidation; testSignal
```

All checks passed on CPU and CUDA. The retained
[input-validation regression](../engine/tests/testInputValidation.m) rejects
protocol expressions, partial CLI conversions, NaN/positive/negative infinity in
both B1 components and all six E components, invalid geometry and finite inputs
that overflow signal/noise computation. Rejected fixtures returned nonzero
status and created no signal/noise output. Valid signed/zero B0, base-0 indices,
NumIso subdivision and missing-map cases passed. The existing proton/sodium
analytic checks retained the exact error maxima reported below, including
nonzero gradients and generated GRE reconstruction. This follow-up does not
claim completion of the outstanding interactive GUI, CST or licensing work.

## Scope

Reviewed baseline: `a416dcbbc6ca7cc6aa020148b119dca7e850e56e`, branch `main`,
`VERSION=2026.0`, initially clean working tree. The target is a public GitHub
research preview, with no additional institutional or journal requirements
identified by the maintainer. This review covers local tracked content, all
locally available Git history, build/deployment boundaries, documentation,
input handling, bundled dependencies, and the numerical checks recorded below.
It is an assessment, not release-wide scientific certification.

## Findings and required follow-up

### R1 — Resolve the public license statement

Root [LICENSE](../LICENSE) contains GPLv3, while [README](../README.md) line 64
prohibits commercial use and distribution. Those statements give recipients
conflicting permissions. The [GNU license FAQ](https://www.gnu.org/licenses/gpl-faq.en.html)
explains that GPL licensing does not permit adding a commercial-use prohibition.
The maintainer confirmed permission exists and requested that the current text
remain unchanged pending clarification. Establish and document the governing
terms before publication; this review does not choose or replace a license.

Also include the following in the redistribution/provenance review:

- `matlab/Bin/sinc.m:19` and `matlab/Bin/jet2.m:10` carry MathWorks copyright
  notices; the repository does not record a separate redistribution grant for
  these copied functions. Confirm coverage or replace them with an authorized
  implementation or documented toolbox call.
- `docs/ref/` contains third-party manuals and a full journal article; the GUI
  includes institutional logos. Confirm that the existing permission covers
  these assets as well as simulator source. Retained attribution is useful but
  is not itself evidence of redistribution permission.

These are provenance questions, not a finding that the maintainer lacks rights.

### R2 — P1: Parse protocol weights without evaluating MATLAB code

[readSetupProtocol.m](../matlab/Bin/inputs/readSetupProtocol.m) line 93 calls
unrestricted `str2num` on a value from `.prot`. Setup consumes these weights
when loading a protocol. A shared data file can therefore run expressions with
the MATLAB user's privileges. MathWorks documents this behavior in
[str2num security considerations](https://www.mathworks.com/help/matlab/ref/str2num.html).

Reproduced on R2026a with a temporary protocol containing:

```text
Tx Mag & Phs:
1 fprintf('AUDIT_EXPRESSION_EXECUTED')
```

Calling `p=readSetupProtocol(file); p.txWeight(1)` printed the marker and returned
`[1 25]`. The probe performed no file modification or external communication.
Replace expression evaluation with strict numeric-token parsing and require
exactly two finite real values per transmitter, with nonnegative magnitude.
Retain a regression check that rejects expressions and malformed rows.

### R3 — P1: Reject nonfinite maps before a run can report success

The active B1 loaders validate record sizes but accept nonfinite field values;
see [B1PlusIn.cpp](../engine/signal/src/B1PlusIn.cpp) line 152 and
[B1MinsIn.cpp](../engine/signal/src/B1MinsIn.cpp) line 155.
Replacing a valid single-voxel transmit map's real component with float32 NaN
made **both freshly built CPU and CUDA executables exit 0 and write
`[NaN NaN]` as the complex signal sample**, with no stderr diagnostic.
The queue uses exit status to classify completion, so this can label an unusable
result completed.

Reject nonfinite active input values with file/record diagnostics, and validate
output finiteness before reporting success. Check receive and E-field paths,
geometry values and overflow cases as part of the repair; the reproduced defect
here is specifically the transmit B1 map. Keep valid ideal missing-map behavior.

### R4 — P2: Validate entire numeric CLI values and their ranges

[signal CmdInterp.cpp](../engine/signal/src/CmdInterp.cpp) line 198 parses B0
with `strtod(..., NULL)`, discarding conversion status and unconsumed text.
On a valid proton fixture, `B0=3garbage` exited 0 with byte-identical signal to
`B0=3`; `B0=garbage` exited 0 with a zero complex signal. These are silent changes
to the requested physical input. `B0=nan` did fail later during magnetization
initialization, so not every invalid value is accepted.

Require complete conversion, finite representable values and documented ranges.
Review the same pattern for widths, bounds, centers, threads and NumIso in both
CLI parsers. Preserve intentional valid zero/sign conventions instead of
assuming new physical restrictions. The existing noise NEX parser illustrates
complete-consumption/range validation. Add focused malformed-input checks.

### R5 — P2: Document the Image Processing Toolbox feature dependency

[README](../README.md) line 22 lists Signal Processing and Parallel Computing
Toolboxes. MATLAB's dependency analyzer also reports **Image Processing Toolbox**
for the combined Setup/reco/reformatter entry points. A concrete use is the
SNR viewer's polygon ROIs, which call `impoly` or `drawpolygon` at
[reconstructionViewer.m](../matlab/Bin/reconstruction/reconstructionViewer.m)
lines 925–937; without them the viewer displays a feature error.

Document Image Processing Toolbox as required for SNR ROI drawing, or clearly
describe that feature as optional. This is not evidence that the basic GRE
simulation requires that toolbox. The official
[drawpolygon reference](https://www.mathworks.com/help/images/ref/drawpolygon.html)
documents the Image Processing Toolbox ROI API.

## Checks performed

### Environment and clean source builds

| Component | Observed environment |
| --- | --- |
| OS | Windows x64, 10.0.26200.9711 |
| CPU | Intel Core Ultra 7 165H |
| GPU | NVIDIA RTX 2000 Ada Generation Laptop GPU, 8 GiB |
| MATLAB | R2026a Update 5, 26.1.0.3346908 |
| MSVC | 19.51.36260.0, Visual Studio 18 2026 |
| Windows SDK | 10.0.26100.0 |
| CMake | 4.3.1-msvc1 |
| CUDA / driver | nvcc 13.2.78 / NVIDIA 596.71 |

Built a fresh `git archive HEAD` extraction using the unchanged native scripts:

```bat
engine\signal\build_windows.cmd
engine\noise\build_windows.cmd
```

Both succeeded. Signal retained C++14 host code, C++17 CUDA,
`/Zc:preprocessor` and architectures `75;80;86;89`. The CUDA build produced
runtime-option deprecation and generated-stub warnings, but completed.
Noise CTest passed **Essentials and NoiseMath (2/2)**.

The original working folder's ignored CMake caches pointed to a previous source
location, so its initial builds stopped. They were preserved and excluded from
the clean-source assessment. Sandboxed CUDA detection initially failed with
MSVC C1902; the unchanged script succeeded outside the sandbox. MATLAB needed a
writable temporary preferences directory. Sandboxed graphics initialization
could not start its local connector and crashed; GUI startup succeeded outside
the sandbox. These environment failures are not counted as source-build defects.

### Existing signal references

From the clean source root in MATLAB:

```matlab
addpath('engine/tests'); testSignal
```

Both backends identified their actual implementations. All three analytic
scenarios passed for both nuclei, as did generated GRE simulation/reconstruction.
The test's signal tolerance was `5e-4/S0`; trajectory tolerance was
`1e-4 cycles/m`. Observed maxima:

| Nucleus | CPU signal error / S0 | CUDA signal error / S0 | Trajectory error, cycles/m |
| --- | --- | --- | --- |
| 1H | 8.12e-7 | 1.03e-6 | 3.20e-5 |
| 23Na | 9.10e-6 | 9.16e-6 | 3.78e-6 |

These checks include nonzero gradients, independent thermal/receive references,
RF response, relaxation/recovery and CPU/CUDA comparison. Their source defines
the exact fixtures and scientific scope.

### Additional temporary numerical probes

These exploratory probes supplement the retained tests; they are not a new
permanent validation suite.

- **All four generators:** GRE, SE, GRE_EPI and RAD_3D, both nuclei and both
  backends, with a 1 micrometre single-voxel reference, B0=3 T, NumIso=1,
  Thread=2, rectangular 0.1 ms RF with 32 points and nominal 90-degree excitation,
  TE=5 ms, TR=100 ms, no dummy TRs, FOV=64 mm, BW=16 kHz. Cartesian matrices
  were 8x8, axial/P--A, SS off and PE/FE on. Radial used 8 samples x 24 spokes
  with all logical axes on. Generation, V1 export, native execution and finite
  nonzero reconstruction passed. Maximum signal CPU/CUDA relative difference
  was `1.15939e-6`, below `5e-4`. SE/EPI results are workflow smoke evidence,
  not independent physical image references.
- **Radial trajectory:** independent golden-angle directions and
  `k_j=(j+0.5)/(2F) * direction`, F=0.064 m. Maximum errors were
  `1.37285e-5` cycles/m for 1H and `1.45986e-5` for 23Na, below the preselected
  `1e-3` tolerance.
- **Radial reconstruction:** synthetic point at `[2 -1 1]*F/N`, 48 independent
  golden-angle spokes, N samples/spoke, half-step radii, F=0.064 m; N=16 and 17.
  Compared the gridded complex volume against an explicit weighted negative-sign
  Fourier sum, using radius-squared weights normalized by their sum. Maximum
  absolute errors were `1.14851e-4` and `1.05032e-4`, below the preselected 0.03
  approximate-gridding tolerance; both peaks occupied the expected voxel.
- **End-to-end noise:** one 1 mm cubed voxel, conductivity 0.4 S/m, T=310 K,
  dwell=0.2 ms, two receive E vectors `[1+2i, .3-.4i, 0]` and
  `[.5-.2i, -.7+.1i, .2+.3i]` V/m. Seed `987654321`, NEX=2, 100,000 samples/set.
  The independent reference was `Cij=4*kB*T*sigma*volume/dwell * Ei*conj(Ej)`.
  On the first set, max covariance error divided by max diagonal power was
  `0.00174741`; max pseudocovariance on that scale was `0.00465613`, both below
  0.025. Sampling uncertainty is of order `1/sqrt(100000)=0.00316`; the tolerance
  is a conservative screening threshold, not a fitted confidence interval.
  Means passed a five-standard-error bound. Receiver files were 800,000 bytes
  each; sets differed and a repeated same-build seeded run reproduced both
  sets byte for byte.
- **Shipped example:** ran its actual geometry, tissue, exported sequence and
  Tx/Rx maps on CPU and CUDA, using saved B0=3, NumIso=1 and Thread=2. Each
  produced 1,024 finite complex samples (8,192 bytes) and matching trajectory
  (12,288 bytes). Reconstruction using its saved protocol produced finite,
  nonzero 32x32 RSS; relative CPU/CUDA signal difference was `1.4885e-6`.
- **MATLAB parsing:** `checkcode` reported no parse errors across the MATLAB
  source and the signal test. Dependency analysis used
  `matlab.codetools.requiredFilesAndProducts` on Setup, reco and reformatter.

### Source distribution, history and dependencies

- Inspected all 290 baseline tracked paths. The source archive contained the
  six self-contained example files and excluded private studies, deployment
  binaries, local archives and build/results directories. Publish from Git or
  a Git archive; `.gitignore` does not make a ZIP of the working folder safe.
- Enumerated all local refs/history: two commits, 291 blob objects including
  objects available through the object database. Screened 279 text blobs for
  private-key blocks, GitHub/AWS token patterns, quoted credential assignments
  and hard-coded Windows user paths; no matches. This was a targeted scan,
  not an exhaustive secret-scanner certification. Remote-only refs, hosting
  settings, LFS stores and external permission records were not inspected.
- Screened the bundled DOCX XML/relationships and JAR metadata for the same
  patterns, with no matches. A raw PDF active-content token check found no
  JavaScript/launch/embedded-file tokens; compressed PDF streams and FIG contents
  did not receive a complete privacy or executable-content audit. Historical
  authorship/contact metadata can remain in reference assets and commits.
- All local Markdown file links resolved. `git diff --check` passed before
  documentation changes. `git fsck --full` found no integrity errors and
  reported one dangling tree, which was left intact.
- yaml-cpp 0.8.0 and SnakeYAML 2.3 have bundled license texts and origin records.
  SnakeYAML SHA-256 matched its documented value:
  `63a76fe66b652360bd4c2c107e6f0258daa7d4bb492008ba8c26fcd230ff9146`.
  The MATLAB loader uses node composition with SafeConstructor. This review
  did not establish a complete current vulnerability inventory or independently
  compare every vendored yaml-cpp file against upstream. Do not treat the
  checksum/provenance check as a vulnerability-free claim.

## Remaining release checks and scope limits

Before declaring the normal GUI workflow tested, record a manual pass for
protocol load/save, geometry import and all three panes, sequence generation
and preview, queued CPU/CUDA runs, cancellation, matching-sidecar reconstruction,
and the field viewer's combined/per-channel maps, orientations, sliders, probes
and overlays. GUI startup was observed, but the interactive protocol workflow
was not completed: the batch session cannot use blocking dialogs, and the
subsequent Computer Use session was stopped. No interactive pass is claimed.
CST import has no supplied representative export fixture and was not executed.
SNR ROI interaction and estimator accuracy were not validated by these checks.

The methods guide already distinguishes phenomenological sodium pools, sample
thermal noise, plain RSS, approximate radial gridding and the global SNR
estimator. Preserve that scope in public release notes. Spatial B0/B0Solver,
gradient-error maps, FOV offsets and SAR remain explicitly unsupported or
experimental; a research preview need not complete them if the limitations
remain prominent. SE/EPI slice profiles, arbitrary EM normalizations and coil
ranking are not independently validated by these smoke probes.

Remaining publication gate: resolve R1, clarify R5, complete the core manual
workflow check, and rerun affected tests on the final release candidate. R2–R4
repairs and their passing regressions are recorded in the follow-up above.
CI, citation metadata, a contribution guide and
a private security-reporting channel would improve the public project but are
not, by themselves, reasons to reject this research preview.

The initial assessment left runtime sources, license text and VERSION unchanged;
the follow-up above changes validation code and tests only.
The assessment does not authorize a tag, push, publication or binary release.
Temporary probe inputs, outputs and logs were cleaned after recording these
results. An ignored clean-source/deployment copy remains under
`.cache/release-audit-20261110/source/` for the interactive MATLAB session;
that session was left untouched after Computer Use was stopped.
