#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SIM_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${SIM_DIR}/build"
FPGA_SIM="${FPGA_SIM:-0}"
VCS_EXTRA_OPTS=()

if [[ "${FPGA_SIM}" == "1" ]]; then
  if [[ -z "${VCS_XILINX_LIB_OPTS:-}" ]]; then
    echo "ERROR: FPGA_SIM=1 requires VCS_XILINX_LIB_OPTS for libraries produced by Vivado compile_simlib" >&2
    exit 2
  fi
  # shellcheck disable=SC2206
  VCS_EXTRA_OPTS=(+define+FPGA ${VCS_XILINX_LIB_OPTS})
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

vcs -full64 -sverilog -timescale=1ns/1ps \
  -debug_access+all \
  "${VCS_EXTRA_OPTS[@]}" \
  -f "${SIM_DIR}/filelist/rtl.f" \
  -f "${SIM_DIR}/filelist/tb.f" \
  -top tb_ddr4_controller \
  -l compile.log

./simv -l sim.log
