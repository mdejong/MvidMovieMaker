//
//  CGFrameBuffer.h
//
//  Created by Moses DeJong on 2/13/09.
//
//  License terms defined in License.txt.
//
//  This implementation of CGFrameBuffer supports MacOSX image and view interfaces.
//  In addition, it supports logic to calculate delta pixels.

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

#define UIView NSView

// Avoid incorrect warnings from clang
#ifndef __has_feature      // Optional.
#define __has_feature(x) 0 // Compatibility with non-clang compilers.
#endif

#ifndef CF_RETURNS_RETAINED
#if __has_feature(attribute_cf_returns_retained)
#define CF_RETURNS_RETAINED __attribute__((cf_returns_retained))
#else
#define CF_RETURNS_RETAINED
#endif
#endif

@interface CGFrameBuffer : NSObject {
@protected
	char *m_pixels;
	size_t m_numBytes;
	size_t m_numBytesAllocated;
	size_t m_width;
	size_t m_height;
	size_t m_bitsPerPixel;
	size_t m_bytesPerPixel;
	int32_t m_isLockedByDataProvider;
	CGImageRef m_lockedByImageRef;
	CGColorSpaceRef m_colorspace;
  BOOL m_usesBigEndianData;
  BOOL m_useHighQualityInterpolation;
}

@property (readonly) char *pixels;

// The numBytes property indicates the number of bytes in length
// of the buffer pointed to by the pixels property. In the event
// that an odd number of pixels is allocated, this numBytes value
// could also include a zero padding pixel in order to keep the
// buffer size an even number of pixels.

@property (readonly) size_t numBytes;

@property (readonly) size_t width;
@property (readonly) size_t height;
@property (readonly) size_t bitsPerPixel;
@property (readonly) size_t bytesPerPixel;
@property (nonatomic, assign) BOOL usesBigEndianData;

@property (nonatomic, assign) BOOL isLockedByDataProvider;
@property (nonatomic, readonly) CGImageRef lockedByImageRef;

// This colorspace will default to device RGB unless explicitly set. If set, then
// the indicated colorspace will be used when invoking CGBitmapContextCreate()
// such that a drawing operation will output pixels in the indicated colorspace.
// The same colorspace will be used when creating a CGImageRef via createCGImageRef.
// While this property is marked as assign, it will retain a ref to the indicate colorspace.

@property (nonatomic, assign) CGColorSpaceRef colorspace;

// If this property is set to TRUE, then CoreGraphics will use the "high quality"
// image interpolation setting when rendering an image into a framebuffer.
// The default is FALSE. This high quality setting is most useful when rendering
// an image that will resize or scale an image in a way that changes the aspect
// ratio or changes the size. Note that this mode is not useful for a resize
// where the aspect ratio stays the same and the size changes in an interval
// multiple, for example a 2x down to 1x size change since the "high quality"
// rendering can change the pixel values in these cases. This flag should be
// enabled when resizing to a very small image where anti-aliasing is needed
// to smooth edges in the small size image.

@property (nonatomic, assign) BOOL useHighQualityInterpolation;

+ (CGFrameBuffer*) cGFrameBufferWithBppDimensions:(NSInteger)bitsPerPixel width:(NSInteger)width height:(NSInteger)height;

// Render the contents of a view as pixels. Returns TRUE
// is successful, otherwise FALSE. Note that the view
// must be opaque and render all of its pixels. 

- (BOOL) renderView:(UIView*)view;

// Render a specific CoreGraphics image ref into this buffer

- (BOOL) renderCGImage:(CGImageRef)cgImageRef;

// Create a Core Graphics image from the pixel data
// in this buffer. The hasDataProvider property
// will be TRUE while the CGImageRef is in use.

- (CGImageRef) createCGImageRef CF_RETURNS_RETAINED;

// Defines the pixel layout, could be overloaded in a derived class

- (CGBitmapInfo) getBitmapInfo;

//- (NSData*) copyData;

// Convert pixels to a PNG image format that can be easily saved to disk.

- (NSData*) formatAsPNG;

// Set all pixels to 0x0

- (void) clear;

// Copy data from another framebuffer into this one

- (void) copyPixels:(CGFrameBuffer *)anotherFrameBuffer;

// Use memcopy() as opposed to an OS level page copy

- (void) memcopyPixels:(CGFrameBuffer *)anotherFrameBuffer;

- (void) zeroCopyToPixels;

// Zero copy from an external read-only location if supported. Otherwise plain copy.

- (void) zeroCopyPixels:(void*)zeroCopyPtr mappedData:(NSData*)mappedData;

// Crop copy a rectangle out of a second framebuffer object.

- (void) cropCopyPixels:(CGFrameBuffer*)anotherFrameBuffer
                  cropX:(NSInteger)cropX
                  cropY:(NSInteger)cropY;

// Optional opaque pixel writing logic to clear the alpha channel values when
// pixels are known to be 24BPP only.

- (void) rewriteOpaquePixels;

@end
