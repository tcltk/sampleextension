/*
 * sample.h --
 *
 *	This header file contains the function declarations needed for
 *	all of the source files in this package.
 *
 * Copyright (c) 1998-1999 Scriptics Corporation.
 * Copyright (c) 2003 ActiveState Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 */

#ifndef _SAMPLE
#define _SAMPLE

#include <tcl.h>

#ifdef HAVE_INTTYPES_H
#   include <inttypes.h>
typedef uint32_t sha_uint32_t;
#else
#   if ((1<<31)<0)
typedef unsigned long sha_uint32_t;
#   else
typedef unsigned int sha_uint32_t;
#   endif
#endif


/*
 * For C++ compilers, use extern "C"
 */

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    sha_uint32_t state[5];
    sha_uint32_t count[2];
    unsigned char buffer[64];
} SHA1_CTX;

MODULE_SCOPE void SHA1Init(SHA1_CTX* context);
MODULE_SCOPE void SHA1Update(SHA1_CTX* context, unsigned char* data, Tcl_Size len);
MODULE_SCOPE void SHA1Final(SHA1_CTX* context, unsigned char digest[20]);

/*
 * Only the _Init function is exported.
 */

extern DLLEXPORT int	Sample_Init(Tcl_Interp * interp);

/*
 * end block for C++
 */

#ifdef __cplusplus
}
#endif

#endif /* _SAMPLE */
