# DDR4 Controller Milestones

## M1 — Icarus smoke regression

Status: **PASS**

- Icarus compile succeeds without package time-unit warnings.
- AXI INCR, FIXED and WRAP four-beat read regressions pass.
- CI publishes simulation logs as workflow artifacts and a report issue.

## M2 — Production RTL compile

Status: **IN PROGRESS**

Acceptance criteria:

- `sim/filelist/rtl_production.f` elaborates `ddr4_controller_top` with Icarus Verilog.
- No compatibility replacement top is used.
- Production compile job is mandatory and no longer uses `continue-on-error`.
- No inherited-timescale warnings remain in production RTL.

Current blockers identified from CI run 29543065135:

- Icarus-incompatible direct bit selection from function results in `rtl/ddr4_scheduler.sv`.
- Icarus-incompatible named packed-struct assignment patterns in `rtl/ddr4_scheduler.sv` and `rtl/ddr4_controller_top.sv`.
- Missing explicit time units in `rtl/ddr4_data_cache.sv`, `rtl/ddr4_scheduler.sv`, and `rtl/ddr4_controller_top.sv`.

## M3 — Production RTL functional regression

Planned after M2:

- Instantiate the production `ddr4_controller_top` with the behavioral DDR4 model.
- Verify APB initialization and AXI read/write paths across asynchronous clock domains.
- Add scoreboarding, timeout checks, and CI artifacts.
