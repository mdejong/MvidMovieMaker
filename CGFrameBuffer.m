//
//  CGFrameBuffer.m
//  AVAnimatorDemo
//
//  Created by Moses DeJong on 2/13/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "CGFrameBuffer.h"

#import <QuartzCore/QuartzCore.h>

#include "runlength.h"

// Pixel format is ARGB with 2 bytes per pixel (alpha is ignored)

#define BITS_PER_COMPONENT 5
#define BITS_PER_PIXEL 16
#define BYTES_PER_PIXEL 2

@implementation DeltaPixel
@end // DeltaPixel

@implementation DeltaBounds
@end // DeltaBounds

void CGFrameBufferProviderReleaseData (void *info, const void *data, size_t size);

@implementation CGFrameBuffer

@synthesize pixels, numBytes, width, height;
@synthesize frameIndex, idc;

- (id) initWithDimensions:(NSInteger)inWidth height:(NSInteger)inHeight
{
	NSAssert(inWidth > 0, @"invalid width");
	NSAssert(inHeight > 0, @"invalid height");

	// Ensure that memory is allocated in terms of whole words, the
	// bitmap context won't make use of the extra half-word.

	size_t numPixels = inWidth * inHeight;
	size_t numPixelsToAllocate = numPixels;

	if ((numPixels % 2) != 0) {
		numPixelsToAllocate++;
	}

	int inNumBytes = numPixelsToAllocate * BYTES_PER_PIXEL;
	char* buffer = (char*) malloc(inNumBytes);

	if (buffer == NULL)
		return nil;

	memset(buffer, 0, inNumBytes);

	self = [super init];

	self->pixels = buffer;
	self->numBytes = inNumBytes;
	self->width = inWidth;
	self->height = inHeight;

	return self;
}

- (BOOL) renderView:(UIView*)view
{
	// Capture the pixel content of the View that contains the
	// UIImageView. A view that displays at the full width and
	// height of the screen will be captured in a 320x480
	// bitmap context. Note that any transformations applied
	// to the UIImageView will be captured *after* the
	// transformation has been applied. Once the bitmap
	// context has been captured, it should be rendered with
	// no transformations. Also note that the colorspace
	// is always ARGBwith no alpha, the bitmap capture happens
	// *after* any colors in the image have been converted to RGB pixels.

//	size_t w = view.layer.bounds.size.width;
//	size_t h = view.layer.bounds.size.height;

	size_t w = view.frame.size.width;
	size_t h = view.frame.size.height;

	if ((self.width != w) || (self.height != h)) {
		return FALSE;
	}

	size_t bytesPerRow = width * BYTES_PER_PIXEL;
	CGBitmapInfo bitmapInfo = [self getBitmapInfo];

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

	NSAssert(pixels != NULL, @"pixels must not be NULL");

//	NSAssert(isLockedByDataProvider == FALSE, @"renderView: pixel buffer locked by data provider");

	CGContextRef bitmapContext =
		CGBitmapContextCreate(pixels, width, height, BITS_PER_COMPONENT, bytesPerRow, colorSpace, bitmapInfo);

	CGColorSpaceRelease(colorSpace);

	if (bitmapContext == NULL) {
		return FALSE;
	}

	// Translation matrix that maps CG space to view space

//	CGContextTranslateCTM(bitmapContext, 0.0, height);
//	CGContextScaleCTM(bitmapContext, 1.0, -1.0);

// FIXME: A lot of memory is being allocated to render into this bitmapContext. But, the bitmap
// should already be tied to memory that does the backing.
	
// Would it be faster/possible to create a CGIMage ref directly from the image data (PNG)
// and then render to the bitmapContext? Would that avoid all the memory allocation?
// That should do the color space conversion but what about the scaling/rotation? For
// full screen images, they should only be oriented one way anyway, the way that the
// wider side indicates.

	// Broken!
//	[view.layer renderInContext:bitmapContext];

	NSRect bounds = NSRectFromCGRect(CGRectMake( 0.0f, 0.0f, w, h ));

	NSGraphicsContext *bitmapGraphicsContext =
		[NSGraphicsContext graphicsContextWithGraphicsPort:bitmapContext flipped:FALSE]; 
	
	[view displayRectIgnoringOpacity:bounds inContext:bitmapGraphicsContext];

	CGContextRelease(bitmapContext);

	return TRUE;
}

