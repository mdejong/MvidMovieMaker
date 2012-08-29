//
//  FlatMovieFile.m
//  ImageSeqMovieMaker
//
//  Created by Moses DeJong on 3/15/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "FlatMovieFile.h"

#import "MovieArchive.h"

#define LOG_MISSED_BUFFER_USAGE

// defined in MovieArchive.m

char*
xdiff_apply_patch(char *from_file_buffer, int from_file_len,
				  char *patch_file_buffer, int patch_file_len,
				  char *use_buffer, int *use_or_wrote_bytes);	

#define FLAT_MOVIE_KEYFRAME_TYPE16 0xFACE
#define FLAT_MOVIE_PATCH_TYPE16 0xC0DE
#define FLAT_MOVIE_DUP_TYPE16 0xCAFE

typedef struct FlatMovieHeader {
	uint16_t width;
	uint16_t height;
	uint16_t numFrames;
	uint16_t numKeyframes;
	uint32_t patchBufferNumWords;
	uint32_t frameBufferNumWords;
} FlatMovieHeader;

typedef struct FlatMovieKeyFrame {
	uint16_t type;
	uint16_t frameIndexOfNextKeyframe;
	off_t offsetOfNextKeyframe;
	uint32_t numBytesInFrameData;
	char *frameData;
} FlatMovieKeyFrame;

// No read/write of frameData

#define FLAT_MOVIE_KEY_FRAME_READWRITE_BYTES (sizeof(FlatMovieKeyFrame) - sizeof(char*))

typedef struct FlatMoviePatchFrame {
	uint16_t type;
	uint16_t pad16;
	uint32_t numBytesInPatchData;
	char *patchData;
} FlatMoviePatchFrame;

// No read/write of numBytesInFrameData, frameData, and patchData fields

#define FLAT_MOVIE_PATCH_FRAME_READWRITE_BYTES \
	(sizeof(FlatMoviePatchFrame) - sizeof(char*))

// A FlatMovieTypeFrame is used to query the type value
// from a word of memory without knowing if the word
// of memory will be the start of a FlatMovieKeyFrame
// or a FlatMoviePatchFrame.

typedef struct FlatMovieTypeFrame {
	uint16_t type;
	uint16_t pad16;
} FlatMovieTypeFrame;

// A common frame is saved in the prevFrame
// slot in a FlatMovieFile object. It
// contains the frame data generated from
// either a patch frame or a keyframe.
// A common frame is never read or written
// from disk, it only exists in memory.

typedef struct FlatMovieCommonFrame {
	uint16_t type;
	uint16_t pad16;

	uint32_t numBytesInFrameData;
	char *frameData;
	uint8_t isFrameDataLocked;
	uint8_t pad8;

	uint16_t frameIndexOfNextKeyframe;
	off_t    offsetOfNextKeyframe;
} FlatMovieCommonFrame;


static
inline
void fwrite_words(char *data, uint32_t numBytes, FILE *flatFILE) {
	int numBytesOverWordBoundry = numBytes % 4;
	int numBytesUnderWordBoundry = (numBytesOverWordBoundry == 0) ? 0 : (4 - numBytesOverWordBoundry);

	int numBytesToPad = numBytesUnderWordBoundry;
	int numBytesPadded;
	int numBytesWritten;
	char zeros[4] = { 0, 0, 0, 0 };

	int numWords = numBytes / 4;
	if (numBytesOverWordBoundry > 0) {
		numWords++;
	}

	assert(((numBytes + numBytesToPad) % 4) == 0);

	numBytesWritten = fwrite(data, 1, numBytes, flatFILE);
	assert(numBytesWritten == numBytes);
	numBytesPadded = fwrite(&zeros[0], 1, numBytesToPad, flatFILE);
	assert(numBytesPadded == numBytesToPad);
	numBytesWritten += numBytesPadded;
	assert(numBytesWritten == (numWords * sizeof(int)));
}

// Read a number of bytes, this logic assumes that the bytes
// have been zero padded out to a whole number of words.
// Returns the number of bytes read.

static
inline
int fread_words(char *data, uint32_t numBytes, FILE *flatFILE) {
	int numBytesOverWordBoundry = numBytes % 4;
	int numBytesUnderWordBoundry = (numBytesOverWordBoundry == 0) ? 0 : (4 - numBytesOverWordBoundry);
	int numBytesInWords = numBytes + numBytesUnderWordBoundry;

	assert(data);
	assert((numBytesInWords % 4) == 0);

	int numBytesRead = fread(data, 1, numBytesInWords, flatFILE);

	assert(numBytesRead == numBytesInWords);

	return numBytes;
}

static
inline
int num_words(uint32_t numBytes)
{
	int numBytesOverWordBoundry = numBytes % 4;
	int numWords = numBytes / 4;
	if (numBytesOverWordBoundry > 0)
		numWords++;
	return numWords;
}

