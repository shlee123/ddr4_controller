#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SIM_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${SIM_DIR}/build"

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

vcs -full64 -sverilog -timescale=1ns/1ps \
  -debug_access+all \
  -f "${SIM_DIR}/filelist/rtl.f" \
  -f "${SIM_DIR}/filelist/tb.f" \
  -top tb_ddr4_controller \
  -l compile.log

./simv -l sim.log
