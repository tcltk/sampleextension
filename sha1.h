/*
 * sha1.h --
 *
 *	This header file contains the function declarations needed for
 *	all of the source files in this package.
 *
 * Copyright (c) 1998-1999 Scriptics Corporation.
 *
 */

/* definitions extracted from sha1.c by Dave Dykstra, 4/22/97 */

#ifndef _TCL
#   include <tcl.h>
#endif

#ifdef BUILD_sha
#undef TCL_STORAGE_CLASS
#define TCL_STORAGE_CLASS DLLEXPORT
#endif

typedef struct {
    unsigned long state[5];
    unsigned long count[2];
    unsigned char buffer[64];
} SHA1_CTX;

void SHA1Init(SHA1_CTX* context);
void SHA1Update(SHA1_CTX* context, unsigned char* data, unsigned int len);
void SHA1Final(unsigned char digest[20], SHA1_CTX* context);

EXTERN int	Tclsha_Init _ANSI_ARGS_((Tcl_Interp * interp));
