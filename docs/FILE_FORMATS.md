# File formats and engine arguments

Use this reference to prepare inputs, read results or call an engine directly.
For the GUI workflow, see the [user manual](USER_MANUAL.md); for execution and
component ownership, see [architecture](ARCHITECTURE.md).

| File | Contents | Written / read by |
| --- | --- | --- |
| [.smpl](#geometry-smpl) | Voxel coordinates and tissue IDs | CST reformatter / Setup, signal and noise |
| [.prop](#tissue-properties) | Tissue relaxation, concentration and electrical properties | User / Setup, signal and noise |
| [.bfld](#b1-maps-bfld) | One complex B1+ or B1− map per channel | CST reformatter / field viewer and signal |
| [.efld](#e-field-maps-efld) | One complex electric vector map per channel | CST reformatter / field viewer; noise uses E1− |
| [Shim text](#transmit-shim-text) | Transmit magnitudes and phases | User / Tx Array dialog |
| [.seqn](#sequence-seqn) | Timing, RF, gradients and acquisition events | Setup / signal and noise |
| [.ksig / .ktrj](#signal-and-trajectory-output) | Complex signal / sample coordinates in k-space | Signal / reconstruction |
| [.nois](#noise-output) | Complex noise samples per receiver | Noise / reconstruction |
| [.prot](#protocol-sidecar-prot) | Study settings and file references | Setup / Setup and reconstruction |
| [nuclei.yaml](#nucleus-configuration) | Nucleus constants and relaxation models | User / MATLAB and both engines |

## Shared rules

Binary files use **little-endian IEEE-754 float32** (four bytes per value).
The layouts below list values in file order; spaces and line breaks in examples
are explanatory, not binary separators. Extensions identify a file's role;
they do not supply metadata missing from its payload.

Spatial B0, B1 and E-field records must follow the geometry's **exact voxel
order**, including voxels outside a selected simulation crop. Matching record
counts alone do not establish spatial alignment. Each channel has its own map;
the order of filenames defines channel numbering.

Counts are also stored as float32. Every integer through 16,777,216 is exactly
representable; larger integers are not all representable. Geometry and active
B1/E1− readers check the actual payload size rather than trusting a rounded
count header. Keep the geometry, maps and matching protocol together.

## Geometry (`.smpl`)

The file begins with 13 float32 values, followed by `N` voxel records:

| Part | Values in order | Size |
| --- | --- | --- |
| Header | `N xmin xmax ymin ymax zmin zmax xctr yctr zctr xwid ywid zwid` | 52 bytes |
| Each voxel | `x y z tissue_id` | 16 bytes |

Total size: **`52 + 16*N` bytes**. Coordinates, bounds, isocenter and tissue
IDs are integer-valued model indices. Grid widths `xwid/ywid/zwid` are in
**mm**. The engine places a voxel at `(index - center) * width` on each axis,
converting widths to metres. Tissue IDs refer to rows in the tissue file.

The CST reformatter writes x fastest, then y, then z. Preserve that order in
all corresponding maps. Readers derive `N = (file_size - 52) / 16`, reject
partial records and warn if the header count differs from the payload.
Native readers reject incomplete/nonfinite geometry headers, nonfinite voxel
records and tissue IDs outside signed-32-bit integer storage before conversion.
Effective voxel widths must remain positive after conversion to metres.

Writer: [reformatter.m](../matlab/reformatter.m).
Native readers: [signal GeomIn](../engine/signal/src/GeomIn.cpp) and
[noise GeomIn](../engine/noise/src/GeomIn.cpp); Setup also reads this layout.

## Tissue properties

A whitespace-delimited text file starts with the literal identifier and
nucleus, then column names, then one row per tissue. For a single-pool model:

```text
TISSUE_PROPERTIES_V1 Nucleus=1H
ID T1_ms T2_ms Concentration_mol_per_L chemical_shift_ppm conductivity_S_per_m mass_density_kg_per_m3 tissue_name
1 600 100 111 0 0.4 1000 water_reference
```

For the independent two-pool model:

```text
TISSUE_PROPERTIES_V1 Nucleus=23Na
ID T1_ms T2s_ms T2l_ms Concentration_mol_per_L chemical_shift_ppm conductivity_S_per_m mass_density_kg_per_m3 tissue_name
1 25 3 20 0.040 0 0.4 1000 sodium_reference
```

| Column | Meaning / unit |
| --- | --- |
| `ID` | Unique signed 32-bit integer matching geometry tissue IDs |
| `T1_ms` | Longitudinal relaxation, ms |
| `T2_ms` | Single-pool transverse relaxation, ms |
| `T2s_ms`, `T2l_ms` | Short/long transverse relaxation, ms; short ≤ long |
| `Concentration_mol_per_L` | Moles of selected isotope nuclei per litre of sample volume |
| `chemical_shift_ppm` | Signed chemical shift, ppm |
| `conductivity_S_per_m` | Conductivity, S/m; used by noise |
| `mass_density_kg_per_m3` | Mass density, kg/m³ |
| `tissue_name` | Label without whitespace |

The exact-case nucleus ID must match the run. Its configuration selects the
relaxation model: `single_pool_bloch` requires `T1_ms/T2_ms`;
`independent_two_pool_bloch` requires `T1_ms/T2s_ms/T2l_ms`. Spin alone does
not select a model. Every selected geometry ID needs a tissue row, including
ID 0; IDs excluded from the simulation crop need no row for that run.

Column names are case-insensitive and may be reordered with their data.
All names must be unique; extra named columns are ignored. Each data row must
have the same number of fields as the header. Values must be finite and
representable in native float storage, including relaxation times converted
to seconds. Physical values are nonnegative except chemical shift; nonzero
concentration requires positive relaxation times.

Concentration counts **nuclei per sample volume**, not molecules or tissue-water
volume: water contains about 111 mol/L of 1H nuclei; 40 mmol/L sodium is entered
as `0.040`. The engine computes equilibrium magnetization from this value,
the nucleus constants, temperature and B0; see
[scientific methods](SCIENTIFIC_METHODS.md#equilibrium-magnetization).

Readers: [shared native parser](../engine/common/TissueProperties.cpp) and
[MATLAB parser](../matlab/Bin/inputs/readTissuePropertyFile.m).

## Delta-B0 map

| Part | Values in order |
| --- | --- |
| Header | Voxel count, one float32 |
| Each voxel | `delta_B0_ppm dB0dx_ppm_per_m dB0dy_ppm_per_m dB0dz_ppm_per_m` |

Size: `4 + 16*N` bytes. Values represent local field offsets in ppm and
spatial derivatives in ppm/m; record order follows geometry.

**This path is incomplete and unvalidated; leave it unset for normal use.**
The current [signal loader](../engine/signal/src/DelB0In.cpp) adds **+0.8 ppm**
to each loaded offset; the missing-map fallback does not. Effective local
field also includes subtraction of tissue chemical shift. This layout does
not imply validated spatial-B0 simulation.

## B1 maps (`.bfld`)

| Part | Values in order |
| --- | --- |
| Header | Voxel count, one float32 |
| Each voxel | `real_B1_T imag_B1_T` |

Size: **`4 + 8*N` bytes**. One file holds one complex B1+ transmit or B1−
receive map in **tesla**. Values are interleaved per voxel, not stored as separate
real and imaginary arrays. Signal readers reject partial records or a payload
that does not match the geometry; a rounded header alone produces a warning.
Every real/imaginary component read for the selected simulation region must be
finite. A nonfinite value is fatal and identifies its file and original,
one-based voxel record. Records outside the selected crop are not loaded.

RF sequence multipliers scale B1+ maps. Receive accumulation uses the complex
conjugate of the stored B1− value. Keep the exported polarization/phasor
convention and record the map's reference drive normalization; it cannot be
inferred from `Tx Mag`. See [scientific methods](SCIENTIFIC_METHODS.md)
for receive conventions.

Writer: [reformatter.m](../matlab/reformatter.m).
Readers: [B1PlusIn](../engine/signal/src/B1PlusIn.cpp) and
[B1MinsIn](../engine/signal/src/B1MinsIn.cpp).

## Transmit shim text

**Tx Array → Import TXT** reads two whitespace-separated columns, with one row
per transmitter in the same order as the B1+ files:

```text
# magnitude phase_deg
1.0 0
0.8 90
```

The filename is arbitrary, for example `shim_export_txmagphs.txt`. Magnitude is
a finite nonnegative **amplitude multiplier**, and phase is finite, in degrees.
The complex weight is `magnitude * exp(1i * phase_deg * pi / 180)`. Do not add
a channel-index column or uncommented header. Blank lines and full-line
comments starting with `#` or `%` are ignored. Data-row count must equal **# Tx**.

Enter **Shim B1+ (uT)** separately as the reference field for those weights,
then click **OK**. It is not another column in the file.
Reader: [TxMagPhsGUI.m](../matlab/Bin/gui/TxMagPhsGUI.m).

## E-field maps (`.efld`)

| Part | Values in order |
| --- | --- |
| Header | Voxel count, one float32 |
| Each voxel | `real_Ex imag_Ex real_Ey imag_Ey real_Ez imag_Ez` |

Size: **`4 + 24*N` bytes**. All components are in **V/m**. Each six-value record
is one voxel's complex vector; one file represents one channel. Preserve the
field convention and reference drive normalization alongside the corresponding
B1 maps. The noise engine combines E1− receive fields with tissue conductivity;
E1+ maps can be viewed, while SAR remains experimental/unvalidated.

Writer: [reformatter.m](../matlab/reformatter.m).
Noise reader: [E1MinsIn](../engine/noise/src/E1MinsIn.cpp), which rejects
partial records and geometry/payload count mismatches.
All six components read for the selected loading region must be finite;
errors identify the file and original, one-based voxel record.

## Gradient-perturbation maps

The header has the same 13-float32 layout as geometry. Each following record
contains `x y z fractional_gradient_perturbation`, four float32 values.
Coordinates are model indices; perturbation is dimensionless. A map with
`M` records occupies `52 + 16*M` bytes.

The [signal reader](../engine/signal/src/DelGradIn.cpp) crops and interpolates
the map to the simulation region. **This path is incomplete and unvalidated:**
y/z perturbations are applied, while the x-gradient setter is disabled.
Leave these inputs unset for normal use.

## Sequence (`.seqn`)

The entire file is float32. It starts with these **five values**:

```text
-1  1  total_time_steps  transmit_coils  receive_coils
```

The first two values are literal format identifiers. The remaining values
count expanded intervals, Tx channels and Rx channels. Sections follow in
this exact order:

| Section | Values per interval | Meaning / unit |
| --- | --- | --- |
| Duration | 1 | Interval duration, ms |
| Event | 1 | Flag from the table below |
| Sample offset | 1 | Time from interval start to observation, ms |
| ADC dwell | 1 | Original ADC-window duration, ms |
| RF, once per Tx | 3 | `real_multiplier imag_multiplier frequency_offset_Hz` |
| Gx | 1 | x gradient, mT/m |
| Gy | 1 | y gradient, mT/m |
| Gz | 1 | z gradient, mT/m |

**Every section is loop-encoded.** A loop stores `L R` followed by `L` records
of that section's width. Repeat those records `R` times. For example,
`2 3 0 1` in a scalar section expands to `0 1 0 1 0 1`. In an RF section,
`L=2` is followed by six values: two interleaved RF/frequency triples.

There is no section-length prefix or separator: loops continue until they
expand to exactly `total_time_steps` records, then the next section starts.
Complete the full RF timeline for one transmitter, including dummy intervals,
before writing the next transmitter's section. Sections may use different
loop compression.

| Event | Action |
| --- | --- |
| `0` | Evolve without acquisition |
| `1` | Observe signal and tracked k at the sample offset |
| `-1` | Reset tracked k at interval end; retain magnetization |
| `-2` | Reset tracked k and apply ideal transverse crushing at interval end |

Durations are nonnegative. Acquisition intervals require positive duration and
dwell after conversion to seconds, with `0 ≤ offset ≤ duration`. Other events
require zero offset and dwell. Zero-duration controls are allowed; acquisition
on a zero-duration interval is not. After observation, evolution continues
through the remaining interval.

Setup places each observation at its original ADC-window midpoint, even when
RF or gradient changes split that window. A midpoint exactly on a field boundary
belongs to the preceding positive interval. Noise bandwidth uses `1/dwell_s`;
signal sampling is a point observation without integration over the dwell.

All waveform values must be finite. Header counts must be integers: steps
`1..4294967295`, Tx `0..65535`, Rx `1..65535`. Loop lengths/repeats must be
positive signed-32-bit integers, representable in float32. Readers reject
incomplete sections, excess steps, trailing data and unsupported flags before
allocating expanded arrays.

Signal requires **identical frequency offsets across all Tx channels** at each
expanded interval, including muted channels and controls. Comparison is exact
in stored float32 (`+0` and `-0` are equivalent); RF amplitudes and phases may
differ. RF multipliers are dimensionless and scale the corresponding B1+ map.
Native readers convert ms to seconds and mT/m to T/m.

Writer: [Setup.m](../matlab/Setup.m), `expSeq`.
Shared layout validation: [SequenceFile.h](../engine/SequenceFile.h).
Engine adapters: [signal SeqnIn](../engine/signal/src/SeqnIn.cpp) and
[noise SeqnIn](../engine/noise/src/SeqnIn.cpp).

## Signal and trajectory output

Neither output has a header. Both contain one record per acquisition event,
in chronological order:

| File | Each sample | Size for `A` acquisitions |
| --- | --- | --- |
| `.ksig` | `real_signal imag_signal` | `8*A` bytes per receiver |
| `.ktrj` | `kx ky kz`, in cycles/m | `12*A` bytes |

The engine inserts a **one-based receiver number** before the signal extension:
`study.ksig` becomes `study1.ksig`, `study2.ksig`, etc., even for one receiver.
There is one shared trajectory file. Its sample count must match each signal
file. Radial reconstruction reads the trajectory; Cartesian reconstruction
uses protocol matrix/order settings.

These streams contain no matrix size, nucleus or orientation metadata. Keep
the matching `.prot` with the results, and `.ktrj` for radial reconstruction.
A failed run may leave partial outputs; use results only after successful
completion.
The shared host export path rejects nonfinite computed signal/trajectory values
and returns failure on either CPU or CUDA. Signal checks all receivers before
opening any signal output; trajectory validation occurs before its file opens.

Writer: [signal Execution.cpp](../engine/signal/src/Execution.cpp),
`expPhantomKSpace` and `expPhantomKMap`.
Reader: [reconstructionViewer.m](../matlab/Bin/reconstruction/reconstructionViewer.m).

## Noise output

Each `.nois` is headerless interleaved `real_noise imag_noise` float32, with
**`8*A` bytes per receiver** and the same chronological acquisition order as
signal. Each realization is written into `noiseSet<N>/` beneath the requested
output directory; receiver numbers are inserted before the extension:

```text
noiseSet1/study1.nois
noiseSet1/study2.nois
noiseSet2/study1.nois
noiseSet2/study2.nois
```

`NEX` counts independent realizations, not averages. A fixed `NoiseSeed`
reproduces output within the same executable build and inputs; exact samples
need not match across C++ standard libraries.
Nonfinite computed noise is rejected before any set's output files are opened;
the diagnostic identifies the set, receiver and sample, and the engine fails.
Writer: [noise Execution.cpp](../engine/noise/src/Execution.cpp).
Reader: [reconstructionViewer.m](../matlab/Bin/reconstruction/reconstructionViewer.m).

## Protocol sidecar (`.prot`)

This text file connects study inputs, GUI settings and reconstruction metadata.
**Native engines do not read it**: Setup turns its settings into engine
arguments and a `.seqn`. Reconstruction reads the matching protocol to interpret
acquired samples.

A field is an exact label on its own line, followed by its value on the next
line. Leading/trailing whitespace is trimmed. For example:

```text
  Nucleus:
    1H
  MatSize:
    32 32
  B1p Filename:
    transmit1.bfld
    transmit2.bfld
  E1p Filename:

```

Channel-file lists extend to the next label; list order defines channel order.
`Tx Mag & Phs:` similarly contains one magnitude/phase pair per transmitter.
Optional filenames and RF calibration values may be blank, but required labels
must remain present.
Each transmit-weight row must contain exactly two whitespace-separated real
decimal numbers (scientific `e`/`E` notation is allowed): nonnegative magnitude
and signed phase in degrees. Both must be finite. MATLAB expressions, complex
numbers, brackets, comma separators and extra values are rejected without
evaluation.

| Group | Contains |
| --- | --- |
| Input/output filenames | Geometry, tissues, sequence, per-channel maps and result paths |
| Geometry editor | Display, sample bounds, gradient isocenter, FOV offset and grid widths |
| Imaging parameters | Nucleus/B0, sequence/RF settings, FOV, matrix, bandwidth and timing |
| Program info | NumIso, CPU/backend selection, NEX, simulation mode and noise domain |

Noise uses three labels: `Noise Loading Domain:` is `Full` or `Cropped`;
`Noise Crop Bounds:` holds `xmin ymin zmin xmax ymax zmax` in original voxel
indices; `Noise Crop Note:` holds a description. Full permits blank bounds/note.
Cropped requires finite ordered integer bounds, independent of the signal box.

Use the [shipped protocol](../protocols/example/example.prot) as a complete
label template. Setup tries each stored input path, then its basename beside
the protocol; relative paths are first resolved against MATLAB's current
folder. Output paths are rebased to the loaded protocol folder. Keep each run's
protocol with its outputs so later settings changes do not obscure their meaning.

Readers/writer: [readSetupProtocol.m](../matlab/Bin/inputs/readSetupProtocol.m),
[writeSetupProtocol.m](../matlab/Bin/inputs/writeSetupProtocol.m) and the
[reconstruction parser](../matlab/Bin/reconstruction/reconstructionViewer.m).

## Nucleus configuration

[config/nuclei.yaml](../config/nuclei.yaml) is shared by MATLAB and both engines.
Its root contains `sample_temperature_K` (positive kelvin), `default_nucleus`
(an existing ID) and a `nuclei` list. Each entry defines:

| Key | Meaning |
| --- | --- |
| `id` | Unique exact-case identifier used by protocols, tissues and CLI |
| `gamma_Hz_per_T` | Positive gyromagnetic ratio, Hz/T |
| `spin` | Positive integer or half-integer spin |
| `relaxation.model` | `single_pool_bloch` or `independent_two_pool_bloch` |
| `relaxation.short_pool_fraction` | Two-pool model only; strictly between 0 and 1 |

IDs use letters, digits, underscores or hyphens and start with a letter/digit.
Unknown or duplicate keys are rejected. See
[adding a nucleus](ARCHITECTURE.md#nucleus-definitions-and-extension) for an example and extension
requirements.

## Engine command lines

Pass each argument as `"Key=value"`, with exact-case keys and no spaces around
`=`. Quote the whole argument when its value contains spaces.

| Engine | Keys | Meaning |
| --- | --- | --- |
| Both, required | `TissueTypeFile`, `GeometryFile`, `SequenceFile` | Input paths |
| Both | `Nucleus` | Exact configured ID; defaults to YAML `default_nucleus`; must match tissues |
| Both | `xMin/xMax`, `yMin/yMax`, `zMin/zMax` | Selected geometry bounds, model indices |
| Both | `xWid`, `yWid`, `zWid` | Override voxel widths, mm |
| Signal | `Thread`, `B0`, `NumIso` | Threads, tesla, z-direction isochromat count; defaults 1, 3, 1 |
| Signal | `xCtr`, `yCtr`, `zCtr` | Gradient isocenter, model indices |
| Signal | `B1PlusFile`, `B1MinsFile` | Ordered transmit/receive map paths |
| Signal | `DelB0File`, `DelGxFile`, `DelGyFile`, `DelGzFile` | Incomplete map paths described above |
| Signal | `KSpaceFile`, `KMapFile` | Signal base path and trajectory path |
| Noise | `E1MinsFile` | Ordered receive E-field paths |
| Noise | `NEX`, `NoiseSeed` | Realization count (default 1), optional unsigned 64-bit seed |
| Noise | `KNoiseFile` | Noise base path |

Repeat each map key once per corresponding channel. For example, two
`B1MinsFile` arguments define receivers 1 and 2 in that order. Signal defaults
to `kSpace1.bin` and `kMap.bin` when output paths are omitted.

Numeric arguments must parse completely; suffixes such as `B0=3garbage`, NaN,
infinity, overflow and nonzero values that underflow native float storage are
errors. B0 and gradient-center overrides retain signed finite values, including
zero. Explicit voxel widths must remain positive after conversion from mm to
metres. `Thread` and `NumIso` must be whole integers in `1..65535`; integral
floating notation such as `1e0` is allowed. Crop bounds use the existing signed
base-0 integer syntax (decimal, leading-zero octal or `0x` hexadecimal) within
signed-32-bit range and must be exactly representable in float storage.

For noise, supply an **absolute Windows `KNoiseFile` path with backslashes**;
the writer uses its parent directory to insert `noiseSet<N>`. `NEX` must be
`1..65535`. The parser accepts decimal, leading-zero octal and `0x` hexadecimal;
use plain decimal without leading zeros. If `NoiseSeed` is omitted, the engine
generates and reports one; Setup supplies it in the saved run script.

Example, as one line in a Windows command prompt:

```bat
NutateSignal_CPU.exe "Nucleus=1H" "B0=3" "GeometryFile=C:\study\geometry.smpl" "TissueTypeFile=C:\study\tissue.prop" "SequenceFile=C:\study\study.seqn" "B1PlusFile=C:\study\transmit.bfld" "B1MinsFile=C:\study\receive.bfld" "KSpaceFile=C:\study\study.ksig" "KMapFile=C:\study\study.ktrj"
```

Standalone engines pause for Enter at completion; provide a trailing newline
to stdin in scripted runs. Setup generates the command and handles this pause.
