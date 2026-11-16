# Quick start: your first simulated image

This walkthrough runs the supplied proton gradient-echo (GRE) example and
reconstructs its image. All required inputs are included in `protocols/example/`.
First complete the [installation](../README.md#installation).

## 1. Open XudoMRI

In MATLAB, run:

```matlab
addpath('C:\path\to\XudoMRI_Simulator\matlab');
Setup;
```

Use the location of your cloned `XudoMRI_Simulator` repository in `addpath`;
start from that folder to avoid
relative-input filename collisions.

## 2. Load and run the example

In `Setup`:

1. Click **Load** and open `protocols/example/example.prot`.
2. Check that all three geometry panes populate and that the nucleus and
   sequence are **1H** and **GRE**. Leave the saved settings unchanged.
3. Click **Plot Seq.** to inspect the supplied waveform, then close the preview.
4. Select **Signal**, leave **GPU** unchecked for CPU execution, and click **Run**.
5. Wait for **completed** in the **Simulation jobs** window. Use **View output**
   for engine messages or **Open run folder** to find the results.

The example already includes an exported sequence. After changing imaging
settings, use **Gen. Seq.** before running again.

Each run creates `protocols/example/run_YYYYMMDD_HHMMSS_signal/`, containing
`example1.ksig`, `example.ktrj`, and matching protocol and sequence copies.
Keep these files together. GUI jobs handle the engine's console prompt
automatically.

## 3. Reconstruct the image

In MATLAB, run:

```matlab
reco
```

Click **Load Signal (.ksig)** and open `example1.ksig` from the completed run
folder. Reconstruction starts when the file loads. Keep **RSS Mag.** selected.

Expect three separated blocks with different brightness; edge ringing is
normal at this small matrix size. This example exercises the workflow, rather
than establishing quantitative image accuracy.

For problems, see [troubleshooting](USER_MANUAL.md#troubleshooting).
