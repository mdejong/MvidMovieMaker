//
//  MovieArchive.m
//  ImageSeqMovieMaker
//
//  Created by Moses DeJong on 3/5/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "MovieArchive.h"

#import "EasyArchive.h"

#import "MovieFrame.h"

//#define LOGGING

#define IGNORE_ADLER_IN_PATCHES

NSData* memory_diff_or_patch(NSData *frame1, NSData *frame2, NSData *delta_path, int isPatch);

uint32_t xdiff_get_bytes_patched_data(char *patchData);

@implementation MovieArchive

@synthesize archive, width, height;
@synthesize	prevFrameData, rpatchDataObjs, prevMovieFrame;
@synthesize outputMD5, frameIndex;
@synthesize patchBufferNumWords, frameBufferNumWords;


- (id) initWithArchive:(EasyArchive*)inArchive
{
	self = [super init];
	if (self == nil)
		return nil;

	self.archive = inArchive;

	//self->prevFrameData = nil;
	self.rpatchDataObjs = [NSMutableArray arrayWithCapacity:600];

	self->frameIndex = -1;

	//self->width = 0;
	//self->height = 0;

	self->ctxtNeedsInit = TRUE;

	return self;
}

- (void) dealloc
{
	[prevFrameData release];
	[prevMovieFrame release];
	[rpatchDataObjs release];

	[outputMD5 release];
	[archive release];

	[super dealloc];
}

- (NSData*) nextFrameData
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	NSString *thisEntryFilename = [archive readEntryFilename];
	if (thisEntryFilename == nil || [thisEntryFilename length] == 0) {
		// EOF
		[pool release];
		return nil;
	}

	self->frameIndex++;

	NSData *entryData = [archive readEntryData];

	NSData *frameData = nil;

	NSString *tail = [thisEntryFilename lastPathComponent];

#ifdef LOGGING
	NSLog([NSString stringWithFormat:@"read %@ from archive", tail]);
