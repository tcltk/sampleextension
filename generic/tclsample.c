/*
 * tclsample.c --
 *
 *	This file implements a Tcl interface to the secure hashing
 *	algorithm functions in sha1.c
 *
 * Copyright (c) 1999 Scriptics Corporation.
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

#define TCL_READ_CHUNK_SIZE 4096

static unsigned char itoa64f[] =
        "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_,";

static int numcontexts = 0;
static SHA1_CTX *sha1Contexts = NULL;
static int *ctxtotalRead = NULL;

static int Sha1 _ANSI_ARGS_((ClientData clientData, Tcl_Interp *interp,
		int argc, char *argv[]));

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
Sha1(clientData, interp, argc, argv)
    ClientData clientData;	/* Not used. */
    Tcl_Interp *interp;		/* Current interpreter */
    int argc;			/* Number of arguments */
    char *argv[];		/* Argument strings */
{
    /*
     * The default base is hex
     */

    int log2base = 4;
    int a;
    char *arg, *string = NULL;
    Tcl_Channel chan = (Tcl_Channel) NULL;
    Tcl_Channel copychan = (Tcl_Channel) NULL;
    int mode;
    int contextnum = 0;
#define sha1Context (sha1Contexts[contextnum])
    char *bufPtr;
    int maxbytes = 0;
    int doinit = 1;
    int dofinal = 1;
    char *descriptor = NULL;
    int totalRead = 0;
    int i, j, n, mask, bits, offset;

    /*
     * For binary representation + null char
     */

    char buf[129];
    unsigned char digest[DIGESTSIZE];

    for (a = 1; a < argc; a++) {
	arg = argv[a];
	if (arg[0] == '-') {
	    if (strcmp(arg, "-log2base") == 0) {
		if ((sscanf(argv[++a], "%d", &log2base) != 1) ||
			    (log2base < 1) || (log2base > 6)) {
		    Tcl_AppendResult (interp, "invalid log2base: ", arg,
			    " must be integer in range 1...6", (char *) NULL);
		    return TCL_ERROR;
		}
	    } else if (strcmp(arg, "-string") == 0) {
		string = argv[++a];
	    } else if (strcmp(arg, "-copychan") == 0) {
		copychan = Tcl_GetChannel(interp, argv[++a], &mode);
		if (copychan == (Tcl_Channel) NULL) {
		    return TCL_ERROR;
		}
		if ((mode & TCL_WRITABLE) == 0) {
		    Tcl_AppendResult(interp, "copychan \"", argv[a],
			    "\" wasn't opened for writing", (char *) NULL);
		    return TCL_ERROR;
		}
	    } else if (strcmp(arg, "-chan") == 0) {
		chan = Tcl_GetChannel(interp, argv[++a], &mode);
		if (chan == (Tcl_Channel) NULL) {
		    return TCL_ERROR;
		}
		if ((mode & TCL_READABLE) == 0) {
		    Tcl_AppendResult(interp, "chan \"", argv[a],
			    "\" wasn't opened for reading", (char *) NULL);
		    return TCL_ERROR;
		}
	    } else if (strcmp(arg, "-maxbytes") == 0) {
		if (sscanf(argv[++a], "%d", &maxbytes) != 1) {
		    Tcl_AppendResult(interp, "parameter to -maxbytes \"",
			    argv[a], "\" must be an integer", (char *) NULL);
		    return TCL_ERROR;
		}
	    } else if (strcmp(arg, "-init") == 0) {
		for (contextnum = 1; contextnum < numcontexts; contextnum++) {
		    if (ctxtotalRead[contextnum] < 0) {
			break;
		    }
		}
		if (contextnum == numcontexts) {
		    /*
		     * Allocate a new context.
		     */

		    numcontexts++;
		    sha1Contexts = (SHA1_CTX *) realloc((void *) sha1Contexts,
			    numcontexts * sizeof(SHA1_CTX));
		    ctxtotalRead = realloc((void *) ctxtotalRead,
			    numcontexts * sizeof(int));
		}
		ctxtotalRead[contextnum] = 0;
		SHA1Init(&sha1Context);
		sprintf(buf, "sha1%d", contextnum);
		Tcl_AppendResult(interp, buf, (char *)NULL);
		return TCL_OK;
	    } else if (strcmp(arg, "-update") == 0) {
		descriptor = argv[++a];
		doinit = 0;
		dofinal = 0;
	    } else if (strcmp(arg, "-final") == 0) {
		descriptor = argv[++a];
		doinit = 0;
	    } else {
		goto wrongArgs;
	    }
	} else {
	    goto wrongArgs;
	}
    }

    if (descriptor != NULL) {
	if ((sscanf(descriptor, "sha1%d", &contextnum) != 1) ||
		(contextnum >= numcontexts) || (ctxtotalRead[contextnum] < 0)) {
	    Tcl_AppendResult(interp, "invalid sha1 descriptor \"", 
		    descriptor, "\"", (char *) NULL);
	    return TCL_ERROR;
	}
    }

    if (doinit) {
	SHA1Init(&sha1Context);
    }
    
    if (string != NULL) {
	if (chan != (Tcl_Channel) NULL) {
	    goto wrongArgs;
	}
	totalRead = strlen(string);
	SHA1Update(&sha1Context, (unsigned char *) string, totalRead);
    } else if (chan != (Tcl_Channel) NULL) {
	bufPtr = ckalloc((unsigned) TCL_READ_CHUNK_SIZE);
	totalRead = 0;
	while ((n = Tcl_Read(chan, bufPtr,
		maxbytes == 0
		? TCL_READ_CHUNK_SIZE
		: (TCL_READ_CHUNK_SIZE < maxbytes
		? TCL_READ_CHUNK_SIZE
		: maxbytes))) != 0) {
	    if (n < 0) {
		ckfree(bufPtr);
		Tcl_AppendResult(interp, argv[0], ": ",
			Tcl_GetChannelName(chan), Tcl_PosixError(interp),
			(char *) NULL);
		return TCL_ERROR;
	    }

	    totalRead += n;

	    SHA1Update(&sha1Context, (unsigned char *) bufPtr, n);

	    if (copychan != (Tcl_Channel) NULL) {
		n = Tcl_Write(copychan, bufPtr, n);
		if (n < 0) {
		    ckfree(bufPtr);
		    Tcl_AppendResult(interp, argv[0], ": ",
			    Tcl_GetChannelName(copychan),
			     Tcl_PosixError(interp),
			    (char *) NULL);
		    return TCL_ERROR;
		}
	    }

	    if ((maxbytes > 0) && ((maxbytes -= n) <= 0)) {
		break;
	    }
	}
	ckfree(bufPtr);
    } else if (descriptor == NULL) {
	goto wrongArgs;
    }
    
    if (!dofinal) {
	ctxtotalRead[contextnum] += totalRead;
	sprintf(buf, "%d", totalRead);
	Tcl_AppendResult(interp, buf, (char *)NULL);
	return TCL_OK;
    }

    if (string == NULL) {
	totalRead += ctxtotalRead[contextnum];
	sprintf(buf, "%d", totalRead);
	Tcl_AppendResult(interp, buf, (char *)NULL);
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
    Tcl_AppendResult (interp, buf, (char *)NULL);
    if (contextnum > 0) {
	ctxtotalRead[contextnum] = -1;
    }
    return TCL_OK;

wrongArgs:
    Tcl_AppendResult (interp, "wrong # args: should be either:\n",
	    "  ",
	    argv[0],
	    " ?-log2base log2base? -string string\n", 
	    " or\n",
	    "  ",
	    argv[0],
	    " ?-log2base log2base? ?-copychan chanID? -chan chanID\n",
	    " or\n",
	    "  ",
	    argv[0],
	    " -init (returns descriptor)\n",
	    "  ",
	    argv[0],
	    " -update descriptor ?-maxbytes n? ?-copychan chanID? -chan chanID\n",
	    "    (any number of -update calls, returns number of bytes read)\n",
	    "  ",
	    argv[0],
	    " ?-log2base log2base? -final descriptor\n",
	    " The default log2base is 4 (hex)",
	    (char *) NULL);
    return TCL_ERROR;
}

/*
 *----------------------------------------------------------------------
 *
 * Sample_Init --
 *
 *	Initialize the new package.  The string "Sample" in the
 *	function name must match the PACKAGE declaration at the top of
 *	configure.in.
 *
 * Results:
 *	A standard Tcl result
 *
 * Side effects:
 *	The Tclsha1 package is created.
 *	One new command "sha1" is added to the Tcl interpreter.
 *
 *----------------------------------------------------------------------
 */

int
Sample_Init(Tcl_Interp *interp)
{
    /*
     * This may work with 8.0, but we are using strictly stubs here,
     * which requires 8.1.
     */
    if (Tcl_InitStubs(interp, "8.1", 0) == NULL) {
	return TCL_ERROR;
    }
    if (Tcl_PkgRequire(interp, "Tcl", "8.1", 0) == NULL) {
	return TCL_ERROR;
    }
    if (Tcl_PkgProvide(interp, "Tclsha1", VERSION) != TCL_OK) {
	return TCL_ERROR;
    }
    Tcl_CreateCommand(interp, "sha1", Sha1,
	    (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);

    numcontexts = 1;
    sha1Contexts = (SHA1_CTX *) malloc(sizeof(SHA1_CTX));
    ctxtotalRead = (int *) malloc(sizeof(int));
    ctxtotalRead[0] = 0;

    return TCL_OK;
}
