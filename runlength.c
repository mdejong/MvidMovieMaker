/*
 *  runlength.c
 *  RunLengthEncode5bpp
 *
 *  Created by Moses DeJong on 2/18/09.
 *  Copyright 2009 __MyCompanyName__. All rights reserved.
 *
 * This file implements a run length encoding implementaiton for 16 bit
 * pixels. This works really well for computer generated images with
 * lots of runs of the same pixels.
 */

#include "runlength.h"

#include <assert.h>
#include <stdlib.h>
#include <math.h>
#include "string.h"

#ifdef LITTLE_ENDIAN
// OK
#else
#error "LITTLE ENDIAN ONLY"
#endif

#define BYTES_PER_PIXEL 2

#ifndef NO_DEBUG_EXTRA_LOCALS
#define DEBUG_EXTRA_LOCALS 1
#endif // NO_DEBUG_EXTRA_LOCALS

#define MAX_PIXEL_RUN 128

#define MAX_WORDS_PIXEL_RUN 128/2

// Unpack RLE encoded bytes in inBytes and store 16 bit pixel values into
// outPixels. This logic assumes that the caller knows how many pixels the
// inBytes encoded data will expand into and that the outNumPixels
// value indicates that amount.

void
pp_decode(char *inBytes, int inNumBytes, uint16_t *outPixels, int outNumPixels)
{
	int n;
	uint16_t val;
	uint16_t *last_outPixels = outPixels + outNumPixels;

#if DEBUG_EXTRA_LOCALS
	char *last_inBytes = inBytes + inNumBytes;
#endif

	// full range fill optimization
	uint16_t *last_full_fill_ptr = NULL;
	uint16_t last_full_fill_pixel = 0;	

	while (outPixels < last_outPixels)
	{
#if DEBUG_EXTRA_LOCALS
		assert(inBytes < last_inBytes);
		inNumBytes--;
#endif
		n = (int) *inBytes++;

#if DEBUG_EXTRA_LOCALS
		// verify proper sign extension
		assert(n >= -128 && n <= 127);
#endif		

		// If n is between 0 and 127 inclusive, copy the next n+1 pixels literally.
		if (n >= 0)
		{
			n += 1;
#ifdef DEBUG_EXTRA_LOCALS
			assert((inBytes + n*2 - 1) < last_inBytes);
			assert((outPixels + n - 1) < last_outPixels);
#endif
			memcpy(outPixels, inBytes, n * 2);
			outPixels += n;
			inBytes += n * 2;
			
#ifdef DEBUG_EXTRA_LOCALS
			outNumPixels -= n;
			inNumBytes -= n * 2;
#endif
		} else if (n == -128) {
			// This special byte is used as a no-op in some RLE implementations.
			// In this implementation it indicates the common case of a full
			// run of pixels followed by another full run of the same pixel.
			// We can save space in the encoded output by not emitting the
			// pixel value for the second run. In addition, a series of writes
			// can be replaced with a single memcpy() from the range filled
			// by the last operation. Multiple -128 bytes are used to indicate
			// a large fill.

#ifdef DEBUG_EXTRA_LOCALS
			assert((outPixels + MAX_PIXEL_RUN - 1) < last_outPixels);
#endif			

			if (last_full_fill_pixel == 0) {
				// fill entire output buffer with black pixels
				memset(outPixels, 0, MAX_PIXEL_RUN * sizeof(uint16_t));
			} else if (last_full_fill_pixel == 0xFFFF) {
				// fill entire output buffer with white pixels
				memset(outPixels, 0xFF, MAX_PIXEL_RUN * sizeof(uint16_t));
			} else {
				// not a black or white pixel, memcpy() previous fill range
#ifdef DEBUG_EXTRA_LOCALS
				// double check that memory does not overlap
				assert(last_full_fill_ptr != NULL);
				assert(last_full_fill_ptr < outPixels);
				assert((last_full_fill_ptr + MAX_PIXEL_RUN - 1) < outPixels);
#endif
				memcpy(outPixels, last_full_fill_ptr, MAX_PIXEL_RUN * sizeof(uint16_t));
			}

			outPixels += MAX_PIXEL_RUN;
#ifdef DEBUG_EXTRA_LOCALS
			outNumPixels -= MAX_PIXEL_RUN;
#endif
		} else {
			// If n is between -127 and -1, copy next duplicated pixel -n+1 times

			n = -n + 1;

			// Read a half word pixel value from inBytes, then write it to
			// outPixels n times in a row.

#if DEBUG_EXTRA_LOCALS
			outNumPixels -= n;
			inNumBytes -= 2;
			assert((inBytes < last_inBytes) && (inBytes < (last_inBytes+1)));
#endif

			val = *((uint16_t*) inBytes);
			inBytes += 2;

#ifdef DEBUG_EXTRA_LOCALS
			assert((outPixels + n - 1) < last_outPixels);
			uint16_t *orig_outPixels = outPixels;
			assert(n >= 2);
#endif

			uint32_t *wptr = (uint32_t*) outPixels;
			uint32_t wval = (val << 16) | val;

			// numWords is the count of 2 pixel pairs
			// to be written as 32 bit words. This
			// value is in the range 1 to 64.

			uint32_t numWords;
			// numWords = (n / 2);
			numWords = ((uint32_t) n) >> 1;

#ifdef DEBUG_EXTRA_LOCALS
			assert(numWords == (n / 2));
#endif

			uint32_t numPixelsPairs;
			//numPixelsPairs = numWords * 2;
			numPixelsPairs = numWords << 1;

#ifdef DEBUG_EXTRA_LOCALS
			assert(numPixelsPairs == (numWords * 2));
#endif

			if (wval == 0) {
				// fill entire output buffer with black pixels
				memset(wptr, 0, numWords * sizeof(uint32_t));
#ifdef DEBUG_EXTRA_LOCALS
				wptr += numWords;
#endif

				if (numWords == MAX_WORDS_PIXEL_RUN) {
					last_full_fill_pixel = val;
				}
			} else if (wval == 0xFFFFFFFF) {
				// fill entire output buffer with white pixels
				memset(wptr, 0xFF, numWords * sizeof(uint32_t));
#ifdef DEBUG_EXTRA_LOCALS
				wptr += numWords;
#endif

				if (numWords == MAX_WORDS_PIXEL_RUN) {
					last_full_fill_pixel = val;
				}				
			} else {
				// Duff's loop to write words to memory

				uint32_t *last_wptr = wptr + numWords;

				switch ((last_wptr - wptr) & 7)
				{
					case 0: 
						while (wptr < last_wptr)
						{
							*wptr++ = wval;
					case 7: *wptr++ = wval;
					case 6: *wptr++ = wval;
					case 5: *wptr++ = wval;
					case 4: *wptr++ = wval;
					case 3: *wptr++ = wval;
					case 2: *wptr++ = wval;
					case 1: *wptr++ = wval;
						}
				}

				// After writing a buffer, save pixel info in case
				// the next run uses the exact same pixel. Don't
				// bother is we have less than a full run.

				if (numWords == MAX_WORDS_PIXEL_RUN) {
					last_full_fill_pixel = val;
					last_full_fill_ptr = (uint16_t*) (wptr - MAX_WORDS_PIXEL_RUN);
				}
			}

			outPixels += numPixelsPairs;

#ifdef DEBUG_EXTRA_LOCALS
			assert(((uint32_t*) outPixels) == wptr);
#endif

			if (numPixelsPairs < n) {
				// odd number of pixels, write 1 more 16bit value
#ifdef DEBUG_EXTRA_LOCALS
				assert(outPixels < last_outPixels);
#endif
				*outPixels++ = val;
			}

#ifdef DEBUG_EXTRA_LOCALS
			// Verify that data was written to buffer properly
			for (uint16_t* ptr = orig_outPixels; ptr < (orig_outPixels + n); ptr++) {
				uint16_t sval = (uint16_t) *ptr;
				if (sval != val) {
					assert(0);
				}
			}
#endif // DEBUG_EXTRA_LOCALS
		} // end if else block
	} // end while loop

#ifdef DEBUG_EXTRA_LOCALS
	assert(outPixels == last_outPixels);
	assert(outNumPixels == 0);
	assert(inNumBytes == 0);
#endif

	return;
}

