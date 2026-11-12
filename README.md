# XudoMRI

XudoMRI is research MRI simulation software for preparing a virtual experiment,
simulating its signal, and reconstructing an image. MATLAB provides the interface;
native C++ engines simulate signal on CPU or NVIDIA GPU and generate receive
noise.

## Installation

Download or clone this repository.
Install the following tools; these versions were tested on Windows x64:

| Software                                     | Tested version                   |
|----------------------------------------------|----------------------------------|
| MATLAB                                       | R2026a Update 5 (26.1.0.3346908) |
| Visual Studio Community with C++ build tools | 2026, 18.10.3; MSVC 19.51.36260  |
| Windows SDK                                  | 10.0.26100.0                     |
| CMake                                        | 4.3.1-msvc1                      |
| CUDA Toolkit                                 | 13.2; nvcc 13.2.78               |
| NVIDIA driver (GPU execution)                | 596.71                           |

Use MATLAB with Java enabled and the Signal Processing Toolbox, Image Processing
Toolbox, and Parallel Computing Toolbox.

Runtime checks used an Intel Core Ultra 7 165H and NVIDIA RTX 2000 Ada Laptop
GPU. The signal build requires CUDA even for CPU use because
it builds both executables.

Open a Visual Studio Developer PowerShell. Use `cd` to enter the cloned
`XudoMRI_Simulator` repository folder, then build the engines:

```powershell
cd C:\path\to\XudoMRI_Simulator
.\engine\signal\build_windows.cmd
.\engine\noise\build_windows.cmd
```

Use the location of your cloned repository in the `cd` command above.
Both build commands must finish successfully;
they place executables and runtime DLLs in `engine/bin/`. The noise build also
runs its mathematical tests. In MATLAB, use the same repository location to
open the interface:

```matlab
addpath('C:\path\to\XudoMRI_Simulator\matlab');
Setup;
```

For a basic signal check after building, run `addpath('engine/tests'); testSignal`
in MATLAB from the repository root. It checks both nuclei on CPU and CUDA and
compares radial gridding against a direct Fourier reference. These are targeted
checks for the cases covered by the test.
After building both engines, `addpath('engine/tests'); testInputValidation`
checks protocol numeric parsing, native malformed-input rejection and nonfinite
output guards on CPU/CUDA. Use `testInputValidation('CPU')` to check CPU only.

## Documentation

| Purpose                                         | Document                                         |
|-------------------------------------------------|--------------------------------------------------|
| Run the supplied example                        | [Quick start](docs/QUICK_START.md)               |
| Use XudoMRI and prepare a study                 | [User manual](docs/USER_MANUAL.md)               |
| Understand and extend the code                  | [Architecture](docs/ARCHITECTURE.md)             |
| Prepare input files or read outputs             | [File formats](docs/FILE_FORMATS.md)             |
| Understand physics, assumptions and limitations | [Scientific methods](docs/SCIENTIFIC_METHODS.md) |
| Review outstanding work                         | [Roadmap](TODO.md)                               |
| Track changes and version policy                | [Changelog](CHANGELOG.md)                        |

The software available on this page is provided free of charge and comes without any warranty. CAI²R, NYU Grossman School of Medicine, and the DKFZ do not take any liability for problems or damage of any kind resulting from the use of the files provided. Operation of the software is solely at the user’s own risk. The software developments provided are not medical products and must not be used for making diagnostic decisions. The software is provided for non-commercial, academic use only. Usage or distribution of the software for commercial purpose is prohibited. If you use the software for academic work, please give credit to the author in publications and cite the related publications.

The [original simulator paper](docs/ref/Zhipeng_2014_Bloch-simulator.pdf)
describes the foundational work. Contact its authors about that work; for this
repository, contact [Henrik zu Jeddeloh](mailto:henrik.zujeddeloh@dkfz-heidelberg.de).
