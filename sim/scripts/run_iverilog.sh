#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SIM_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${SIM_DIR}/build_iverilog"

if ! command -v iverilog >/dev/null 2>&1; then
  echo "ERROR: iverilog is not installed or not in PATH." >&2
  echo "Ubuntu/Debian: sudo apt-get install iverilog" >&2
  exit 127
fi

if ! command -v vvp >/dev/null 2>&1; then
  echo "ERROR: vvp is not installed or not in PATH." >&2
  exit 127
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

set -o pipefail
iverilog -g2012 \
  -Wall \
  -Wimplicit \
  -s tb_ddr4_controller \
  -o simv \
  -f "${SIM_DIR}/filelist/rtl.f" \
  -f "${SIM_DIR}/filelist/tb.f" \
  2>&1 | tee compile.log

vvp ./simv 2>&1 | tee sim.log

if ! grep -q "DDR4 controller AXI burst-read regression completed successfully" sim.log; then
  echo "ERROR: expected regression PASS banner was not found." >&2
  exit 1
fi

echo "PASS: Icarus Verilog compile and AXI burst-read regression completed."