static
inline
void read_keyframe_data(FlatMovieFile *flatMovieFilePtr, FlatMovieKeyFrame *flatKeyFramePtr) {
	FILE *flatFILE = flatMovieFilePtr->flatFILE;

	// Read a whole number of words from the flat movie into the frame buffer

	int numWordsToRead = num_words(flatKeyFramePtr->numBytesInFrameData);

	if (numWordsToRead > flatMovieFilePtr->numWordsFrameBuffer) {
		// Handle an input keyframe data chunk that is larger than
		// the common size

#ifdef LOG_MISSED_BUFFER_USAGE
		NSLog([NSString stringWithFormat:
			   @"keyframe of size %d bytes is too large to fit in cached buffer of size %d bytes",
			   numWordsToRead*4,
			   flatMovieFilePtr->numWordsFrameBuffer*4]);
#endif // LOG_MISSED_BUFFER_USAGE

		flatKeyFramePtr->frameData = malloc(numWordsToRead * sizeof(int));

		fread_words(flatKeyFramePtr->frameData,
					flatKeyFramePtr->numBytesInFrameData, flatFILE);
	} else {
		// The keyframe data fits inside the default frame buffer,
		// any time we read a keyframe we know that both frame
		// buffers should be unlocked.

		assert(flatMovieFilePtr->isFrameBuffer1Locked == FALSE);
		assert(flatMovieFilePtr->isFrameBuffer2Locked == FALSE);

		flatMovieFilePtr->isFrameBuffer1Locked = TRUE;

		fread_words(flatMovieFilePtr->frameBuffer1,
					flatKeyFramePtr->numBytesInFrameData, flatFILE);

		flatKeyFramePtr->frameData = flatMovieFilePtr->frameBuffer1;
	}

	return;
}

// Invoke this method when done with a keyframe, it takes care of
// the edge case where the data for a kayframe is larger than
// theinput buffer size.

/*
static
inline
void
cleanup_keyframe(FlatMovieFile *flatMovieFilePtr, FlatMovieKeyFrame *flatKeyFramePtr)
{
	if (flatKeyFramePtr->frameData != flatMovieFilePtr->frameBuffer) {
		free(flatKeyFramePtr->frameData);
	} else {
		assert(flatMovieFilePtr->isFrameBufferLocked == TRUE);
		flatMovieFilePtr->isFrameBufferLocked = FALSE;
	}
	flatKeyFramePtr->frameData = NULL;
}
*/

static
inline
void read_patchframe(FlatMovieFile *flatMovieFilePtr, FlatMoviePatchFrame *flatPatchFramePtr) {
	FILE *flatFILE = flatMovieFilePtr->flatFILE;

	// Read a whole number of words from the flat movie into the patch buffer

	int numWordsToRead = num_words(flatPatchFramePtr->numBytesInPatchData);

	if (numWordsToRead > flatMovieFilePtr->numWordsPatchBuffer) {
		// This patch data buffer is too large to fit into
		// the input buffer.

#ifdef LOG_MISSED_BUFFER_USAGE
		NSLog([NSString stringWithFormat:
			   @"patch of size %d bytes is too large to fit in cached buffer of size %d bytes",
			   numWordsToRead*4,
			   flatMovieFilePtr->numWordsPatchBuffer*4]);
#endif // LOG_MISSED_BUFFER_USAGE		

		flatPatchFramePtr->patchData = malloc(numWordsToRead * sizeof(int));

		fread_words(flatPatchFramePtr->patchData,
					flatPatchFramePtr->numBytesInPatchData, flatFILE);
	} else {
		// The patch data fits in the patch buffer

		assert(flatMovieFilePtr->isPatchBufferLocked == FALSE);
		flatMovieFilePtr->isPatchBufferLocked = TRUE;

		fread_words(flatMovieFilePtr->patchBuffer,
					flatPatchFramePtr->numBytesInPatchData, flatFILE);

		flatPatchFramePtr->patchData = flatMovieFilePtr->patchBuffer;
	}
	
	return;
}

// Invoke this method when finished with the patch application
// process. The patch data is not needed once a patch has
// been applied so release it if needed.

static
inline
void
cleanup_patchframe(FlatMovieFile *flatMovieFilePtr, FlatMoviePatchFrame *flatPatchFramePtr)
{
	if (flatPatchFramePtr->patchData != flatMovieFilePtr->patchBuffer) {
		free(flatPatchFramePtr->patchData);
	} else {
		assert(flatMovieFilePtr->isPatchBufferLocked == TRUE);
		flatMovieFilePtr->isPatchBufferLocked = FALSE;
	}
	flatPatchFramePtr->patchData = NULL;
}

static
inline
void
cleanup_commonframe(FlatMovieFile *flatMovieFilePtr, FlatMovieCommonFrame *flatCommonFramePtr)
{
	if (flatCommonFramePtr->type == 0) {
		// init state

		return;
	}

	if (flatCommonFramePtr->isFrameDataLocked) {
		// Could be either of the frame buffers

		if (flatCommonFramePtr->frameData == flatMovieFilePtr->frameBuffer1) {
			assert(flatMovieFilePtr->isFrameBuffer1Locked == TRUE);
			flatMovieFilePtr->isFrameBuffer1Locked = FALSE;
		} else if (flatCommonFramePtr->frameData == flatMovieFilePtr->frameBuffer2) {
			assert(flatMovieFilePtr->isFrameBuffer2Locked == TRUE);
			flatMovieFilePtr->isFrameBuffer2Locked = FALSE;
		} else {
			assert(0);
		}
	} else {
		// Not a common frame buffer, buffer was allocated with malloc()
		free(flatCommonFramePtr->frameData);
	}
}

// Read a word from the flat movie file, return the type found in the
// word and store the word at nextWordPtr. The user would later
// invoke 

static
inline
uint16_t read_next_word_type(FlatMovieFile *flatMovieFilePtr, uint32_t *nextWordPtr) {
	int numBytesRead = fread(nextWordPtr, 1, sizeof(uint32_t), flatMovieFilePtr->flatFILE);
	assert(numBytesRead == sizeof(uint32_t));
	FlatMovieTypeFrame *flatTypeFrame = (FlatMovieTypeFrame*) nextWordPtr;
	return flatTypeFrame->type;
}

