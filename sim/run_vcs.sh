#!/usr/bin/env bash
set -e
mkdir -p log
VCS_OPTS="-full64 -sverilog -timescale=1ns/1ps -debug_access+all +v2k +lint=TFIPC-L"
# For Verdi/Novas FSDB. If your site uses a different path, set NOVAS_HOME before running.
if [[ -n "${NOVAS_HOME:-}" ]]; then
  VCS_OPTS="$VCS_OPTS -P ${NOVAS_HOME}/share/PLI/VCS/LINUX64/novas.tab ${NOVAS_HOME}/share/PLI/VCS/LINUX64/pli.a"
else
  echo "[WARN] NOVAS_HOME not set. FSDB system tasks may require your site VCS/Verdi setup."
fi
vcs $VCS_OPTS -f filelist.f -top ddr4_ctrl_tb -l log/compile.log -o simv
./simv +fsdb+autoflush -l log/sim.log
