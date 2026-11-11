# Scientific methods and assumptions

This guide describes the methods **implemented in XudoMRI**: tissue and field
inputs → magnetization evolution → receive signal and noise → reconstructed
images. It combines the current radial and sodium methods in one reference.
File layouts are in [FILE_FORMATS](FILE_FORMATS.md); code organization is in
[ARCHITECTURE](ARCHITECTURE.md).

| Used in | Method | Main assumption |
| --- | --- | --- |
| Tissue initialization | High-temperature thermal equilibrium | Supplied isotope concentration and common temperature |
| Signal engine | Piecewise-constant Bloch evolution | Fixed tissue properties and fields within each model voxel |
| Sodium relaxation | Two independent Bloch pools | 60/40 fractions, shared T1, no exchange |
| Receive signal | Complex B1− weighting and voxel integration | Consistent EM map phase and normalization |
| Noise engine | Cao et al. equations 11–12 | Sample-induced thermal noise |
| Cartesian reconstruction | Ordered 2D Fourier transform | Cartesian acquisition and matching protocol |
| Radial reconstruction | Density-weighted Kaiser–Bessel gridding | Approximate normalized weighted adjoint |
| SNR display | Two-noisy-image difference estimate | One global noise denominator |

Equations use SI units unless stated otherwise. `*` means complex conjugation;
`H` means conjugate transpose. Define `γ_Hz` in Hz/T and `γ = 2πγ_Hz` in rad/s/T.
The configured values are 42.576 MHz/T for 1H and 11.262 MHz/T for 23Na.

## Equilibrium magnetization

**Used to initialize each signal voxel and set its longitudinal recovery target.**
For isotope concentration `C` in mol/L of sample volume:

$$
n = 1000 N_A C, \qquad
M_0 = \frac{n\,\gamma^2\hbar^2 I(I+1)\,B}{3k_B T}
    = \frac{n\,\gamma_{\mathrm{Hz}}^2 h^2 I(I+1)\,B}{3k_B T}.
$$

Here `n` is nuclei/m³, `I` is nuclear spin, `B` is tesla and `M0` is A/m.
The code uses the second expression, evaluates the coefficient in double
precision and stores magnetization in float state. It uses `B = B0 + δB`,
including its existing chemical-shift/local-field convention below.

