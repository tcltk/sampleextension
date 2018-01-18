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
LIBRARY define set author {{Tcl Core}}
LIBRARY define set license BSD
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

switch [lindex $argv 0] {
  install {
    if {[info exists ::env(DESTDIR)]} {
      set DESTDIR $::env(DESTDIR)
    }
    LIBRARY target depends library doc
    LIBRARY target do
    if {[llength $argv]>1} {
      set DESTDIR [file normalize [string trimright [lindex $argv 1]]]
    }
    set dat [LIBRARY target pkginfo]
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
    #========================================================================
    # This rule installs platform-independent files, such as header files.
    #========================================================================
    puts "Installing header files in ${includedir}"
    foreach hfile [LIBRARY install-headers] {
      ::practcl::copyDir [file join $srcdir $hfile] ${includedir}
    }
    #========================================================================
    # Install documentation.  Unix manpages should go in the $(mandir)
    # directory.
    #========================================================================
    puts "Installing documentation in ${mandir}"
    foreach file [glob -nocomplain [file join $srcdir doc *.n]] {
      ::practcl::copyDir $file [file join ${mandir} mann]
    }
    #========================================================================
    # Install binary object libraries.  On Windows this includes both .dll and
    # .lib files.  Because the .lib files are not explicitly listed anywhere,
    # we need to deduce their existence from the .dll file of the same name.
    # Library files go into the lib directory.
    # In addition, this will generate the pkgIndex.tcl
    # file in the install location (assuming it can find a usable tclsh shell)
    #========================================================================
    puts "Installing Package to ${pkglibdir}"
    ::practcl::copyDir [LIBRARY define get libfile] $pkglibdir
    foreach file [glob -nocomplain *.lib] {
      ::practcl::copyDir $file $pkglibdir
    }
    ::practcl::copyDir pkgIndex.tcl $pkglibdir
    if {[LIBRARY define get output_tcl] ne {}} {
      ::practcl::copyDir [LIBRARY define get output_tcl] $pkglibdir
    }
  }
  install-package {
    if {[llength $argv]<1} {
      error "Usage: install DESTINATION"
    }
    LIBRARY target depends library doc
    LIBRARY target do
    set dat [LIBRARY target pkginfo]
    dict with dat {}
    set pkglibdir [file join [lindex $argv 1] $PKG_DIR]
    #========================================================================
    # Install binary object libraries.  On Windows this includes both .dll and
    # .lib files.  Because the .lib files are not explicitly listed anywhere,
    # we need to deduce their existence from the .dll file of the same name.
    # Library files go into the lib directory.
    # In addition, this will generate the pkgIndex.tcl
    # file in the install location (assuming it can find a usable tclsh shell)
    #========================================================================
    puts "Installing Package to ${pkglibdir}"
    ::practcl::copyDir [LIBRARY define get libfile] $pkglibdir
    foreach file [glob -nocomplain *.lib] {
      ::practcl::copyDir $file $pkglibdir
    }
    ::practcl::copyDir pkgIndex.tcl $pkglibdir
    if {[LIBRARY define get output_tcl] ne {}} {
      ::practcl::copyDir [LIBRARY define get output_tcl] $pkglibdir
    }
  }
  info {
    set dat [LIBRARY target pkginfo]
    foreach {field value} $dat {
      puts [list $field: $value]
    }
    exit 0
  }
  teapot {
    LIBRARY target depends library doc
    LIBRARY target do
    set dat [LIBRARY target pkginfo]
    dict with dat {}
    set teapotvfs [file join $CWD teapot.vfs]
    if {[file exists $teapotvfs]} {
      file delete -force $teapotvfs
    }
    file mkdir $teapotvfs
    file copy -force [LIBRARY define get libfile] $teapotvfs
    foreach file [glob -nocomplain *.lib] {
      file copy -force $file $teapotvfs
    }
    file copy -force pkgIndex.tcl $teapotvfs
    if {[LIBRARY define get output_tcl] ne {}} {
      file copy -force [LIBRARY define get output_tcl] $teapotvfs
    }
    ###
    # Generate the teapot meta file
    ###
    set fout [open [file join $teapotvfs teapot.txt] w]
    puts $fout [list Package $name $version]
    puts $fout [list Meta platform [LIBRARY define get TEACUP_PROFILE]]
    foreach field {
      description license platform subject summary
    } {
      if {[dict exists $dat $field]} {
        puts $fout [list Meta $field [dict get $dat $field]]
      }
    }
    foreach field {
      author category require
    } {
      if {[dict exists $dat $field]} {
        foreach entry [dict get $dat $field] {
          puts $fout [list Meta $field $entry]
        }
      }
    }
    close $fout
    ::practcl::tcllib_require zipfile::mkzip
    ::zipfile::mkzip::mkzip ${name}-${version}-[LIBRARY define get TEACUP_PROFILE].zip -directory $teapotvfs
  }
  default {
    LIBRARY target trigger {*}$argv
    LIBRARY target do
  }
}
