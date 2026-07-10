# DDR4 Controller V2.1 Simulation Environment

This package contains a synthesizable DDR4 controller reference RTL plus a VCS simulation environment.

## FPGA/Vivado clock output

The Linux MPS3 FPGA flow uses Vivado by default. Define `FPGA` for FPGA
compilation so that `ddr4_ck_out` instantiates `ddr4_fpga_clockgen`, which
generates the external differential DDR clock with Xilinx `ODDR` and
`OBUFDS` primitives. Builds without `FPGA` retain the portable
simulation/ASIC fallback.

Run batch synthesis from the repository root after selecting the exact Xilinx
device part used by the target image:

```bash
XILINX_PART=<vivado-part> vivado -mode batch -source synth/vivado/mps3_synth.tcl
```

The Tcl entry point supplies `FPGA` automatically. Board pin assignments and
I/O standards remain platform constraints and must be provided by the target
MPS3 integration; this repository does not guess a device part or pinout.

## V2.1 changes
- AXI/APB clock domain is 200MHz (`aclk`).
- DRAM/controller clock domain is 500MHz (`ddr_clk`).
- AXI and DRAM domains are asynchronous.
- Added 8-entry AXI AW FIFO and 8-entry AXI AR FIFO.
- Added asynchronous request FIFOs between AXI and DRAM domains.
  - Read request FIFO and write request FIFO are implemented separately so the scheduler can prioritize reads.
- Added asynchronous response FIFO from DRAM domain back to AXI domain.
- Added DRAM scheduler with read-cycle priority over write-cycle issue.
- Added a 64-line direct-mapped data cache in the DRAM domain.

## Compile strategy
`ddr4_pkg.sv` is compiled exactly once in `sim/filelist.f`. Other files use `import ddr4_pkg::*;` and do not `include` the package, avoiding duplicate package definition errors in VCS.

## Run
```bash
cd sim
./run_vcs.sh
```

The testbench generates `ddr4_ctrl_v2_1.fsdb` when VCS/Verdi FSDB PLI is available.

## Contents
- `rtl/ddr4_pkg.sv` : common parameters/types
- `rtl/sync_fifo.sv` : synchronous FIFO for AXI AW/AR buffering
- `rtl/async_fifo.sv` : gray-coded asynchronous FIFO for request/response CDC
- `rtl/ddr4_ctrl_top.sv` : AXI/APB-to-DDR4 controller reference RTL
- `sim/model/ddr4_sdram_model.sv` : simplified Micron 4Gb DDR4 SDRAM behavioral model
- `sim/tb/ddr4_ctrl_tb.sv` : random AXI write/read testbench with 200MHz/500MHz asynchronous clocks
- `sim/filelist.f` : VCS filelist
- `sim/run_vcs.sh` : compile/run script

## Model scope
The SDRAM model implements command decode for ACT/READ/WRITE/PRE/MRS/REF/ZQCL and a bank/row/column array abstraction. It is intended for controller bring-up and random access simulation, not a full JEDEC timing sign-off model.
