puts "LOCAL.TCL"
# For this project, disable the pager for --help and --ref
# The user can still enable by using --nopager=0 or --disable-nopager
dict set autosetup(optdefault) nopager 1


# This procedure is a customized version of "cc-check-function-in-lib",
# that does not modify the LIBS variable.  Its use prevents prematurely
# pulling in libraries that will be added later anyhow (e.g. "-ldl").
proc check-function-in-lib {function libs {otherlibs {}}} {
    if {[string length $otherlibs]} {
        msg-checking "Checking for $function in $libs with $otherlibs..."
    } else {
        msg-checking "Checking for $function in $libs..."
    }
    set found 0
    cc-with [list -libs $otherlibs] {
        if {[cctest_function $function]} {
            msg-result "none needed"
            define lib_$function ""
            incr found
        } else {
            foreach lib $libs {
                cc-with [list -libs -l$lib] {
                    if {[cctest_function $function]} {
                        msg-result -l$lib
                        define lib_$function -l$lib
                        incr found
                        break
                    }
                }
            }
        }
    }
    if {$found} {
        define [feature-define-name $function]
    } else {
        msg-result "no"
    }
    return $found
}

# Searches for a usable Tcl (prefer 8.6, 8.5, 8.4) in the given paths
# Returns a dictionary of the contents of the tclConfig.sh file, or
# empty if not found
proc parse-tclconfig-sh {args} {
	foreach p $args {
		# Allow pointing directly to the path containing tclConfig.sh
		if {[file exists $p/tclConfig.sh]} {
			return [parse-tclconfig-sh-file $p/tclConfig.sh]
		}
		# Some systems allow for multiple versions
		foreach libpath {lib/tcl8.6 lib/tcl8.5 lib/tcl8.4 lib/tcl tcl lib}  {
			if {[file exists $p/$libpath/tclConfig.sh]} {
				return [parse-tclconfig-sh-file $p/$libpath/tclConfig.sh]
			}
		}
	}
}

