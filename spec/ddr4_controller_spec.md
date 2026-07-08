# DDR4 Controller Specification Notes

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

## Clocking

- Target controller operating frequency: 500 MHz.
- Timing closure must be considered from the beginning because 500 MHz is aggressive for a DDR4 controller core.

## RTL Coding Policy

- SystemVerilog RTL must be synthesizable.
- Packages are compiled once and imported where needed.
- Do not `include` the same package in multiple modules.
- Keep protocol definitions, parameters, enums, and structs in `rtl/pkg/ddr4_ctrl_pkg.sv`.

## Planned Blocks

```text
AXI slave frontend
  -> command decoder
  -> transaction splitter / burst handler
  -> DDR4 scheduler
  -> bank machine / timing checker
  -> command generator
  -> write-data buffer
  -> read-data return path
  -> APB register block
  -> DDR4 simulation model for VCS
```

## Open Items

- Exact DDR4 device organization from datasheet
- Timing parameter extraction: tRCD, tRP, tRAS, tRC, tWR, tWTR, tCCD, tRRD, tFAW, tRFC, refresh interval
- PHY boundary definition
- DQS training/write leveling abstraction level
- VREF/ODT/IO primitive modeling strategy
