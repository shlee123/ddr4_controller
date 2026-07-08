# DDR4 Controller

This repository tracks the DDR4 controller project generated and iteratively refined with ChatGPT.

## Project Target

- DDR4 SDRAM controller RTL
- AXI4 slave interface for memory read/write access
- APB slave interface for mode/register configuration
- Synthesizable SystemVerilog RTL
- VCS simulation environment
- DDR4 SDRAM behavioral simulation model based on the provided 4Gb DDR4 SDRAM datasheet

## Current User Requirements

| Item | Requirement |
| --- | --- |
| Project name | DDR4 controller |
| AXI data width | 32 bits |
| AXI address width | 32 bits |
| APB data width | 32 bits |
| APB address width | 32 bits |
| AXI transaction support | single, burst, wrap |
| Mode register access | via APB interface |
| Target operating frequency | 500 MHz |
| RTL style | synthesizable SystemVerilog |
| Simulation | VCS-compatible environment |
| Package/include policy | avoid duplicate package definitions caused by repeated `include` across `.sv` files |

## Repository Layout

```text
rtl/                  Synthesizable RTL
  pkg/                SystemVerilog packages; compile once, do not include repeatedly
  axi/                AXI interface logic
  apb/                APB register/control logic
  core/               DDR4 controller core FSM/scheduler/datapath
sim/                  Simulation environment
  tb/                 Testbench
  model/              DDR4 SDRAM behavioral model
  filelist/           VCS filelists
  scripts/            Simulation scripts
spec/                 Project specifications and design notes
```

## Compile Policy for SystemVerilog Packages

To avoid VCS duplicate-definition errors:

1. Put package definitions only under `rtl/pkg/`.
2. Compile packages exactly once in the filelist before modules that import them.
3. Use `import ddr4_ctrl_pkg::*;` instead of including the package source in multiple `.sv` files.
4. Do not write `` `include "ddr4_ctrl_pkg.sv" `` inside normal RTL modules.

## Current Status

This is the synchronized initial project scaffold. RTL and DDR4 model implementation will be added incrementally.