#endif

	// Find file extension, split into ROOT.EXT
	
	NSRange dotRange = [tail rangeOfString:@"." options:NSBackwardsSearch];
	
	if (dotRange.location == NSNotFound) {
		NSString *msg = [NSString stringWithFormat:@"entry filename must have a suffix \"%@\"", tail];
		NSLog(msg);
		assert(FALSE);
	}
	
	NSRange extRange;
	extRange.location = dotRange.location + 1;
	extRange.length = [tail length] - dotRange.location - 1;
	NSString *ext = [tail substringWithRange:extRange];
	
	NSRange rootRange;
	rootRange.location = 0;
	rootRange.length = dotRange.location;		
	NSString *root = [tail substringWithRange:rootRange];
	
	// Verify that the frame number string matches the frame number we expect
	// to find next. For example, examine the first 5 characters of "F0003.dup"
	// and compare to "F0003".

	NSRange frameNumberRange;
	frameNumberRange.location = 0;
	frameNumberRange.length = 1 + 4;
	NSString *frameNumberStr = [root substringWithRange:frameNumberRange];

	NSString *expectedFrameNumberStr;
	if (frameIndex == 0) {
		// Special case for header entry, read "F0000.hdr" in first invocation,
		// then read "F0001.rle" in second invocation.

		NSString *expectedFrameNumberStr1 = @"F0000";
		NSString *expectedFrameNumberStr2 = @"F0001";

		assert([frameNumberStr isEqualToString:expectedFrameNumberStr1] ||
			   [frameNumberStr isEqualToString:expectedFrameNumberStr2]);
	} else {
		expectedFrameNumberStr = [NSString stringWithFormat:@"F%04d", frameIndex+1];
		assert([frameNumberStr isEqualToString:expectedFrameNumberStr]);
	}

	// Handle entry type based on file extension

	if ([ext isEqualToString:@"hdr"]) {
		// Movie header
		// F0000.hdr

		NSData *headerData = entryData;

		CGSize dimensions = [MovieArchive decodeMovieHeaderDimensions:headerData];

		self->width = dimensions.width;
		self->height = dimensions.height;

		// Read MD5 generated from original RLE encoded data

		[self decodeMovieHeaderOutputMD5:headerData];

		self->patchBufferNumWords = [self decodeMovieHeaderPatchBufferNumWords:headerData];
		self->frameBufferNumWords = [self decodeMovieHeaderFrameBufferNumWords:headerData];

		// Once header has been handled, invoke this method again so
		// the the first frame's data is returned by the first
		// invocation of this method.

		self->frameIndex--;

		[pool release];

		return [self nextFrameData];
	} else if ([ext isEqualToString:@"rle"]) {
		// Keyframe:
		// F0001.rle

		frameData = entryData;
	} else if ([ext isEqualToString:@"dup"]) {
		// Duplicate of previous frame (frame 2 duplicates frame 1)
		// F0002.dup

		frameData = prevFrameData;
	} else if ([ext isEqualToString:@"patch"]) {
		// Unique patch that converts frame 2 (previous frame) to frame 3
		// F0003.patch

		NSData *patchData = entryData;

		frameData = [MovieArchive patchFrame:prevFrameData patchData:patchData];
	} else if ([ext isEqualToString:@"rpatch"]) {
		// A repeated patch is the same as a regular patch except that it
		// will be applied again in the future. Save the patch data
		// in an array with an integer index.

		NSData *patchData = entryData;

		frameData = [MovieArchive patchFrame:prevFrameData patchData:patchData];

		[rpatchDataObjs addObject:patchData];
		assert([rpatchDataObjs count] > 0);
	} else if ([ext isEqualToString:@"rapatch"]) {
		// Repeated application of a patch, an additional
		// repeated patch index is included in the entry
		// name to indicates the rpatch seen earlier
		// that this patch duplicates.		
		//
		// F0004_1.rapatch

		NSRange underscoreRange = [root rangeOfString:@"_" options:NSLiteralSearch];
		assert(underscoreRange.location != NSNotFound);

		NSRange repeatFrameNumberRange;
		repeatFrameNumberRange.location = underscoreRange.location + 1;
		repeatFrameNumberRange.length = [root length] - underscoreRange.location - 1;
		NSString *repeatFrameNumberRangeStr = [root substringWithRange:repeatFrameNumberRange];			

		int repIndex = [repeatFrameNumberRangeStr intValue];
		repIndex--;

		assert([rpatchDataObjs count] > 0);
		NSData *repeatedPatchData = [rpatchDataObjs objectAtIndex:repIndex];

		frameData = [MovieArchive patchFrame:prevFrameData patchData:repeatedPatchData];		
	} else {
		assert(0);
	}

	self.prevFrameData = frameData;

	[pool release];

	return frameData;
}

- (MovieFrame*) nextMovieFrame
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSString *thisEntryFilename = [archive readEntryFilename];
	if (thisEntryFilename == nil || [thisEntryFilename length] == 0) {
		// EOF
		[pool release];
		return nil;
	}

	self->frameIndex++;

	NSData *entryData = [archive readEntryData];

	MovieFrame *movieFrameObj = nil;
	NSData *keyframeData = nil;
	NSData *patchData = nil;

	NSString *tail = [thisEntryFilename lastPathComponent];
	
#ifdef LOGGING
	NSLog([NSString stringWithFormat:@"read %@ from archive", tail]);