static uint16_t* _pp_findNextDuplicate(uint16_t *inptr, uint16_t *last_inptr, int maxPixelSearch);
static int _pp_findRunLength(uint16_t *inptr, uint16_t *last_inptr, int maxPixelRun);

// Read pixels (stored as 16 bit integers) and pack them into outBytes. This
// logic assumes that outBuffer will be large enough to store the
// run length encoded bytes. Returns the actual number of bytes
// stored into outBytes.

int
pp_encode(uint16_t *inPixels, int inNumPixels, char *outBytes, int outNumBytes)
{
	uint16_t *last_inPixels = inPixels + inNumPixels;
	char *last_outBytes = outBytes + outNumBytes;
	char *orig_outBytes = outBytes;

	// full fill optimization
	uint16_t was_last_run_full_fill = 0;
	uint16_t last_run_full_fill_pixel = 0;

	while (inPixels < last_inPixels)
	{
		uint16_t *dup = _pp_findNextDuplicate(inPixels, last_inPixels, 128);

		if (inPixels == dup)
		{
			// start of a run, write the run length byte followed by the
			// 2 byte pixel value.

			int len = _pp_findRunLength(inPixels, last_inPixels, 128);
			int actual_len = 128;
			if (len < actual_len)
				actual_len = len;
			assert(actual_len > 1);

			// special case for a full run that follows another full run
			// of the same pixel. We don't emit the pixel again in this
			// case, instead just write -128 as the byte value. Note
			// that this optimization applies to the last run, so a full
			// run followed by literals then another full run will
			// trigger the optimization even though the literals were
			// in between the fills.

			if (actual_len == 128 && was_last_run_full_fill &&
					(*inPixels == last_run_full_fill_pixel)) {
				assert(outBytes < last_outBytes);
				*outBytes++ = -128;
				inPixels += 128;
			} else {
				// write n as a byte that stores the number of pixels in a run
				
				char n = (actual_len - 1) * -1;
				assert(outBytes < last_outBytes);
				*outBytes++ = n;

				// write the 16 bit pixel value as two bytes
				assert(inPixels < last_inPixels);
				assert(outBytes < last_outBytes && (outBytes+1) < last_outBytes);
				uint16_t val = *inPixels;
				*((uint16_t*) outBytes) = val;
				outBytes += 2;
				inPixels += actual_len;

				// save full fill state for this run

				if (actual_len == 128) {
					was_last_run_full_fill = 1;
					last_run_full_fill_pixel = val;
				} else {
					was_last_run_full_fill = 0;
				}
			}
		}
		else { // write literals
			int len;

			if (dup != NULL)
			{
				// literals followed by a run, find len of literals
				len = dup - inPixels;
			} else {
				// no run found in next chunk of data
				len = last_inPixels - inPixels;
			}

			int actual_len = 128;
			if (len < actual_len)
				actual_len = len;

			char n = (actual_len - 1);
			assert(outBytes < last_outBytes);
			*outBytes++ = n;

			// copy actual_len pixels to outBytes

			int actualBytes = actual_len * 2;

			assert((inPixels + actual_len - 1) < last_inPixels);
			assert((outBytes + actualBytes - 1) < last_outBytes);

			memcpy(outBytes, inPixels, actualBytes);

			inPixels += actual_len;
			outBytes += actualBytes;
		}
	}

	// Verify that we read all the pixels

	assert(inPixels == last_inPixels);

	// Return the number of bytes that we actually wrote, the user will
	// have to pass a larger buffer that is needed since the worst
	// case must be taken into account.

	return (outBytes - orig_outBytes);
}


