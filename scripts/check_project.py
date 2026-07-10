#!/usr/bin/env python3
"""License-free structural checks for the Vivado/MPS3 integration tree."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")

for rel in ("sim/filelist/rtl.f", "sim/filelist.f"):
    fl = ROOT / rel
    for raw in fl.read_text().splitlines():
        item = raw.strip()
        if not item or item.startswith("+") or item.startswith("#"):
            continue
        require((fl.parent / item).resolve().is_file(), f"missing {item} from {rel}")

build = (ROOT / "synth/vivado/mps3_build.tcl").read_text()
for token in ("BUILD_MODE", "native", "mig", "FPGA NATIVE_DDR4",
              "FPGA MIG_DDR4", "synth_design", "place_design",
              "route_design", "write_bitstream", "BOARD_XDC"):
    require(token in build, f"Vivado flow missing {token}")

clock_rtl = (ROOT / "rtl/platform/ddr4_clock_manager.sv").read_text()
require("ddr4_mps3_clk_wiz" in clock_rtl, "Clock Wizard wrapper missing")
require("locked_i" in clock_rtl and "reset_sync" in clock_rtl,
        "locked/reset synchronization missing")

native = (ROOT / "rtl/platform/ddr4_mps3_native_top.sv").read_text()
mig = (ROOT / "rtl/platform/ddr4_mps3_mig_platform.sv").read_text()
require("ddr4_controller_top" in native, "native top does not instantiate controller")
require(not re.search(r"\bddr_(?:dq|dqs|ck|a|ba|bg)\b", mig),
        "MIG platform shell must not own DDR pins")

pins = (ROOT / "constraints/mps3_pins_template.xdc").read_text().splitlines()
active_pin_lines = [x for x in pins if "PACKAGE_PIN" in x and not x.lstrip().startswith("#")]
require(not active_pin_lines, "pin template contains guessed active PACKAGE_PIN constraints")

rtl = (ROOT / "sim/filelist/rtl.f").read_text()
require(rtl.index("ddr4_ctrl_pkg.sv") < rtl.index("ddr4_controller_top.sv"),
        "package must precede dependent RTL")
require("ddr4_mps3_native_top.sv" in rtl and "ddr4_mps3_mig_platform.sv" in rtl,
        "platform wrappers missing from RTL filelist")

print("PASS: filelists, build modes, clock/reset, mode ownership, XDC placeholders")
sys.exit(0)
