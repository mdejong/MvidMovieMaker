//
//  MovieFrame.m
//  MovieArchiveDemo
//
//  Created by Moses DeJong on 3/11/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "MovieFrame.h"

#import "MovieArchive.h"

@implementation MovieFrame

@synthesize frameData, patchData, isKeyframe;

- (id) initFrame:(NSData*)inPatchData
{
	self = [super init];
	if (self == nil)
		return nil;

	NSAssert(inPatchData, @"inPatchData");
	self.patchData = inPatchData;
	self->isKeyframe = FALSE;

	return self;
}

- (id) initKeyframe:(NSData*)inFrameData
{
	self = [super init];
	if (self == nil)
		return nil;
	
	NSAssert(inFrameData, @"inFrameData");
	self.frameData = inFrameData;
	self->isKeyframe = TRUE;

	return self;
}

- (void) dealloc
{
	[frameData release];
	[patchData release];

	[super dealloc];
}

+ (id) movieFrame:(NSData*)inPatchData
{
	MovieFrame *mfObj = [[MovieFrame alloc] initFrame:inPatchData];

	[mfObj autorelease];

	return mfObj;
}

+ (id) movieKeyframe:(NSData*)inFrameData
{
	MovieFrame *mfObj = [[MovieFrame alloc] initKeyframe:inFrameData];

	[mfObj autorelease];

	return mfObj;
}

- (BOOL) patchFrame:(MovieFrame*)prevFrame
{
	if (isKeyframe)
		NSAssert(FALSE, @"can't patch a frame with isKeyframe set");

	if (self == prevFrame)
		NSAssert(FALSE, @"frame can't patch itself");

	NSAssert(prevFrame.frameData != nil, @"previous frame's frameData is nil");

	// Need a pool around the patch operation because the patch result buffer
	// can be large and we can't afford to have a lot of these stack up in
	// a loop that applies a lot of patches.

	NSAutoreleasePool *patch_pool = [[NSAutoreleasePool alloc] init];

	int worked;

	NSData *patchedData = [MovieArchive patchFrame:prevFrame.frameData patchData:patchData];

	if (patchedData == nil) {
		// This really should not happen, something has gone very wrong
		worked = FALSE;
	} else {
		self.frameData = patchedData;

		// Done with previous frame's frameData field, unless it is a keyframe

		[prevFrame doneFrameData];
		
		worked = TRUE;
	}

	[patch_pool release];

	return worked;
}

- (void) doneFrameData
{
	if (isKeyframe)
		return;

	self.frameData = nil;
}

@end
