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

Planned work:

- Instantiate the production `ddr4_controller_top` with the behavioral DDR4 model.
- Verify APB initialization and AXI read/write paths across asynchronous clock domains.
- Add scoreboarding, timeout checks, and CI artifacts.
- Replace the compatibility smoke test as the primary functional gate after equivalent production coverage is achieved.