Constants are `N_A = 6.02214076×10²³ mol⁻¹`, `h = 6.62607015×10⁻³⁴ J·s` and
`k_B = 1.380649×10⁻²³ J/K`, matching the
[BIPM defining constants](https://www.bipm.org/en/measurement-units/si-defining-constants).
The common temperature in
[config/nuclei.yaml](../config/nuclei.yaml) is **310 K**. At fixed inputs,
`M0 ∝ 1/T`; changing temperature does not adjust supplied T1, T2 or conductivity.

Concentration counts isotope **nuclei**, not molecules: water has about
111 mol/L of 1H nuclei; 40 mmol/L sodium is `C = 0.040`. Proton spin is 1/2,
sodium spin is 3/2; both use the same formula. No separate empirical
sodium-to-proton multiplier is applied. The receive-induction factor described
below is a separate physical factor. Thermal polarization is assumed;
hyperpolarization and quadrupolar spin dynamics are not modeled.

Implementation: [ThermalMagnetization.h](../engine/common/ThermalMagnetization.h)
and [Execution.cpp](../engine/signal/src/Execution.cpp), `initPhantomMagn`.

## Bloch evolution and excitation

**Used by both CPU and CUDA signal backends.** Geometry defines fixed voxel
positions and tissue properties. Each waveform interval holds RF and gradients
constant. With all transmitters sharing one carrier `f_RF`, the effective field is:

$$
B_{\mathrm{eff},x}+iB_{\mathrm{eff},y}
  = \sum_c a_c(t) B_{1,c}^{+}(\mathbf r), \qquad
B_{\mathrm{eff},z}
  = \delta B(\mathbf r)+\mathbf G(t)\cdot\mathbf r
    -\frac{f_{\mathrm{RF}}(t)}{\gamma_{\mathrm{Hz}}}.
$$

`a_c` is the dimensionless complex RF multiplier, B1+ is tesla, `G` is T/m and
`r` is metres relative to the gradient isocenter. In the ordinary path without
spatial B0/gradient-error maps, the tissue chemical shift `χ` in ppm contributes
`δB = −10⁻⁶ B0 χ`. Spatial correction-map paths remain incomplete.

For each pool, the code first rotates about the held effective field, then
applies exponential relaxation:

$$
\theta=\gamma|\mathbf B_{\mathrm{eff}}|\Delta t,\quad
\mathbf u=\frac{\mathbf B_{\mathrm{eff}}}{|\mathbf B_{\mathrm{eff}}|},\quad
\mathbf M'=\mathbf M\cos\theta+(\mathbf u\times\mathbf M)\sin\theta
 +\mathbf u(\mathbf u\cdot\mathbf M)(1-\cos\theta),
$$
$$
M_x^{\mathrm{new}}=M_x'e^{-\Delta t/T_2},\quad
M_y^{\mathrm{new}}=M_y'e^{-\Delta t/T_2},\quad
M_z^{\mathrm{new}}=M_{0,p}+(M_z'-M_{0,p})e^{-\Delta t/T_1}.
$$

At zero effective field, rotation is the identity. `M0,p` is the pool's
equilibrium magnetization. This rotation–relaxation splitting approximates
simultaneous relaxation during finite RF; results depend on RF time resolution.
The GUI default is 512 RF points. Tested recipes meet their recorded accuracy
budgets, but other pulse/tissue settings require convergence checks.

For a fixed-phase, on-resonance pulse, nominal flip angle uses its sampled area:

$$
\alpha=\gamma B_{1,\mathrm{ref}}\sum_j e_j\Delta t_j,\qquad
w_c=m_c e^{i\phi_c\pi/180},\qquad
s=\begin{cases}
1 & \text{target blank},\\
0 & \text{target zero},\\
B_{1,\mathrm{target}}/B_{1,\mathrm{shim}} & \text{target positive, shim positive}.
\end{cases}
$$

`e_j` is the normalized RF envelope, `α` is radians, and `w_c` is the Tx Array
magnitude/phase weight. A specified target scales the weights by `s`; zero switches RF off and a blank
target leaves the weights unscaled. A positive target requires a positive shim reference. The reference B1+ must match the supplied maps and
shim. Tx Mag is amplitude, not watts. SE uses its RF FA control for relative
refocusing strength; a nominal flip angle does not guarantee the same response
for different pulse lengths or spatially varying B1+.

Implementation: [Voxel.cpp](../engine/signal/src/Voxel.cpp),
[Vect3D.cpp](../engine/signal/src/Vect3D.cpp) and
[RF calibration helpers](../matlab/Bin/sequence/resolveTxAmplitudeScale.m).
The model does not include diffusion, flow, motion, exchange or magnetization
transfer.

## Sodium biexponential relaxation

**Used by the configured 23Na model.** Each voxel holds two complete
magnetization vectors, with equilibria `M0,s = 0.6 M0` and `M0,l = 0.4 M0`.
They share T1, RF rotations, gradients and frequency offsets, but relax with
the supplied `T2s` and `T2l`. Their states are evolved independently and summed:

$$
\mathbf M=\mathbf M_s+\mathbf M_l,\qquad
M_{xy}(t)=M_{xy}(0)e^{i\varphi(t)}
 \left[0.6e^{-t/T_{2s}}+0.4e^{-t/T_{2l}}\right].
$$

Here `Mxy = Mx + iMy` and `φ(t)` is accumulated common precession phase
(`φ(0)=0`). The bracket gives the decay envelope after proportionate excitation
of the two states, with RF off. Setting `φ=0` gives the demodulated decay law. During finite RF, evolve each full pool state with
the Bloch updates above. Do not repeatedly apply the weighted biexponential
factor to one combined state: that does not reproduce this decay law.

Fractions come from the nucleus configuration; proton uses one pool. This is
an empirical independent-pool relaxation model, with no pool exchange,
quadrupolar coherences or orientation-dependent relaxation. The two states are
computational components, not identified intracellular/extracellular compartments.
The 60/40 decay model has a quadrupolar-relaxation basis for a homogeneous
sodium environment; that ratio is not universal for mixed tissue environments.
See [Burstein and Springer (2019)](https://doi.org/10.1002/mrm.27738).
Implementation: [Voxel.cpp](../engine/signal/src/Voxel.cpp), pool rotation,
relaxation and combined-state routines.

## Spatial averaging and receive signal

**Used at each ADC observation.** `NumIso` subdivides each geometry voxel only
along z; x/y retain one sample each. Properties and field-map values are shared
by these subvoxels. The public build approximates x/y intravoxel phase averaging
with sinc factors from tracked magnetization derivatives:

$$
\phi_x=\frac{M_x\partial_x M_y-M_y\partial_x M_x}{M_x^2+M_y^2},\qquad
A_{xy}=\operatorname{sinc}\!\left(\frac{\Delta x\phi_x}{2}\right)
       \operatorname{sinc}\!\left(\frac{\Delta y\phi_y}{2}\right),\qquad
\operatorname{sinc}(u)=\frac{\sin u}{u}.
$$

`φ_y` is defined analogously; phase derivatives are set to zero when transverse
magnetization is zero. `sinc(0)=1`. For receiver `c`, the implemented sum is:

$$
S_c(t)=\sum_v (M_{x,v}+iM_{y,v})\,[B^-_{1,c}(\mathbf r_v)]^*
       \,\gamma(B_0+\delta B_v)\,\Delta V_v\,A_{xy,v}.
$$

The sum includes z subvoxels, whose volumes add to the original voxel volume.
This is a local linear-phase approximation in x/y; it does not resolve
arbitrary subvoxel tissue or EM-field variation. Sample-box cropping excludes
signal sources and can change the image even when those sources lie outside
the displayed FOV. Magnetization and derivative states are tracked per pool
and combined before phase and receive evaluation. No separate spectral/T2*
distribution is integrated.

Implementation: [Voxel.cpp](../engine/signal/src/Voxel.cpp),
`calculatePhaseDerivatives` and `receiveSignalContribution`.

## Encoding and ADC timing

**Used by sequence generation and signal acquisition.** The nominal trajectory
integrates the programmed gradients:

$$
\mathbf k(t+\Delta t)=\mathbf k(t)
 +\gamma_{\mathrm{Hz}}\mathbf G(t)\Delta t
 \quad\text{[cycles/m]}.
$$

The engine's spatial phase is positive, `exp(+i2π k·r)`. ADC observations use
the original window midpoint; if fields change within that window, evolution
is split around that same observation time. Signal is a point sample, with
no dwell integration or receiver filter. Reset controls set tracked k to zero;
an ideal crusher also zeroes transverse magnetization while retaining Mz.
A k reset alone does not reset magnetization.

GRE/SE use Cartesian phase-encode lines. GRE_EPI alternates readout polarity.
RAD_3D uses nonselective excitation and one center-out half-spoke per TR;
Fibonacci-sphere directions cover the complete sphere, and rewinders return
the nominal gradient moment to zero. For sample index `j = 0…Ns−1`:

$$
\Delta k=\frac{1}{2F},\qquad
\mathbf k_j=(j+\tfrac12)\Delta k\,\mathbf u_{\mathrm{spoke}}.
$$

`F` is the isotropic FOV in metres. Radial TE is RF center to **ADC onset**;
the first stored sample is half a radial step from zero. Spoke count controls
angular coverage. The sequence assumes ideal gradient waveforms; hardware
slew/amplitude limits and scanner realizability are not established. Coherent
Bloch state persists between TRs unless an explicit crusher acts; no automatic
RF-spoiling model is added.

Implementation: [SimulationRunner.cpp](../engine/signal/src/SimulationRunner.cpp)
and [RAD_3D.m](../matlab/Sequences/RAD_3D.m).

## EM inputs and CST reformatting

**Used to place tissues and coil fields on one simulation grid.** The reformatter
assigns CST material cells by closest normalized electrical-property match:

$$
J_t=\frac{|\sigma-\sigma_t|}{\max_t|\sigma_t|}
   +\frac{|\epsilon-\epsilon_t|}{\max_t|\epsilon_t|}
   +\frac{|\rho-\rho_t|}{\max_t|\rho_t|},\qquad
\mathrm{ID}=\mathrm{ID}_{\arg\min_t J_t}.
$$

The material table must match model type and CST frequency. Exactly zero mass
density selects **Air (53)** first. Other nonfinite/negative properties select
**Undefined (255)**. Valid properties use the minimum cost without a rejection
threshold. This classification is separate from assigning MR tissue properties.

Materials use containing-cell sampling; H/E fields use nearest-node sampling
on the same uniform physical target grid (midpoint ties choose the larger
index). One common crop and centered padding preserve map/geometry registration.
B1 values outside the represented body mask, and NaN B1 samples, are zeroed;
E fields retain their represented loading extent.

For exported H phasors in A/m, the code uses the fixed coefficient
`2π×10⁻⁷` (the conventional `μ0/2` conversion) to construct B1 in tesla:

$$
B_1^+=2\pi10^{-7}(H_x+iH_y),\qquad
B_1^-=2\pi10^{-7}(H_x-iH_y)^*.
$$

E retains its raw complex phasor, and signal uses the conjugate of stored B1−.
Keep H/E port ordering, phase basis and reference drive normalization paired.
Maps at different normalizations cannot be compared as absolute signal/noise
without accounting for their scaling. The simulator does not solve Maxwell's
equations or certify that supplied maps cover the physical sample.
Implementation: [reformatter.m](../matlab/reformatter.m).

## Receive noise

**Used by the noise engine; added to complex signal before reconstruction.**
The baseline is **Cao et al. (2014), equations 11–12**. Conductivity-weighted
receive E-field overlap defines the Hermitian coupling matrix:

$$
\Phi_{ij}=\sum_v\sigma_v\,
 \mathbf E^-_{i,v}\cdot[\mathbf E^-_{j,v}]^*\,\Delta V,\qquad
C_s=\mathbb E[\mathbf n_s\mathbf n_s^H]
 =\frac{4k_BT}{d_s}\Phi.
$$

`σ` is S/m, E is V/m, `ΔV` is m³, and `d_s` is the original ADC dwell in seconds.
Diagonal entries describe channel noise power; off-diagonal entries describe
complex correlations. The implementation factors the thermal matrix and draws:

$$
LL^H=4k_BT\Phi,\qquad
\mathbf z_s=(\mathbf x_s+i\mathbf y_s)/\sqrt2,\qquad
\mathbf n_s=L\mathbf z_s/\sqrt{d_s}.
$$

Components of `x_s/y_s` are independent standard normal variables; a fresh vector
is drawn per acquisition. Thus `E[z z^H]=I` and `E[n n^T]=0` (proper complex
noise). A positive-semidefinite Cholesky-like factor supports correlated and
singular channel combinations. NEX produces separate realizations. A fixed
seed reproduces samples within the same executable build and inputs.

**Full** loading integrates the represented geometry/E-field extent independently
of the signal box. **Cropped** loading omits tissue contributions and can reduce
noise power and change correlations. It can therefore overstate SNR; a crop
requires a separate application comparison. Full loading still depends on
complete, correctly normalized EM inputs.

This model includes sample-induced thermal noise. Coil-conductor, matching-network,
preamplifier and receiver-chain noise are excluded. `BW=1/dwell` is the retained
bandwidth convention; absolute scanner-voltage calibration is not established.
The common 310 K temperature gives noise amplitude proportional to `√T`.
Implementation: [noise Execution.cpp](../engine/noise/src/Execution.cpp),
[Functions.cpp](../engine/noise/src/Functions.cpp) and [main.cpp](../engine/noise/src/main.cpp).

## Reconstruction

### Cartesian images

Each receiver's samples are reshaped to the saved matrix. EPI reverses every
even readout line before the transform; saved PE direction and orientation
control the subsequent ordering/display. The implemented transform is:

```matlab
I_c = fftshift(fft2(fftshift(K_c)));
```

This uses the negative Fourier exponent. Cartesian output retains MATLAB's
unscaled FFT gain; the normalized radial gain below is different.

A prescribed offset is measured from the gradient isocenter. During a
slice-selective RF pulse, the carrier is `gamma_Hz * Gss * dSS`, with the
gradient in T/m and the through-plane displacement in metres. The RF shape
still determines the spatial profile. Nonselective dummy pulses use zero
carrier offset. Before reconstruction, the viewer multiplies each receiver's
sample by `exp(-i2*pi*k·d)` using the matching trajectory and displacement
in metres. It uses only the two in-plane components for Cartesian data and
all three for radial data. The signal sample bounds do not enter this phase
correction.
Implementation: [reconstructCartesianDataset.m](../matlab/Bin/reconstruction/reconstructCartesianDataset.m).

### 3D radial images

The matching exported trajectory supplies `k`; no empirical center is subtracted.
For isotropic FOV `F`, target size `N = samples per spoke` and grid size `Ng=2N`:

$$
\mathbf q=\mathbf k F\frac{N_g}{N},\qquad
\Delta x=F/N,\qquad
w_s=\frac{\max(r_s,r_{\min}/2)^2}{\max_j\max(r_j,r_{\min}/2)^2}.
$$

Here `r_s = |k_s|/max|k|` and `r_min` is the smallest positive normalized radius.
These radius-squared weights approximate 3D sampling density; they are not
trajectory-optimized or exact finite-cell quadrature weights.

Samples are gridded separately per receiver with a separable Kaiser–Bessel kernel:

$$
K(d)=\frac{I_0\!\left(\beta\sqrt{1-(2d/W)^2}\right)}{I_0(\beta)},
\quad |d|\le W/2,\quad
\beta=\pi\sqrt{[W(\alpha-0.5)/\alpha]^2-0.8},
\quad W=4,\ \alpha=2.
$$

`I0` is the modified Bessel function; the kernel is zero outside its support.
A 4096-point table is linearly interpolated. Each sample deposits
`w_s S_c(s) Kx Ky Kz` onto **every** supported integer grid node. Grid indices
wrap periodically; distances use the unwrapped nodes.

The code then applies a centered negative-sign 3D FFT, deapodization and gain
normalization. With `u` the normalized image-grid coordinate:

$$
T(u)=\frac{W}{I_0(\beta)}
 \frac{\sinh\sqrt{\beta^2-(\pi Wu)^2}}{\sqrt{\beta^2-(\pi Wu)^2}},\qquad
D(u)=\max\!\left(\frac{\operatorname{Re}[T(u)]}{\max_\ell\operatorname{Re}[T(u_\ell)]},10^{-3}\right),
$$
$$
I_c=\operatorname{crop}_N\!\left[
 \frac{\operatorname{fftshift}(\operatorname{fftn}(\operatorname{ifftshift}(G_c)))}
 {D(u_x)D(u_y)D(u_z)\,T(0)^3\sum_s w_s}\right].
$$

The code evaluates the square root in complex arithmetic. Grid coordinates are
`u_l = (l − floor(Ng/2))/Ng`, for `l=0…Ng−1`; their sampled transform maximum
is `T(0)` for the configured kernel. The removable zero in `T` is filled by its
limit. The crop places physical zero
at index `floor(N/2)+1` for even and odd matrices. The resulting operator
approximates the normalized weighted adjoint:

$$
I_c(\mathbf r)\approx
 \frac{\sum_s w_sS_c(s)e^{-i2\pi\mathbf k_s\cdot\mathbf r}}{\sum_s w_s},
\qquad \mathbf r=\mathbf m F/N.
$$

`m` runs from `−floor(N/2)` to `ceil(N/2)−1` per axis. The output is a cubic
quick-look volume. Density compensation and analytic deapodization are
approximations; matrix/FOV spacing does not establish achieved resolution.
The kernel design follows the gridding framework of
[Beatty et al. (2005)](https://doi.org/10.1109/TMI.2005.848376); the weights,
gain and cubic crop above specify XudoMRI's implementation.
There is no iterative SENSE/PICS inversion, sensitivity estimation, gradient-delay,
off-resonance or motion correction. Sparse spokes can produce substantial artifacts.

Implementation: [trajectory/weights](../matlab/Bin/reconstruction/prepareRadialTrajectory.m),
[kernel/deapodization context](../matlab/Bin/reconstruction/buildRadialReconstructionContext.m)
and [radial reconstruction](../matlab/Bin/reconstruction/reconstructRadialDataset.m).

### Coil combination

Both reconstruction paths form the same three combinations from coil images:

$$
I_{\mathrm{RSS}}=\sqrt{\sum_c|I_c|^2},\qquad
I_{\mathrm{SOM}}=\sum_c|I_c|,\qquad
I_{\mathrm{coherent}}=\sum_c I_c.
$$

No noise whitening, optimal sensitivity weighting or receiver phase alignment is
applied. Coherent sums can cancel. Unequal channel gains can affect plain-RSS
comparisons; a common gain must also scale its matching noise.

## SNR estimate

**Used by the reconstruction viewer's SNR map.** Reconstruct clean signal and
two copies with independent added noise, using the same settings and noise scale.
The implemented estimator uses RSS images:

$$
\hat\sigma=\frac{\operatorname{std}_{\mathrm{all\ pixels}}
 (I_{\mathrm{RSS},1}-I_{\mathrm{RSS},2})}{\sqrt2},\qquad
\mathrm{SNR}(\mathbf r)=\frac{I_{\mathrm{RSS,clean}}(\mathbf r)}{\max(\hat\sigma,\epsilon)}.
$$

`std` is the sample standard deviation over non-NaN differences (denominator
`P−1` for `P>1` samples); `ε` is MATLAB double-precision `eps`. The GUI rejects
`σ̂ ≤ 10 ε`.
The numerator is noise-free RSS; one whole-image denominator is shared by every
pixel. Spatially varying noise, background, channel correlations, low-signal
magnitude bias and reconstruction-induced spatial correlations limit its
interpretation as local SNR. It is not an absolute low-signal calibration or
the covariance-weighted SNR reconstruction described by
[Kellman and McVeigh, corrected 2007](https://doi.org/10.1002/mrm.21261).
Use two independent noise realizations, not the same file twice.
Implementation: [reconstructionViewer.m](../matlab/Bin/reconstruction/reconstructionViewer.m),
`computeSNRMap`.

## Scope and supporting evidence

The equations above describe current behavior. They do not establish absolute
scanner calibration or validate arbitrary anatomy, EM exports, RF settings or
coil rankings. Spatial B0 maps/B0Solver, gradient-error maps and SAR
remain incomplete or known-defect paths; the [SAR task](../TODO.md) explains
the experimental route. Final post-refactor release-wide scientific revalidation
remains separate from the controlled checks already recorded.

The foundation is **Cao et al., Magnetic Resonance in Medicine 72:237–247 (2014)**,
[original paper](ref/Zhipeng_2014_Bloch-simulator.pdf); equations 11–12 remain the
noise-method baseline. The bundled tests cover a small set of essential
contracts; they do not establish release-wide scientific validation.
