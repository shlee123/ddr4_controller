# Check Tcl parser completeness without requiring Vivado commands/licenses.
if {$argc == 0} { error "usage: tclsh scripts/check_tcl.tcl <file>..." }
foreach path $argv {
  set fh [open $path r]
  set data [read $fh]
  close $fh
  if {![info complete $data]} { error "incomplete Tcl syntax: $path" }
  puts "PASS Tcl syntax: $path"
}
