/*
 * tclsample.c --
 *
 *	This file implements a Tcl interface to the secure hashing
 *	algorithm functions in sha1.c
 *
 * Copyright (c) 1999 Scriptics Corporation.
 * Copyright (c) 2003 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 */

/*
 * Modified from tclmd5.c by Dave Dykstra, dwd@bell-labs.com, 4/22/97
 */

#include <tcl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sample.h"
#include "sampleUuid.h"

#define TCL_READ_CHUNK_SIZE 4096

static const unsigned char itoa64f[] =
        "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_,";

static int numcontexts = 0;
static SHA1_CTX *sha1Contexts = NULL;
static Tcl_Size *ctxtotalRead = NULL;

static int Sha1_Cmd(void *clientData, Tcl_Interp *interp,
		int objc, Tcl_Obj *const objv[]);

#define DIGESTSIZE 20

/*
 *----------------------------------------------------------------------
 *
 * Sha1 --
 *
 *	 Implements the new Tcl "sha1" command.
 *
 * Results:
 *	A standard Tcl result
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

static int
Sha1_Cmd(
    void *dummy,	/* Not used. */
    Tcl_Interp *interp,		/* Current interpreter */
    int objc,			/* Number of arguments */
    Tcl_Obj *const objv[]	/* Argument strings */
    )
{
    /*
     * The default base is hex
     */

    int log2base = 4;
    int a;
    Tcl_Obj *stringObj = NULL;
    Tcl_Channel chan = NULL;
    Tcl_Channel copychan = NULL;
    int mode;
    int contextnum = 0;
#define sha1Context (sha1Contexts[contextnum])
    char *bufPtr;
    Tcl_WideInt maxbytes = 0;
    int doinit = 1;
    int dofinal = 1;
    Tcl_Obj *descriptorObj = NULL;
    Tcl_Size totalRead = 0, n;
    int i, j, mask, bits, offset;
    (void)dummy;

    /*
     * For binary representation + null char
     */

    char buf[129];
    unsigned char digest[DIGESTSIZE];

    static const char *options[] = {
	"-chan", "-copychan", "-final", "-init", "-log2base", "-maxbytes",
	"-string", "-update", NULL
    };
    enum ShaOpts {
	SHAOPT_CHAN, SHAOPT_COPY, SHAOPT_FINAL, SHAOPT_INIT, SHAOPT_LOG,
	SHAOPT_MAXB, SHAOPT_STRING, SHAOPT_UPDATE
    };

    for (a = 1; a < objc; a++) {
	int index;

	if (Tcl_GetIndexFromObjStruct(interp, objv[a], options, sizeof(char *),
		"option", 0, &index) != TCL_OK) {
	    return TCL_ERROR;
	}
	/*
	 * Everything except -init takes an argument...
	 */
	if ((index != SHAOPT_INIT) && (++a >= objc)) {
	    goto wrongArgs;
	}
	switch ((enum ShaOpts) index) {
	case SHAOPT_INIT:
	    for (contextnum = 1; contextnum < numcontexts; contextnum++) {
		if (ctxtotalRead[contextnum] == -1) {
		    break;
		}
	    }
	    if (contextnum == numcontexts) {
		/*
		 * Allocate a new context.
		 */

		numcontexts++;
		sha1Contexts = (SHA1_CTX *) ckrealloc((void *) sha1Contexts,
			numcontexts * sizeof(SHA1_CTX));
		ctxtotalRead = (Tcl_Size *)ckrealloc(ctxtotalRead,
			numcontexts * sizeof(Tcl_Size));
	    }
	    ctxtotalRead[contextnum] = 0;
	    SHA1Init(&sha1Context);
	    snprintf(buf, sizeof(buf), "sha1%d", contextnum);
	    Tcl_AppendResult(interp, buf, NULL);
	    return TCL_OK;
	case SHAOPT_CHAN:
	    chan = Tcl_GetChannel(interp, Tcl_GetString(objv[a]), &mode);
	    if (chan == NULL) {
		return TCL_ERROR;
	    }
	    if ((mode & TCL_READABLE) == 0) {
		Tcl_AppendResult(interp, "chan \"", Tcl_GetString(objv[a]),
			"\" wasn't opened for reading", NULL);
		return TCL_ERROR;
	    }
	    continue;
	case SHAOPT_COPY:
	    copychan = Tcl_GetChannel(interp, Tcl_GetString(objv[a]), &mode);
	    if (copychan == NULL) {
		return TCL_ERROR;
	    }
	    if ((mode & TCL_WRITABLE) == 0) {
		Tcl_AppendResult(interp, "copychan \"", Tcl_GetString(objv[a]),
			"\" wasn't opened for writing", NULL);
		return TCL_ERROR;
	    }
	    continue;
	case SHAOPT_FINAL:
	    descriptorObj = objv[a];
	    doinit = 0;
	    continue;
	case SHAOPT_LOG:
	    if (Tcl_GetIntFromObj(interp, objv[a], &log2base) != TCL_OK) {
		return TCL_ERROR;
	    } else if ((log2base < 1) || (log2base > 6)) {
		Tcl_AppendResult(interp, "parameter to -log2base \"",
			Tcl_GetString(objv[a]),
			"\" must be integer in range 1...6", NULL);
		return TCL_ERROR;
	    }
	    continue;
	case SHAOPT_MAXB:
	    if (Tcl_GetWideIntFromObj(interp, objv[a], &maxbytes) != TCL_OK) {
		return TCL_ERROR;
	    }
	    continue;
	case SHAOPT_STRING:
	    stringObj = objv[a];
	    continue;
	case SHAOPT_UPDATE:
	    descriptorObj = objv[a];
	    doinit = 0;
	    dofinal = 0;
	    continue;
	}
    }

    if (descriptorObj != NULL) {
	if ((sscanf(Tcl_GetString(descriptorObj), "sha1%d",
		&contextnum) != 1) || (contextnum >= numcontexts) ||
		(ctxtotalRead[contextnum] == -1)) {
	    Tcl_AppendResult(interp, "invalid sha1 descriptor \"",
		    Tcl_GetString(descriptorObj), "\"", NULL);
	    return TCL_ERROR;
	}
    }

    if (doinit) {
	SHA1Init(&sha1Context);
    }

    if (stringObj != NULL) {
	char *string;
	if (chan != NULL) {
	    goto wrongArgs;
	}
	string = Tcl_GetStringFromObj(stringObj, &totalRead);
	SHA1Update(&sha1Context, (unsigned char *) string, totalRead);
    } else if (chan != NULL) {
	bufPtr = (char *)ckalloc(TCL_READ_CHUNK_SIZE);
	totalRead = 0;
	while ((n = Tcl_Read(chan, bufPtr,
		maxbytes == 0
		? TCL_READ_CHUNK_SIZE
		: (TCL_READ_CHUNK_SIZE < maxbytes
		? TCL_READ_CHUNK_SIZE
		: maxbytes))) != 0) {
	    if (n == -1) {
		ckfree(bufPtr);
		Tcl_AppendResult(interp, Tcl_GetString(objv[0]), ": ",
			Tcl_GetChannelName(chan), Tcl_PosixError(interp),
			NULL);
		return TCL_ERROR;
	    }

	    totalRead += n;

	    SHA1Update(&sha1Context, (unsigned char *) bufPtr, n);

	    if (copychan != NULL) {
		n = Tcl_Write(copychan, bufPtr, n);
		if (n == -1) {
		    ckfree(bufPtr);
		    Tcl_AppendResult(interp, Tcl_GetString(objv[0]), ": ",
			    Tcl_GetChannelName(copychan),
			     Tcl_PosixError(interp), NULL);
		    return TCL_ERROR;
		}
	    }

	    if ((maxbytes > 0) && (maxbytes <= n)) {
		break;
	    }
	    maxbytes -= n;
	}
	ckfree(bufPtr);
    } else if (descriptorObj == NULL) {
	goto wrongArgs;
    }

    if (!dofinal) {
	ctxtotalRead[contextnum] += totalRead;
	Tcl_SetObjResult(interp, Tcl_NewWideIntObj(totalRead));
	return TCL_OK;
    }

    if (stringObj == NULL) {
	totalRead += ctxtotalRead[contextnum];
	Tcl_SetObjResult(interp, Tcl_NewWideIntObj(totalRead));
    }

    SHA1Final(&sha1Context, digest);

    /*
     * Take the 20 byte array and print it in the requested base
     * e.g. log2base=1 => binary,  log2base=4 => hex
     */

    n = log2base;
    i = j = bits = 0;

    /*
     * if 160 bits doesn't divide exactly by n then the first character of
     *  the output represents the residual bits.  e.g for n=6 (base 64) the
     *  first character can only take the values 0..f
     */

    offset = (DIGESTSIZE * 8) % n;
    if (offset > 0) {
	offset = n - offset;
    }
    mask = (2 << (n-1)) - 1;
    while (1) {
        bits <<= n;
        if (offset <= n) {
    	    if (i == DIGESTSIZE) {
		break;
	    }
    	    bits += (digest[i++] << (n - offset));
    	    offset += 8;
        }
        offset -= n;
        buf[j++] = itoa64f[(bits>>8)&mask];
    }
    buf[j++] = itoa64f[(bits>>8)&mask];
    buf[j++] = '\0';
    Tcl_AppendResult(interp, buf, NULL);
    if (contextnum > 0) {
	ctxtotalRead[contextnum] = -1;
    }
    return TCL_OK;

wrongArgs:
    Tcl_AppendResult(interp, "wrong # args: should be either:\n",
	    "  ",
	    Tcl_GetString(objv[0]),
	    " ?-log2base log2base? -string string\n",
	    " or\n",
	    "  ",
	    Tcl_GetString(objv[0]),
	    " ?-log2base log2base? ?-copychan chanID? -chan chanID\n",
	    " or\n",
	    "  ",
	    Tcl_GetString(objv[0]),
	    " -init (returns descriptor)\n",
	    "  ",
	    Tcl_GetString(objv[0]),
	    " -update descriptor ?-maxbytes n? ?-copychan chanID? -chan chanID\n",
	    "    (any number of -update calls, returns number of bytes read)\n",
	    "  ",
	    Tcl_GetString(objv[0]),
	    " ?-log2base log2base? -final descriptor\n",
	    " The default log2base is 4 (hex)",
	    NULL);
    return TCL_ERROR;
}

