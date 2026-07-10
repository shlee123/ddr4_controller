# DDR4 Controller V2.1 Simulation Environment

This package contains a synthesizable DDR4 controller reference RTL plus a VCS simulation environment.

## Linux MPS3/Vivado project

The batch flow creates a project, generates the Clock Wizard IP, reads all
RTL/XDC, runs synthesis and implementation, and writes timing, utilization,
CDC, route and DRC reports under `build/vivado/<mode>/`. It never guesses an
FPGA part or package pin.

Required environment:

- Vivado available through `$XILINX_VIVADO/settings64.sh`.
- `XILINX_PART` set to the exact device part used by the MPS3 integration.
- A reviewed board XDC derived from the board schematic/official board files.

Native/custom-controller build:

```bash
source "$XILINX_VIVADO/settings64.sh"
export XILINX_PART=<exact-vivado-device-part>
BUILD_MODE=native vivado -mode batch -source synth/vivado/mps3_build.tcl
```

`ddr4_mps3_native_top` instantiates a generated Clock Wizard with 200 MHz
AXI/APB and 500 MHz controller outputs. Reset deassertion is synchronized only
after `locked`. The forwarded DDR CK/CK# uses Xilinx `ODDR` plus `OBUFDS`.
The input clock configuration currently assumes 100 MHz; update both the
Clock Wizard Tcl configuration and `constraints/mps3_timing.xdc` if the board
clock differs.

To generate a bitstream, copy `constraints/mps3_pins_template.xdc`, fill every
required pin, bank, I/O standard and electrical property from authoritative
board data, review it, then run:

```bash
BOARD_XDC=/absolute/path/mps3_board.xdc WRITE_BITSTREAM=1 BUILD_MODE=native \
  vivado -mode batch -source synth/vivado/mps3_build.tcl
```

Without `WRITE_BITSTREAM=1`, implementation and reports still run, but the
bitstream step is intentionally skipped to avoid hiding unconstrained I/O.

### Native and MIG build modes

The modes are mutually exclusive:

- `BUILD_MODE=native` connects this repository's controller and PHY boundary
  directly to DDR pins and defines `FPGA NATIVE_DDR4`.
- `BUILD_MODE=mig` defines `FPGA MIG_DDR4`, imports a board-configured MIG XCI,
  and synthesizes an integration top supplied by the platform. MIG exclusively
  owns DDR pins, calibration and PHY timing; do not instantiate the native top.

MIG mode requires a MIG generated for the exact FPGA, memory component and
pinout. A newline-separated file list may add the surrounding integration RTL:

```bash
BUILD_MODE=mig MIG_XCI=/absolute/path/ddr4_mig.xci \
MIG_TOP=<platform_mig_top> MIG_RTL_FILELIST=/absolute/path/mig_rtl.f \
BOARD_XDC=/absolute/path/mps3_board.xdc \
vivado -mode batch -source synth/vivado/mps3_build.tcl
```

`rtl/platform/ddr4_mps3_mig_platform.sv` is an ownership contract and reset
shell; it intentionally exposes no physical DDR pins. The generated MIG's
`ui_clk` and `ui_clk_sync_rst` must clock/reset application-side AXI logic.

## Simulation

Portable simulation does not define `FPGA`, so no Xilinx primitive or library
is required:

```bash
cd sim
./scripts/run_vcs.sh
```

For FPGA primitive simulation, first compile the Vivado libraries for VCS
using `compile_simlib`, then pass your site's library switches explicitly:

```bash
export FPGA_SIM=1
export VCS_XILINX_LIB_OPTS='-L unisims_ver -L secureip'
cd sim && ./scripts/run_vcs.sh
```

Vivado/VCS stages are manual or self-hosted because licenses are site-local.
GitHub Actions runs license-free shell, Tcl parser, filelist/architecture and
Verilator lint/elaboration checks.

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
`rtl/pkg/ddr4_ctrl_pkg.sv` is compiled exactly once and before dependent RTL.
The RTL-only filelist is `sim/filelist/rtl.f`; testbench/model files remain in
the simulation filelists and are never read by the Vivado flow.

## Run
```bash
cd sim
./run_vcs.sh
```

The testbench generates `ddr4_ctrl_v2_1.fsdb` when VCS/Verdi FSDB PLI is available.

## Contents
- `rtl/pkg/ddr4_ctrl_pkg.sv` : common parameters/types
- `rtl/sync_fifo.sv` : synchronous FIFO for AXI AW/AR buffering
- `rtl/async_fifo.sv` : gray-coded asynchronous FIFO for request/response CDC
- `rtl/ddr4_controller_top.sv` : AXI/APB-to-DDR4 controller reference RTL
- `rtl/platform/` : native and MIG platform wrappers plus clock/reset manager
- `constraints/` : timing constraints and deliberately unassigned pin template
- `synth/vivado/mps3_build.tcl` : native/MIG synthesis and implementation flow
- `sim/model/ddr4_sdram_model.sv` : simplified Micron 4Gb DDR4 SDRAM behavioral model
- `sim/tb/ddr4_ctrl_tb.sv` : random AXI write/read testbench with 200MHz/500MHz asynchronous clocks
- `sim/filelist.f` : VCS filelist
- `sim/run_vcs.sh` : compile/run script

## Model scope
The SDRAM model implements command decode for ACT/READ/WRITE/PRE/MRS/REF/ZQCL and a bank/row/column array abstraction. It is intended for controller bring-up and random access simulation, not a full JEDEC timing sign-off model.