- (BOOL) renderCGImage:(CGImageRef)cgImageRef
{
	// Render the contents of an image to pixels.

	size_t w = CGImageGetWidth(cgImageRef);
	size_t h = CGImageGetHeight(cgImageRef);

	BOOL isRotated = FALSE;

	if ((self.width == w) && (self.height == h)) {
		// width and height match
	} else if ((self.width == h) && (self.height == w)) {
		// rotated 90
		isRotated = TRUE;
	} else {
		return FALSE;
	}
	
	size_t bytesPerRow = width * BYTES_PER_PIXEL;
	CGBitmapInfo bitmapInfo = [self getBitmapInfo];
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	
	NSAssert(pixels != NULL, @"pixels must not be NULL");

	//	NSAssert(isLockedByDataProvider == FALSE, @"renderView: pixel buffer locked by data provider");

	CGContextRef bitmapContext =
		CGBitmapContextCreate(pixels, width, height, BITS_PER_COMPONENT, bytesPerRow, colorSpace, bitmapInfo);
	
	CGColorSpaceRelease(colorSpace);
	
	if (bitmapContext == NULL) {
		return FALSE;
	}

	CGRect bounds = CGRectMake( 0.0f, 0.0f, width, height );

	if (isRotated) {
		// Rotate a landscape image 90 degrees CW so that it is
		// rendered in a portrait orientation by default.
		// Translate rotation center point up so that image
		// is rotated about the upper left hand corner of screen.

		CGContextTranslateCTM(bitmapContext, 0, height);
		CGContextRotateCTM(bitmapContext, -M_PI / 2);
		bounds = CGRectMake( 0.0f, 0.0f, height, width );
	}

	CGContextDrawImage(bitmapContext, bounds, cgImageRef);
	
	CGContextRelease(bitmapContext);
	
	return TRUE;
}

- (CGImageRef) createCGImageRef
{
	// Load pixel data as a core graphics image object.

	size_t bytesPerRow = width * BYTES_PER_PIXEL; // ARGB = 2 bytes per pixel (16 bits)

	CGBitmapInfo bitmapInfo = [self getBitmapInfo];

	CGDataProviderReleaseDataCallback releaseData = CGFrameBufferProviderReleaseData;

	CGDataProviderRef dataProviderRef = CGDataProviderCreateWithData(self,
																	 pixels,
																	 width * height * BYTES_PER_PIXEL,
																	 releaseData);

	BOOL shouldInterpolate = FALSE; // images at exact size already

	CGColorRenderingIntent renderIntent = kCGRenderingIntentDefault;

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

	CGImageRef inImageRef = CGImageCreate(width, height, BITS_PER_COMPONENT, BITS_PER_PIXEL, bytesPerRow,
										  colorSpace, bitmapInfo, dataProviderRef, NULL,
										  shouldInterpolate, renderIntent);

	CGDataProviderRelease(dataProviderRef);

	CGColorSpaceRelease(colorSpace);

	if (inImageRef != NULL) {
		self.isLockedByDataProvider = TRUE;
	}

	return inImageRef;
}

- (void) createBitmapImageFromImage:(NSImage*)image
{
	NSSize imageSize = [image size];
	NSRect imageRect = NSMakeRect(0, 0, imageSize.width, imageSize.height);

	[image lockFocus];
	NSBitmapImageRep* bitmapImage = [[NSBitmapImageRep alloc] initWithFocusedViewRect:imageRect];
	[image unlockFocus];

	if(bitmapImage) {
		/*
		 Do something with the raw pixels contents
		 using [bitmapImage bitmapData] and [bitmapImage bytesPerRow]
		*/
		[bitmapImage release];
	}
}

// Calculate deltas between this frame and the indicated other frame.
// The return value is an array of DeltaPixel values that store
// the location of the pixel, the old value (the one in this frame)
// and the new value (the one in the new frame).

- (NSArray*) calculateDeltaPixels:(CGFrameBuffer*)otherFrame
{
	NSMutableArray *deltaPixels = [NSMutableArray arrayWithCapacity:1024];
	
	NSAssert(width == otherFrame.width, @"frame widths don't match");
	NSAssert(height == otherFrame.height, @"frame heights don't match");

	uint16_t *pixelData = (uint16_t*) pixels;
	uint16_t *other_pixelData = (uint16_t*) otherFrame->pixels;

	for (int y = 0; y < height; y++) {
		for (int x = 0; x < width; x++) {
			uint16_t pixel = pixelData[(width * y) + x];
			uint16_t other_pixel = other_pixelData[(width * y) + x];

			if (pixel != other_pixel) {
				DeltaPixel *deltaPixel = [[DeltaPixel alloc] init];
				deltaPixel->x = x;
				deltaPixel->y = y;
				deltaPixel->oldValue = pixel;
				deltaPixel->newValue = other_pixel;

				[deltaPixels addObject:deltaPixel];
				[deltaPixel release];
			}
		}
	}

	return deltaPixels;
}

// Given an array of delta pixels that applies to this image, calculate a
// set of damage regions (DeltaBounds objects) that indicate the
// bounds of the delta pixels.

