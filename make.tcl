set CWD [pwd]
set ::project(builddir) $::CWD
set ::project(srcdir) [file dirname [file normalize [info script]]]
set ::project(sandbox)  [file dirname $::project(srcdir)]

if {[file exists [file join $CWD .. tclconfig practcl.tcl]]} {
  source [file join $CWD .. tclconfig practcl.tcl]
} else {
  source [file join $SRCPATH tclconfig practcl.tcl]
}


array set ::project [::practcl::config.tcl $CWD]
::practcl::library create LIBRARY [array get ::project]
LIBRARY add [file join $::project(srcdir) generic sample.c]
LIBRARY add [file join $::project(srcdir) generic sample.tcl]

###
# Create build targets
###
::practcl::target autoconf {}

switch [lindex $argv 0] {
  default {
    ::practcl::trigger {*}$argv
  }
}

if {$make(autoconf)} {
  LIBRARY implement $::project(builddir)
  set fout [open pkgIndex.tcl w]
  puts $fout "
  #
  # Tcl package index file
  #
  "
  puts $fout [LIBRARY package-ifneeded]
  close $fout
}
