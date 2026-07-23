# DDR4 Controller Specification Notes

## Datasheet Source

- Authoritative project datasheet: `docs/datasheet/MT40A512M8SA-075_F.pdf`
- Target device: Micron `MT40A512M8SA-075:F`, 4Gb DDR4 SDRAM, 512 Meg x 8
- All future timing, initialization, mode-register, command, and simulation-model updates must be checked against this file.

## Interface Requirements

### AXI4 Slave Interface

- Data width: 32 bits
- Address width: 32 bits
- Supported transactions:
  - single transfer
  - incrementing burst
  - wrapping burst
- Used for DDR4 memory read/write access.

### APB Slave Interface

- Data width: 32 bits
- Address width: 32 bits
- Used for controller configuration and DDR4 mode-register related controls.

## DDR4 Device Geometry Used By Current Model

| Item | x8 | x16 |
| --- | --- | --- |
| Density | 4Gb | 4Gb |
| Organization | 512 Meg x 8 | 256 Meg x 16 |
| Bank groups | 4, BG[1:0] | 2, BG0 |
| Banks per group | 4, BA[1:0] | 4, BA[1:0] |
| Row address | 32K, A[14:0] | 32K, A[14:0] |
| Column address | 1K, A[9:0] | 1K, A[9:0] |
| Page size | 1KB | 2KB |

The default simulation build currently uses x16 mode because it maps naturally to a 16-bit DDR4 DQ model and two DQS/DM bytes.

## Command/Address Model

The DDR4 model decodes the command bus using:

- CS_n
- ACT_n
- RAS_n/A16
- CAS_n/A15
- WE_n/A14
- A10/AP
- A12/BC_n reserved for later burst-chop support
- BG/BA for bank group/bank and MRS selection

Implemented first-stage command checks:

- DES / NOP
- ACT
- READ / READ with auto-precharge
- WRITE / WRITE with auto-precharge
- PRE / PREA
- REF
- MRS
- ZQCL / ZQCS

## Initialization Sequence Skeleton

The controller now has an APB-triggered initialization sequence based on the datasheet order:

```text
RESET_n deassert
CKE high
MRS MR3
MRS MR6
MRS MR5
MRS MR4
MRS MR2
MRS MR1
MRS MR0
ZQCL
READY
```

The current implementation uses simulation-oriented wait counters for tMRD/tMOD/ZQCL and must still be refined for exact speed-bin timing.

## Clocking

- Target controller operating frequency: 500 MHz.
- Testbench clock period: 2 ns.
- The datasheet supports speed grades including DDR4-2400, DDR4-2666, and DDR4-3200; exact CL/CWL/timing selection remains a configuration item.

## RTL Coding Policy

- SystemVerilog RTL must be synthesizable.
- Packages are compiled once and imported where needed.
- Do not `include` the same package in multiple modules.
- Keep protocol definitions, parameters, enums, and structs in `rtl/pkg/ddr4_ctrl_pkg.sv`.

## Planned Blocks

```text
AXI slave frontend
  -> transaction splitter / burst handler
  -> address mapper
  -> DDR4 scheduler
  -> bank machine / timing checker
  -> command generator
  -> write-data buffer
  -> read-data return path
  -> APB register block
  -> DDR4 simulation model for VCS
```

## Current Model Limitations

- Data storage array is not yet implemented.
- DQ/DQS timing and bidirectional data burst are not yet implemented.
- CRC, DBI, DM behavior, CA parity, ODT electrical behavior, write leveling, VREF training, and MPR are not yet implemented.
- tCCD_S/tCCD_L, tRRD_S/tRRD_L, tFAW, tWTR, tWR, tRFC, and refresh scheduling still need to be added.
- Controller AXI frontend is still held off after initialization; real transaction scheduling is the next RTL step.
