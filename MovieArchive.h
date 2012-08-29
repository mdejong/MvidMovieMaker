//
//  MovieArchive.h
//  ImageSeqMovieMaker
//
//  Created by Moses DeJong on 3/5/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "EasyArchive.h"

#import "MovieFrame.h"

@interface MovieArchive : NSObject {
@public
	EasyArchive *archive;

	NSUInteger frameIndex;

	NSUInteger width;
	NSUInteger height;
@private
	NSData *prevFrameData;
	MovieFrame *prevMovieFrame;
	NSMutableArray *rpatchDataObjs;

	uint32_t patchBufferNumWords;
	uint32_t frameBufferNumWords;

	NSData *outputMD5;
	CC_MD5_CTX ctxt;

	BOOL ctxtNeedsInit;
	BOOL isMD5InArchive;
}

@property (nonatomic, retain) EasyArchive *archive;

@property (readonly) NSUInteger frameIndex;

@property (readonly) NSUInteger width;
@property (readonly) NSUInteger height;

@property (nonatomic, retain) NSData *prevFrameData;
@property (nonatomic, retain) MovieFrame *prevMovieFrame;
@property (nonatomic, retain) NSMutableArray *rpatchDataObjs;

@property (readonly) uint32_t patchBufferNumWords;
@property (readonly) uint32_t frameBufferNumWords;

// The outputMD5 field is a special MD5 added to the header data
// for the movie, it is used to verify that the raw image bytes
// emitted when decoding a movie match the original source. This
// header is not verified during normal loading of a movie
// from an archive since it would take a long time.

@property (nonatomic, retain) NSData *outputMD5;

- (id) initWithArchive:(EasyArchive*)inArchive;

// Extract a NSData that contains the RLE encoded frame data
// for the next frame. Return nil on EOF.

- (NSData*) nextFrameData;

// Extract the next MovieFrame object from a movie archive.
// A movie frame is either a keyframe or a patch frame.

- (MovieFrame*) nextMovieFrame;

// Format header info based on contents of an encoded movie.
// The dimensions are the width and height of the video.
// The rleMD5Data is a MD5 checksum that can be run to check
// the output of the decoding process. The readBufferNumWords
// size indicates a general size for the patch input buffer
// that will support most frames in this animation. The
// frameBufferNumWords size is the general size of the
// decoded RLE data for most frames in the animation.

+ (NSData*) formatMovieHeaderData:(CGSize)dimensions
					   rleMD5Data:(NSData*)rleMD5Data
			  patchBufferNumWords:(uint32_t)patchBufferNumWords
			  frameBufferNumWords:(uint32_t)frameBufferNumWords;

+ (CGSize) decodeMovieHeaderDimensions:(NSData*)headerData;

- (uint32_t) decodeMovieHeaderPatchBufferNumWords:(NSData*)headerData;

- (uint32_t) decodeMovieHeaderFrameBufferNumWords:(NSData*)headerData;	

// Create 32 byte large file md5 checksum from the data
// objects in the array.

+ (NSData*) calcMD5ForData:(NSArray*)dataObjs;

- (void) decodeMovieHeaderOutputMD5:(NSData*)headerData;

- (void) updateOutputMD5:(NSData*)data;

- (BOOL) validateOutputMD5;

+ (NSData*) patchFrame:(NSData*)frameData patchData:(NSData*)patchData;

@end
