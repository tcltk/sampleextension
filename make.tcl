set CWD [pwd]
set ::project(builddir) $::CWD
set ::SRCDIR   [file dirname [file normalize [info script]]]
set ::SANDBOX  [file dirname $::SRCDIR]

if {[file exists [file join $::SANDBOX tclconfig practcl.tcl]]} {
  source [file join $::SANDBOX tclconfig practcl.tcl]
} else {
  source [file join $SRCDIR tclconfig practcl.tcl]
}

array set ::project [::practcl::config.tcl $CWD]
::practcl::library create LIBRARY [array get ::project]
LIBRARY define set builddir $CWD
LIBRARY define set srcdir $SRCDIR
LIBRARY add [file join $::SRCDIR generic sample.c]
LIBRARY add [file join $::SRCDIR generic sample.tcl]
LIBRARY define add public-verbatim [file join $::SRCDIR generic sample.h]

if {![LIBRARY define exists TCL_SRC_DIR]} {
  # Did not detect the Tcl source directory. Run autoconf
  ::practcl::doexec sh [file join $::SRCDIR configure]
  array set ::project [::practcl::config.tcl $CWD]
  LIBRARY define set [array get ::project]
}
###
# Create build targets
###
LIBRARY target add implement {
  filename sample.c
} {
  LIBRARY go
  LIBRARY implement $::project(builddir)
  set fout [open pkgIndex.tcl w]
  puts $fout "
  #
  # Tcl package index file
  #
  "
  puts $fout [LIBRARY package-ifneeded]
  close $fout
  if {![file exists make.tcl]} {
    set fout [open make.tcl w]
    puts $fout "# Redirect to the make file that lives in the project's source dir"
    puts $fout [list source [file join $::SRCDIR make.tcl]]
    close $fout
    if {$::tcl_platform(platform)!="windows"} {
      file attributes -permission a+x make.tcl
    }
  }
}

LIBRARY target add all {
  aliases {binaries libraries}
  depends library
}

LIBRARY target add library {
  aliases {all libraries}
  triggers implement
  filename [LIBRARY define get libfile]
} {
  puts "BUILDING [my define get libfile]"
  my build-library [my define get libfile] [self]
}

LIBRARY target add install-info {
} {
  ###
  # Build local variables needed for install
  ###
  
  set dat [my define dump]
  set PKG_DIR [dict get $dat name][dict get $dat version]
  
  dict with dat {}
  if {$DESTDIR ne {}} {
    foreach path {
      includedir
      mandir
      datadir
      libdir
    } {
      set $path [file join [string trimright $DESTDIR /] [string trimleft [set $path] /]]
    }
  }
  
  set pkgdatadir [file join $datadir $PKG_DIR]
  set pkglibdir [file join $libdir $PKG_DIR]
  set pkgincludedir [file join $includedir $PKG_DIR]
}

LIBRARY target add install {
  depends {library doc}
  triggers {install-info install-package}
} {
  #========================================================================
  # This rule installs platform-independent files, such as header files.
  #========================================================================
  puts "Installing header files in ${includedir}"
  set result {}
  foreach hfile [my install-headers] {
    ::practcl::installDir [file join $srcdir $hfile] ${includedir}
  }
  #========================================================================
  # Install documentation.  Unix manpages should go in the $(mandir)
  # directory.
  #========================================================================
  puts "Installing documentation in ${mandir}"
  foreach file [glob -nocomplain [file join $srcdir doc *.n]] {
    ::practcl::installDir $file [file join ${mandir} mann]
  }
}

LIBRARY target add install-package {
  depends {library doc}
  triggers {install-info}
} {
  #========================================================================
  # Install binary object libraries.  On Windows this includes both .dll and
  # .lib files.  Because the .lib files are not explicitly listed anywhere,
  # we need to deduce their existence from the .dll file of the same name.
  # Library files go into the lib directory.
  # In addition, this will generate the pkgIndex.tcl
  # file in the install location (assuming it can find a usable tclsh shell)
  #
  # You should not have to modify this target.
  #========================================================================
  puts "Installing Library to ${pkglibdir}"
  ::practcl::installDir [my define get libfile] $pkglibdir
  foreach file [glob -nocomplain *.lib] {
    ::practcl::installDir $file $pkglibdir
  }
  ::practcl::installDir pkgIndex.tcl $pkglibdir
  if {[my define get output_tcl] ne {}} {
    ::practcl::installDir [my define get output_tcl] $pkglibdir
  }
}


if {[info exists ::env(DESTDIR)]} {
  LIBRARY define set DESTDIR $::env(DESTDIR)
}
switch [lindex $argv 0] {
  install {
    LIBRARY target trigger install
    LIBRARY define set DESTDIR [file normalize [string trimright [lindex $argv 1]]]
  }
  install-package {
    LIBRARY target trigger install
    LIBRARY define set DESTDIR [file normalize [string trimright [lindex $argv 1]]]
  }
  default {
    LIBRARY target trigger {*}$argv
  }
}
LIBRARY target do