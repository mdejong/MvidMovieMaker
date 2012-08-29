/*
 *  runlength.h
 *  RunLengthEncode5bpp
 *
 *  Created by Moses DeJong on 2/18/09.
 *  Copyright 2009 __MyCompanyName__. All rights reserved.
 *
 */

#include <stdint.h>
#include <sys/types.h>

int
pp_encode(uint16_t *inPixels, int inNumPixels, char *outBytes, int outNumBytes);

void
pp_decode(char *inBytes, int inNumBytes, uint16_t *outPixels, int outNumPixels);