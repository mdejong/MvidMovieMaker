//
//  CGFrameBuffer.h
//  AVAnimatorDemo
//
//  Created by Moses DeJong on 2/13/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

#define UIView NSView

@class DeltaBounds;
@class DeltaPixel;

@interface CGFrameBuffer : NSObject {

@public
	char *pixels;
	size_t numBytes;
	size_t width;
	size_t height;
	NSUInteger frameIndex;
	char idc;

@private
	int32_t isLockedByDataProvider;
	int32_t isLockedByReadyQueue;

}

@property (readonly) char *pixels;
@property (readonly) size_t numBytes;
@property (readonly) size_t width;
@property (readonly) size_t height;
@property (readonly) NSUInteger frameIndex;

@property (nonatomic, assign) BOOL isLockedByDataProvider;

@property (nonatomic, assign) BOOL isLockedByReadyQueue;

@property (nonatomic, assign) char idc;

- (id) initWithDimensions:(NSInteger)inWidth height:(NSInteger)inHeight;

// Render the contents of a view as pixels. Returns TRUE
// is successful, otherwise FALSE. Note that the view
// must be opaque and render all of its pixels. 

- (BOOL) renderView:(UIView*)view;

// Render a CGImageRef directly into the pixels

- (BOOL) renderCGImage:(CGImageRef)cgImageRef;

// Create a Core Graphics image from the pixel data
// in this buffer. The hasDataProvider property
// will be TRUE while the CGImageRef is in use.

- (CGImageRef) createCGImageRef;

// Defines the pixel layout, could be overloaded in a derived class

- (CGBitmapInfo) getBitmapInfo;

- (NSData*) copyData;

- (NSArray*) calculateDeltaPixels:(CGFrameBuffer*)otherFrame;

- (NSArray*) calculateDamageBounds:(NSArray*)deltaPixels;

@end

// Util struct/object

@interface DeltaPixel : NSObject {
@public
	uint16_t x;
	uint16_t y;
	uint16_t oldValue;
	uint16_t newValue;
	DeltaBounds *deltaBounds;
}
@end

// Util struct/object

@interface DeltaBounds : NSObject {
@public
	uint16_t x;
	uint16_t y;
	uint16_t width;
	uint16_t height;
}
@end