#endif
	
	// Find file extension, split into ROOT.EXT
	
	NSRange dotRange = [tail rangeOfString:@"." options:NSBackwardsSearch];
	
	if (dotRange.location == NSNotFound) {
		NSString *msg = [NSString stringWithFormat:@"entry filename must have a suffix \"%@\"", tail];
		NSLog(msg);
		assert(FALSE);
	}
	
	NSRange extRange;
	extRange.location = dotRange.location + 1;
	extRange.length = [tail length] - dotRange.location - 1;
	NSString *ext = [tail substringWithRange:extRange];
	
	NSRange rootRange;
	rootRange.location = 0;
	rootRange.length = dotRange.location;		
	NSString *root = [tail substringWithRange:rootRange];
	
	// Verify that the frame number string matches the frame number we expect
	// to find next. For example, examine the first 5 characters of "F0003.dup"
	// and compare to "F0003".
	
	NSRange frameNumberRange;
	frameNumberRange.location = 0;
	frameNumberRange.length = 1 + 4;
	NSString *frameNumberStr = [root substringWithRange:frameNumberRange];
	
	NSString *expectedFrameNumberStr;
	if (frameIndex == 0) {
		// Special case for header entry, read "F0000.hdr" in first invocation,
		// then read "F0001.rle" in second invocation.
		
		NSString *expectedFrameNumberStr1 = @"F0000";
		NSString *expectedFrameNumberStr2 = @"F0001";
		
		assert([frameNumberStr isEqualToString:expectedFrameNumberStr1] ||
			   [frameNumberStr isEqualToString:expectedFrameNumberStr2]);
	} else {
		expectedFrameNumberStr = [NSString stringWithFormat:@"F%04d", frameIndex+1];
		assert([frameNumberStr isEqualToString:expectedFrameNumberStr]);
	}

	// Handle entry type based on file extension

	if ([ext isEqualToString:@"hdr"]) {
		// Movie header
		// F0000.hdr

		NSData *headerData = entryData;

		CGSize dimensions = [MovieArchive decodeMovieHeaderDimensions:headerData];

		self->width = dimensions.width;
		self->height = dimensions.height;
		
		// Read MD5 generated from original RLE encoded data
		
		[self decodeMovieHeaderOutputMD5:headerData];

		self->patchBufferNumWords = [self decodeMovieHeaderPatchBufferNumWords:headerData];
		self->frameBufferNumWords = [self decodeMovieHeaderFrameBufferNumWords:headerData];
		
		// Once header has been handled, invoke this method again so
		// the the first frame's data is returned by the first
		// invocation of this method.
		
		self->frameIndex--;
		
		[pool release];

		return [self nextMovieFrame];
	} else if ([ext isEqualToString:@"rle"]) {
		// Keyframe:
		// F0001.rle

		keyframeData = entryData;
	} else if ([ext isEqualToString:@"dup"]) {
		// Duplicate of previous frame (frame 2 duplicates frame 1)
		// F0002.dup

		movieFrameObj = prevMovieFrame;
	} else if ([ext isEqualToString:@"patch"]) {
		// Unique patch that converts frame 2 (previous frame) to frame 3
		// F0003.patch

		patchData = entryData;
	} else if ([ext isEqualToString:@"rpatch"]) {
		// A repeated patch is the same as a regular patch except that it
		// will be applied again in the future. Save the patch data
		// in an array with an integer index.

		patchData = entryData;
		
		[rpatchDataObjs addObject:patchData];
		assert([rpatchDataObjs count] > 0);		
	} else if ([ext isEqualToString:@"rapatch"]) {
		// Patch (same as above) except the patch data exactly
		// dupliates patch data read in previously. The number
		// that follows the underscore indicates which patch
		// this one duplicates.
		//
		// F0004_1.rapatch

		// Parse repeated patch index
		
		NSRange underscoreRange = [root rangeOfString:@"_" options:NSLiteralSearch];
		assert(underscoreRange.location != NSNotFound);
		
		NSRange repeatFrameNumberRange;
		repeatFrameNumberRange.location = underscoreRange.location + 1;
		repeatFrameNumberRange.length = [root length] - underscoreRange.location - 1;
		NSString *repeatFrameNumberRangeStr = [root substringWithRange:repeatFrameNumberRange];			
		
		int repIndex = [repeatFrameNumberRangeStr intValue];
		repIndex--;

		assert([rpatchDataObjs count] > 0);
		patchData = [rpatchDataObjs objectAtIndex:repIndex];
	} else {
		assert(0);
	}

	if (movieFrameObj != nil) {
		// no-op for duplicate frame, reuse same MovieFrame
	} else if (keyframeData != nil) {
		movieFrameObj = [MovieFrame movieKeyframe:keyframeData];
	} else if (patchData != nil) {
		movieFrameObj = [MovieFrame movieFrame:patchData];
	} else {
		assert(FALSE);
	}

	self.prevMovieFrame = movieFrameObj;

	[pool release];

	return movieFrameObj;
}


+ (NSData*) patchFrame:(NSData*)frameData patchData:(NSData*)patchData
{
	assert(frameData != nil && [frameData length] > 0);
	assert(patchData != nil && [patchData length] > 0);

	NSData *patchedFrameData = memory_diff_or_patch(frameData, nil, patchData, TRUE);
	assert(patchedFrameData != nil && [patchedFrameData length] > 0);
	
	return patchedFrameData;
}