static
inline
void finish_read_next_word_type(FlatMovieFile *flatMovieFilePtr,
								uint32_t *nextWordPtr,
								void *framePtr)
{
	char *ptr = (char *)framePtr;
	memcpy(ptr, nextWordPtr, sizeof(int));

	FlatMovieTypeFrame *flatTypeFrame = (FlatMovieTypeFrame*) nextWordPtr;
	uint16_t type = flatTypeFrame->type;

	int numBytesToRead, numBytesRead;

	if (type == FLAT_MOVIE_PATCH_TYPE16) {
		numBytesToRead = FLAT_MOVIE_PATCH_FRAME_READWRITE_BYTES - sizeof(int);
	} else if (type == FLAT_MOVIE_KEYFRAME_TYPE16) {
		numBytesToRead = FLAT_MOVIE_KEY_FRAME_READWRITE_BYTES - sizeof(int);
	} else {
		assert(0);
	}

	ptr += sizeof(int);
	numBytesRead = fread(ptr, 1, numBytesToRead, flatMovieFilePtr->flatFILE);
	assert(numBytesRead == numBytesToRead);
}

// Given a ref to the previous frame, read a patch from the stream,
// apply the delta, and then set the prevFrame to the result of
// the patch operation.

static
inline
void applyPatch(FlatMovieFile *flatMovieFilePtr,
				uint32_t *nextWordPtr,
				FlatMovieCommonFrame *prevFramePtr)
{
	// Finish reading the rest of the patch data from the stream

	FlatMoviePatchFrame flatPatchFrame;

	finish_read_next_word_type(flatMovieFilePtr, nextWordPtr, &flatPatchFrame);

	read_patchframe(flatMovieFilePtr, &flatPatchFrame);
	
	// Get buffer that will contain the output of the patch operation
	
	char *patchedDataBuffer;
	int patchedDataBufferLen = flatMovieFilePtr->numWordsFrameBuffer * sizeof(int);
	int lockedWhichBuffer;
	
	if (!flatMovieFilePtr->isFrameBuffer1Locked) {
		patchedDataBuffer = flatMovieFilePtr->frameBuffer1;
		flatMovieFilePtr->isFrameBuffer1Locked = TRUE;
		lockedWhichBuffer = 1;
	} else if (!flatMovieFilePtr->isFrameBuffer2Locked) {
		patchedDataBuffer = flatMovieFilePtr->frameBuffer2;
		flatMovieFilePtr->isFrameBuffer2Locked = TRUE;
		lockedWhichBuffer = 2;
	} else {
		// Both buffers can't be locked
		assert(0);
	}

	// Apply patch data to the previous frame buffer data

	char *prevFrameData = prevFramePtr->frameData;
	int prevFrameDataLength = prevFramePtr->numBytesInFrameData;
	
	char *patchDataBytes = flatPatchFrame.patchData;
	int patchDataLength = flatPatchFrame.numBytesInPatchData;
	
	// FIXME: likely not needed

	assert(prevFrameData);
	assert(patchDataBytes);
	assert(patchedDataBuffer);

	char *patched_data = xdiff_apply_patch(prevFrameData, prevFrameDataLength,
										   patchDataBytes, patchDataLength,
										   patchedDataBuffer, &patchedDataBufferLen);

	assert(patched_data);

	// If the buffer we passed was used, then the patched_data will be the same
	// as patchedDataBuffer. If a larger buffer was allocated because the
	// patched data would not fit, then that buffer would be returned.
	// either way, the number of bytes written is returned in patchedDataBufferLen
	
	if (patched_data == patchedDataBuffer) {
		// wrote patched data to the locked buffer, all is well
	} else {
		// had to allocate a new buffer for patch data that was very
		// large. Unlock the buffer that we just locked above.
		
		if (lockedWhichBuffer == 1) {
			flatMovieFilePtr->isFrameBuffer1Locked = FALSE;
		} else {
			flatMovieFilePtr->isFrameBuffer2Locked = FALSE;					
		}
		lockedWhichBuffer = -1;
	}
	
	// Release the patch data
	
	cleanup_patchframe(flatMovieFilePtr, &flatPatchFrame);
	
	// Release contents of previous frame, this deallocates
	// any memory held by the struct, but it does not
	// null out the contents.
	
	cleanup_commonframe(flatMovieFilePtr, prevFramePtr);
	
	// The contents of prevFrame are now updated, take note
	// of what is not done here. The frameIndexOfNextKeyframe
	// and nextKeyframeOffset are not changed because they
	// are retained from one frame to the next.
	
	prevFramePtr->type = flatPatchFrame.type;
	prevFramePtr->numBytesInFrameData = patchedDataBufferLen;
	prevFramePtr->frameData = patched_data;
	
	prevFramePtr->isFrameDataLocked = (lockedWhichBuffer > 0);
}

// Load the next keyframe by reading data from the stream
// and saving it as prevFrame. This method assumes that
// the caller has already invoked cleanup_commonframe()
// to release the previous frame data.

