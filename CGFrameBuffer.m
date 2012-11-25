//
//  CGFrameBuffer.m
//  AVAnimatorDemo
//
//  Created by Moses DeJong on 2/13/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "CGFrameBuffer.h"

#import <QuartzCore/QuartzCore.h>

// Pixel format is ARGB with 2 bytes per pixel (alpha is ignored)

#define BITS_PER_COMPONENT 5
#define BITS_PER_PIXEL 16
#define BYTES_PER_PIXEL 2

void CGFrameBufferProviderReleaseData (void *info, const void *data, size_t size);


// Input is a ABGR, Output is ARGB

static inline
uint32_t abgr_to_argb(uint32_t pixel)
{
  uint32_t alpha = (pixel >> 24) & 0xFF;
  uint32_t blue = (pixel >> 16) & 0xFF;
  uint32_t green = (pixel >> 8) & 0xFF;
  uint32_t red = (pixel >> 0) & 0xFF;
  
  return (alpha << 24) | (red << 16) | (green << 8) | blue;
}

// Output as ABGR format pixel

static inline
uint32_t rgba_to_rbga(uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha)
{  
  //return (alpha << 24) | (red << 16) | (green << 8) | blue;
  return (alpha << 24) | (blue << 16) | (green << 8) | red;
}

// Input is a 32 bit ABGR, Output is 16 bit XRRRRGGGGBBBB
// This method does not resample a color down to the smaller
// range, instead it simply crops.

static inline
uint16_t abgr_to_rgb15(uint32_t pixel)
{
# define MAX_5_BITS 0x1F
  uint32_t blue  = (pixel >> 16) & MAX_5_BITS;
  uint32_t green = (pixel >> 8)  & MAX_5_BITS;
  uint32_t red   = (pixel >> 0)  & MAX_5_BITS;
  
  return (red << 10) | (green << 5) | blue;
}

@implementation CGFrameBuffer

@synthesize pixels = m_pixels;
@synthesize numBytes = m_numBytes;
@synthesize width = m_width;
@synthesize height = m_height;
@synthesize bitsPerPixel = m_bitsPerPixel;
@synthesize bytesPerPixel = m_bytesPerPixel;
//@synthesize isLockedByDataProvider = m_isLockedByDataProvider;
@synthesize lockedByImageRef = m_lockedByImageRef;
@synthesize colorspace = m_colorspace;

@synthesize usesBigEndianData = m_usesBigEndianData;

+ (CGFrameBuffer*) cGFrameBufferWithBppDimensions:(NSInteger)bitsPerPixel
                                            width:(NSInteger)width
                                           height:(NSInteger)height
{
  CGFrameBuffer *obj = [[CGFrameBuffer alloc] initWithBppDimensions:bitsPerPixel width:width height:height];
  [obj autorelease];
  return obj;
}

- (id) initWithBppDimensions:(NSInteger)bitsPerPixel
                       width:(NSInteger)width
                      height:(NSInteger)height;
{
	// Ensure that memory is allocated in terms of whole words, the
	// bitmap context won't make use of the extra half-word.
  
	size_t numPixels = width * height;
	size_t numPixelsToAllocate = numPixels;
  
	if ((numPixels % 2) != 0) {
		numPixelsToAllocate++;
	}
  
  // 16bpp -> 2 bytes per pixel, 24bpp and 32bpp -> 4 bytes per pixel
  
  size_t bytesPerPixel;
  if (bitsPerPixel == 16) {
    bytesPerPixel = 2;
  } else if (bitsPerPixel == 24 || bitsPerPixel == 32) {
    bytesPerPixel = 4;
  } else {
    NSAssert(FALSE, @"bitsPerPixel is invalid");
  }
  
	size_t inNumBytes = numPixelsToAllocate * bytesPerPixel;
    
	char* buffer;
  size_t allocNumBytes;
  allocNumBytes = inNumBytes;
  
  size_t pagesize = getpagesize();
  size_t numpages = (inNumBytes / pagesize);
  if (inNumBytes % pagesize) {
    numpages++;
  }
  size_t allocNumBytesInPages = numpages * pagesize;
  assert(allocNumBytesInPages > numpages); // watch for overflow
  buffer = (char*) valloc(allocNumBytesInPages);
  if (buffer) {
    bzero(buffer, allocNumBytesInPages);
  }
  
	if (buffer == NULL) {
		return nil;
  }
  
  if ((self = [super init])) {
    self->m_bitsPerPixel = bitsPerPixel;
    self->m_bytesPerPixel = bytesPerPixel;
    self->m_pixels = buffer;
    self->m_numBytes = allocNumBytes;
    self->m_width = width;
    self->m_height = height;
  } else {
    free(buffer);
  }
  
	return self;
}