proc parse-tclconfig-sh-file {filename} {
  define TCL_BIN_DIR [file normalize [file dirname $filename]]
	return [read_sh_file $filename]
}
proc read_sh_subst {line info} {
  regsub -all {\x28} $line \x7B line
  regsub -all {\x29} $line \x7D line

  #set line [string map $key [string trim $line]]
  foreach {field value} $info {
    catch {set $field $value}
  }
  if [catch {subst $line} result] {
    return {}
  }
  set result [string trim $result]
  return [string trim $result ']
}
proc read_sh_file {filename {localdat {}}} {
  set fin [open $filename r]
  set result {}
  if {$localdat eq {}} {
    set top 1
    set local [array get ::env]
    dict set local EXE {}
  } else {
    set top 0
    set local $localdat
  }
  while {[gets $fin line] >= 0} {
    set line [string trim $line]
    if {[string index $line 0] eq "#"} continue
    if {$line eq {}} continue
    catch {
    if {[string range $line 0 6] eq "export "} {
      set eq [string first "=" $line]
      set field [string trim [string range $line 6 [expr {$eq - 1}]]]
      set value [read_sh_subst [string range $line [expr {$eq+1}] end] $local]
      dict set result $field [read_sh_subst $value $local]
      dict set local $field $value
    } elseif {[string range $line 0 7] eq "include "} {
      set subfile [read_sh_subst [string range $line 7 end] $local]
      foreach {field value} [read_sh_file $subfile $local] {
        dict set result $field $value
      }
    } else {
      set eq [string first "=" $line]
      if {$eq > 0} {
        set field [read_sh_subst [string range $line 0 [expr {$eq - 1}]] $local]
        set value [string trim [string range $line [expr {$eq+1}] end] ']
        #set value [read_sh_subst [string range $line [expr {$eq+1}] end] $local]
        dict set local $field $value
        dict set result $field $value
      }
    }
    } err opts
    if {[dict get $opts -code] != 0} {
      #puts $opts
      puts "Error reading line:\n$line\nerr: $err\n***"
      return $err {*}$opts
    }
  }
  return $result
}


proc is_mingw {} {
    return [string match *mingw* [get-define host]]
}

proc tea-generate {tclpath} {

  puts "BEGIN TEA-GENERATE"
  set windows 0
  # Until we hear otherwise, assume Unix
  define TEA_PLATFORM unix
  define TEA_WINDOWINGSYSTEM x11
  define EXTRA_CFLAGS "-Wall"
  define TEACUP_TOOLSET gcc
  define PRACTCL_TOOLSET gcc
  define OBJEXT o
  define PRACTCL_VC_MANIFEST_EMBED_DLL :
	define PRACTCL_VC_MANIFEST_EMBED_EXE :
	set shared [opt-bool enable-shared]
  define SHARED_BUILD $shared
  define PRACTCL_DEFS {}
  define DEFS {}
  define PACKAGE_LIB_PREFIX {}
  define LIBRARY_PREFIX {}
  #set tclprivatestubs [opt-bool with-tcl-private-stubs]
  set tclprivatestubs 1
  # Note parse-tclconfig-sh is in autosetup/local.tcl
  if {$tclpath eq "1"} {
      set tcldir [file dirname $autosetup(dir)]/compat/tcl-8.6
      if {$tclprivatestubs} {
          set tclconfig(TCL_INCLUDE_SPEC) -I$tcldir/generic
          set tclconfig(TCL_VERSION) {Private Stubs}
          set tclconfig(TCL_PATCH_LEVEL) {}
          set tclconfig(TCL_PREFIX) $tcldir
          set tclconfig(TCL_LD_FLAGS) { }
      } else {
          # Use the system Tcl. Look in some likely places.
          array set tclconfig [parse-tclconfig-sh \
              $tcldir/unix $tcldir/win \
              /usr /usr/local /usr/share /opt/local]
          set msg "on your system"
      }
  } else {
      array set tclconfig [parse-tclconfig-sh $tclpath]
      set msg "at $tclpath"
  }
  if {![opt-bool enable-shared]} {
      set tclconfig(TCL_LD_FLAGS) { }
  }
  if {![info exists tclconfig(TCL_INCLUDE_SPEC)]} {
      user-error "Cannot find Tcl $msg"
  }
  set tclstubs [opt-bool with-tcl-stubs]
  if {$tclprivatestubs} {
      define MIGRATE_ENABLE_TCL_PRIVATE_STUBS
      define USE_TCL_STUBS
  } elseif {$tclstubs && $tclconfig(TCL_SUPPORTS_STUBS)} {
      set libs "$tclconfig(TCL_STUB_LIB_SPEC)"
      define MIGRATE_ENABLE_TCL_STUBS
      define USE_TCL_STUBS
  } else {
      set libs "$tclconfig(TCL_LIB_SPEC) $tclconfig(TCL_LIBS)"
  }
  set cflags $tclconfig(TCL_INCLUDE_SPEC)
  if {!$tclprivatestubs} {
      set foundtcl 0; # Did we find a working Tcl library?
      cc-with [list -cflags $cflags -libs $libs] {
          if {$tclstubs} {
              if {[cc-check-functions Tcl_InitStubs]} {
                  set foundtcl 1
              }
          } else {
              if {[cc-check-functions Tcl_CreateInterp]} {
                  set foundtcl 1
              }
          }
      }
      if {!$foundtcl && [string match *-lieee* $libs]} {
          # On some systems, using "-lieee" from TCL_LIB_SPEC appears
          # to cause issues.
          msg-result "Removing \"-lieee\" and retrying for Tcl..."
          set libs [string map [list -lieee ""] $libs]
          cc-with [list -cflags $cflags -libs $libs] {
              if {$tclstubs} {
                  if {[cc-check-functions Tcl_InitStubs]} {
                      set foundtcl 1
                  }
              } else {
                  if {[cc-check-functions Tcl_CreateInterp]} {
                      set foundtcl 1
                  }
              }
          }
      }
      if {!$foundtcl && ![string match *-lpthread* $libs]} {
          # On some systems, TCL_LIB_SPEC appears to be missing
          # "-lpthread".  Try adding it.
          msg-result "Adding \"-lpthread\" and retrying for Tcl..."
          set libs "$libs -lpthread"
          cc-with [list -cflags $cflags -libs $libs] {
              if {$tclstubs} {
                  if {[cc-check-functions Tcl_InitStubs]} {
                      set foundtcl 1
                  }
              } else {
                  if {[cc-check-functions Tcl_CreateInterp]} {
                      set foundtcl 1
                  }
              }
          }
      }
      if {!$foundtcl} {
          if {$tclstubs} {
              user-error "Cannot find a usable Tcl stubs library $msg"
          } else {
              user-error "Cannot find a usable Tcl library $msg"
          }
      }
  }
  set version $tclconfig(TCL_VERSION)$tclconfig(TCL_PATCH_LEVEL)
  msg-result "Found Tcl $version at $tclconfig(TCL_PREFIX)"
  define-append LIBS " $tclconfig(TCL_BUILD_LIB_SPEC)"
  if {!$tclprivatestubs} {
      define-append LIBS $libs
  }
  define-append EXTRA_CFLAGS $cflags
  if {[info exists zlibpath] && $zlibpath eq "tree"} {
    #
    # NOTE: When using zlib in the source tree, prevent Tcl from
    #       pulling in the system one.
    #
    set tclconfig(TCL_LD_FLAGS) [string map [list -lz ""] \
        $tclconfig(TCL_LD_FLAGS)]
  }
  #
  # NOTE: Remove "-ldl" from the TCL_LD_FLAGS because it will be
  #       be checked for near the bottom of this file.
  #
  set tclconfig(TCL_LD_FLAGS) [string map [list -ldl ""] \
      $tclconfig(TCL_LD_FLAGS)]
  define-append EXTRA_LDFLAGS $tclconfig(TCL_LD_FLAGS)



  if {!$shared} {
    # XXX: This will not work on all systems.
    define-append EXTRA_LDFLAGS -static
    msg-result "Trying to link statically"
  } else {
  }

  foreach {f v} [array get tclconfig] {
    switch $f {
      TCL_LD_FLAGS {
        define LDFLAGS $v
        define LDFLAGS_DEFAULT $v
      }
      TCL_LIBS -
      TCL_BUILD_LIB_SPEC -
      TCL_BUILD_STUB_LIB_SPEC -
      TCL_SHLIB_LD -
      TCL_STLIB_LD -
      TCL_DEFS -
      TCL_VERSION -
      TCL_MAJOR_VERSION -
      TCL_MINOR_VERSION -
      TCL_PATCH_LEVEL -
      TCL_SHARED_BUILD -
      TCL_BIN_DIR -
      TCL_SRC_DIR -
      TCL_ZIP_FILE -
      TCL_STUB_LIB_SPEC -
      TCL_LIB_FILE {
        define $f $v
      }
      default {
        #puts [list [string range $f 4 end] $f $v]
        define [string range $f 4 end] $v
      }
    }
  }
  define CFLAGS_DEFAULT  [get-define CFLAGS]
  define CFLAGS_WARNING  {-Wall}
  define CFLAGS {-pipe  ${CFLAGS_DEFAULT} ${CFLAGS_WARNING}  }
  #define SHLIB_LD "[get-define CC] [get-define SHOBJ_CFLAGS] [get-define CFLAGS] [get-define TCL_LD_FLAGS] "
  define MAKE_STATIC_LIB    "\${STLIB_LD} \[$]@ \$(PKG_OBJECTS)"
  define MAKE_SHARED_LIB    "\${SHLIB_LD} -o \[\$\]@ \$(PKG_OBJECTS) \${SHLIB_LD_LIBS}"
  define MAKE_STUB_LIB      "\${STLIB_LD} \[$]@ \$(PKG_STUB_OBJECTS)"
  define PRACTCL_STATIC_LIB "%STLIB_LD% %OUTFILE% %LIBRARY_OBJECTS%"
  define PRACTCL_SHARED_LIB "%SHLIB_LD% -o %OUTFILE% %LIBRARY_OBJECTS% %SHLIB_LD_LIBS%"
  define PRACTCL_STUB_LIB   "%STLIB_LD% %OUTFILE% %LIBRARY_OBJECTS%"
  define PRACTCL_NAME_LIBRARY "lib%LIBRARY_PREFIX%%LIBRARY_NAME%%LIBRARY_VERSION%"
  define RANLIB_STUB        [get-define RANLIB]
  define SHLIB_LD_LIBS [get-define LIBS]

  set HOST [get-define host]
  define TEA_SYSTEM $HOST
  switch -glob -- [string tolower $HOST] {
    *-*-darwin* {
      define TEA_PLATFORM unix
      define TEA_WINDOWINGSYSTEM aqua
      define TEACUP_OS macosx
      define TEACUP_PROFILE macosx-universal
      set arch [lindex [split $HOST -] 0]
      if {$arch eq "x86_64"} {
        define TEACUP_PROFILE macosx10.5-i386-x86_84
      }
      define TEACUP_ARCH $arch
    }
    *-*-ming* - *-*-cygwin - *-*-msys {
      set windows 1
      define TEACUP_OS windows
      if {[string match "*mingw32*" $HOST]} {
        set arch ix86
        define TEACUP_PROFILE win32-ix86
      }
      if {[string match "*mingw64*" $HOST]} {
        set arch x86_64
        define TEACUP_PROFILE win32-x86_64
      }
      define TEACUP_ARCH $arch
      define TEA_PLATFORM windows
      define TEA_WINDOWINGSYSTEM win32
      if {![is_mingw]} {
        # Assume msvc
        define PRACTCL_TOOLSET msvc
        define PRACTCL_STATIC_LIB  "%STLIB_LD% -out:%OUTFILE% %LIBRARY_OBJECTS%"
        define PRACTCL_SHARED_LIB  "%SHLIB_LD% %SHLIB_LD_LIBS% %LDFLAGS_DEFAULT% -out:%OUTFILE% %LIBRARY_OBJECTS%"
        define MAKE_STATIC_LIB     "\${STLIB_LD} -out:\[$]@ \$(PKG_OBJECTS)"
        define MAKE_SHARED_LIB     "\${SHLIB_LD} \${SHLIB_LD_LIBS} \${LDFLAGS_DEFAULT} -out:\[$]@ \$(PKG_OBJECTS)"
		    define PRACTCL_STUB_LIB    "%STLIB_LD% -nodefaultlib -out:%OUTFILE% %LIBRARY_OBJECTS%"
	      define MAKE_STUB_LIB       "\${STLIB_LD} -nodefaultlib -out:\[$]@ \$(PKG_STUB_OBJECTS)"
        define OBJEXT obj
        if 0 {
        {
    #if defined(_MSC_VER) && _MSC_VER >= 1400
    print("manifest needed")
    #endif
    }
          # Could do a CHECK_PROG for mt, but should always be with MSVC8+
          define PRACTCL_VC_MANIFEST_EMBED_DLL "mt.exe -nologo -manifest %OUTFILE%.manifest -outputresource:%OUTFILE%\;2"
          define PRACTCL_VC_MANIFEST_EMBED_EXE "mt.exe -nologo -manifest %OUTFILE%.manifest -outputresource:%OUTFILE%\;1"
          define VC_MANIFEST_EMBED_DLL "if test -f \[$]@.manifest ; then mt.exe -nologo -manifest \[$]@.manifest -outputresource:\[$]@\;2 ; fi"
          define VC_MANIFEST_EMBED_EXE "if test -f \[$]@.manifest ; then mt.exe -nologo -manifest \[$]@.manifest -outputresource:\[$]@\;1 ; fi"
          define MAKE_SHARED_LIB "${MAKE_SHARED_LIB} ; ${VC_MANIFEST_EMBED_DLL}"
          define-append TEA_ADD_CLEANFILES *.manifest
        }
      }
    }
    *-*-linux* {
      define TEACUP_OS linux
    }
    *-*-gnu* {
      define TEACUP_OS gnu
    }
    *-*-netbsd*debian* {
      define TEACUP_OS netbsd-debian
    }
    *-*-netbsd* {
      define TEACUP_OS netbsd
    }
    *openbsd* {
      define TEACUP_OS openbsd
    }
    default {
      set os   [lindex [split $HOST -] 2]
      define TEACUP_OS $os
    }
  }
  if {$arch eq "unknown"} {
    set arch [lindex [split $HOST -] 0]
    define TEACUP_ARCH $arch
    define TEACUP_PROFILE "[get-define TEACUP_OS]-$arch"
  }

  switch -glob -- $HOST {
    sparc* {
      if {[msg-quiet cc-check-decls __SUNPRO_C]} {
      }
    }
    *-*-solaris* {
      if {[msg-quiet cc-check-decls __SUNPRO_C]} {

      }
    }
    *-*-hpux {

    }
    *-*-haiku {
    }
  }
  if {[get-define SHARED_BUILD]} {
	  define MAKE_LIB [get-define MAKE_SHARED_LIB]
  } else {
	  define MAKE_LIB [get-define MAKE_STATIC_LIB]
  }
  define SHLIB_LD [get-define TCL_SHLIB_LD]
  define DEFS "[get-define PACKAGE_DEFS] [get-define TCL_DEFS]"
  ###
  # autosetup -> TEA mappings
  ###
  puts "END TEA-GENERATE"

}
