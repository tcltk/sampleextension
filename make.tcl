set CWD [pwd]
set ::project(builddir) $::CWD
set ::project(srcdir) [file dirname [file normalize [info script]]]
set ::project(sandbox)  [file dirname $::project(srcdir)]

if {[file exists [file join $CWD $::project(sandbox) tclconfig practcl.tcl]]} {
  source [file join $CWD $::project(sandbox) tclconfig practcl.tcl]
} else {
  source [file join $SRCPATH tclconfig practcl.tcl]
}


array set ::project [::practcl::config.tcl $CWD]
::practcl::library create LIBRARY [array get ::project]
LIBRARY add [file join $::project(srcdir) generic sample.c]
LIBRARY add [file join $::project(srcdir) generic sample.tcl]
LIBRARY define add public-verbatim [file join $::project(srcdir) generic sample.h]
###
# Create build targets
###
::practcl::target implement {}
::practcl::target autoconf {
  triggers implement
}
::practcl::target all {
  triggers library
}
::practcl::target binaries {
  triggers library
}
::practcl::target libraries {
  triggers library
}
::practcl::target library {
  triggers implement
}
::practcl::target doc {}

::practcl::target install {
  depends {library doc}
  triggers {install-package}
}
::practcl::target install-package {
  depends {library doc}
}
switch [lindex $argv 0] {
  install {
    ::practcl::trigger install
    set DESTDIR [file normalize [string trimright [lindex $argv 1]]]
  }
  install-package {
    ::practcl::trigger install
    set DESTDIR [file normalize [string trimright [lindex $argv 1]]]
  }
  default {
    ::practcl::trigger {*}$argv
  }
}

if {$make(implement)} {
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
    puts $fout [list source [file join $::project(srcdir) make.tcl]]
    close $fout
    if {$::tcl_platform(platform)!="windows"} {
      file attributes -permission a+x make.tcl
    }
  }
}

if {$make(autoconf)} {
  #set mkout [open sample.mk w]
  #puts $mkout [::practcl::build::Makefile $::project(builddir) LIBRARY]
  #close $mkout
  LIBRARY generate-decls [LIBRARY define get name] $::project(builddir)
  if {![file exists make.tcl]} {
    set fout [open make.tcl w]
    puts $fout [list source [file join $::project(srcdir) make.tcl]]
    close $fout
  }
}

if {$make(library)} {
  puts "BUILDING [LIBRARY define get libfile]"
  ::practcl::build::library [LIBRARY define get libfile] LIBRARY
}

# Generate documentation
if {$make(doc)} {

}

if {![info exists DESTDIR] && [info exists ::env(DESTDIR)]} {
  set DESTDIR $::env(DESTDIR)
} else {
  set DESTDIR {}
}

###
# Build local variables needed for install
###
set dat [LIBRARY define dump]
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

if {$make(install)} {
  #========================================================================
  # This rule installs platform-independent files, such as header files.
  #========================================================================
  puts "Installing header files in ${includedir}"
  set result {}
  foreach hfile [LIBRARY install-headers] {
    ::practcl::installDir [file join $srcdir $hfile] ${includedir}
  }
  
  #========================================================================
  # Install documentation.  Unix manpages should go in the $(mandir)
  # directory.
  #========================================================================
  puts "Installing documentation in ${mandir}"
  foreach file [glob -nocomplain [file join $srcdir doc *.n]] {
    if {$DESTDIR ne {}} {
      ::practcl::installDir $file [file join ${DESTDIR} ${mandir} mann]
    } else {
      ::practcl::installDir $file [file join ${mandir} mann]
    }
  }
}

if {$make(install-package)} {
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
  if {$DESTDIR ne {}} {
    ::practcl::installDir [LIBRARY define get libfile] [file join ${DESTDIR} $pkglibdir]
    foreach file [glob -nocomplain *.lib] {
      ::practcl::installDir $file [file join ${DESTDIR} $pkglibdir]
    }
    if {[LIBRARY define get output_tcl] ne {}} {
      ::practcl::installDir [LIBRARY define get output_tcl] [file join ${DESTDIR} $pkglibdir] 
    }
  } else {
    ::practcl::installDir [LIBRARY define get libfile] $pkglibdir
    foreach file [glob -nocomplain *.lib] {
      ::practcl::installDir $file $pkglibdir
    }
    ::practcl::installDir pkgIndex.tcl $pkglibdir
    if {[LIBRARY define get output_tcl] ne {}} {
      ::practcl::installDir [LIBRARY define get output_tcl] $pkglibdir
    }
  }
}