/*
 *----------------------------------------------------------------------
 *
 * Sample_Init --
 *
 *	Initialize the new package.  The string "Sample" in the
 *	function name must match the PACKAGE declaration at the top of
 *	configure.ac.
 *
 * Results:
 *	A standard Tcl result
 *
 * Side effects:
 *	The Sample package is created.
 *	One new command "sha1" is added to the Tcl interpreter.
 *
 *----------------------------------------------------------------------
 */

#ifndef STRINGIFY
#  define STRINGIFY(x) STRINGIFY1(x)
#  define STRINGIFY1(x) #x
#endif

#ifdef __cplusplus
extern "C" {
#endif  /* __cplusplus */
DLLEXPORT int
Sample_Init(
    Tcl_Interp* interp)		/* Tcl interpreter */
{
    Tcl_CmdInfo info;

    /*
     * This may work with 8.0, but we are using strictly stubs here,
     * which requires 8.1.
     */
    if (Tcl_InitStubs(interp, "8.1", 0) == NULL) {
	return TCL_ERROR;
    }

    if (Tcl_GetCommandInfo(interp, "::tcl::build-info", &info)) {
	Tcl_CreateObjCommand(interp, "::sample::build-info",
		info.objProc, (void *)(
		    PACKAGE_VERSION "+" STRINGIFY(SAMPLE_VERSION_UUID)
#if defined(__clang__) && defined(__clang_major__)
			    ".clang-" STRINGIFY(__clang_major__)
#if __clang_minor__ < 10
			    "0"
#endif
			    STRINGIFY(__clang_minor__)
#endif
#if defined(__cplusplus) && !defined(__OBJC__)
			    ".cplusplus"
#endif
#ifndef NDEBUG
			    ".debug"
#endif
#if !defined(__clang__) && !defined(__INTEL_COMPILER) && defined(__GNUC__)
			    ".gcc-" STRINGIFY(__GNUC__)
#if __GNUC_MINOR__ < 10
			    "0"
#endif
			    STRINGIFY(__GNUC_MINOR__)
#endif
#ifdef __INTEL_COMPILER
			    ".icc-" STRINGIFY(__INTEL_COMPILER)
#endif
#ifdef TCL_MEM_DEBUG
			    ".memdebug"
#endif
#if defined(_MSC_VER)
			    ".msvc-" STRINGIFY(_MSC_VER)
#endif
#ifdef USE_NMAKE
			    ".nmake"
#endif
#ifndef TCL_CFG_OPTIMIZED
			    ".no-optimize"
#endif
#ifdef __OBJC__
			    ".objective-c"
#if defined(__cplusplus)
			    "plusplus"
#endif
#endif
#ifdef TCL_CFG_PROFILED
			    ".profile"
#endif
#ifdef PURIFY
			    ".purify"
#endif
#ifdef STATIC_BUILD
			    ".static"
#endif
		), NULL);
    }

    /* Provide the current package */

    if (Tcl_PkgProvideEx(interp, PACKAGE_NAME, PACKAGE_VERSION, NULL) != TCL_OK) {
	return TCL_ERROR;
    }
    Tcl_CreateObjCommand(interp, "sha1", (Tcl_ObjCmdProc *)Sha1_Cmd,
	    NULL, NULL);

    numcontexts = 1;
    sha1Contexts = (SHA1_CTX *) ckalloc(sizeof(SHA1_CTX));
    ctxtotalRead = (Tcl_Size *) ckalloc(sizeof(Tcl_Size));
    ctxtotalRead[0] = 0;

    return TCL_OK;
}
#ifdef __cplusplus
}
#endif  /* __cplusplus */


/*
 *----------------------------------------------------------------------
 *
 * Sample_Unload --
 *
 *	Allow to unload the new package.  The string "Sample" in the
 *	function name must match the PACKAGE declaration at the top of
 *	configure.ac.
 *
 * Results:
 *	A standard Tcl result
 *
 * Side effects:
 *	Library is unloaded.
 *
 *----------------------------------------------------------------------
 */

#ifdef __cplusplus
extern "C" {
#endif  /* __cplusplus */
DLLEXPORT int
Sample_Unload(
    Tcl_Interp* interp,		/* Tcl interpreter */
    int flags)			/* interpreter or process detach */
{
    if (sha1Contexts != NULL) {
	ckfree(sha1Contexts);
	sha1Contexts = NULL;
    }
    if (ctxtotalRead != NULL) {
	ckfree(ctxtotalRead);
	ctxtotalRead = NULL;
    }
    return TCL_OK;
}
#ifdef __cplusplus
}
#endif  /* __cplusplus */
