/*
 * exampleA.h --
 *
 *	This header file contains the function declarations needed for
 *	all of the source files in this package.
 *
 * Copyright (c) 1998-1999 Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 */

#ifndef _EXAMPLEA
#define _EXAMPLEA

#include <tcl.h>

/*
 * Windows needs to know which symbols to export.  Unix does not.
 * BUILD_sha should be undefined for Unix.
 */

#ifdef BUILD_exampleA
#undef TCL_STORAGE_CLASS
#define TCL_STORAGE_CLASS DLLEXPORT
#endif /* BUILD_exampleA */

typedef struct {
    unsigned long state[5];
    unsigned long count[2];
    unsigned char buffer[64];
} SHA1_CTX;

void SHA1Init	_ANSI_ARGS_((SHA1_CTX* context));
void SHA1Update	_ANSI_ARGS_((SHA1_CTX* context, unsigned char* data,
		 unsigned int len));
void SHA1Final	_ANSI_ARGS_((SHA1_CTX* context, unsigned char digest[20]));

/*
 * Only the _Init function is exported.
 */

EXTERN int	Examplea_Init _ANSI_ARGS_((Tcl_Interp * interp));

#endif /* _EXAMPLEA */