static
inline
void loadKeyframe(FlatMovieFile *flatMovieFilePtr,
				uint32_t *nextWordPtr,
				FlatMovieCommonFrame *prevFramePtr)	
{	
	FlatMovieKeyFrame flatMovieKeyFrame;
	memset(&flatMovieKeyFrame, 0, sizeof(FlatMovieKeyFrame));

	finish_read_next_word_type(flatMovieFilePtr, nextWordPtr, &flatMovieKeyFrame);
	
	// Read data for keyframe into frame buffer 1
	
	read_keyframe_data(flatMovieFilePtr, &flatMovieKeyFrame);
	
	// Convert to FlatMovieCommonFrame and save in prevFrame

	FlatMovieCommonFrame commonFrame;
	memset(&commonFrame, 0, sizeof(FlatMovieCommonFrame));

	commonFrame.type = flatMovieKeyFrame.type;
	commonFrame.numBytesInFrameData = flatMovieKeyFrame.numBytesInFrameData;
	commonFrame.frameData = flatMovieKeyFrame.frameData;
	
	// read_keyframe_data() will only ever lock frame buffer 1
	
	commonFrame.isFrameDataLocked = flatMovieFilePtr->isFrameBuffer1Locked;
	
	// Update the frameIndexOfNextKeyframe and nextKeyframeOffset fields
	// in the common frame struct. These values are retained as frames
	// are patched so that we can always figure out where to seek to
	// when we want the next keyframe.

	commonFrame.frameIndexOfNextKeyframe = flatMovieKeyFrame.frameIndexOfNextKeyframe;
	commonFrame.offsetOfNextKeyframe = flatMovieKeyFrame.offsetOfNextKeyframe;

	memcpy(prevFramePtr, &commonFrame, sizeof(FlatMovieCommonFrame));	
}

@implementation FlatMovieFile

@synthesize isOpen;

- (id) init
{
	// Allocate a FlatMovieFakeFrame on the heap so that
	// invalid writing bounds is detected by debug malloc

	void *buf = malloc(sizeof(FlatMovieFakeFrame));	
	if (buf == NULL)
		return nil;

	self = [super init];
	if (self == nil)
		return nil;

	self->prevFrame = buf;
	memset(buf, 0, sizeof(FlatMovieFakeFrame));

	self->frameIndex = -1;

	return self;
}

- (void) _allocatePatchBuffer:(NSUInteger)numWords
{
	void *buf = malloc(numWords * sizeof(int));
	assert(buf);

	self->patchBuffer = buf;
	self->numWordsPatchBuffer = numWords;

	return;
}

- (void) _allocateFrameBuffer:(NSUInteger)numWords
{
	self->numWordsFrameBuffer = numWords;

	self->frameBuffer1 = malloc(numWords * sizeof(int));
	assert(self->frameBuffer1);

	self->frameBuffer2 = malloc(numWords * sizeof(int));
	assert(self->frameBuffer2);
	
	return;
}

- (void) dealloc
{
	if (flatFILE != NULL)
		[self close];
	if (header != NULL)
		free(header);
	if (patchBuffer != NULL)
		free(patchBuffer);
	if (frameBuffer1 != NULL)
		free(frameBuffer1);
	if (frameBuffer2 != NULL)
		free(frameBuffer2);
	if (prevFrame != NULL)
		free(prevFrame);
	[super dealloc];
}	