// Search for the next duplicate set of pixels in the input
// buffer with an upper search bound. Returns the first location
// where 2 identical pixels were found, otherwise NULL.

static
uint16_t* _pp_findNextDuplicate(uint16_t *inptr, uint16_t *last_inptr, int maxPixelSearch)
{
	assert(inptr <= last_inptr);

	if (inptr == last_inptr) {
		return NULL;
	}

	uint16_t *max_searchptr = inptr + maxPixelSearch;
	if (last_inptr < max_searchptr)
		max_searchptr = last_inptr;

	uint16_t prev = *inptr++;

	for (; inptr < max_searchptr; inptr++) {
		assert(inptr < last_inptr);
		uint16_t val = *inptr;

		if (val == prev) {
			return (inptr - 1);
		}

		prev = val;
	}
	
	return NULL;
}

// Given a pointer to the start of a run, return the number
// of elements in the run. The length of a run is bound
// by a max number of pixels.

static
int _pp_findRunLength(uint16_t *inptr, uint16_t *last_inptr, int maxPixelRun)
{
	uint16_t *matchptr = inptr;
	uint16_t *max_matchptr = matchptr + maxPixelRun;
	if (last_inptr < max_matchptr)
		max_matchptr = last_inptr;

	uint16_t val = *matchptr++;

	for ( ; (matchptr < max_matchptr) && (*matchptr == val); matchptr++) {
		// no-op
	}

	return (int) (matchptr - inptr);	
}