- (NSArray*) calculateDamageBounds:(NSArray*)deltaPixels
{
	DeltaPixel *damagePixels[width][height];
	memset(&damagePixels, 0, sizeof(damagePixels));

	// Iterate over all the damage pixels and fill in values

	for (DeltaPixel *deltaPixel in deltaPixels) {
		damagePixels[deltaPixel->x][deltaPixel->y] = deltaPixel;
	}

	// Iterate over damage pixels and use array info to determine if a
	// pixel defines the upper left corner of a damage region or the
	// lower right corner.

	NSMutableArray *damageBounds = [NSMutableArray arrayWithCapacity:1024];

	for (DeltaPixel *deltaPixel in deltaPixels) {
		// Check for a pixel that defines the left edge or a damage
		// region. For a given pixel check the 8 around it.

		// 1 2 3
		// 4 P 5
		// 6 7 8

		NSUInteger x = deltaPixel->x;
		NSUInteger y = deltaPixel->y;
		
		NSUInteger left = x;
		NSUInteger right = x;
		NSUInteger top = y;
		NSUInteger bottom = y;

		// If a damage region is already defined for a pixel around
		// this one, then use that region. Otherwise, create a
		// new damage region.

		NSMutableArray *otherPixels = [NSMutableArray arrayWithCapacity:8];
		
		// 1 2 3

		if (x > 0 && y > 0 && damagePixels[x-1][y-1] != NULL) {
			left = x-1;
			top = y-1;

			DeltaPixel *otherPixel = damagePixels[x-1][y-1];
			if (otherPixel->deltaBounds != nil) {
				deltaPixel->deltaBounds = otherPixel->deltaBounds;
			} else {
				[otherPixels addObject:otherPixel];
			}
		}
		if (y > 0 && damagePixels[x][y-1] != NULL) {
			top = y-1;

			DeltaPixel *otherPixel = damagePixels[x][y-1];
			if (otherPixel->deltaBounds != nil) {
				deltaPixel->deltaBounds = otherPixel->deltaBounds;
			} else {
				[otherPixels addObject:otherPixel];
			}
		}
		if (x < width-1 && y > 0 && damagePixels[x+1][y-1] != NULL) {
			right = x+1;
			top = y-1;
			
			DeltaPixel *otherPixel = damagePixels[x+1][y-1];
			if (otherPixel->deltaBounds != nil) {
				deltaPixel->deltaBounds = otherPixel->deltaBounds;
			} else {
				[otherPixels addObject:otherPixel];
			}			
		}

		// 4 P 5
		
		if (x > 0 && damagePixels[x-1][y] != NULL) {
			left = x-1;

			DeltaPixel *otherPixel = damagePixels[x-1][y];
			if (otherPixel->deltaBounds != nil) {
				deltaPixel->deltaBounds = otherPixel->deltaBounds;
			} else {
				[otherPixels addObject:otherPixel];
			}			
		}
		if (x < width-1 && damagePixels[x+1][y] != NULL) {
			right = x+1;

			DeltaPixel *otherPixel = damagePixels[x+1][y];
			if (otherPixel->deltaBounds != nil) {
				deltaPixel->deltaBounds = otherPixel->deltaBounds;
			} else {
				[otherPixels addObject:otherPixel];
			}			
		}

		// 6 7 8
		
		if (x > 0 && y < height-1 && damagePixels[x-1][y+1] != NULL) {
			left = x-1;
			bottom = y+1;

			DeltaPixel *otherPixel = damagePixels[x-1][y+1];
			if (otherPixel->deltaBounds != nil) {
				deltaPixel->deltaBounds = otherPixel->deltaBounds;
			} else {
				[otherPixels addObject:otherPixel];
			}			
		}
		if (y < height-1 && damagePixels[x][y+1] != NULL) {
			left = x-1;
			bottom = y+1;

			DeltaPixel *otherPixel = damagePixels[x][y+1];
			if (otherPixel->deltaBounds != nil) {
				deltaPixel->deltaBounds = otherPixel->deltaBounds;
			} else {
				[otherPixels addObject:otherPixel];
			}			
		}
		if (x < width-1 && y < height-1 && damagePixels[x+1][y+1] != NULL) {
			left = x-1;
			bottom = y+1;

			DeltaPixel *otherPixel = damagePixels[x+1][y+1];
			if (otherPixel->deltaBounds != nil) {
				deltaPixel->deltaBounds = otherPixel->deltaBounds;
			} else {
				[otherPixels addObject:otherPixel];
			}			
		}

		// If no damage region was found near this one, then this must be the
		// first pixel in the damage region.

		if (deltaPixel->deltaBounds == nil) {
			DeltaBounds *newDeltaBounds = [[DeltaBounds alloc] init];
			[damageBounds addObject:newDeltaBounds];
			[newDeltaBounds release];

			newDeltaBounds->x = x;
			newDeltaBounds->y = y;
			newDeltaBounds->width = 1;
			newDeltaBounds->height = 1;

			// the pixel contains a pointer but does not hold a ref

			deltaPixel->deltaBounds = newDeltaBounds;
			
			// Update the damage region pointer for any nearby pixels

			for (DeltaPixel *otherPixel in otherPixels) {
				otherPixel->deltaBounds = newDeltaBounds;
			}
		} else {
			// A bound was found at a nearby pixel, update any bounds
			// that might be changed by this pixel.
			
			DeltaBounds *currentBounds = deltaPixel->deltaBounds;

			// The left edge can move to the left if another pixel farther
			// to the left is found in a row below a pervious one.

			if (left < currentBounds->x) {
				int currentRight = currentBounds->x + currentBounds->width;
				currentBounds->x = left;
				currentBounds->width = currentRight - currentBounds->x;
			}
			if ((currentBounds->x + currentBounds->width) < right) {
				currentBounds->width = right - currentBounds->x;
			}

			// The upper Y bound for a damage region can't move upward
			// since columns are scanned first.

			NSAssert(top >= currentBounds->y, @"can't be smaller than existing damage region Y");

			if ((currentBounds->y + currentBounds->height) < bottom) {
				currentBounds->height = bottom - currentBounds->y;
			}			
		}
	}

	return damageBounds;	
}