+ (BOOL) flattenMovie:(MovieArchive*)mArchive flatMoviePath:(NSString*)flatMoviePath
{	
	// A flat movie is a data file that contains all
	// the patch and keyframe data in order that the
	// frames will be played. A flat file does not
	// attempt to minimize space usage, it is generated
	// at runtime from a more compact representation.
	// Instead, a flat file is designed to optimize
	// runtime execution speed. All values are word
	// aligned. The user of a flat file need not
	// read the contents of the file before hand.

	char *flatFilePath = (char*) [flatMoviePath UTF8String];
	FILE *flatFILE = fopen(flatFilePath, "w+");
	if (flatFILE == NULL) {
		char *errstr = strerror(errno);
		NSLog([NSString stringWithFormat:@"strerror \"%s\" for file with path \"%s\"",
			   errstr, flatFilePath]);

		return FALSE;
	}

// FIXME: Does opening with "w+" vs "w" make any diff in executon time?
// IF it does make a BIG diff, we could include the number of key frames
// in the movie header.

	[mArchive.archive rewind];
	
	// Write an empty header, the real header info
	// will be filled in after all the data has been
	// read from the archive.

	int numBytesWritten;

	FlatMovieHeader header;
	memset(&header, 0, sizeof(header));
	assert((sizeof(header) % 4) == 0);
	numBytesWritten = fwrite(&header, 1, sizeof(header), flatFILE);
	assert(numBytesWritten == sizeof(header));

	MovieFrame *lastMovieFrame;
	MovieFrame *movieFrame = nil;

	NSMutableArray *keyframeOffsetAndIndexPairs = [NSMutableArray arrayWithCapacity:512];

	int frameIndex = 0;

#define DOUBLE_CHECK_FLAT_WRITES

	while (TRUE) {
		NSAutoreleasePool *loop_pool = [[NSAutoreleasePool alloc] init];
		
		if (movieFrame != nil) {
			lastMovieFrame = movieFrame;
		}
		movieFrame = [mArchive nextMovieFrame];
		
		if (movieFrame == nil) {
			// EOF read from archive
			[loop_pool release];
			break;
		}

		// count number of frames, ignore header entry
		
		header.numFrames++;

		if (movieFrame.isKeyframe) {
			// Keyframe

			FlatMovieKeyFrame flatKeyFrame;
			memset(&flatKeyFrame, 0, sizeof(flatKeyFrame));

			flatKeyFrame.type = FLAT_MOVIE_KEYFRAME_TYPE16;
			flatKeyFrame.frameIndexOfNextKeyframe = 0;
			flatKeyFrame.offsetOfNextKeyframe = 0;
			flatKeyFrame.numBytesInFrameData = [movieFrame.frameData length];
			flatKeyFrame.frameData = (char*) [movieFrame.frameData bytes];

			assert(flatKeyFrame.numBytesInFrameData > 0);

			// Save file offset before writing key frame, once the
			// whole file is written offsets for specific keyframes
			// can be updated.

			off_t offset = ftello(flatFILE);
			unsigned long long offsetLL = (unsigned long long) offset;
			NSNumber *offsetNumber = [NSNumber numberWithUnsignedLongLong:offsetLL];
			NSNumber *frameIndexNumber = [NSNumber numberWithUnsignedInt:frameIndex];
			NSArray *pair = [NSArray arrayWithObjects:offsetNumber, frameIndexNumber, nil];			

			[keyframeOffsetAndIndexPairs addObject:pair];

			// Write keyframe, it is always a whole number of words

			assert((FLAT_MOVIE_KEY_FRAME_READWRITE_BYTES % 4) == 0);
			numBytesWritten = fwrite(&flatKeyFrame, 1, FLAT_MOVIE_KEY_FRAME_READWRITE_BYTES, flatFILE);
			assert(numBytesWritten == FLAT_MOVIE_KEY_FRAME_READWRITE_BYTES);

#ifdef DOUBLE_CHECK_FLAT_WRITES
			// reread what we just wrote?
#endif //DOUBLE_CHECK_FLAT_WRITES

			// Write numBytesInFrameData padded out with zero bytes to the the word size

			fwrite_words(flatKeyFrame.frameData, flatKeyFrame.numBytesInFrameData, flatFILE);
		} else {
			// Patch frame, either a plain patch frame or
			// an exact duplicate of the previous frame
			
			if (movieFrame == lastMovieFrame) {
				// The current movie frame is the exact same object
				// as the previous movie frame, this indicates that
				// this frame duplicates the previous one. In this
				// case, write a FlatMovieDupFrame word.

				FlatMovieTypeFrame typeFrame;
				memset(&typeFrame, 0, sizeof(typeFrame));
				typeFrame.type = FLAT_MOVIE_DUP_TYPE16;

				// Repeated patch frame is always 1 word

				assert(sizeof(typeFrame) == 4);
				numBytesWritten = fwrite(&typeFrame, 1, sizeof(typeFrame), flatFILE);
				assert(numBytesWritten == sizeof(typeFrame));
			} else {
				// Note that it is possible that numBytesInPatchData
				// can be zero even though the decoder does not see
				// it as a duplicate frame.

				FlatMoviePatchFrame flatPatchFrame;

				flatPatchFrame.type = FLAT_MOVIE_PATCH_TYPE16;
				flatPatchFrame.numBytesInPatchData = [movieFrame.patchData length];
				flatPatchFrame.patchData = (char *) [movieFrame.patchData bytes];
				
				// write bytes up to but not including the patch data pointer,
				// a patch frame is always a whole number of words.

				assert((FLAT_MOVIE_PATCH_FRAME_READWRITE_BYTES % 4) == 0);
				numBytesWritten = fwrite(&flatPatchFrame, 1, FLAT_MOVIE_PATCH_FRAME_READWRITE_BYTES, flatFILE);
				assert(numBytesWritten == FLAT_MOVIE_PATCH_FRAME_READWRITE_BYTES);

				// Write numBytesInPatchData bytes padded out with zero bytes to the the word size

				fwrite_words(flatPatchFrame.patchData, flatPatchFrame.numBytesInPatchData, flatFILE);
			}
		}

		frameIndex++;

		[loop_pool release];
	} // end of while (TRUE) loop

	// Done writing now, go back and write the header back over the front of the data file

	header.width = mArchive.width;
	header.height = mArchive.height;

	// header.numFrames is set above
	assert(header.numFrames > 0);

	header.numKeyframes = [keyframeOffsetAndIndexPairs count];
	assert(header.numKeyframes > 0);

	assert(mArchive.patchBufferNumWords > 0);
	assert(mArchive.frameBufferNumWords > 0);

	header.patchBufferNumWords = mArchive.patchBufferNumWords;
	header.frameBufferNumWords = mArchive.frameBufferNumWords;

	fseek(flatFILE, 0, SEEK_SET);
	numBytesWritten = fwrite(&header, 1, sizeof(header), flatFILE);
	assert(numBytesWritten == sizeof(header));

	// number and location of keyframes is now known, update
	// only when multiple keyframes exist in the file.

	if ([keyframeOffsetAndIndexPairs count] > 1) {
		NSNumber *prevOffset = nil;
		NSNumber *prevIndex = nil;

		int numKeyframeToRewrite = [keyframeOffsetAndIndexPairs count];

		for (NSArray *pair in keyframeOffsetAndIndexPairs) {
			NSNumber *keyframeOffset = [pair objectAtIndex:0];
			NSNumber *keyframeIndex = [pair objectAtIndex:1];

			if (prevOffset == nil) {
				// first keyframe
				prevOffset = keyframeOffset;
				prevIndex = keyframeIndex;
				continue;
			}

			// Calculate the delta between the previous
			// keyframe and this keyframe in terms of
			// words
			
			unsigned long long prevOffsetLL = [prevOffset unsignedLongLongValue];
			unsigned long long keyframeOffsetLL = [keyframeOffset unsignedLongLongValue];

			uint16_t keyframeIndexValue = [keyframeIndex unsignedIntValue];
			uint16_t prevIndexValue = [prevIndex unsignedIntValue];

			// Read keyframe entry currently on disk, then
			// update frameIndexOfNextKeyframe and
			// numWordsToNextKeyframe fields.

			FlatMovieKeyFrame prevKeyFrame;

			off_t prevOffsetT = (off_t) prevOffsetLL;
			int result = fseeko(flatFILE, prevOffsetT, SEEK_SET);
			assert(result == 0);

#ifdef DOUBLE_CHECK_FLAT_WRITES
			off_t currentOffsetT = ftello(flatFILE);
			assert(currentOffsetT == prevOffsetT);
#endif //DOUBLE_CHECK_FLAT_WRITES

			fread_words((char *)&prevKeyFrame, FLAT_MOVIE_KEY_FRAME_READWRITE_BYTES, flatFILE);

			assert(prevKeyFrame.type == FLAT_MOVIE_KEYFRAME_TYPE16);

#ifdef DOUBLE_CHECK_FLAT_WRITES
			uint16_t readFrameIndexOfNextKeyframe = prevKeyFrame.frameIndexOfNextKeyframe;
			off_t readOffsetOfNextKeyframe = prevKeyFrame.offsetOfNextKeyframe;

			assert(readFrameIndexOfNextKeyframe == 0);
			assert(readOffsetOfNextKeyframe == 0);
#endif //DOUBLE_CHECK_FLAT_WRITES
	
			assert(keyframeIndexValue > 0);
			prevKeyFrame.frameIndexOfNextKeyframe = keyframeIndexValue;
			assert(keyframeOffsetLL > 0);
			prevKeyFrame.offsetOfNextKeyframe = keyframeOffsetLL;

			// Write the modified keyframe header

			result = fseek(flatFILE, prevOffsetT, SEEK_SET);
			assert(result == 0);
#ifdef DOUBLE_CHECK_FLAT_WRITES
			currentOffsetT = ftello(flatFILE);
			assert(currentOffsetT == prevOffsetT);
#endif //DOUBLE_CHECK_FLAT_WRITES

			numBytesWritten = fwrite(&prevKeyFrame, 1, FLAT_MOVIE_KEY_FRAME_READWRITE_BYTES, flatFILE);
			assert(numBytesWritten == FLAT_MOVIE_KEY_FRAME_READWRITE_BYTES);

#ifdef DOUBLE_CHECK_FLAT_WRITES
			currentOffsetT = ftello(flatFILE);
			assert(currentOffsetT == (prevOffsetT + FLAT_MOVIE_KEY_FRAME_READWRITE_BYTES));

			FlatMovieKeyFrame checkKeyframe;

			result = fseek(flatFILE, prevOffsetT, SEEK_SET);
			assert(result == 0);

			fread_words((char *)&checkKeyframe, FLAT_MOVIE_KEY_FRAME_READWRITE_BYTES, flatFILE);

			assert(checkKeyframe.type == FLAT_MOVIE_KEYFRAME_TYPE16);

			BOOL same = memcmp(&checkKeyframe, &prevKeyFrame, sizeof(FLAT_MOVIE_KEY_FRAME_READWRITE_BYTES));

			assert(same == 0);

			NSLog([NSString stringWithFormat:@"processed keyframe at index %d, prev keyframe was at index %d",
				   keyframeIndexValue, prevIndexValue]);
#endif // DOUBLE_CHECK_FLAT_WRITES

			numKeyframeToRewrite--;

			prevOffset = keyframeOffset;
			prevIndex = keyframeIndex;
		}

		assert(numKeyframeToRewrite == 1); // we don't rewrite the last one
	}

	fclose(flatFILE);

	return TRUE;
}