+ (NSData*) formatMovieHeaderData:(CGSize)dimensions
					   rleMD5Data:(NSData*)rleMD5Data
			  patchBufferNumWords:(uint32_t)inPatchBufferNumWords
			  frameBufferNumWords:(uint32_t)inFrameBufferNumWords
{
	int width = dimensions.width;
	int height = dimensions.height;

	NSAssert(width > 0 && width <= 1024, @"width must be 1024 or less");
	NSAssert(height > 0 && height <= 1024, @"height must be 1024 or less");

	NSData *width_data = [EasyArchive encodeShortInt:(uint16_t)width];
	NSData *height_data = [EasyArchive encodeShortInt:(uint16_t)height];

	NSData *patchBufferNumWordsData = [EasyArchive encodeInt:inPatchBufferNumWords];
	NSData *frameBufferNumWordsData = [EasyArchive encodeInt:inFrameBufferNumWords];	

	NSMutableData *header = [NSMutableData dataWithCapacity:64];

	[header appendData:width_data];
	[header appendData:height_data];

	NSAssert([rleMD5Data length] == 32, @"expected 32bytes of md5 data");
	[header appendData:rleMD5Data];

	[header appendData:patchBufferNumWordsData];
	[header appendData:frameBufferNumWordsData];

	NSAssert([header length] == (2 + 2 + 32 + 4 + 4), @"expected 44 header bytes");

	return [NSData dataWithData:header];
}

+ (CGSize) decodeMovieHeaderDimensions:(NSData*)headerData
{
	NSRange widthRange;
	widthRange.location = 0;
	widthRange.length = 2;

	NSData *widthData = [headerData subdataWithRange:widthRange];
	uint16_t width = [EasyArchive decodeShortInt:widthData];

	NSRange heightRange;
	heightRange.location = 2;
	heightRange.length = 2;

	NSData *heightData = [headerData subdataWithRange:heightRange];
	uint16_t height = [EasyArchive decodeShortInt:heightData];

	CGSize dimensions;
	dimensions.width = width;
	dimensions.height = height;
	return dimensions;
}

+ (NSData*) calcMD5ForData:(NSArray*)dataObjs
{
	CC_MD5_CTX ctxt;
	CC_MD5_CTX *ctxtPtr = &ctxt;
	CC_MD5_Init(ctxtPtr);

	for (NSData *data in dataObjs) {
		CC_MD5_Update(ctxtPtr, [data bytes], [data length]);
	}

	NSData *md5 = [EasyArchive _finishMD5:ctxtPtr];

	return md5;
}

- (void) updateOutputMD5:(NSData*)data
{
	if (!isMD5InArchive)
		return;

	if (ctxtNeedsInit) {
		CC_MD5_Init(&self->ctxt);
		self->ctxtNeedsInit = FALSE;
	}

	CC_MD5_Update(&self->ctxt, [data bytes], [data length]);
}

- (BOOL) validateOutputMD5
{
	if (!isMD5InArchive)
		return FALSE;

	NSData *calcOutputMD5 = [EasyArchive _finishMD5:&self->ctxt];

	NSData *emptyMD5 = [NSMutableData dataWithLength:32];

	if ([calcOutputMD5 isEqualToData:emptyMD5])
		return FALSE;

	return [outputMD5 isEqualToData:calcOutputMD5];
}

// Read MD5 generated from original RLE encoded data

- (void) decodeMovieHeaderOutputMD5:(NSData*)headerData
{
	NSRange widthRange;
	widthRange.location = 4;
	widthRange.length = 32;

	self.outputMD5 = [headerData subdataWithRange:widthRange];

	NSData *emptyMD5 = [NSMutableData dataWithLength:32];

	// Calculate an MD5 for generated RLE data if there is a
	// non-zero MD5 in the archive.

	if (![outputMD5 isEqualToData:emptyMD5])
		self->isMD5InArchive = TRUE;

	return;
}

// Read MD5 generated from original RLE encoded data

- (uint32_t) decodeMovieHeaderPatchBufferNumWords:(NSData*)headerData
{
	NSRange patchBufferRange;
	patchBufferRange.location = 36;
	patchBufferRange.length = 4;

	NSData *numWords = [headerData subdataWithRange:patchBufferRange];
	return [EasyArchive decodeInt:numWords];
}

