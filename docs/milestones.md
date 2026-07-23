# DDR4 Controller Milestones

## M1 — Icarus smoke regression

Status: **PASS**

- Icarus compile succeeds without package time-unit warnings.
- AXI INCR, FIXED and WRAP four-beat read regressions pass.
- CI publishes simulation logs as workflow artifacts and a report issue.

## M2 — Production RTL compile

Status: **PASS**

Acceptance criteria completed:

- `sim/filelist/rtl_production.f` elaborates `ddr4_controller_top` with Icarus Verilog.
- No compatibility replacement top is used by the production compile job.
- Production compile is a mandatory CI gate.
- Inherited-timescale warnings were removed from the package, scheduler, data cache, and controller top.
- Icarus-incompatible function-result bit selections and named packed-struct assignment patterns were replaced with portable RTL.

Reference CI run: `29544225711`.

## M3 — Production RTL functional regression

Status: **IN PROGRESS**

Current CI validation:

- Production testbench directly instantiates `ddr4_controller_top` and the behavioral DDR4 model.
- Asynchronous AXI/APB and DDR clocks, reset, initialization timeout, APB status, MRS and ZQCL checks are enabled.
- CI was explicitly retriggered on 2026-07-19 to validate the production functional workflow.

Planned work:

- Verify APB initialization and AXI read/write paths across asynchronous clock domains.
- Add single-write, single-read and read-after-write scoreboarding.
- Expand to AXI burst and randomized regression.
- Replace the compatibility smoke test as the primary functional gate after equivalent production coverage is achieved.

## M34 — DDR4 PHY wrapper and training

Status: **PASS**

- A dedicated controller/PHY boundary owns all DQ, DQS and DM tri-state behavior.
- Write-level and read-level sweeps calculate an independent eye center for each x16 byte lane.
- Normal scheduler traffic is held until controller initialization and PHY training both complete.
- APB status reports PHY done, busy and fail state.
- The production file list and an M34 CI regression cover training and pin isolation.