// Double check the contents of an emitted flat movie. This
// check would not typically be done on an embedded client,
// only on the desktop. This method assumes that the self
// object is in the init state, meaning it was just allocated
// and no methods have been invoked.

- (BOOL) validateFlattenedMovie:(MovieArchive*)mArchive flatMoviePath:(NSString*)flatMoviePath
{
	// Open the flat file and read the header

	BOOL worked = [self openForReading:flatMoviePath];
	if (!worked)
		return FALSE;

	FlatMovieHeader *headerPtr = (FlatMovieHeader *) self->header;

	assert(headerPtr->width == mArchive.width);
	assert(headerPtr->height == mArchive.height);
	assert(headerPtr->numFrames == (mArchive.archive.numEntries - 1));

	// header values can't be zero and they must match the values in mArchive

	assert(headerPtr->numKeyframes > 0);

	assert(headerPtr->patchBufferNumWords > 0);
	assert(headerPtr->frameBufferNumWords > 0);

	assert(headerPtr->patchBufferNumWords == mArchive.patchBufferNumWords);
	assert(headerPtr->frameBufferNumWords == mArchive.frameBufferNumWords);	

	// Verify that we can store either a FlatMovieKeyFrame
	// or a FlatMoviePatchFrame as prevFrame.

	assert(sizeof(FlatMovieCommonFrame) == sizeof(FlatMovieFakeFrame));

	FlatMovieFakeFrame empty;
	memset(&empty, 0, sizeof(empty));
	BOOL same = (memcmp(self->prevFrame, &empty, sizeof(empty)) == 0);
	assert(same);

	// Read frames until we run out of data

	NSUInteger numFramesToRead = headerPtr->numFrames;

	assert(numFramesToRead > 0);
	assert(frameIndex == -1);

	BOOL isFirstKeyframe = TRUE;

	int numKeyframesRead = headerPtr->numKeyframes;

	// Read keyframes, patch frames, or dup patch frames

	for ( frameIndex = 0; numFramesToRead > 0 ; numFramesToRead--, frameIndex++ ) {
		// Read one word from the stream and examine it to determine
		// the type of the next frame.

		uint32_t nextWord;
		uint16_t type = read_next_word_type(self, &nextWord);

		if (type == FLAT_MOVIE_DUP_TYPE16) {
			// Frame is a duplicate of the previous frame. Keep the same prevFrame
			// and continue with the next frame.
			
			// no-op
		} else if (type == FLAT_MOVIE_PATCH_TYPE16) {
			// A patch frame. Read the patch data from the stream
			// and apply the patch delta to the frame buffer
			// from the previous frame. The patch data is
			// not used after it has been applied.

			FlatMovieCommonFrame *prevFramePtr = (FlatMovieCommonFrame*) self->prevFrame;
			type = prevFramePtr->type;

			if (type == 0) {
				// Initial frame can't be a patch frame, invalid state
				NSAssert(FALSE, @"patch frame with no intial keyframe");
			} else if (type == FLAT_MOVIE_PATCH_TYPE16) {
				// Previous frame was a patch frame
			} else if (type == FLAT_MOVIE_KEYFRAME_TYPE16) {
				// Previous frame was a key frame
			} else {
				NSAssert(FALSE, @"unmatched frame type for prev frame");
			}

			applyPatch(self, &nextWord, prevFramePtr);
		} else if (type == FLAT_MOVIE_KEYFRAME_TYPE16) {
			// Next frame is a keyframe. Free up previous frame's
			// data and release it. Then, read the rest of the
			// FlatMovieKeyFrame struct and process the keyframe.
			// Previous frame is either a patch frame or a keyframe,
			// or empty in the initial keyframe case.

			FlatMovieCommonFrame *prevFramePtr = (FlatMovieCommonFrame*) self->prevFrame;
			type = prevFramePtr->type;

			if (type == 0) {
				// First keyframe
				if (!isFirstKeyframe) {
					NSAssert(FALSE, @"zero type when not the first keyframe");
				}
			} else if ((type == FLAT_MOVIE_PATCH_TYPE16) ||
					   (type == FLAT_MOVIE_KEYFRAME_TYPE16)) {
				// no-op
			} else {
				NSAssert(FALSE, @"unmatched frame type for prev frame");
			}
			cleanup_commonframe(self, prevFramePtr);

			// Frame Buffers can't be locked at this point
			assert((self->isFrameBuffer1Locked == FALSE));
			assert((self->isFrameBuffer2Locked == FALSE));			

			// Load keyframe data and save in prevFramePtr

			loadKeyframe(self, &nextWord, prevFramePtr);

			if (isFirstKeyframe) {
				// If there is only one keyframe, the values are zero

				if (headerPtr->numKeyframes == 1) {
					NSAssert(prevFramePtr->frameIndexOfNextKeyframe == 0, @"non-zero frameIndexOfNextKeyframe");
					NSAssert(prevFramePtr->offsetOfNextKeyframe == 0, @"non-zero offsetOfNextKeyframe");					
				} else {
					NSAssert(prevFramePtr->frameIndexOfNextKeyframe > 0, @"zero frameIndexOfNextKeyframe");
					NSAssert(prevFramePtr->offsetOfNextKeyframe > 0, @"zero offsetOfNextKeyframe");
				}
			} else {
				// All keyframes must have non-zero values, except for the last one
				
				if (numKeyframesRead == 1) {
					NSAssert(prevFramePtr->frameIndexOfNextKeyframe == 0, @"non-zero frameIndexOfNextKeyframe");
					NSAssert(prevFramePtr->offsetOfNextKeyframe == 0, @"non-zero offsetOfNextKeyframe");					
				} else {
					NSAssert(prevFramePtr->frameIndexOfNextKeyframe > 0, @"zero frameIndexOfNextKeyframe");
					NSAssert(prevFramePtr->offsetOfNextKeyframe > 0, @"zero offsetOfNextKeyframe");
				}
			}

			if (isFirstKeyframe)
				isFirstKeyframe = FALSE;

			numKeyframesRead--;
		} else {
			// unmatched start of frame header, likely
			// data corruption of incorrect read logic.

			NSAssert(FALSE, @"unmatched frame type, data read logic likely to blame");
		}
	}

	assert(numKeyframesRead == 0);

	// Cleanup prevFrame after reading all frames

	FlatMovieCommonFrame *prevFramePtr = (FlatMovieCommonFrame*) self->prevFrame;

	assert(prevFramePtr->type != 0);

	cleanup_commonframe(self, prevFramePtr);

	memset(prevFramePtr, 0, sizeof(FlatMovieCommonFrame));

	// All of the data in the file should have been read at this point,
	// but EOF would not have been read from the stream.

	BOOL isAtEOF = feof(flatFILE);
	assert(isAtEOF == FALSE);
	int c = fgetc(flatFILE);
	assert(c == -1);
	isAtEOF = feof(flatFILE);
	assert(isAtEOF == TRUE);	

	[self rewind];

	return TRUE;
}