- (uint32_t) decodeMovieHeaderFrameBufferNumWords:(NSData*)headerData
{
	NSRange frameBufferRange;
	frameBufferRange.location = 40;
	frameBufferRange.length = 4;

	NSData *numWords = [headerData subdataWithRange:frameBufferRange];
	return [EasyArchive decodeInt:numWords];
}

@end // class MovieArchive


// Linked binary diff impl

#include "xdiff.h"

#define XDLT_STD_BLKSIZE (1024 * 8)

static void *wrap_malloc(void *priv, unsigned int size) {	
	return malloc(size);
}

static void wrap_free(void *priv, void *ptr) {
	free(ptr);
}

static void *wrap_realloc(void *priv, void *ptr, unsigned int size) {	
	return realloc(ptr, size);
}

static int wasLibXdiffInitialized = 0;

static
inline
void init_xdiff_library()
{
	// init the library, in the odd case of a thread race condition,
	// the xdl_set_allocator wil lbe invoked twice but it will not matter.

	if (!wasLibXdiffInitialized) {
		memallocator_t malt;

		malt.priv = NULL;
		malt.malloc = wrap_malloc;
		malt.free = wrap_free;
		malt.realloc = wrap_realloc;
		xdl_set_allocator(&malt);

		wasLibXdiffInitialized = 1;
	}
}

// Apply a patch to a file contained in memory, the output file is
// stored in memory.

int xdlt_load_mmbuffer(char *data, int data_length, mmfile_t *mf)
{
	long flags = XDL_MMF_ATOMIC;

#ifdef IGNORE_ADLER_IN_PATCHES
	flags |= XDL_MMF_IGNORE_ADLER;
#endif // IGNORE_ADLER_IN_PATCHES

	if (xdl_init_mmfile(mf, XDLT_STD_BLKSIZE, flags) < 0) {
		return -1;
	}

	long numBytesAdded = xdl_mmfile_ptradd(mf, data, data_length, XDL_MMB_READONLY);

	if (numBytesAdded == -1) {
		xdl_free_mmfile(mf);
		return -1;
	}

	return 0;
}

typedef struct OutBuffer {
	char *buffer;
	int size;
	int offset;
} OutBuffer;

static int xdlt_outbuffer(void *priv, mmbuffer_t *mb, int nbuf) {
	int i;
	
	OutBuffer *privOutBuffer = (OutBuffer *)priv;
	
	for (i = 0; i < nbuf; i++) {
		if (privOutBuffer->offset >= privOutBuffer->size)
			return -1;

		memcpy(privOutBuffer->buffer + privOutBuffer->offset, mb[i].ptr, mb[i].size);
		privOutBuffer->offset += mb[i].size;
	}
	
	return 0;
}

// Apply a patch and return the buffer the bytes were
// written into. The user can suggest the use of
// the buffer use_buffer, if it is too small then
// malloc will be invoked to create a new buffer.
// The wrote_bytes argument returns the number
// of bytes written to the buffer.

char*
xdiff_apply_patch(char *from_file_buffer, int from_file_len,
			char *patch_file_buffer, int patch_file_len,
			char *use_buffer, int *use_or_wrote_bytes)
{
	xdemitcb_t ecb;
	mmfile_t mf1, mf2;
	OutBuffer *obPtr;
	int result;

	init_xdiff_library();

	result = xdlt_load_mmbuffer(from_file_buffer, from_file_len, &mf1);
	if (result < 0) {
		return nil;
	}
	
	result = xdlt_load_mmbuffer(patch_file_buffer, patch_file_len, &mf2);
	if (result < 0) {
		xdl_free_mmfile(&mf1);
		return nil;
	}

	obPtr = (OutBuffer*) malloc(sizeof(OutBuffer));
	obPtr->size = xdl_bdiff_tgsize(&mf2);
	if (use_buffer != NULL) {
		// Caller suggest a buffer to use, use it if it
		// is large enough.

		if (obPtr->size <= *use_or_wrote_bytes) {
			obPtr->buffer = use_buffer;			
		} else {
			obPtr->buffer = malloc(obPtr->size);
		}
	} else {
		obPtr->buffer = malloc(obPtr->size);
	}
	obPtr->offset = 0;

	ecb.priv = obPtr;
	ecb.outf = xdlt_outbuffer;
	
	if (xdl_bpatch(&mf1, &mf2, &ecb) < 0) {
		free(obPtr->buffer);
		free(obPtr);
		xdl_free_mmfile(&mf2);
		xdl_free_mmfile(&mf1);
		return nil;
	}
	
	xdl_free_mmfile(&mf2);
	xdl_free_mmfile(&mf1);

	// Create a NSData object that contains the bytes we just allocated
	// and filled. The data should not be modified after this point
	// since it is now owned as a read only value.

	assert(obPtr->size == obPtr->offset);

	char *retBuffer = obPtr->buffer;
	*use_or_wrote_bytes = obPtr->size;

	//obPtr->buffer = NULL;
	free(obPtr);

	return retBuffer;
}

