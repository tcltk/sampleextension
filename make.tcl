set CWD [pwd]
set ::project(builddir) $::CWD
set ::SRCDIR   [file dirname [file normalize [info script]]]
set ::SANDBOX  [file dirname $::SRCDIR]

source [file join $SRCDIR tools practcl.tcl]

array set ::project [::practcl::config.tcl $CWD]
::practcl::library create LIBRARY [array get ::project]
LIBRARY define set builddir $CWD
LIBRARY define set srcdir $SRCDIR
LIBRARY clay set meta license BSD
LIBRARY clay set meta description {The Reference TEA Extension for Developers}
###
# Generate List of Authors
###
set authors {}
foreach match [::practcl::grep \<.*\@ [file join $SRCDIR ChangeLog]] {
  lappend authors [lrange $match 1 end]
}
LIBRARY clay set meta authors $authors

LIBRARY add [file join $::SRCDIR generic sample.c]
LIBRARY add [file join $::SRCDIR generic sample.tcl]
LIBRARY define add public-verbatim [file join $::SRCDIR generic sample.h]

if {![LIBRARY define exists TCL_SRC_DIR]} {
  # Did not detect the Tcl source directory. Run autoconf
  ::practcl::doexec sh [file join $::SRCDIR configure]
  array set ::project [::practcl::config.tcl $CWD]
  LIBRARY define set [array get ::project]
  # Generate a make.tcl in this directory
  if {![file exists make.tcl]} {
    set fout [open make.tcl w]
    puts $fout "# Redirect to the make file that lives in the project's source dir"
    puts $fout [list source [file join $srcdir make.tcl]]
    close $fout
    if {$::tcl_platform(platform)!="windows"} {
      file attributes -permission a+x make.tcl
    }
  }
}

###
# Create build targets
###

# Virtual target to mimic the behavior of "make all"
LIBRARY make target all {
  aliases {binaries libraries}
  depends library
}


# Generate the dynamic library and pkgIndex.tcl
LIBRARY make target library {
  triggers implement
  files {sample.c sample.h pkgIndex.tcl [LIBRARY define get libfile]}
} {
  # Collect configuration
  my go

  ##
  # Generate dynamic C files
  ##
  set builddir [my define get builddir]
  my implement $builddir

  ###
  # Compile the library
  ###
  puts "BUILDING [my define get libfile]"
  my build-library [file join $builddir [my define get libfile]] [self]

  ##
  # Generate pkgIndex.tcl
  ##
  set fout [open [file join $builddir pkgIndex.tcl] w]
  puts $fout "
#
# Tcl package index file
#
  "
  puts $fout [my package-ifneeded]
  close $fout
}

if {"clean" in $argv} {
  # Clean is a little weird because it screws with dependencies
  # We do it as a separate action
  foreach {name obj} [LIBRARY make objects] {
    set files [$obj output]
    foreach file $files {
      file delete -force [file join $CWD $file]
    }
  }
  foreach pattern {*.lib *.zip *.vfs objs/*} {
    foreach file [glob -nocomplain [file join $CWD $file]] {
      file delete -force $pattern
    }
  }
}

switch [lindex $argv 0] {
  info {
    set dat [LIBRARY make pkginfo]
    foreach {field value} $dat {
      puts [list $field: $value]
    }
    exit 0
  }
  install {
    if {[info exists ::env(DESTDIR)]} {
      set DESTDIR $::env(DESTDIR)
    }
    LIBRARY make depends library doc
    LIBRARY make do
    if {[llength $argv]>1} {
      set DESTDIR [file normalize [string trimright [lindex $argv 1]]]
    }
    set dat [LIBRARY make pkginfo]
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
    LIBRARY make depends library doc
    LIBRARY make do
    set dat [LIBRARY make pkginfo]
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
  teapot {
    LIBRARY make depends library doc
    LIBRARY make do
    set dat [LIBRARY make pkginfo]
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
    puts $fout [list Meta practcl::build_date [clock format [file mtime [LIBRARY define get libfile]]]]
    # Pull SCM checkout info
    ::practcl::distribution select LIBRARY
    set info [LIBRARY scm_info]
    foreach item {scm hash isodate tags} {
      if {![dict exists $info $item]} continue
      set value [dict get $info $item]
      if {$value eq {}} continue
      puts $fout [list Meta practcl::scm_$item $value]
    }

    set mdat [LIBRARY clay get meta]
    foreach {field value} $mdat {
      if {$field in {authors requires}} {
        foreach item $value {
          puts $fout [list Meta $field $item]
        }
      } else {
        puts $fout [list Meta [string trimright $field :] $value]
      }
    }
    close $fout
    ::practcl::tcllib_require zipfile::mkzip
    ::zipfile::mkzip::mkzip [dict get $dat zipfile] -directory $teapotvfs
  }
  default {
    LIBRARY make trigger {*}$argv
    LIBRARY make do
  }
}