- (BOOL) _readHeader
{
	// opening the file reads the header data

	FlatMovieHeader *headerPtr = (FlatMovieHeader *) malloc(sizeof(FlatMovieHeader));
	if (headerPtr == NULL) {
		return FALSE;
	}

	self->header = headerPtr;

	int numRead = fread(headerPtr, 1, sizeof(FlatMovieHeader), flatFILE);
	assert(numRead == sizeof(FlatMovieHeader));	

	// The movie archive should have figured out some good default
	// sizes for the input buffer and the frame buffer. If the
	// data for a specific frame is bigger than this amount,
	// then a malloc() will be used to take care of the edge case.

	assert(headerPtr->patchBufferNumWords > 0);

	[self _allocatePatchBuffer:headerPtr->patchBufferNumWords];

	assert(headerPtr->frameBufferNumWords > 0);

	[self _allocateFrameBuffer:headerPtr->frameBufferNumWords];

#ifdef LOG_MISSED_BUFFER_USAGE
	NSLog([NSString stringWithFormat:
		   @"allocated patch buffer of size %d bytes", numWordsPatchBuffer*4]);

	NSLog([NSString stringWithFormat:
		   @"allocated frame buffers of size %d bytes", numWordsFrameBuffer*4]);
#endif // LOG_MISSED_BUFFER_USAGE	

	return TRUE;
}