// apply patch to data file to generate new data file

NSData* in_memory_patch(NSData *from_file_data, NSData *patch)
{
	char *from_file_buffer = (char*) [from_file_data bytes];
	int from_file_len = [from_file_data length];

	char *patch_file_buffer = (char*) [patch bytes];
	int patch_file_len = [patch length];

	int wrote_bytes;

	char *patchedData = xdiff_apply_patch(from_file_buffer, from_file_len,
									  patch_file_buffer, patch_file_len,
									  NULL, &wrote_bytes);

	NSData *data = [NSData dataWithBytesNoCopy:patchedData length:wrote_bytes];

	return data;
}

NSData*
create_patch(char *from_file_buffer, int from_file_len,
			 char *to_file_buffer, int to_file_len)
{
	xdemitcb_t ecb;
	mmfile_t mf1, mf2;
	OutBuffer *obPtr;
	int result;
	
	result = xdlt_load_mmbuffer(from_file_buffer, from_file_len, &mf1);
	if (result < 0) {
		return nil;
	}
	
	result = xdlt_load_mmbuffer(to_file_buffer, to_file_len, &mf2);
	if (result < 0) {
		xdl_free_mmfile(&mf1);
		return nil;
	}

	obPtr = (OutBuffer*) malloc(sizeof(OutBuffer));
	obPtr->size = from_file_len; // handle worst case
	if (obPtr->size < to_file_len)
		obPtr->size = to_file_len;

	obPtr->buffer = malloc(obPtr->size);
	obPtr->offset = 0;

	ecb.priv = obPtr;
	ecb.outf = xdlt_outbuffer;

	// FIXME: diff vs rabdiff
	
	if (xdl_rabdiff(&mf1, &mf2, &ecb) < 0) {
		xdl_free_mmfile(&mf2);
		xdl_free_mmfile(&mf1);
		return nil;
	}
	
	xdl_free_mmfile(&mf2);
	xdl_free_mmfile(&mf1);

	NSData *data = [NSData dataWithBytes:obPtr->buffer length:obPtr->offset];

	free(obPtr->buffer);
	free(obPtr);
	
	return data;
}

// create patch from file1 to file2

NSData* in_memory_diff(NSData *from_file_data, NSData *to_file_data)
{
	char *from_file_buffer = (char*) [from_file_data bytes];
	int from_file_len = [from_file_data length];

	char *to_file_buffer = (char*) [to_file_data bytes];
	int to_file_len = [to_file_data length];

	NSData *patchData = create_patch(from_file_buffer, from_file_len,
									to_file_buffer, to_file_len);

	return patchData;
}
	
NSData* exec_diff_or_patch(NSString *frame1, NSString *frame2, NSString *delta_path, int isPatch)
{
	NSData *frame1Data = [NSData dataWithContentsOfFile:frame1];
	NSData *frame2Data = nil;
	NSData *patchData = nil;

	if (!isPatch)
		frame2Data = [NSData dataWithContentsOfFile:frame2];
	else
		patchData = [NSData dataWithContentsOfFile:delta_path];	

	return memory_diff_or_patch(frame1Data, frame2Data, patchData, isPatch);
}

NSData* memory_diff_or_patch(NSData *frame1, NSData *frame2, NSData *delta, int isPatch)
{
	// frame1 and frame2 contain RLE ecoded data

	init_xdiff_library();

	if (isPatch) {
		NSData *data2 = in_memory_patch(frame1, delta);
		return data2;
	} else {
		// create patch by computing delta between frame1 and frame2

		NSData *patchData = in_memory_diff(frame1, frame2);
		return patchData;
	}
}

