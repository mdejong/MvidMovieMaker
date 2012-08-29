//
//  FlatMovieFile.h
//  ImageSeqMovieMaker
//
//  Created by Moses DeJong on 3/15/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MovieArchive;

typedef struct FlatMovieFakeFrame {
	uint32_t fake1;
	uint32_t fake2;
	uint32_t fake3;
	uint32_t fake4;
	uint32_t fake5;
	uint32_t fake6;
} FlatMovieFakeFrame;

@interface FlatMovieFile : NSObject {
@public
	FILE *flatFILE;
	void *header;

	BOOL isOpen;

	// The input buffer stores incoming delta data from one frame to the next.
	// The input buffer is typically smaller than the frame buffer.

	void *patchBuffer;
	NSUInteger numWordsPatchBuffer;
	BOOL isPatchBufferLocked;

	// The frame buffer contains the result of the previous patch
	// operation. If a keyframe is found, the data is copied into
	// the frame buffer directly. This buffer will be read when
	// decoding data to be sent to the graphics subsystem, but it is
	// not directly related to graphics memory.

	void *frameBuffer1;
	NSUInteger numWordsFrameBuffer;
	BOOL isFrameBuffer1Locked;

	// During a patch operation, both a source and a destination
	// buffer are needed. This second frameBuffer acts just
	// like the first and is always the same size.

	void *frameBuffer2;
	BOOL isFrameBuffer2Locked;	

	FlatMovieFakeFrame *prevFrame;

	int frameIndex;
}

@property (readonly) NSUInteger width;
@property (readonly) NSUInteger height;
@property (readonly) NSUInteger numFrames;
@property (readonly) BOOL isOpen;

- (id) init;

- (void) dealloc;

- (BOOL) openForReading:(NSString*)flatMoviePath;

- (void) close;

- (void) rewind;

- (BOOL) advanceToFrame:(NSUInteger)newFrameIndex;

- (char*) currentFrameBytes:(NSUInteger*)numBytesPtr;

+ (BOOL) flattenMovie:(MovieArchive*)mArchive flatMoviePath:(NSString*)flatMoviePath;

- (BOOL) validateFlattenedMovie:(MovieArchive*)mArchive flatMoviePath:(NSString*)flatMoviePath;

@end
