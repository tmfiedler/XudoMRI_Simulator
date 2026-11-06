# TODO

- [ ] Integrate validated SAR calculation into the experiment workflow.

The historical C++ source in `engine/sar/` and MATLAB interface in
`matlab/sar.m` / `matlab/Bin/sar.fig` are incomplete and unvalidated. The source
originates from the original project tree and retains its copyright notices.
B1+ scaling remains unresolved; a successful build does not establish physical
correctness.

`engine/sar/build_windows.cmd` creates a review executable in
`engine/sar/build-msvc/bin/`, outside normal `engine/bin/` deployment. Setup
exposes it only through the warned **Experimental SAR** route. This is for
controlled inspection, not routine SAR simulation or safety claims.

Completing this task requires reviewed equations, units and B1+/RF scaling;
documented inputs and outputs; comparison with trusted reference cases; and
tested integration with Setup and protocol/run handling. Preserve the distinction
between SAR computed here and independently obtained external SAR results.