- (BOOL) openForReading:(NSString*)flatMoviePath
{
	if (isOpen)
		return FALSE;

	char *flatFilePath = (char*) [flatMoviePath UTF8String];
	self->flatFILE = fopen(flatFilePath, "r");

	if (flatFILE == NULL) {
		return FALSE;
	}

	if ([self _readHeader] == FALSE) {
		[self close];
		return FALSE;
	}

	self->isOpen = TRUE;
	return TRUE;
}

- (void) close
{
	if (self->flatFILE != NULL) {
		fclose(self->flatFILE);
		self->flatFILE = NULL;
		self->isOpen = FALSE;
	}
}

- (void) rewind
{
	if (!isOpen)
		return;

	// Cleanup last rendered buffer

	FlatMovieCommonFrame *prevFramePtr = (FlatMovieCommonFrame*) self->prevFrame;

	cleanup_commonframe(self, prevFramePtr);

	memset(prevFramePtr, 0, sizeof(FlatMovieCommonFrame));

	// Restart at the first keyframe

	fseek(flatFILE, sizeof(FlatMovieHeader), SEEK_SET);

	frameIndex = -1;
}

- (BOOL) advanceToFrame:(NSUInteger)newFrameIndex
{
	// movie frame index can only go forward

	if ((frameIndex != -1) && (newFrameIndex <= frameIndex)) {
		NSString *msg = [NSString stringWithFormat:@"%@: %d -> %d",
						 @"can't advance to frame before current frameIndex",
						 frameIndex,
						 newFrameIndex];
		NSAssert(FALSE, msg);
	}

	// Get the number of frames directly from the header
	// instead of invoking method to query self.numFrames.

	FlatMovieHeader *headerPtr = (FlatMovieHeader *) self->header;

	if (newFrameIndex >= headerPtr->numFrames) {
		NSString *msg = [NSString stringWithFormat:@"%@: %d",
						 @"can't advance past last frame",
						 newFrameIndex];
		NSAssert(FALSE, msg);
	}

	// Return TRUE when a patch has been applied or a new keyframe was
	// read. Return FALSE when 1 or more duplicate frames were read.
	
	BOOL changeFrameData = FALSE;
	const int newFrameIndexSigned = (int) newFrameIndex;

	for ( ; frameIndex < newFrameIndexSigned; frameIndex++) {
		// Read one word from the stream and examine it to determine
		// the type of the next frame.

		uint32_t nextWord;
		uint16_t type = read_next_word_type(self, &nextWord);

		if (type == FLAT_MOVIE_DUP_TYPE16) {
			// Frame is a duplicate of the previous frame. Keep the same prevFrame
			// and continue with the next frame.

			// no-op
		} else if (type == FLAT_MOVIE_PATCH_TYPE16) {
			// A patch frame. Read the patch data from the stream
			// and apply the patch delta to the frame buffer
			// from the previous frame. The patch data is
			// not used after it has been applied.

			FlatMovieCommonFrame *prevFramePtr = (FlatMovieCommonFrame*) self->prevFrame;
			applyPatch(self, &nextWord, prevFramePtr);
			changeFrameData = TRUE;
		} else if (type == FLAT_MOVIE_KEYFRAME_TYPE16) {
			// Next frame is a keyframe. Free up previous frame's
			// data and release it. Then, read the rest of the
			// FlatMovieKeyFrame struct and process the keyframe.
			// Previous frame is either a patch frame or a keyframe,
			// or empty in the initial keyframe case.

			FlatMovieCommonFrame *prevFramePtr = (FlatMovieCommonFrame*) self->prevFrame;
			cleanup_commonframe(self, prevFramePtr);

			// Load keyframe data and save in prevFramePtr

			loadKeyframe(self, &nextWord, prevFramePtr);
			changeFrameData = TRUE;
		} else {
			NSAssert(FALSE, @"unmatched frame type, data corruption or faulty read logic");
		}
	}

	return changeFrameData;
}

- (char*) currentFrameBytes:(NSUInteger*)numBytesPtr
{
	if (!isOpen)
		return NULL;

	// Return the frame buffer bytes for the current frame
	// without a buffer copy.

	FlatMovieCommonFrame *prevFramePtr = (FlatMovieCommonFrame*) self->prevFrame;
	if (prevFramePtr->type == 0)
		return NULL;

	assert(prevFramePtr->numBytesInFrameData > 0);
	assert(prevFramePtr->frameData != NULL);

	*numBytesPtr = prevFramePtr->numBytesInFrameData;
	return prevFramePtr->frameData;
}

// Properties

- (NSUInteger) width
{
	FlatMovieHeader *headerPtr = (FlatMovieHeader *) self->header;
	if (headerPtr == NULL)
		return 0;
	return headerPtr->width;
}

- (NSUInteger) height
{
	FlatMovieHeader *headerPtr = (FlatMovieHeader *) self->header;
	if (headerPtr == NULL)
		return 0;
	return headerPtr->height;
}

- (NSUInteger) numFrames
{
	FlatMovieHeader *headerPtr = (FlatMovieHeader *) self->header;
	if (headerPtr == NULL)
		return 0;
	return headerPtr->numFrames;
}

@end
