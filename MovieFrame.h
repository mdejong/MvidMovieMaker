//
//  MovieFrame.h
//  MovieArchiveDemo
//
//  Created by Moses DeJong on 3/11/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MovieFrame : NSObject {
	NSData *frameData;
	NSData *patchData;
	BOOL isKeyframe;
}

@property (nonatomic, retain) NSData *frameData;
@property (nonatomic, retain) NSData *patchData;

// TRUE when the frame is not a delta, it contains
// all the RLE data for the frame. The first frame
// is always a keyframe.

@property (readonly) BOOL isKeyframe;

// init a regular frame, a regular frame depends
// on data from a previous frame and is created
// by applying a patch (delta) to the previous
// frame data.

- (id) initFrame:(NSData*)inPatchData;

// init a keyframe, a key frame fully defines
// itself and does not depend on an earlier
// frame. The first frame is always a key frame.

- (id) initKeyframe:(NSData*)inFrameData;

// Same as initFrame but adds to autorelease pool 

+ (id) movieFrame:(NSData*)inPatchData;

// Same as initKeyframe but adds to autorelease pool 

+ (id) movieKeyframe:(NSData*)inFrameData;

// Apply a patch to the frame data for the previous
// frame to generate this frame.

- (BOOL) patchFrame:(MovieFrame*)prevFrame;

// Invoked to indicate that the rendered frame data
// for this frame is no longer needed. Will release
// the frameData object unless the frame data is
// a key frame.

- (void) doneFrameData;

@end
