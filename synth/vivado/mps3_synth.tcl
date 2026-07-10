# Backward-compatible synthesis entry point. The complete flow now lives in
# mps3_build.tcl and defaults to BUILD_MODE=native.
source [file join [file dirname [file normalize [info script]]] mps3_build.tcl]