- (CGBitmapInfo) getBitmapInfo
{
/*
	CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
	bitmapInfo |= kCGImageAlphaNoneSkipLast;		// 32 bit RGBA where the A is ignored
	//bitmapInfo |= kCGImageAlphaLast;				// 32 bit RGBA
	//bitmapInfo |= kCGImageAlphaPremultipliedLast;	// 32 bit RGBA where A is pre-multiplied alpha

*/

	CGBitmapInfo bitmapInfo = kCGBitmapByteOrder16Little;
	bitmapInfo |= kCGImageAlphaNoneSkipFirst;

	return bitmapInfo;
}

- (NSData*) runLengthEncode
{
	// Create a NSMutableData to contain the encoded data, then
	// encode to compress duplicate pixels.
	
	int encodedNumBytes = numBytes + numBytes/2;
	NSMutableData *buffer = [NSMutableData dataWithCapacity:encodedNumBytes];
	NSAssert(buffer, @"could not allocate pixel buffer");
	[buffer setLength:encodedNumBytes];
	
	uint16_t *buffer_bytes = (uint16_t *) [buffer mutableBytes];
	
	encodedNumBytes = pp_encode((uint16_t *)pixels, width * height,
								(char*)[buffer mutableBytes], encodedNumBytes);
	
	return [NSData dataWithBytes:buffer_bytes length:encodedNumBytes];	
}

- (void) runLengthDecode:(NSData*)encoded numEncodedBytes:(NSUInteger)numEncodedBytes
{
	char *input_bytes = (char *)[encoded bytes];
	pp_decode(input_bytes, numEncodedBytes, (uint16_t*) pixels, width * height);
}

- (NSData*) copyData
{
	return [NSData dataWithBytes:pixels length:numBytes];
}

// These properties are implemented explicitly to aid
// in debugging of read/write operations. These method
// are used to set values that could be set in one thread
// and read or set in another. The code must take care to
// use these fields correctly to remain thread safe.

- (BOOL) isLockedByDataProvider
{
	return self->isLockedByDataProvider;
}

- (void) setIsLockedByDataProvider:(BOOL)newValue
{
	NSAssert(isLockedByDataProvider == !newValue,
			 @"isLockedByDataProvider property can only be switched");

	self->isLockedByDataProvider = newValue;

	if (isLockedByDataProvider) {
		[self retain]; // retain extra ref to self
	} else {
		[self release]; // release extra ref to self	
	}
}

- (BOOL) isLockedByReadyQueue
{
	return self->isLockedByReadyQueue;
}

- (void) setIsLockedByReadyQueue:(BOOL)newValue
{
	self->isLockedByReadyQueue = newValue;
}

- (void)dealloc {
	NSAssert(isLockedByDataProvider == FALSE, @"dealloc: buffer still locked by data provider");

	if (pixels != NULL)
		free(pixels);

    [super dealloc];
}

@end

// C callback invoked by core graphics when done with a buffer, this is tricky
// since an extra ref is held on the buffer while it is locked by the
// core graphics layer.

void CGFrameBufferProviderReleaseData (void *info, const void *data, size_t size) {
	CGFrameBuffer *cgBuffer = (CGFrameBuffer *) info;
	cgBuffer.isLockedByDataProvider = FALSE;
}