- (void)dealloc {
  NSAssert(self->m_isLockedByDataProvider == FALSE, @"dealloc: buffer still locked by data provider");

  self.colorspace = NULL;
  
  if (self->m_pixels != NULL) {
    free(self->m_pixels);
  }
  
  [super dealloc];
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
	// is always ARGB with no alpha, the bitmap capture happens
	// *after* any colors in the image have been converted to RGB pixels.
  
	size_t w = view.frame.size.width;
	size_t h = view.frame.size.height;
  
  if ((self.width != w) || (self.height != h)) {
  		return FALSE;
  }
  
  size_t bitsPerComponent;
  size_t numComponents;
  size_t bitsPerPixel;
  size_t bytesPerRow;
  
  if (self.bitsPerPixel == 16) {
    bitsPerComponent = 5;
    //    numComponents = 3;
    bitsPerPixel = 16;
    bytesPerRow = self.width * (bitsPerPixel / 8);    
  } else if (self.bitsPerPixel == 24 || self.bitsPerPixel == 32) {
    bitsPerComponent = 8;
    numComponents = 4;
    bitsPerPixel = bitsPerComponent * numComponents;
    bytesPerRow = self.width * (bitsPerPixel / 8);
  } else {
    NSAssert(FALSE, @"unmatched bitsPerPixel");
  }
  
	CGBitmapInfo bitmapInfo = [self getBitmapInfo];
  
	CGColorSpaceRef colorSpace = self.colorspace;
	if (colorSpace) {
		CGColorSpaceRetain(colorSpace);
	} else {
		colorSpace = CGColorSpaceCreateDeviceRGB();
	}
  
	NSAssert(self.pixels != NULL, @"pixels must not be NULL");
  
	NSAssert(self.isLockedByDataProvider == FALSE, @"renderView: pixel buffer locked by data provider");
  
	CGContextRef bitmapContext =
    CGBitmapContextCreate(self.pixels, self.width, self.height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
  
	CGColorSpaceRelease(colorSpace);
  
	if (bitmapContext == NULL) {
		return FALSE;
	}
  
  // FIXME: A lot of memory is being allocated to render into this bitmapContext. But, the bitmap
  // should already be tied to memory that does the backing.
	
  // Would it be faster/possible to create a CGIMage ref directly from the image data (PNG)
  // and then render to the bitmapContext? Would that avoid all the memory allocation?
  // That should do the color space conversion but what about the scaling/rotation? For
  // full screen images, they should only be oriented one way anyway, the way that the
  // wider side indicates.
  
	// Translation matrix that maps CG space to view space
  
	//CGContextTranslateCTM(bitmapContext, 0.0, self.height);
	//CGContextScaleCTM(bitmapContext, 1.0, -1.0);
	//[view.layer renderInContext:bitmapContext];
  
	NSRect bounds = NSRectFromCGRect(CGRectMake( 0.0f, 0.0f, w, h ));
  
	NSGraphicsContext *bitmapGraphicsContext =
  [NSGraphicsContext graphicsContextWithGraphicsPort:bitmapContext flipped:FALSE]; 

  // Draw reciever and any subviews. The Ignoring Opacity this simply means that
  // the drawing operation will draw only considering the view and any windows
  // that it contains.
  
  [view displayRectIgnoringOpacity:bounds inContext:bitmapGraphicsContext];
  
	CGContextRelease(bitmapContext);
  
	return TRUE;
}

- (BOOL) renderCGImage:(CGImageRef)cgImageRef
{
  // Render cgImageRef into this buffer at the current width and height
  
  size_t bitsPerComponent;
  size_t numComponents;
  size_t bitsPerPixel;
  size_t bytesPerRow;
  
  if (self.bitsPerPixel == 16) {
    bitsPerComponent = 5;
    //    numComponents = 3;
    bitsPerPixel = 16;
    bytesPerRow = self.width * (bitsPerPixel / 8);    
  } else if (self.bitsPerPixel == 24 || self.bitsPerPixel == 32) {
    bitsPerComponent = 8;
    numComponents = 4;
    bitsPerPixel = bitsPerComponent * numComponents;
    bytesPerRow = self.width * (bitsPerPixel / 8);
  } else {
    NSAssert(FALSE, @"unmatched bitsPerPixel");
  }
  
	CGBitmapInfo bitmapInfo = [self getBitmapInfo];
  
	CGColorSpaceRef colorSpace = self.colorspace;
	if (colorSpace) {
		CGColorSpaceRetain(colorSpace);
	} else {
		colorSpace = CGColorSpaceCreateDeviceRGB();
	}
  
	NSAssert(self.pixels != NULL, @"pixels must not be NULL");
  
	NSAssert(self.isLockedByDataProvider == FALSE, @"renderView: pixel buffer locked by data provider");
  
	CGContextRef bitmapContext =
    CGBitmapContextCreate(self.pixels, self.width, self.height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
  
	CGColorSpaceRelease(colorSpace);
  
	if (bitmapContext == NULL) {
		return FALSE;
	}
  
	CGRect bounds = CGRectMake( 0.0f, 0.0f, self.width, self.height );
  
	CGContextDrawImage(bitmapContext, bounds, cgImageRef);
	
	CGContextRelease(bitmapContext);
  
	return TRUE;
}

- (CGImageRef) createCGImageRef
{
	// Load pixel data as a core graphics image object.
  
  NSAssert(self.width > 0 && self.height > 0, @"width or height is zero");
  
  size_t bitsPerComponent;
  size_t numComponents;
  size_t bitsPerPixel;
  size_t bytesPerRow;
  
  if (self.bitsPerPixel == 16) {
    bitsPerComponent = 5;
    //    numComponents = 3;
    bitsPerPixel = 16;
    bytesPerRow = self.width * (bitsPerPixel / 8);    
  } else if (self.bitsPerPixel == 24 || self.bitsPerPixel == 32) {
    bitsPerComponent = 8;
    numComponents = 4;
    bitsPerPixel = bitsPerComponent * numComponents;
    bytesPerRow = self.width * (bitsPerPixel / 8);
  } else {
    NSAssert(FALSE, @"unmatched bitsPerPixel");
  }  
  
	CGBitmapInfo bitmapInfo = [self getBitmapInfo];
  
	CGDataProviderReleaseDataCallback releaseData = CGFrameBufferProviderReleaseData;
  
  void *pixelsPtr = self.pixels;
  
	NSAssert(self.isLockedByDataProvider == FALSE, @"createCGImageRef: pixel buffer locked by data provider");
  
	CGDataProviderRef dataProviderRef = CGDataProviderCreateWithData(self,
                                                                   pixelsPtr,
                                                                   self.width * self.height * (bitsPerPixel / 8),
                                                                   releaseData);
  
	BOOL shouldInterpolate = FALSE; // images at exact size already
  
	CGColorRenderingIntent renderIntent = kCGRenderingIntentDefault;
  
	CGColorSpaceRef colorSpace = self.colorspace;
	if (colorSpace) {
		CGColorSpaceRetain(colorSpace);
	} else {
		colorSpace = CGColorSpaceCreateDeviceRGB();
	}
  
	CGImageRef inImageRef = CGImageCreate(self.width, self.height, bitsPerComponent, bitsPerPixel, bytesPerRow,
                                        colorSpace, bitmapInfo, dataProviderRef, NULL,
                                        shouldInterpolate, renderIntent);
  
	CGDataProviderRelease(dataProviderRef);
  
	CGColorSpaceRelease(colorSpace);
  
	if (inImageRef != NULL) {
		self.isLockedByDataProvider = TRUE;
		self->m_lockedByImageRef = inImageRef; // Don't retain, just save pointer
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

	if (bitmapImage) {
    // FIXME: Do something with raw bitmap data
    
    void *bitmapData = [bitmapImage bitmapData];
    int bytesPerRow = [bitmapImage bytesPerRow];
    int totalBytesInBuffer = bytesPerRow * self.height;
    
    assert(totalBytesInBuffer == self.numBytes);
    memcpy(self.pixels, bitmapData, bytesPerRow * self.height);

		[bitmapImage release];
	}
}

- (CGBitmapInfo) getBitmapInfo
{
	CGBitmapInfo bitmapInfo = 0;
  if (self.bitsPerPixel == 16) {
    bitmapInfo |= kCGImageAlphaNoneSkipFirst;
  } else if (self.bitsPerPixel == 24) {
    bitmapInfo |= kCGImageAlphaNoneSkipFirst;
  } else if (self.bitsPerPixel == 32) {
    bitmapInfo |= kCGImageAlphaPremultipliedFirst;
  } else {
    assert(0);
  }

  if (self.bitsPerPixel == 16) {
    if (self.usesBigEndianData == TRUE) {
      bitmapInfo |= kCGBitmapByteOrder16Big;
    } else {
      bitmapInfo |= kCGBitmapByteOrder16Host;
    }
  } else {
    if (self.usesBigEndianData == TRUE) {
      bitmapInfo |= kCGBitmapByteOrder32Big;
    } else {
      bitmapInfo |= kCGBitmapByteOrder32Host;
    }
  }
  
	return bitmapInfo;
}

//- (NSData*) copyData
//{
//	return [NSData dataWithBytes:self.pixels length:self.numBytes];
//}

// These properties are implemented explicitly to aid
// in debugging of read/write operations. These method
// are used to set values that could be set in one thread
// and read or set in another. The code must take care to
// use these fields correctly to remain thread safe.

- (BOOL) isLockedByDataProvider
{
	return self->m_isLockedByDataProvider;
}

- (void) setIsLockedByDataProvider:(BOOL)newValue
{
	NSAssert(m_isLockedByDataProvider == !newValue,
           @"isLockedByDataProvider property can only be switched");
  
	self->m_isLockedByDataProvider = newValue;
  
	if (m_isLockedByDataProvider) {
		[self retain]; // retain extra ref to self
	} else {
#ifdef DEBUG_LOGGING
		if (TRUE)
#else
      if (FALSE)
#endif
      {
        // Catch the case where the very last ref to
        // an object is dropped fby CoreGraphics
        
        int refCount = [self retainCount];
        
        if (refCount == 1) {
          // About to drop last ref to this frame buffer
          
          NSLog(@"dropping last ref to CGFrameBuffer held by DataProvider");
        }
        
        [self release];
      } else {
        // Regular logic for non-debug situations
        
        [self release]; // release extra ref to self
      }
	}
}

// Convert pixels to a PNG image format that can be easily saved to disk.

- (NSData*) formatAsPNG
{
  NSMutableData *mData = [NSMutableData data];
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  /*
  
  NSInteger samplesPerPixel;
  NSInteger bitsPerSample;
  NSInteger bitsPerPixel = self.bitsPerPixel;
  NSInteger bytesPerRow;
  NSInteger bitmapBytesPerPixel;
  NSInteger bitmapBitsPerPixel;
  
  BOOL alpha;
  
  // Note that RGB555 is resampled to RGB888
  
  if (bitsPerPixel == 16 || bitsPerPixel == 24) {
    samplesPerPixel = 3;
    bitsPerSample = 8;
    alpha = FALSE;
    bitmapBitsPerPixel = 32;
    bitmapBytesPerPixel = 4;
    bytesPerRow = bitmapBytesPerPixel * self.width;
  } else if (bitsPerPixel == 32) {
    samplesPerPixel = 4;
    bitsPerSample = 8;
    alpha = TRUE;
    bitmapBitsPerPixel = 32;
    bitmapBytesPerPixel = 4;
    bytesPerRow = bitmapBytesPerPixel * self.width;
  } else {
    assert(0);
  }
  
  // FIXME: write with CGImageDestinationCreateWithData()
  // CGImageDestinationCreateWithURL()
  //
  // Write PNG data directly instead of interfacing with NSBitmapImageRep !
  
  // The pixel format for a NSBitmapImageRep is RGBA so we need to manually convert
  // from BGRA when writing pixels. If the pixel format in the frame buffer is
  // 16bpp then we have to resample to 24bpp so that the PNG can be written
  // from 8bpp pixels. Note that we do not pass NSAlphaNonpremultipliedBitmapFormat
  // to bitmapFormat since the format of the input pixel format is premultiplied.
  
  NSBitmapImageRep* imgBitmap = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                         pixelsWide:self.width
                                                                         pixelsHigh:self.height
                                                                      bitsPerSample:bitsPerSample
                                                                    samplesPerPixel:samplesPerPixel
                                                                           hasAlpha:alpha
                                                                           isPlanar:FALSE
                                                                     colorSpaceName:NSDeviceRGBColorSpace
                                                                       bitmapFormat:0
                                                                        bytesPerRow:bytesPerRow
                                                                       bitsPerPixel:bitmapBitsPerPixel] autorelease];
  NSAssert(imgBitmap != nil, @"NSBitmapImageRep initWithBitmapDataPlanes failed");
  
  BOOL needToResample = FALSE;
  
  if (bitsPerPixel == 16) {
    needToResample = TRUE;
  }
  
  CGFrameBuffer *inputFrameBuffer = self;
  
  if (needToResample) {
    CGImageRef imgRefAtOriginalBPP = [self createCGImageRef];
    
    // Note that it is only possible to resample rbg555 to rbg888, since there is no alpha channel
    int otherBpp = 24;
    
    CGFrameBuffer *frameBufferAtAnotherBPP = [CGFrameBuffer cGFrameBufferWithBppDimensions:otherBpp width:self.width height:self.height];
    
    [frameBufferAtAnotherBPP renderCGImage:imgRefAtOriginalBPP];
    
    CGImageRelease(imgRefAtOriginalBPP);
    
    inputFrameBuffer = frameBufferAtAnotherBPP;
  }

  // inputFrameBuffer contains either 24bpp or 32bpp formatted words at this point
  
  uint32_t *inPtr  = (uint32_t*) inputFrameBuffer.pixels;
  uint32_t *outPtr = (uint32_t*) imgBitmap.bitmapData;
  
  int numPixels = (self.width * self.height);
  for (int i = 0; i < numPixels; i++) {
    uint32_t value = inPtr[i];
    // BGRA -> RGBA
    value = abgr_to_argb(value);
    outPtr[i] = value;
  }
   
   */
  
  /*
  
  // Copy pixels to bitmap storage but invert the BGRA format pixels to RGBA format
  
  if (bitsPerPixel == 16) {
    uint16_t *inPtr  = (uint16_t*) self.pixels;
    uint32_t *outPtr = (uint32_t*) imgBitmap.bitmapData;
    bzero(outPtr, (self.width * self.height) * sizeof(uint32_t));
    
    for (int i = 0; i < (self.width * self.height); i++) {
      // Input format is 16 bit pixel already
      uint16_t value = inPtr[i];

      // FIXME: this RGB vs BGR parsing logic might be backwards, output is correct though
      
      // rgb555 = XRRRRRGGGGGBBBBB
      
      #define CG_MAX_5_BITS 0x1F
      
      uint8_t red = (value >> 10) & CG_MAX_5_BITS;
      uint8_t green = (value >> 5) & CG_MAX_5_BITS;
      uint8_t blue = value & CG_MAX_5_BITS;
      
      // rgb555 to rgb888 (execution speed is not an issue here)
      
      red   = (int) floor( red   * (255.0 / 31.0) + 0.5);
      green = (int) floor( green * (255.0 / 31.0) + 0.5);
      blue  = (int) floor( blue  * (255.0 / 31.0) + 0.5);
      
      // emit RGBA pixel, ALPHA will be ignored
      
      uint32_t rgba = rgba_to_rbga(red, green, blue, 0xFF);
      
      outPtr[i] = rgba;
    }
  } else {
    uint32_t *inPtr  = (uint32_t*) self.pixels;
    uint32_t *outPtr = (uint32_t*) imgBitmap.bitmapData;
    bzero(outPtr, (self.width * self.height) * sizeof(uint32_t));
    
    for (int i = 0; i < (self.width * self.height); i++) {
      uint32_t value = inPtr[i];
      // BGRA -> RGBA
      value = abgr_to_argb(value);
      outPtr[i] = value;
    }      
  }
   
  */
  
  // Render buffer as a PNG image
  
  CFStringRef type = kUTTypePNG;
  size_t count = 1;  
  CGImageDestinationRef dataDest;
  dataDest = CGImageDestinationCreateWithData((CFMutableDataRef)mData,
                                              type,
                                              count,
                                              NULL);
  assert(dataDest);
  
  CGImageRef imgRef = [self createCGImageRef];
  
	CGImageDestinationAddImage(dataDest, imgRef, NULL);
	CGImageDestinationFinalize(dataDest);
  
  CGImageRelease(imgRef);
  CFRelease(dataDest);
  
  [pool drain];
  
  // Return instance object that was allocated outside the scope of pool
  
  return [NSData dataWithData:mData];
}

- (void) copyPixels:(CGFrameBuffer *)anotherFrameBuffer
{
  assert(self.numBytes == anotherFrameBuffer.numBytes);
 
  void *anotherFrameBufferPixelsPtr;
  anotherFrameBufferPixelsPtr = anotherFrameBuffer.pixels;
  
  memcpy(self.pixels, anotherFrameBufferPixelsPtr, anotherFrameBuffer.numBytes);
}

// Explicitly memcopy pixels instead of an OS level page copy,
// this is useful only when we want to deallocate the mapped
// memory and an os copy would keep that memory mapped.

- (void) memcopyPixels:(CGFrameBuffer *)anotherFrameBuffer
{
  [self copyPixels:anotherFrameBuffer];
}

// This method is a no-op in this implementation because no zero copy pixels are supported.

- (void) zeroCopyToPixels
{
}

// Zero copy from an external read-only location if supported. Otherwise plain copy.
// This implementation does not support zero copy, so just assume the size and memcpy().

- (void) zeroCopyPixels:(void*)zeroCopyPtr mappedData:(NSData*)mappedData
{
  void *anotherFrameBufferPixelsPtr;
  anotherFrameBufferPixelsPtr = zeroCopyPtr;
  
  memcpy(self.pixels, anotherFrameBufferPixelsPtr, self.numBytes);
}

// Setter for self.colorspace property. While this property is declared as assign,
// it will actually retain a ref to the colorspace.

- (void) setColorspace:(CGColorSpaceRef)colorspace
{
  if (colorspace) {
    CGColorSpaceRetain(colorspace);
  }
  
  if (self->m_colorspace) {
    CGColorSpaceRelease(self->m_colorspace);
  }
  
  self->m_colorspace = colorspace;
}

@end

// C callback invoked by core graphics when done with a buffer, this is tricky
// since an extra ref is held on the buffer while it is locked by the
// core graphics layer.

void CGFrameBufferProviderReleaseData (void *info, const void *data, size_t size) {
	CGFrameBuffer *cgBuffer = (CGFrameBuffer *) info;
	cgBuffer.isLockedByDataProvider = FALSE;
}
