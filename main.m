#import <Cocoa/Cocoa.h>

#import "CGFrameBuffer.h"

#import "AVFrame.h"

#import "AVMvidFileWriter.h"

#import "AVMvidFrameDecoder.h"

#import "SegmentedMappedData.h"

// private properties declaration for class AVMvidFrameDecoder, used here
// to implete looking directly into the file header.

@interface AVMvidFrameDecoder ()
@property (nonatomic, assign, readonly) void *mvFrames;
@end


#include "maxvid_encode.h"

#include "maxvid_deltas.h"

#import "movdata.h"

#import "MvidFileMetaData.h"

CGSize _movieDimensions;

NSString *movie_prefix;

CGFrameBuffer *prevFrameBuffer = nil;

// Define this symbol to create a -test option that can be run from the command line.
#define TESTMODE

// Define to enable mode that will split the RGB+A into RGB and A in two different mvid files
#define SPLITALPHA

// A MovieOptions struct is filled in as the user passes
// specific command line options.

typedef struct
{
  float framerate;
  int   bpp;
  int   keyframe;
  int   deltas;
} MovieOptions;

// BGRA is iOS native pixel format, it is the most optimal format since
// pixels need not be swapped when reading from a file format.

static inline
uint32_t rgba_to_bgra(uint32_t red, uint32_t green, uint32_t blue, uint32_t alpha)
{
  return (alpha << 24) | (red << 16) | (green << 8) | blue;
}

void process_frame_file_write_nodeltas(BOOL isKeyframe,
                                       CGFrameBuffer *cgBuffer,
                                       AVMvidFileWriter *mvidWriter);

#if MV_ENABLE_DELTAS

void process_frame_file_write_deltas(BOOL isKeyframe,
                                     CGFrameBuffer *cgBuffer,
                                     CGFrameBuffer *emptyInitialFrameBuffer,
                                     AVMvidFileWriter *mvidWriter);

#endif // MV_ENABLE_DELTAS

// ------------------------------------------------------------------------
//
// mvidmoviemaker
//
// To convert a .mov to .mvid (Quicktime to optimized .mvid) execute.
//
// mvidmoviemaker movie.mov movie.mvid
//
// The following arguments can be used to create a .mvid video file
// from a series of PNG or other images. The -fps option indicates
// that the framerate is 15 frames per second. By default, the
// system will assume 24bpp "Millions". If input images make use
// of an alpha channel, then 32bpp "Millions+" will be used automatically.
//
// mvidmoviemaker FRAMES/Frame001.png movie.mvid -fps 15
//
// To extract the contents of an .mvid movie to PNG images:
//
// mvidmoviemaker -extract movie.mvid ?FILEPREFIX?"
//
// The optional FILEPREFIX should be specified as "DumpFile" to get
// frames files named "DumpFile0001.png" and "DumpFile0002.png" and so on.
//
//  To see a summary of MVID header info for a specific file.
//
//  mvidmoviemaker -info movie.mvid
// ------------------------------------------------------------------------

static
char *usageArray =
"usage: mvidmoviemaker FIRSTFRAME.png OUTFILE.mvid ?OPTIONS?" "\n"
"or   : mvidmoviemaker -extract FILE.mvid ?FILEPREFIX?" "\n"
"or   : mvidmoviemaker -info movie.mvid" "\n"
"or   : mvidmoviemaker -crop \"X Y WIDTH HEIGHT\" INFILE.mvid OUTFILE.mvid" "\n"
"or   : mvidmoviemaker -resize OPTIONS_RESIZE INFILE.mvid OUTFILE.mvid" "\n"
#if defined(SPLITALPHA)
"or   : mvidmoviemaker -splitalpha FILE.mvid (writes FILE_rgb.mvid and FILE_alpha.mvid)" "\n"
"or   : mvidmoviemaker -joinalpha FILE.mvid (reads FILE_rgb.mvid and FILE_alpha.mvid)" "\n"
"or   : mvidmoviemaker -mixalpha FILE.mvid (writes FILE_mix.mvid)" "\n"
"or   : mvidmoviemaker -unmixalpha FILE.mvid (reads FILE_mix.mvid)" "\n"
"or   : mvidmoviemaker -mixstraight RGB.mvid ALPHA.mvid MIXED.mvid" "\n"
#endif
"options that are less commonly used" "\n"
"or   : mvidmoviemaker -flatten INORIG.mvid FLAT.png" "\n"
"or   : mvidmoviemaker -unflatten INORIG.mvid FLAT.png OUT.mvid" "\n"
"or   : mvidmoviemaker -upgrade FILE.mvid ?OUTFILE.mvid?" "\n"
"or   : mvidmoviemaker -4up INFILE.mvid" "\n"
"or   : mvidmoviemaker -pixels movie.mvid" "\n"
"or   : mvidmoviemaker -extractpixels FILE.mvid ?FILEPREFIX?" "\n"
"or   : mvidmoviemaker -extractcodec FILE.mvid ?FILEPREFIX?" "\n"
"or   : mvidmoviemaker -alphamap FILE.mvid OUTFILE.mvid MAPSPEC" "\n"
"or   : mvidmoviemaker -rdelta INORIG.mvid INMOD.mvid OUTFILE.mvid" "\n"
"or   : mvidmoviemaker -adler movie.mvid" "\n"
"or   : mvidmoviemaker -fps movie.mvid" "\n"
"OPTIONS:\n"
"-fps FLOAT : required when creating .mvid from a series of images\n"
"-framerate FLOAT : alternative way to indicate 1.0/fps\n"
"-bpp INTEGER : 16, 24, or 32 (Thousands, Millions, Millions+)\n"
"-keyframe INTEGER : create a keyframe every N frames, 1 for all keyframes\n"
#if MV_ENABLE_DELTAS
"-deltas BOOL : 1 or true to enable frame deltas mode\n"
#endif // MV_ENABLE_DELTAS
"OPTIONS_RESIZE:\n"
"\"WIDTH HEIGHT\" : pass integer width and height to scale to specific dimensions\n"
"DOUBLE : resize to 2x input width and height with special 4up pixel copy logic\n"
"HALF : resize to 1/2 input width and height\n"
;

#define USAGE (char*)usageArray

// Create a CGImageRef given a filename. Image data is read from the file

CGImageRef createImageFromFile(NSString *filenameStr)
{
  CGImageSourceRef sourceRef;
  CGImageRef imageRef;
  
  if (FALSE) {
    // FIXME : values not the same after read from rgb24 -> rgb555 -> rbg24
    
    // This input PNG was downsampled from a smooth 24BPP gradient
    filenameStr = @"RGBGradient16BPP_SRGB.png";
  }
  
  if (FALSE) {
    filenameStr = @"SunriseFunkyColorspace.jpg";
  }
  
  if (FALSE) {
    filenameStr = @"RGBGradient24BPP_SRGB.png";
  }
  
  if (FALSE) {
    // Device RGB colorspace
    filenameStr = @"TestBlack.png";
  }
  
  if (FALSE) {
    filenameStr = @"TestOpaque.png";
  }
  
  if (FALSE) {
    filenameStr = @"TestAlphaOnOrOff.png";
  }
  
  if (FALSE) {
    filenameStr = @"TestAlpha.png";
  }

  if (FALSE) {
    filenameStr = @"Colorbands_sRGB.png";
  }
  
	NSData *image_data = [NSData dataWithContentsOfFile:filenameStr];
	if (image_data == nil) {
		fprintf(stderr, "can't read image data from file \"%s\"\n", [filenameStr UTF8String]);
		exit(1);
	}
  
	// Create image object from src image data.
  
  sourceRef = CGImageSourceCreateWithData((CFDataRef)image_data, NULL);
  
  // Make sure the image source exists before continuing
  
	if (sourceRef == NULL) {
		fprintf(stderr, "can't create image data from file \"%s\"\n", [filenameStr UTF8String]);
		exit(1);
	}
  
  // Create an image from the first item in the image source.
  
  imageRef = CGImageSourceCreateImageAtIndex(sourceRef, 0, NULL);
  
  CFRelease(sourceRef);
  
  return imageRef;
}

// Make a new MVID file writing object in the autorelease pool and configure
// with the indicated framerate, total number of frames, and bpp.

AVMvidFileWriter* makeMVidWriter(
                                 NSString *mvidFilename,
                                 NSUInteger bpp,
                                 NSTimeInterval frameRate,
                                 NSUInteger totalNumFrames
                                 )
{
  AVMvidFileWriter *mvidWriter = [AVMvidFileWriter aVMvidFileWriter];
  assert(mvidWriter);
  
  mvidWriter.mvidPath = mvidFilename;
  mvidWriter.bpp = bpp;
  // Note that we don't know the movie size until the first frame is read
  
  mvidWriter.frameDuration = frameRate;
  mvidWriter.totalNumFrames = totalNumFrames;
  
  mvidWriter.genAdler = TRUE;
  mvidWriter.genV3 = TRUE;
  
  BOOL worked = [mvidWriter open];
  if (worked == FALSE) {
    fprintf(stderr, "error: Could not open .mvid output file \"%s\"\n", (char*)[mvidFilename UTF8String]);        
    exit(1);
  }
  
  return mvidWriter;
}

// This method is invoked with a path that contains the frame
// data and the offset into the frame array that this specific
// frame data is found at. A writer is passed to this method
// to indicate where to write to, unless an initial scan in
// needed and then no write is done.
//
// If the input image is in another colorspace,
// then it will be converted to sRGB. If the RGB data is not
// tagged with a specific colorspace (aka GenericRGB) then
// it is assumed to be sRGB data.
//
// mvidWriter  : Output destination for MVID frame data. If NULL, no output will be written.
// filenameStr : Name of .png file that contains the frame data
// existingImageRef : If NULL, image is loaded from filenameStr instead
// frameIndex  : Frame index (starts at zero)
// mvidFileMetaData : container for info found while scanning/writing
// isKeyframe  : TRUE if this specific frame should be stored as a keyframe (as opposed to a delta frame)
// optionsPtr : command line options settings

int process_frame_file(AVMvidFileWriter *mvidWriter,
                       NSString *filenameStr,
                       CGImageRef existingImageRef,
                       int frameIndex,
                       MvidFileMetaData *mvidFileMetaData,
                       BOOL isKeyframe,
                       MovieOptions *optionsPtr)
{
  // Push pool after creating global resources

  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  CGImageRef imageRef;
  if (existingImageRef == NULL) {
    imageRef = createImageFromFile(filenameStr);
  } else {
    imageRef = existingImageRef;
    CGImageRetain(imageRef);
  }
  assert(imageRef);
  
  // General logic is to assume sRGB colorspace since that is what the iOS device assumes.
  //
  // SRGB
  // https://gist.github.com/1130831
  // http://www.mailinglistarchive.com/html/quartz-dev@lists.apple.com/2010-04/msg00076.html
  // http://www.w3.org/Graphics/Color/sRGB.html (see alpha masking topic)
  //
  // Render from input (if it has an ICC profile) into sRGB, this could involve conversions
  // but it makes the results portable and it basically better because it is still as
  // lossless as possible given the constraints. We only deal with sRGB tagged data
  // once this conversion is complete.
  
  CGSize imageSize = CGSizeMake(CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));
  int imageWidth = imageSize.width;
  int imageHeight = imageSize.height;

  assert(imageWidth > 0);
  assert(imageHeight > 0);
  
  // If this is the first frame, set the movie size based on the size of the first frame
  
  if (frameIndex == 0) {
    if (mvidWriter) {
      mvidWriter.movieSize = imageSize;
    }
    _movieDimensions = imageSize;
  } else if (CGSizeEqualToSize(imageSize, _movieDimensions) == FALSE) {
    // Size of next frame must exactly match the size of the previous one
    
    fprintf(stderr, "error: frame file \"%s\" size %d x %d does not match initial frame size %d x %d\n",
            [filenameStr UTF8String],
            (int)imageSize.width, (int)imageSize.height,
            (int)_movieDimensions.width, (int)_movieDimensions.height);
    exit(2);
  }
    
  // Render input image into a CGFrameBuffer at a specific BPP. If the input buffer actually contains
  // 16bpp pixels expanded to 24bpp, then this render logic will resample down to 16bpp.
  
  int bppNum = mvidFileMetaData.bpp;
  int checkAlphaChannel = mvidFileMetaData.checkAlphaChannel;
  int recordFramePixelValues = mvidFileMetaData.recordFramePixelValues;

  if (bppNum == 24 && checkAlphaChannel) {
    bppNum = 32;
  }
  
  int isSizeOkay = maxvid_v3_frame_check_max_size(imageWidth, imageHeight, bppNum);
  if (isSizeOkay != 0) {
    fprintf(stderr, "error: frame size is so large that it cannot be stored in MVID file : %d x %d at %d BPP\n",
            (int)imageWidth, (int)imageHeight, bppNum);
    exit(2);
  }
  
  CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:imageWidth height:imageHeight];
  
  // Query the colorspace used in the input image. Note that if no ICC tag was used then we assume sRGB.
  
  CGColorSpaceRef inputColorspace;
  inputColorspace = CGImageGetColorSpace(imageRef);
  // Should default to RGB if nothing is specified
  assert(inputColorspace);
  
  BOOL inputIsRGBColorspace = FALSE;
  BOOL inputIsSRGBColorspace = FALSE;
  
  {
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    
    NSString *colorspaceDescription = (NSString*) CGColorSpaceCopyName(colorspace);
    NSString *inputColorspaceDescription = (NSString*) CGColorSpaceCopyName(inputColorspace);
    
    if ([colorspaceDescription isEqualToString:inputColorspaceDescription]) {
      inputIsRGBColorspace = TRUE;
    }

    CGColorSpaceRelease(colorspace);
    [colorspaceDescription release];
    [inputColorspaceDescription release];
  }

  {
    CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    
    NSString *colorspaceDescription = (NSString*) CGColorSpaceCopyName(colorspace);
    NSString *inputColorspaceDescription = (NSString*) CGColorSpaceCopyName(inputColorspace);
    
    if ([colorspaceDescription isEqualToString:inputColorspaceDescription]) {
      inputIsSRGBColorspace = TRUE;
    }
    
    CGColorSpaceRelease(colorspace);
    [colorspaceDescription release];
    [inputColorspaceDescription release];
  }
  
  if (inputIsRGBColorspace) {
    assert(inputIsSRGBColorspace == FALSE);
  }
  if (inputIsSRGBColorspace) {
    assert(inputIsRGBColorspace == FALSE);
  }
  
  // Output is always going to be "sRGB", so we have a couple of cases.
  //
  // 1. Input is already in sRGB and output is in sRGB, easy
  // 2. Input is in "GenericRGB" colorspace, so assign this same colorspace to the output
  //    buffer so that no colorspace conversion is done in the render step.
  // 3. If we do not detect sRGB or GenericRGB, then some other ICC profile is defined
  //    and we can convert from that colorspace to sRGB.
  
  BOOL outputSRGBColorspace = FALSE;
  BOOL outputRGBColorspace = FALSE;
  
  if (inputIsSRGBColorspace) {
    outputSRGBColorspace = TRUE;
  } else if (inputIsRGBColorspace) {
    outputRGBColorspace = TRUE;
  } else {
    // input is not sRGB and it is not GenericRGB, so convert from this colorspace
    // to the sRGB colorspace during the render operation.
    outputSRGBColorspace = TRUE;
  }
  
  // Use sRGB colorspace when reading input pixels into format that will be written to
  // the .mvid file. This is needed when using a custom color space to avoid problems
  // related to storing the exact original input pixels.
  
  if (outputSRGBColorspace) {
    CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    cgBuffer.colorspace = colorspace;
    CGColorSpaceRelease(colorspace);
  } else if (outputRGBColorspace) {
    // Weird case where input RGB image was automatically assigned the GenericRGB colorspace,
    // use the same colorspace when rendering so that no colorspace conversion is done.
    cgBuffer.colorspace = inputColorspace;
    
    if (frameIndex == 0 && filenameStr != nil) {
      fprintf(stdout, "treating input pixels as sRGB since image does not define an ICC color profile\n");
    }
  } else {
    assert(0);
  }
  
  BOOL worked = [cgBuffer renderCGImage:imageRef];
  assert(worked);
  
  CGImageRelease(imageRef);
  
  if (outputRGBColorspace) {
    // Assign the sRGB colorspace to the framebuffer so that if we write an image
    // file or use the framebuffer in the next loop, we know it is really sRGB.
    
    CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    cgBuffer.colorspace = colorspace;
    CGColorSpaceRelease(colorspace);
  }
  
  if (bppNum == 24 && (checkAlphaChannel == FALSE)) {
    // In the case where we know that opaque 24 BPP pixels are going to be emitted,
    // rewrite the pixels in the output buffer once the image has been rendered.
    // CoreGraphics will write 0xFF as the alpha value even though we know the
    // alpha value will be ignored due to the bitmap flags.
    
    [cgBuffer rewriteOpaquePixels];
  }
    
  // Debug dump contents of framebuffer to a file
  
  if (FALSE) {
    NSString *dumpFilename = [NSString stringWithFormat:@"WriteDumpFrame%0.4d.png", frameIndex+1];
    
    NSData *pngData = [cgBuffer formatAsPNG];
    
    [pngData writeToFile:dumpFilename atomically:NO];
    
    NSLog(@"wrote %@", dumpFilename);
  }
  
  // Scan the alpha values in the framebuffer to determine if any of the pixels have a non-0xFF alpha channel
  // value. If any pixels are non-opaque then the data needs to be treated as 32BPP.
  
  if ((checkAlphaChannel || recordFramePixelValues) && (prevFrameBuffer.bitsPerPixel != 16)) {
    uint32_t *currentPixels = (uint32_t*)cgBuffer.pixels;
    int width = cgBuffer.width;
    int height = cgBuffer.height;
    int numPixels = (width * height);
    
    BOOL allOpaque = TRUE;
    
    for (int i=0; i < numPixels; i++) {
      uint32_t currentPixel = currentPixels[i];
      
      // ABGR non-opaque pixel detection
      uint8_t alpha = (currentPixel >> 24) & 0xFF;
      if (alpha != 0xFF) {
        allOpaque = FALSE;
        
        if (!recordFramePixelValues) {
          break;
        }
      }
      
      // Store pixel value in the next available slot
      // in a global hashtable of pixel values mapped
      // to a usage 32 bit integer.
      
      if (recordFramePixelValues) {
        if (prevFrameBuffer.bitsPerPixel == 16) {
          assert(0);
        } else {
          [mvidFileMetaData foundPixel32:currentPixel];
        }
      }
    }
    
    if (allOpaque == FALSE && checkAlphaChannel) {
      mvidFileMetaData.bpp = 32;
      mvidFileMetaData.checkAlphaChannel = FALSE;
    }
  } else if (recordFramePixelValues && (prevFrameBuffer.bitsPerPixel == 16)) {
    uint16_t *currentPixels = (uint16_t*)cgBuffer.pixels;
    int width = cgBuffer.width;
    int height = cgBuffer.height;
    int numPixels = (width * height);
    
    for (int i=0; i < numPixels; i++) {
      uint16_t currentPixel = currentPixels[i];
      [mvidFileMetaData foundPixel16:currentPixel];
    }
  }
  
  // Emit either regular or delta data depending on mode
  
  if (mvidWriter) {
#if MV_ENABLE_DELTAS
    if (optionsPtr &&
        optionsPtr->deltas == 1)
    {
      CGFrameBuffer *emptyInitialFrameBuffer = nil;
      if (frameIndex == 0) {
        emptyInitialFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:imageWidth height:imageHeight];
      }
      process_frame_file_write_deltas(isKeyframe, cgBuffer, emptyInitialFrameBuffer, mvidWriter);
    } else
#endif // MV_ENABLE_DELTAS
    {
      process_frame_file_write_nodeltas(isKeyframe, cgBuffer, mvidWriter);
    }
  } // if (mvidWriter)

  // cleanup
  
  if (TRUE) {
    if (prevFrameBuffer) {
      [prevFrameBuffer release];
    }
    prevFrameBuffer = cgBuffer;
    [prevFrameBuffer retain];
  }
  
	// free up resources
  
  [pool drain];
	
	return 0;
}

// This method implements the "writing" portion of the frame emit logic for the normal case
// where either a keyframe or a delta frame is generated. If pixel deltas are going to be
// calculated then the other write method is invoked.

void process_frame_file_write_nodeltas(BOOL isKeyframe,
                                       CGFrameBuffer *cgBuffer,
                                       AVMvidFileWriter *mvidWriter)
{
  BOOL worked;  
  BOOL emitKeyframe = isKeyframe;
  
  uint32_t encodeFlags = 0;
  
  // In the case where we know the frame is a keyframe, then don't bother to run delta calculation
  // logic. In the case of the first frame, there is nothing to compare to anyway. The tricky case
  // is when the delta compare logic finds that all of the pixels have changed or the vast majority
  // of pixels have changed, in this case it is actually less optimal to emit a delta frame as compared
  // to a keyframe.
  
  NSData *encodedDeltaData = nil;
  
  if (isKeyframe == FALSE) {
    // Calculate delta pixels by comparing the previous frame to the current frame.
    // Once we know specific delta pixels, then only those pixels that actually changed
    // can be stored in a delta frame.
    
    assert(prevFrameBuffer);
    
    assert(prevFrameBuffer.width == cgBuffer.width);
    assert(prevFrameBuffer.height == cgBuffer.height);
    assert(prevFrameBuffer.bitsPerPixel == cgBuffer.bitsPerPixel);
    
    void *prevPixels = (void*)prevFrameBuffer.pixels;
    void *currentPixels = (void*)cgBuffer.pixels;
    int numWords;
    int width = cgBuffer.width;
    int height = cgBuffer.height;
    
    BOOL emitKeyframeAnyway = FALSE;
    
    if (prevFrameBuffer.bitsPerPixel == 16) {
      numWords = cgBuffer.numBytes / sizeof(uint16_t);
      encodedDeltaData = maxvid_encode_generic_delta_pixels16(prevPixels,
                                                              currentPixels,
                                                              numWords,
                                                              width,
                                                              height,
                                                              &emitKeyframeAnyway,
                                                              encodeFlags);
      
    } else {
      numWords = cgBuffer.numBytes / sizeof(uint32_t);
      encodedDeltaData = maxvid_encode_generic_delta_pixels32(prevPixels,
                                                              currentPixels,
                                                              numWords,
                                                              width,
                                                              height,
                                                              &emitKeyframeAnyway,
                                                              encodeFlags);
    }
    
    if (emitKeyframeAnyway) {
      // The delta calculation indicates that all the pixels in the frame changed or
      // so many changed that it would be better to emit a whole keyframe as opposed
      // to a delta frame.
      
      emitKeyframe = TRUE;
    }
  }
  
  
  if (emitKeyframe) {
    // Emit Keyframe
    
    char *buffer = cgBuffer.pixels;
    int numBytesInBuffer = cgBuffer.numBytes;
    
    worked = [mvidWriter writeKeyframe:buffer bufferSize:numBytesInBuffer];
    
    if (worked == FALSE) {
      fprintf(stderr, "cannot write keyframe data to mvid file \"%s\"\n", [mvidWriter.mvidPath UTF8String]);
      exit(1);
    }
  } else {
    // Emit the delta frame
    
    if (encodedDeltaData == nil) {
      // The two frames are pixel identical, this is a no-op delta frame
      
      [mvidWriter writeNopFrame];
      worked = TRUE;
    } else {
      // Convert generic maxvid codes to c4 codes and emit as a data buffer
      
      void *pixelsPtr = (void*)cgBuffer.pixels;
      int inputBufferNumBytes = cgBuffer.numBytes;
      NSUInteger frameBufferNumPixels = cgBuffer.width * cgBuffer.height;
      
      worked = maxvid_write_delta_pixels(mvidWriter,
                                         encodedDeltaData,
                                         pixelsPtr,
                                         inputBufferNumBytes,
                                         frameBufferNumPixels,
                                         encodeFlags);
    }
    
    if (worked == FALSE) {
      fprintf(stderr, "cannot write deltaframe data to mvid file \"%s\"\n", [mvidWriter.mvidPath UTF8String]);
      exit(1);
    }
  }
}

#if MV_ENABLE_DELTAS

// This method implements the "writing" portion of the frame emit logic for case where
// pixel deltas will be generated. Pixel deltas imply that a diff of every frame is needed
// since the delta logic is tied up with the delta logic.

void process_frame_file_write_deltas(BOOL isKeyframe,
                                     CGFrameBuffer *cgBuffer,
                                     CGFrameBuffer *emptyInitialFrameBuffer,
                                     AVMvidFileWriter *mvidWriter)
{
  BOOL worked;
  
  // In the case of the first frame, we need to create a fake "empty" previous frame so that
  // delta logic can generate a diff from all black to the current frame.
  
  if (emptyInitialFrameBuffer) {
    [emptyInitialFrameBuffer retain];
    prevFrameBuffer = emptyInitialFrameBuffer;
  }
  
  if (mvidWriter.isAllKeyframes) {
    // This type of file contains all deltas, so we know it
    // is not "all feyframes"

    mvidWriter.isAllKeyframes = FALSE;
  }
  
#if MV_ENABLE_DELTAS
  // Mark the mvid file as containing all frame deltas and pixel deltas
  mvidWriter.isDeltas = TRUE;
#endif // MV_ENABLE_DELTAS
  
  // Run delta calculation in all cases, a keyframe in the initial frame is basically just the
  // same as a plain delta. Note that all frames are deltas when emitting pixel deltas, no
  // specific support for keyframes exists in this mode since max space savings is the goal.
  // The decoder will implicitly create an all black prev frame also.
  
  NSData *encodedDeltaData = nil;
  
  assert(prevFrameBuffer);
  
  assert(prevFrameBuffer.width == cgBuffer.width);
  assert(prevFrameBuffer.height == cgBuffer.height);
  assert(prevFrameBuffer.bitsPerPixel == cgBuffer.bitsPerPixel);
  
  void *prevPixels = (void*)prevFrameBuffer.pixels;
  void *currentPixels = (void*)cgBuffer.pixels;
  int numWords;
  int width = cgBuffer.width;
  int height = cgBuffer.height;
  
  // In the case of deltas, set this special flag to indicate that DUP codes
  // should not be generated. Instead, only COPY codes will be emitted. This
  // leads to less code overhead since only SKIP and COPY codes should be
  // emitted.

  //uint32_t encodeFlags = 0;
  uint32_t encodeFlags = MaxvidEncodeFlags_NO_DUP;
  
  // Note that we pass NULL as the emitKeyframeAnyway argument to explicitly
  // ignore the case where all the pixels change. We want to emit a delta
  // in the case, not a keyframe.
  
  if (prevFrameBuffer.bitsPerPixel == 16) {
    numWords = cgBuffer.numBytes / sizeof(uint16_t);
    encodedDeltaData = maxvid_encode_generic_delta_pixels16(prevPixels,
                                                            currentPixels,
                                                            numWords,
                                                            width,
                                                            height,
                                                            NULL,
                                                            encodeFlags);
    
  } else {
    numWords = cgBuffer.numBytes / sizeof(uint32_t);
    encodedDeltaData = maxvid_encode_generic_delta_pixels32(prevPixels,
                                                            currentPixels,
                                                            numWords,
                                                            width,
                                                            height,
                                                            NULL,
                                                            encodeFlags);
  }
  
  // Emit the delta frame
  
  if (encodedDeltaData == nil) {
    // The two frames are pixel identical, this is a no-op delta frame
    
    if (emptyInitialFrameBuffer) {
      // Special case handler for first frame that is a nop frame, this basically
      // means that an all black prev frame should be used.
      [mvidWriter writeInitialNopFrame];
    } else {
      [mvidWriter writeNopFrame];
    }

    worked = TRUE;
  } else {
    // There is a bunch of tricky logic involved in converting the raw deltas pixels
    // into a set of generic codes that capture all the pixels in the delta. Use
    // the output of the generic delta pixels logic as input to another method that
    // will examine the COPY (and possibly the DUP codes) and transform these
    // COPY codes to COPYD codes which indicate application of a pixel delta.
    
    void *pixelsPtr = (void*)cgBuffer.pixels;
    int inputBufferNumBytes = cgBuffer.numBytes;
    NSUInteger frameBufferNumPixels = cgBuffer.width * cgBuffer.height;
    
    NSMutableData *recodedDeltaData = [NSMutableData data];
    
    uint32_t processAsBPP;
    if (cgBuffer.bitsPerPixel == 16) {
      processAsBPP = 16;
    } else {
      processAsBPP = 32;
    }
    
    // Rewrite pixel values using previous pixel values as opposed to
    // absolute pixel values. This logic will not change the generic
    // codes, it will only modify the pixel values of the COPY and
    // DUP values.
    
    worked = maxvid_deltas_compress(encodedDeltaData,
                                    recodedDeltaData,
                                    pixelsPtr,
                                    inputBufferNumBytes,
                                    frameBufferNumPixels,
                                    processAsBPP);
    
    if (worked == FALSE) {
      fprintf(stderr, "cannot recode delta data to pixel delta\n");
      exit(1);
    }
    
    // Convert generic maxvid codes to c4 codes and emit as a data buffer
    
    worked = maxvid_write_delta_pixels(mvidWriter,
                                       recodedDeltaData,
                                       pixelsPtr,
                                       inputBufferNumBytes,
                                       frameBufferNumPixels,
                                       encodeFlags);
    
    // FIXME: if additional modification is needed then translate the code values
    // of the c4 codes after writing. For example, if there will be more COPY
    // codes than SKIP, then make SKIP 0x0 and make DUP 0x1 so that there will
    // be the maximul number of zero bits in a row. Another possible optimization
    // would be to store the SKIP and number values so that the 1 values are together
    // for the most common small values. This might result in additional compression
    // even though the actual values would be the same
  }
  
  if (worked == FALSE) {
    fprintf(stderr, "cannot write deltaframe data to mvid file \"%s\"\n", [mvidWriter.mvidPath UTF8String]);
    exit(1);
  }
}

#endif // MV_ENABLE_DELTAS

// Extract all the frames of movie data from an archive file into
// files indicated by a path prefix.

typedef enum
{
  EXTRACT_FRAMES_TYPE_PNG = 0,
  EXTRACT_FRAMES_TYPE_PIXELS,
  EXTRACT_FRAMES_TYPE_CODEC
} ExtractFramesType;

void extractFramesFromMvidMain(char *mvidFilename,
                               char *extractFramesPrefix,
                               ExtractFramesType type) {
	BOOL worked;
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];

	NSString *mvidPath = [NSString stringWithUTF8String:mvidFilename];
  
  worked = [frameDecoder openForReading:mvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open mvid filename \"%s\"\n", mvidFilename);
    exit(1);
  }
    
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);

  int isV3 = (maxvid_file_version([frameDecoder header]) == MV_FILE_VERSION_THREE);
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
    assert(frame);
    
    // Release the NSImage ref inside the frame since we will operate on the CG image directly.
    frame.image = nil;
    
    CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
    assert(cgFrameBuffer);
    
    // The frame decoder should have created the frame buffers using the sRGB colorspace.
    
    CGColorSpaceRef sRGBColorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    assert(sRGBColorspace == cgFrameBuffer.colorspace);
    CGColorSpaceRelease(sRGBColorspace);

    NSString *outFilename;
    
    if (type == EXTRACT_FRAMES_TYPE_PNG) {
      NSData *pngData = [cgFrameBuffer formatAsPNG];
      assert(pngData);
      
      outFilename = [NSString stringWithFormat:@"%s%0.4d%s", extractFramesPrefix, frameIndex+1, ".png"];
      
      [pngData writeToFile:outFilename atomically:NO];
    } else if (type == EXTRACT_FRAMES_TYPE_PIXELS) {
      // Write data as "*.pixels" with format {WIDTH HEIGHT PIXEL0 PIXEL1 ...}

      outFilename = [NSString stringWithFormat:@"%s%0.4d%s", extractFramesPrefix, frameIndex+1, ".pixels"];
      
      FILE *outfd = fopen((char*)[outFilename UTF8String], "wb");
      assert(outfd);
      
      uint32_t width = (uint32_t)cgFrameBuffer.width;
      uint32_t height = (uint32_t)cgFrameBuffer.height;
      
      int result;
      
      result = (int)fwrite(&width, sizeof(uint32_t), 1, outfd);
      assert(result == 1);
      result = (int)fwrite(&height, sizeof(uint32_t), 1, outfd);
      assert(result == 1);
      
      uint32_t size = sizeof(uint32_t);
      if (cgFrameBuffer.bitsPerPixel == 16) {
        size = sizeof(uint16_t);
      }
      
      result = (int)fwrite(cgFrameBuffer.pixels, size * width * height, 1, outfd);
      assert(result == 1);
      
      fclose(outfd);
    } else if (type == EXTRACT_FRAMES_TYPE_CODEC && !isV3) {
      // Read the frame data encoded with codec specific word values.
      // Format: {WIDTH HEIGHT IS_DELTA WORD0 WORD1 ...}
      
      MVFrame *frame = maxvid_file_frame(frameDecoder.mvFrames, frameIndex);
      assert(frame);
      
      outFilename = [NSString stringWithFormat:@"%s%0.4d%s", extractFramesPrefix, frameIndex+1, ".codec"];
      
      FILE *outfd = fopen((char*)[outFilename UTF8String], "wb");
      assert(outfd);
      
      uint32_t width = (uint32_t)cgFrameBuffer.width;
      uint32_t height = (uint32_t)cgFrameBuffer.height;
      
      if (maxvid_frame_isnopframe(frame)) {
        // A nop frame is the same as the previous one, write a zero length file.
      } else {
        // Write: WIDTH HEIGHT
        
        int result;
        
        result = (int)fwrite(&width, sizeof(uint32_t), 1, outfd);
        assert(result == 1);
        result = (int)fwrite(&height, sizeof(uint32_t), 1, outfd);
        assert(result == 1);
        
        // Write: IS_DELTA
        
        uint32_t is_delta = 1;
        if (maxvid_frame_iskeyframe(frame)) {
          is_delta = 0;
        }
        
        result = (int)fwrite(&is_delta, sizeof(uint32_t), 1, outfd);
        assert(result == 1);
        
        // Write: WORDS
        
        // The memory is already mapped, so just get the pointer to
        // the front of the frame data and the length.
              
        uint32_t offset = maxvid_frame_offset(frame);
        uint32_t length = maxvid_frame_length(frame);
        
        uint32_t *frameDataPtr = (uint32_t*) (frameDecoder.mappedData.bytes + offset);
        
        result = (int)fwrite(frameDataPtr, length, 1, outfd);
        assert(result == 1);
      }
      
      fclose(outfd);
    } else if (type == EXTRACT_FRAMES_TYPE_CODEC && isV3) {
      // Read the frame data encoded with codec specific word values.
      // Format: {WIDTH HEIGHT IS_DELTA WORD0 WORD1 ...}
      
      MVV3Frame *frame = maxvid_v3_file_frame(frameDecoder.mvFrames, frameIndex);
      assert(frame);
      
      outFilename = [NSString stringWithFormat:@"%s%0.4d%s", extractFramesPrefix, frameIndex+1, ".codec"];
      
      FILE *outfd = fopen((char*)[outFilename UTF8String], "wb");
      assert(outfd);
      
      uint32_t width = (uint32_t)cgFrameBuffer.width;
      uint32_t height = (uint32_t)cgFrameBuffer.height;
      
      if (maxvid_v3_frame_isnopframe(frame)) {
        // A nop frame is the same as the previous one, write a zero length file.
      } else {
        // Write: WIDTH HEIGHT
        
        int result;
        
        result = (int)fwrite(&width, sizeof(uint32_t), 1, outfd);
        assert(result == 1);
        result = (int)fwrite(&height, sizeof(uint32_t), 1, outfd);
        assert(result == 1);
        
        // Write: IS_DELTA
        
        uint32_t is_delta = 1;
        if (maxvid_v3_frame_iskeyframe(frame)) {
          is_delta = 0;
        }
        
        result = (int)fwrite(&is_delta, sizeof(uint32_t), 1, outfd);
        assert(result == 1);
        
        // Write: WORDS
        
        // The memory is already mapped, so just get the pointer to
        // the front of the frame data and the length.
        
        uint64_t offset = maxvid_v3_frame_offset(frame);
        uint32_t length = maxvid_v3_frame_length(frame);
        
        uint32_t *frameDataPtr = (uint32_t*) (frameDecoder.mappedData.bytes + offset);
        
        result = (int)fwrite(frameDataPtr, length, 1, outfd);
        assert(result == 1);
      }
      
      fclose(outfd);
    } else {
      assert(0);
    }
        
    NSString *dupString = @"";
    if (frame.isDuplicate) {
      dupString = @" (duplicate)";
    }
    
    fprintf(stdout, "wrote %s%s\n", [outFilename UTF8String], [dupString UTF8String]);
    
    [pool drain];
  }

  [frameDecoder close];
  
	return;
}

// Return TRUE if file exists, FALSE otherwise

BOOL fileExists(NSString *filePath) {
  if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
    return TRUE;
	} else {
    return FALSE;
  }
}

// Entry point for logic that encodes a .mvid from a series of frames.

void encodeMvidFromFramesMain(char *mvidFilenameCstr,
                              char *firstFilenameCstr,
                              MovieOptions *optionsPtr)
{
  NSString *mvidFilename = [NSString stringWithUTF8String:mvidFilenameCstr];
  
  BOOL isMvid = [mvidFilename hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  // Given the first frame image filename, build and array of filenames
  // by checking to see if files exist up until we find one that does not.
  // This makes it possible to pass the 25th frame ofa 50 frame animation
  // and generate an animation 25 frames in duration.
  
  NSString *firstFilename = [NSString stringWithUTF8String:firstFilenameCstr];
  
  if (fileExists(firstFilename) == FALSE) {
    fprintf(stderr, "error: first filename \"%s\" does not exist\n", firstFilenameCstr);
    exit(1);
  }
  
  NSString *firstFilenameExt = [firstFilename pathExtension];
    
  // Find first numerical character in the [0-9] range starting at the end of the filename string.
  // A frame filename like "Frame0001.png" would be an example input. Note that the last frame
  // number must be the last character before the extension.
  
  NSArray *upToLastPathComponent = [firstFilename pathComponents];
  NSRange upToLastPathComponentRange;
  upToLastPathComponentRange.location = 0;
  upToLastPathComponentRange.length = [upToLastPathComponent count] - 1;
  upToLastPathComponent = [upToLastPathComponent subarrayWithRange:upToLastPathComponentRange];
  NSString *upToLastPathComponentPath = [NSString pathWithComponents:upToLastPathComponent];
  
  NSString *firstFilenameTail = [firstFilename lastPathComponent];
  NSString *firstFilenameTailNoExtension = [firstFilenameTail stringByDeletingPathExtension];
  
  int numericStartIndex = -1;
  BOOL foundNonAlpha = FALSE;
  
  for (int i = [firstFilenameTailNoExtension length] - 1; i > 0; i--) {
    unichar c = [firstFilenameTailNoExtension characterAtIndex:i];
    if ((c >= '0') && (c <= '9') && (foundNonAlpha == FALSE)) {
      numericStartIndex = i;
    } else {
      foundNonAlpha = TRUE;
    }
  }
  if (numericStartIndex == -1 || numericStartIndex == 0) {
    fprintf(stderr, "error: could not find frame number in first filename \"%s\"\n", firstFilenameCstr);
    exit(1);
  }
  
  // Extract the numeric portion of the first frame filename
  
  NSString *namePortion = [firstFilenameTailNoExtension substringToIndex:numericStartIndex];
  NSString *numberPortion = [firstFilenameTailNoExtension substringFromIndex:numericStartIndex];
  
  if ([namePortion length] < 1 || [numberPortion length] == 0) {
    fprintf(stderr, "error: could not find frame number in first filename \"%s\"\n", firstFilenameCstr);
    exit(1);
  }
  
  // Convert number with leading zeros to a simple integer
  
  NSMutableArray *inFramePaths = [NSMutableArray arrayWithCapacity:1024];
  
  int formatWidth = [numberPortion length];
  int startingFrameNumber = [numberPortion intValue];
  int endingFrameNumber = -1;
  
#define CRAZY_MAX_FRAMES 9999999
#define CRAZY_MAX_DIGITS 7
  
  // Note that we include the first frame in this loop just so that it gets added to inFramePaths.
  
  for (int i = startingFrameNumber; i < CRAZY_MAX_FRAMES; i++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSMutableString *frameNumberWithLeadingZeros = [NSMutableString string];
    [frameNumberWithLeadingZeros appendFormat:@"%07d", i];
    if ([frameNumberWithLeadingZeros length] > formatWidth) {
      int numToDelete = [frameNumberWithLeadingZeros length] - formatWidth;
      NSRange delRange;
      delRange.location = 0;
      delRange.length = numToDelete;
      [frameNumberWithLeadingZeros deleteCharactersInRange:delRange];
      assert([frameNumberWithLeadingZeros length] == formatWidth);
    }
    [frameNumberWithLeadingZeros appendString:@"."];
    [frameNumberWithLeadingZeros appendString:firstFilenameExt];
    [frameNumberWithLeadingZeros insertString:namePortion atIndex:0];
    NSString *framePathWithNumber = [upToLastPathComponentPath stringByAppendingPathComponent:frameNumberWithLeadingZeros];
    
    if (fileExists(framePathWithNumber)) {
      // Found frame at indicated path, add it to array of known frame filenames
      
      [inFramePaths addObject:framePathWithNumber];
      endingFrameNumber = i;
    } else {
      // Frame filename with indicated frame number not found, done scanning for frame files
      [pool drain];
      break;
    }
    
    [pool drain];
  }

  if ([inFramePaths count] <= 1) {
    fprintf(stderr, "error: at least 2 input frames are required\n");
    exit(1);    
  }
  
  if ((startingFrameNumber == endingFrameNumber) || (endingFrameNumber == CRAZY_MAX_FRAMES-1)) {
    fprintf(stderr, "error: could not find last frame number\n");
    exit(1);
  }
  
  // FRAMERATE is a floating point number that indicates the delay between frames.
  // This framerate value is a constant that does not change over the course of the
  // movie, though it is possible that a certain frame could repeat a number of times.
  
  float framerateNum = optionsPtr->framerate;

  if (framerateNum <= 0.0f) {
    fprintf(stderr, "error: -framerate or -fps is required\n");
    exit(1);
  }
  
  // KEYFRAME : integer that indicates a keyframe should be emitted every N frames
  
  int keyframeNum = optionsPtr->keyframe;
  if (keyframeNum == 0 || keyframeNum == 1) {
    // All frames as stored as keyframes. This takes up more space but the frames can
    // be blitted into graphics memory directly from mapped memory at runtime.
    keyframeNum = 0;
  } else if (keyframeNum < 0) {
    // Just revert to the default
    keyframeNum = 10000;
  }
  
  // BITSPERPIXEL : 16, 24, or 32 BPP.
  //
  // Determine the BPP that the output movie will be written as, when reading from image
  // files 16BPP input data would automatically be converted to 24BPP before the data
  // could be read, so this logic only needs to determine the setting for the check alpha
  // logic.
  
  BOOL checkAlphaChannel;
  int renderAtBpp;
  
  if (optionsPtr->bpp == -1) {
    // No -bpp option given on the command line, detect either 24BPP or 32BPP depending
    // on the pixel data read from the image frames.
    
    renderAtBpp = 24;
    checkAlphaChannel = TRUE;
  } else {
    // When -bpp is explicitly set on the command line, checkAlphaChannel is always FALSE
    checkAlphaChannel = FALSE;
    
    if (optionsPtr->bpp == 16) {
      renderAtBpp = 16;
    } else if (optionsPtr->bpp == 24) {
      renderAtBpp = 24;
    } else {
      renderAtBpp = 32;
    }
  }

  // Stage 1: scan all the pixels in all the frames to figure out key info like the BPP
  // of output pixels. We cannot know certain key info about the input data until it
  // has all been scanned.
  
  MvidFileMetaData *mvidFileMetaData = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaData.bpp = renderAtBpp;
  mvidFileMetaData.checkAlphaChannel = checkAlphaChannel;
  //mvidFileMetaData.recordFramePixelValues = TRUE;
  
  int frameIndex;
  
  frameIndex = 0;
  for (NSString *framePath in inFramePaths) {
    //fprintf(stdout, "saved %s as frame %d\n", [framePath UTF8String], frameIndex+1);
    //fflush(stdout);
    
    BOOL isKeyframe = FALSE;
    if (frameIndex == 0) {
      isKeyframe = TRUE;
    }
    if (keyframeNum == 0) {
      // All frames are key frames
      isKeyframe = TRUE;
    } else if ((keyframeNum > 0) && ((frameIndex % keyframeNum) == 0)) {
      // Keyframe every N frames
      isKeyframe = TRUE;
    }
        
    process_frame_file(NULL, framePath, NULL, frameIndex, mvidFileMetaData, isKeyframe, optionsPtr);
    frameIndex++;
  }
  
  // Stage 2: once scanning all the input pixels is completed, we can loop over all the frames
  // again but this time we actually write the output at the correct BPP. The scan step takes
  // extra time, but it means that we do not need to write twice in the common case where
  // input is all 24 BPP pixels, so this logic is a win.
  
  if (mvidFileMetaData.recordFramePixelValues) {
    [mvidFileMetaData doneRecordingFramePixelValues];
  }

  renderAtBpp = mvidFileMetaData.bpp;
  mvidFileMetaData.checkAlphaChannel = FALSE;
  
  AVMvidFileWriter *mvidWriter;
  mvidWriter = makeMVidWriter(mvidFilename, renderAtBpp, framerateNum, [inFramePaths count]);
  
  fprintf(stdout, "writing %d frames to %s\n", [inFramePaths count], [[mvidFilename lastPathComponent] UTF8String]);
  fflush(stdout);
  
  // We now know the start and end integer values of the frame filename range.
  
  frameIndex = 0;
  for (NSString *framePath in inFramePaths) {
    //fprintf(stdout, "saved %s as frame %d\n", [framePath UTF8String], frameIndex+1);
    //fflush(stdout);
    
    BOOL isKeyframe = FALSE;
    if (frameIndex == 0) {
      isKeyframe = TRUE;
    }
    if (keyframeNum == 0) {
      // All frames are key frames
      isKeyframe = TRUE;
    } else if ((keyframeNum > 0) && ((frameIndex % keyframeNum) == 0)) {
      // Keyframe every N frames
      isKeyframe = TRUE;
    }
    
    process_frame_file(mvidWriter, framePath, NULL, frameIndex, mvidFileMetaData, isKeyframe, optionsPtr);
    frameIndex++;
  }
  
  // Done writing .mvid file
  
  [mvidWriter rewriteHeader];
  
  [mvidWriter close];
    
  fprintf(stdout, "done writing %d frames to %s\n", frameIndex, mvidFilenameCstr);
  fflush(stdout);
  
  // cleanup
  
  if (prevFrameBuffer) {
    [prevFrameBuffer release];
  }
}

void fprintStdoutFixedWidth(char *label)
{
  fprintf(stdout, "%-20s", label);
}

// Entry point for movie info printing logic. This will print the headers of the file
// and some encoding info.

void printMovieHeaderInfo(char *mvidFilenameCstr) {
  NSString *mvidFilename = [NSString stringWithUTF8String:mvidFilenameCstr];

  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked = [frameDecoder openForReading:mvidFilename];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open mvid filename \"%s\"\n", mvidFilenameCstr);
    exit(1);
  }
  
  //worked = [frameDecoder allocateDecodeResources];
  //assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);

  float frameDuration = [frameDecoder frameDuration];
  float movieDuration = frameDuration * numFrames;
  
  int bpp = [frameDecoder header]->bpp;
  
  // Format left side in fixed 20 space width
  
  fprintStdoutFixedWidth("MVID:");
  fprintf(stdout, "%s\n", [[mvidFilename lastPathComponent] UTF8String]);
  
  fprintStdoutFixedWidth("Version:");
  int version = maxvid_file_version([frameDecoder header]);
  fprintf(stdout, "%d\n", version);

  fprintStdoutFixedWidth("Width:");
  fprintf(stdout, "%d\n", [frameDecoder width]);
  
  fprintStdoutFixedWidth("Height:");
  fprintf(stdout, "%d\n", [frameDecoder height]);

  fprintStdoutFixedWidth("BitsPerPixel:");
  fprintf(stdout, "%d\n", bpp);

  // Note that pixels stored in .mvid file are always in the sRGB colorspace.
  // If any conversions are needed to convert from some other colorspace, they
  // would need to have been executed when writing the .mvid file.
  
  fprintStdoutFixedWidth("ColorSpace:");
  if (TRUE) {
    fprintf(stdout, "%s\n", "sRGB");
  } else {
    fprintf(stdout, "%s\n", "RGB");    
  }
  
  fprintStdoutFixedWidth("Duration:");
  fprintf(stdout, "%.4fs\n", movieDuration);

  fprintStdoutFixedWidth("FrameDuration:");
  fprintf(stdout, "%.4fs\n", frameDuration);

  fprintStdoutFixedWidth("FPS:");
  fprintf(stdout, "%.4f\n", (1.0f / frameDuration));

  fprintStdoutFixedWidth("Frames:");
  fprintf(stdout, "%d\n", numFrames);
  
  // If the "all keyframes" bit is set then print TRUE for this element
  
  fprintStdoutFixedWidth("AllKeyFrames:");
  fprintf(stdout, "%s\n", [frameDecoder isAllKeyframes] ? "TRUE" : "FALSE");
  
#if MV_ENABLE_DELTAS
  
  // If the "deltas" bit is set, then print TRUE to indicate that all
  // pixel values are deltas and all frames are deltas.

  fprintStdoutFixedWidth("Deltas:");
  fprintf(stdout, "%s\n", [frameDecoder isDeltas] ? "TRUE" : "FALSE");
  
#endif // MV_ENABLE_DELTAS
  
  [frameDecoder close];
}

// testmode() runs a series of basic test logic having to do with rendering
// and then checking the results of a graphics render operation.

#if defined(TESTMODE)

static inline
NSString* bgra_to_string(uint32_t pixel) {
  uint8_t alpha = (pixel >> 24) & 0xFF;
  uint8_t red = (pixel >> 16) & 0xFF;
  uint8_t green = (pixel >> 8) & 0xFF;
  uint8_t blue = (pixel >> 0) & 0xFF;
  return [NSString stringWithFormat:@"(%d, %d, %d, %d)", red, green, blue, alpha];
}

void testmode()
{
  // Create a framebuffer that contains a 75% gray color in 16bpp and device RGB
  
  @autoreleasepool
  {
    int bppNum = 16;
    int width = 2;
    int height = 2;
    
    CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    uint16_t *pixels = (uint16_t *)cgBuffer.pixels;
    int numPixels = width * height;
    
    uint32_t grayLevel = (int) (0x1F * 0.75);
    uint16_t grayPixel = (grayLevel << 10) | (grayLevel << 5) | grayLevel;
    
    for (int i=0; i < numPixels; i++) {
      pixels[i] = grayPixel;
    }
    
    // Create image from test data
    
    CGImageRef imageRef = [cgBuffer createCGImageRef];
    
    // Render test image into a new CGFrameBuffer and then verify that the pixel value is the same
    
    CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    [renderBuffer renderCGImage:imageRef];
    
    uint16_t *renderPixels = (uint16_t *)renderBuffer.pixels;
    
    for (int i=0; i < numPixels; i++) {
      uint16_t pixel = renderPixels[i];      
      assert(pixel == grayPixel);
    }
  }
  
  // Create a framebuffer that contains a 75% gray color in 24bpp and device RGB
  
  @autoreleasepool
  {
    int bppNum = 24;
    int width = 2;
    int height = 2;
    
    CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
   
    uint32_t *pixels = (uint32_t *)cgBuffer.pixels;
    //int numBytes = cgBuffer.numBytes;
    int numPixels = width * height;
    int numBytes = numPixels * sizeof(uint32_t);

    uint32_t grayLevel = (int) (255 * 0.75);
    uint32_t grayPixel = rgba_to_bgra(grayLevel, grayLevel, grayLevel, 0xFF);
    
    for (int i=0; i < numPixels; i++) {
      pixels[i] = grayPixel;
    }
    
    // calculate alder
    
    uint32_t adler1 = maxvid_adler32(0L, (unsigned char *)pixels, numBytes);
    assert(adler1 != 0);
    
    // Create image from test data
    
    CGImageRef imageRef = [cgBuffer createCGImageRef];
    
    // Render test image into a new CGFrameBuffer and then verify that the pixel value is the same
    
    CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    [renderBuffer renderCGImage:imageRef];
    
    uint32_t *renderPixels = (uint32_t *)renderBuffer.pixels;
    
    for (int i=0; i < numPixels; i++) {
      uint32_t pixel = renderPixels[i];      
      assert(pixel == grayPixel);
    }
    
    uint32_t adler2 = maxvid_adler32(0L, (unsigned char *)renderPixels, numBytes);
    assert(adler2 != 0);

    assert(adler1 == adler2);
  }
  
  // Create a framebuffer that contains a 75% gray color with alpha 0xFF in 32bpp and device RGB
  
  @autoreleasepool
  {
    int bppNum = 32;
    int width = 2;
    int height = 2;
    
    CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    uint32_t *pixels = (uint32_t *)cgBuffer.pixels;
    //int numBytes = cgBuffer.numBytes;
    int numPixels = width * height;
    //int numBytes = numPixels * sizeof(uint32_t);
    
    uint32_t grayLevel = (int) (255 * 0.75);
    uint32_t grayPixel = rgba_to_bgra(grayLevel, grayLevel, grayLevel, 0xFF);
    
    for (int i=0; i < numPixels; i++) {
      pixels[i] = grayPixel;
    }
    
    // Create image from test data
    
    CGImageRef imageRef = [cgBuffer createCGImageRef];
    
    // Render test image into a new CGFrameBuffer and then verify that the pixel value is the same
    
    CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    [renderBuffer renderCGImage:imageRef];
    
    uint32_t *renderPixels = (uint32_t *)renderBuffer.pixels;
    
    for (int i=0; i < numPixels; i++) {
      uint32_t pixel = renderPixels[i];      
      assert(pixel == grayPixel);
    }
  }
  
  // Create a framebuffer that contains a 75% gray color with alpha 0.5 in 32bpp and device RGB
  
  @autoreleasepool
  {
    int bppNum = 32;
    int width = 2;
    int height = 2;
    
    CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    uint32_t *pixels = (uint32_t *)cgBuffer.pixels;
    //int numBytes = cgBuffer.numBytes;
    int numPixels = width * height;
    //int numBytes = numPixels * sizeof(uint32_t);
    
    uint32_t grayLevel = (int) (255 * 0.75);
    uint32_t grayPixel = rgba_to_bgra(grayLevel, grayLevel, grayLevel, 0xFF/2);
    
    for (int i=0; i < numPixels; i++) {
      pixels[i] = grayPixel;
    }
    
    // Create image from test data
    
    CGImageRef imageRef = [cgBuffer createCGImageRef];
    
    // Render test image into a new CGFrameBuffer and then verify that the pixel value is the same
    
    CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    [renderBuffer renderCGImage:imageRef];
    
    uint32_t *renderPixels = (uint32_t *)renderBuffer.pixels;
    
    for (int i=0; i < numPixels; i++) {
      uint32_t pixel = renderPixels[i];      
      assert(pixel == grayPixel);
    }
  }
  
  // Create a framebuffer that contains all device RGB pixel values at 24 bpp

  @autoreleasepool
  {
    int bppNum = 24;
    int width = 256;
    int height = 3;
    
    CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    uint32_t *pixels = (uint32_t *)cgBuffer.pixels;
    //int numPixels = width * height;

    int offset = 0;

    for (int step=0; step < 256; step++) {
      uint32_t redPixel = rgba_to_bgra(step, 0, 0, 0xFF);      
      pixels[offset++] = redPixel;
    }

    for (int step=0; step < 256; step++) {
      uint32_t greenPixel = rgba_to_bgra(0, step, 0, 0xFF);      
      pixels[offset++] = greenPixel;
    }    

    for (int step=0; step < 256; step++) {
      uint32_t bluePixel = rgba_to_bgra(0, 0, step, 0xFF);      
      pixels[offset++] = bluePixel;
    }
    
    assert(offset == (256 * 3));
    
    // Create image from test data
    
    CGImageRef imageRef = [cgBuffer createCGImageRef];
    
    // Render test image into a new CGFrameBuffer and then verify that the pixel value is the same
    
    CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    [renderBuffer renderCGImage:imageRef];
    
    uint32_t *renderPixels = (uint32_t *)renderBuffer.pixels;
    
    offset = 0;
    
    for (int step=0; step < 256; step++) {
      uint32_t redPixel = rgba_to_bgra(step, 0, 0, 0xFF);  
      uint32_t pixel = renderPixels[offset++];
      assert(pixel == redPixel);
    }
    
    for (int step=0; step < 256; step++) {
      uint32_t greenPixel = rgba_to_bgra(0, step, 0, 0xFF);  
      uint32_t pixel = renderPixels[offset++];
      assert(pixel == greenPixel);
    }    

    for (int step=0; step < 256; step++) {
      uint32_t bluePixel = rgba_to_bgra(0, 0, step, 0xFF);  
      uint32_t pixel = renderPixels[offset++];
      assert(pixel == bluePixel);
    }
    
    assert(offset == (256 * 3));
  }

  // Create a framebuffer that contains all sRGB pixel values at 24 bpp
  
  @autoreleasepool
  {
    int bppNum = 24;
    int width = 256;
    int height = 3;
    
    CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];

    CGColorSpaceRef colorSpace;
    colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    assert(colorSpace);
    
    cgBuffer.colorspace = colorSpace;
    
    uint32_t *pixels = (uint32_t *)cgBuffer.pixels;
    //int numPixels = width * height;
    
    int offset = 0;
    
    for (int step=0; step < 256; step++) {
      uint32_t redPixel = rgba_to_bgra(step, 0, 0, 0xFF);
      pixels[offset++] = redPixel;
    }
    
    for (int step=0; step < 256; step++) {
      uint32_t greenPixel = rgba_to_bgra(0, step, 0, 0xFF);
      pixels[offset++] = greenPixel;
    }    
    
    for (int step=0; step < 256; step++) {
      uint32_t bluePixel = rgba_to_bgra(0, 0, step, 0xFF);
      pixels[offset++] = bluePixel;
    }
    
    assert(offset == (256 * 3));
    
    // Create image from test data
    
    CGImageRef imageRef = [cgBuffer createCGImageRef];
    
    // Render test image into a new CGFrameBuffer and then verify that the pixel value is the same
    
    CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    renderBuffer.colorspace = colorSpace;
    CGColorSpaceRelease(colorSpace);
    
    [renderBuffer renderCGImage:imageRef];
        
    uint32_t *renderPixels = (uint32_t *)renderBuffer.pixels;
    
    offset = 0;
    
    for (int step=0; step < 256; step++) {
      uint32_t redPixel = rgba_to_bgra(step, 0, 0, 0xFF);  
      uint32_t pixel = renderPixels[offset++];
      assert(pixel == redPixel);
    }
    
    for (int step=0; step < 256; step++) {
      uint32_t greenPixel = rgba_to_bgra(0, step, 0, 0xFF);  
      uint32_t pixel = renderPixels[offset++];
      assert(pixel == greenPixel);
    }    
    
    for (int step=0; step < 256; step++) {
      uint32_t bluePixel = rgba_to_bgra(0, 0, step, 0xFF);  
      uint32_t pixel = renderPixels[offset++];
      assert(pixel == bluePixel);
    }
    
    assert(offset == (256 * 3));
  }
  
  // Create a framebuffer that contains device RGB pixel values with an alpha step at 32bpp
  
  @autoreleasepool
  {
    int bppNum = 32;
    int width = 256;
    int height = 3;
    
    CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    uint32_t *pixels = (uint32_t *)cgBuffer.pixels;
    
    int offset = 0;
    
    for (int step=0; step < 256; step++) {
      uint32_t redPixel = rgba_to_bgra(0xFF, 0, 0, step);
      pixels[offset++] = redPixel;
    }
    
    for (int step=0; step < 256; step++) {
      uint32_t greenPixel = rgba_to_bgra(0, 0xFF, 0, step);
      pixels[offset++] = greenPixel;
    }    
    
    for (int step=0; step < 256; step++) {
      uint32_t bluePixel = rgba_to_bgra(0, 0, 0xFF, step);
      pixels[offset++] = bluePixel;
    }
    
    assert(offset == (256 * 3));
    
    // Create image from test data
    
    CGImageRef imageRef = [cgBuffer createCGImageRef];
    
    // Render test image into a new CGFrameBuffer and then verify that the pixel value is the same
    
    CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    [renderBuffer renderCGImage:imageRef];
    
    uint32_t *renderPixels = (uint32_t *)renderBuffer.pixels;
    
    offset = 0;
    
    for (int step=0; step < 256; step++) {
      uint32_t redPixel = rgba_to_bgra(0xFF, 0, 0, step);
      uint32_t pixel = renderPixels[offset++];
      assert(pixel == redPixel);
    }
    
    for (int step=0; step < 256; step++) {
      uint32_t greenPixel = rgba_to_bgra(0, 0xFF, 0, step);
      uint32_t pixel = renderPixels[offset++];
      assert(pixel == greenPixel);
    }    
    
    for (int step=0; step < 256; step++) {
      uint32_t bluePixel = rgba_to_bgra(0, 0, 0xFF, step);
      uint32_t pixel = renderPixels[offset++];
      assert(pixel == bluePixel);
    }
    
    assert(offset == (256 * 3));
  }

  // Create a framebuffer that contains sRGB pixel values with an alpha step at 32bpp
  
  @autoreleasepool
  {
    int bppNum = 32;
    int width = 256;
    int height = 3;
    
    CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    CGColorSpaceRef colorSpace;
    colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    assert(colorSpace);
    
    cgBuffer.colorspace = colorSpace;
    
    uint32_t *pixels = (uint32_t *)cgBuffer.pixels;
    
    int offset = 0;
    
    for (int step=0; step < 256; step++) {
      uint32_t redPixel = rgba_to_bgra(0xFF, 0, 0, step);
      pixels[offset++] = redPixel;
    }
    
    for (int step=0; step < 256; step++) {
      uint32_t greenPixel = rgba_to_bgra(0, 0xFF, 0, step);
      pixels[offset++] = greenPixel;
    }    
    
    for (int step=0; step < 256; step++) {
      uint32_t bluePixel = rgba_to_bgra(0, 0, 0xFF, step);
      pixels[offset++] = bluePixel;
    }
    
    assert(offset == (256 * 3));
    
    // Create image from test data
    
    CGImageRef imageRef = [cgBuffer createCGImageRef];
    
    // Render test image into a new CGFrameBuffer and then verify that the pixel value is the same
    
    CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    renderBuffer.colorspace = colorSpace;
    CGColorSpaceRelease(colorSpace);
    
    [renderBuffer renderCGImage:imageRef];
    
    uint32_t *renderPixels = (uint32_t *)renderBuffer.pixels;
    
    offset = 0;
    
    for (int step=0; step < 256; step++) {
      uint32_t redPixel = rgba_to_bgra(0xFF, 0, 0, step);
      uint32_t pixel = renderPixels[offset++];
      assert(pixel == redPixel);
    }
    
    for (int step=0; step < 256; step++) {
      uint32_t greenPixel = rgba_to_bgra(0, 0xFF, 0, step);
      uint32_t pixel = renderPixels[offset++];
      assert(pixel == greenPixel);
    }    
    
    for (int step=0; step < 256; step++) {
      uint32_t bluePixel = rgba_to_bgra(0, 0, 0xFF, step);
      uint32_t pixel = renderPixels[offset++];
      assert(pixel == bluePixel);
    }
    
    assert(offset == (256 * 3));
  }
  
  /*
  
  // This test case will create a 1x4 RGB with the pixels (RED, GREEN, BLUE, GRAY)
  // where gray component is 50% gray. These pixels will then be converted to the
  // sRGB colorspace and then back to RGB to make sure the SRGB -> RGB is actually
  // reversing the mapping into sRGB colosspace.
  
  @autoreleasepool
  {
    int bppNum = 24;
    int width = 4;
    int height = 1;
    
    CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
   
    CGColorSpaceRef rgbColorSpace;
    rgbColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    assert(rgbColorSpace);
    cgBuffer.colorspace = rgbColorSpace;
    CGColorSpaceRelease(rgbColorSpace);
    
    uint32_t *pixels = (uint32_t *)cgBuffer.pixels;
    
    pixels[0] = rgba_to_bgra(0xFF, 0, 0, 0xFF);
    pixels[1] = rgba_to_bgra(0, 0xFF, 0, 0xFF);
    pixels[2] = rgba_to_bgra(0, 0, 0xFF, 0xFF);
    pixels[3] = rgba_to_bgra(0xFF/2, 0xFF/2, 0xFF/2, 0xFF);
    
    uint32_t redPixel = pixels[0];
    uint32_t greenPixel = pixels[1];
    uint32_t bluePixel = pixels[2];
    uint32_t grayPixel = pixels[3];
    
    NSString *redStr = bgra_to_string(redPixel);
    NSString *greenStr = bgra_to_string(greenPixel);
    NSString *blueStr = bgra_to_string(bluePixel);
    NSString *grayStr = bgra_to_string(grayPixel);
    
    assert([redStr isEqualToString:@"(255, 0, 0, 255)"]);
    assert([greenStr isEqualToString:@"(0, 255, 0, 255)"]);
    assert([blueStr isEqualToString:@"(0, 0, 255, 255)"]);
    assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
        
    // Create image from test data
    
    CGImageRef imageRef = [cgBuffer createCGImageRef];
    
    // Render test image into a new CGFrameBuffer in sRGB colorspace and then examine pixel values.
    
    CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    CGColorSpaceRef srgbColorSpace;
    srgbColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    renderBuffer.colorspace = srgbColorSpace;
    CGColorSpaceRelease(srgbColorSpace);
    
    [renderBuffer renderCGImage:imageRef];
    CGImageRelease(imageRef);
    
    uint32_t *renderPixels = (uint32_t *)renderBuffer.pixels;

    redPixel = renderPixels[0];
    greenPixel = renderPixels[1];
    bluePixel = renderPixels[2];
    grayPixel = renderPixels[3];
    
    redStr = bgra_to_string(redPixel);
    greenStr = bgra_to_string(greenPixel);
    blueStr = bgra_to_string(bluePixel);
    grayStr = bgra_to_string(grayPixel);
    
    // sRGB values are shifted
    
    assert([redStr isEqualToString:@"(255, 38, 0, 255)"]);
    assert([greenStr isEqualToString:@"(0, 249, 0, 255)"]);
    assert([blueStr isEqualToString:@"(4, 51, 255, 255)"]);
    assert([grayStr isEqualToString:@"(145, 145, 145, 255)"]);
    
    // Emit "RedGreenBlueGray_sRGB.png"
    
    if (TRUE) {
      NSString *filename = @"RedGreenBlueGray_sRGB.png";
      
      NSData *pngData = [renderBuffer formatAsPNG];
      
      [pngData writeToFile:filename atomically:NO];
      
      NSLog(@"wrote %@", filename);
    }
    
    // Now attempt to convert the sRGB values back to GenericRGB to see if the pixel values match.
    
    assert(cgBuffer.isLockedByDataProvider == FALSE);
    memset(cgBuffer.pixels, 0, cgBuffer.numBytes);
    
    imageRef = [renderBuffer createCGImageRef];
    
    [cgBuffer renderCGImage:imageRef];
    CGImageRelease(imageRef);

    redPixel = pixels[0];
    greenPixel = pixels[1];
    bluePixel = pixels[2];
    grayPixel = pixels[3];
    
    redStr = bgra_to_string(redPixel);
    greenStr = bgra_to_string(greenPixel);
    blueStr = bgra_to_string(bluePixel);
    grayStr = bgra_to_string(grayPixel);
    
    assert([redStr isEqualToString:@"(255, 0, 0, 255)"]);
    assert([greenStr isEqualToString:@"(0, 255, 0, 255)"]);
    assert([blueStr isEqualToString:@"(0, 0, 255, 255)"]);
    assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
    
    // Emit "RedGreenBlueGray_RGB.png"
    
    if (TRUE) {
      NSString *filename = @"RedGreenBlueGray_RGB.png";
      
      NSData *pngData = [cgBuffer formatAsPNG];
      
      [pngData writeToFile:filename atomically:NO];
      
      NSLog(@"wrote %@", filename);
    }
  }
   
  */
  
  /*
  
  // This test case will load a 1x4 image from a file on disk. When a file is not tagged
  // with a specific profile, it defaults to a generic RGB profile. This test attempts
  // to determine if loading from a file leads to different results when rendering into
  // sRGB vs setting data directly into a pixel array. One immediate diff to note is
  // that kCGColorSpaceDeviceRGB is the colorspace for a file loaded from disk that has
  // no specific colorspace while the generic RGB profile is actually a profile that can
  // be attached to a file.
  
  @autoreleasepool
  {
    int bppNum = 24;
    int width = 4;
    int height = 1;
    
    // Load "RedGreenBlueGray_RawRGB.png";
    
    NSString *filename;
    
    //filename = @"RedGreenBlueGray_RawRGB.png";
    filename = @"RedGreenBlueGray_Gimp.bmp";
    
    CGImageRef imageRef = createImageFromFile(filename);
    assert(imageRef);
    
    assert(width == CGImageGetWidth(imageRef));
    assert(height == CGImageGetHeight(imageRef));
    
    CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    // When no colorspace is applied to an image, it is loaded with "kCGColorSpaceDeviceRGB"
    
    CGColorSpaceRef rgbColorSpace;
    //rgbColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    rgbColorSpace = CGImageGetColorSpace(imageRef);
    assert(rgbColorSpace);
    cgBuffer.colorspace = rgbColorSpace;
    CGColorSpaceRelease(rgbColorSpace);
    
    [cgBuffer renderCGImage:imageRef];
    
    uint32_t *pixels = (uint32_t *)cgBuffer.pixels;
        
    uint32_t redPixel = pixels[0];
    uint32_t greenPixel = pixels[1];
    uint32_t bluePixel = pixels[2];
    uint32_t grayPixel = pixels[3];
    
    NSString *redStr = bgra_to_string(redPixel);
    NSString *greenStr = bgra_to_string(greenPixel);
    NSString *blueStr = bgra_to_string(bluePixel);
    NSString *grayStr = bgra_to_string(grayPixel);
    
    assert([redStr isEqualToString:@"(255, 0, 0, 255)"]);
    assert([greenStr isEqualToString:@"(0, 255, 0, 255)"]);
    assert([blueStr isEqualToString:@"(0, 0, 255, 255)"]);
    assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
    
    // Create image from test data
    
    if (FALSE) {
      CGImageRelease(imageRef);
      imageRef = [cgBuffer createCGImageRef];
    }
    
    // Render test image into a new CGFrameBuffer in sRGB colorspace and then examine pixel values.
    
    CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    CGColorSpaceRef srgbColorSpace;
    srgbColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    renderBuffer.colorspace = srgbColorSpace;
    CGColorSpaceRelease(srgbColorSpace);
    
    [renderBuffer renderCGImage:imageRef];
    CGImageRelease(imageRef);
    
    uint32_t *renderPixels = (uint32_t *)renderBuffer.pixels;
    
    redPixel = renderPixels[0];
    greenPixel = renderPixels[1];
    bluePixel = renderPixels[2];
    grayPixel = renderPixels[3];
    
    redStr = bgra_to_string(redPixel);
    greenStr = bgra_to_string(greenPixel);
    blueStr = bgra_to_string(bluePixel);
    grayStr = bgra_to_string(grayPixel);
    
    // sRGB values are shifted, not the same as conversion from "Generic RGB"
    
    if (TRUE) {
    assert([redStr isEqualToString:@"(233, 63, 51, 255)"]);
    assert([greenStr isEqualToString:@"(128, 242, 0, 255)"]);
    assert([blueStr isEqualToString:@"(0, 72, 251, 255)"]);
    assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
    }
    
    // Now attempt to convert the sRGB values back to GenericRGB to see if the pixel values match.
    
    assert(cgBuffer.isLockedByDataProvider == FALSE);
    memset(cgBuffer.pixels, 0, cgBuffer.numBytes);
    
    imageRef = [renderBuffer createCGImageRef];
    
    [cgBuffer renderCGImage:imageRef];
    CGImageRelease(imageRef);
    
    redPixel = pixels[0];
    greenPixel = pixels[1];
    bluePixel = pixels[2];
    grayPixel = pixels[3];
    
    redStr = bgra_to_string(redPixel);
    greenStr = bgra_to_string(greenPixel);
    blueStr = bgra_to_string(bluePixel);
    grayStr = bgra_to_string(grayPixel);
    
    if (TRUE) {
      // Write file that contains the results converting from device RGB to sRGB then back to device RGB
      
      if (TRUE) {
        NSString *filename = @"RedGreenBlueGray_Device2SRGB.png";
        
        NSData *pngData = [cgBuffer formatAsPNG];
        
        [pngData writeToFile:filename atomically:NO];
        
        NSLog(@"wrote %@", filename);
      }

    }
    
    assert([redStr isEqualToString:@"(255, 0, 0, 255)"]);
    assert([greenStr isEqualToString:@"(0, 255, 0, 255)"]);
    assert([blueStr isEqualToString:@"(0, 0, 255, 255)"]);
    assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);    
  }
  
  */
  
  /*
  
  // This test case defines an in memory buffer that contains the same results as
  // would be loaded from RedGreenBlueGray_Gimp.bmp. Loading from a BMP will
  // not use a specific colorspace, instead the device profile would be attached
  // automatically by the system. Loading the exact same pixel data with the
  // same colorspace means a test case can run without an external file.
  
  @autoreleasepool
  {
    int bppNum = 24;
    int width = 4;
    int height = 1;
    
    CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    CGColorSpaceRef rgbColorSpace;
    rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    assert(rgbColorSpace);
    cgBuffer.colorspace = rgbColorSpace;
    CGColorSpaceRelease(rgbColorSpace);
    
    uint32_t *pixels = (uint32_t *)cgBuffer.pixels;
    
    pixels[0] = rgba_to_bgra(0xFF, 0, 0, 0xFF);
    pixels[1] = rgba_to_bgra(0, 0xFF, 0, 0xFF);
    pixels[2] = rgba_to_bgra(0, 0, 0xFF, 0xFF);
    pixels[3] = rgba_to_bgra(0xFF/2, 0xFF/2, 0xFF/2, 0xFF);
    
    uint32_t redPixel = pixels[0];
    uint32_t greenPixel = pixels[1];
    uint32_t bluePixel = pixels[2];
    uint32_t grayPixel = pixels[3];
    
    NSString *redStr = bgra_to_string(redPixel);
    NSString *greenStr = bgra_to_string(greenPixel);
    NSString *blueStr = bgra_to_string(bluePixel);
    NSString *grayStr = bgra_to_string(grayPixel);
    
    assert([redStr isEqualToString:@"(255, 0, 0, 255)"]);
    assert([greenStr isEqualToString:@"(0, 255, 0, 255)"]);
    assert([blueStr isEqualToString:@"(0, 0, 255, 255)"]);
    assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
    
    // Render test image into a new CGFrameBuffer in sRGB colorspace and then examine pixel values.
    
    CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    CGColorSpaceRef srgbColorSpace;
    srgbColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    renderBuffer.colorspace = srgbColorSpace;
    CGColorSpaceRelease(srgbColorSpace);

    CGImageRef imageRef;
    imageRef = [cgBuffer createCGImageRef];
    [renderBuffer renderCGImage:imageRef];
    CGImageRelease(imageRef);
    
    uint32_t *renderPixels = (uint32_t *)renderBuffer.pixels;
    
    redPixel = renderPixels[0];
    greenPixel = renderPixels[1];
    bluePixel = renderPixels[2];
    grayPixel = renderPixels[3];
    
    redStr = bgra_to_string(redPixel);
    greenStr = bgra_to_string(greenPixel);
    blueStr = bgra_to_string(bluePixel);
    grayStr = bgra_to_string(grayPixel);
    
    // sRGB values are shifted, not the same as conversion from "Generic RGB"
    
    if (TRUE) {
      assert([redStr isEqualToString:@"(233, 63, 51, 255)"]);
      assert([greenStr isEqualToString:@"(128, 242, 0, 255)"]);
      assert([blueStr isEqualToString:@"(0, 72, 251, 255)"]);
      assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
    }
    
    // Now attempt to convert the sRGB values back to GenericRGB to see if the pixel values match.
    
    assert(cgBuffer.isLockedByDataProvider == FALSE);
    memset(cgBuffer.pixels, 0, cgBuffer.numBytes);
    
    imageRef = [renderBuffer createCGImageRef];
    
    [cgBuffer renderCGImage:imageRef];
    CGImageRelease(imageRef);
    
    redPixel = pixels[0];
    greenPixel = pixels[1];
    bluePixel = pixels[2];
    grayPixel = pixels[3];
    
    redStr = bgra_to_string(redPixel);
    greenStr = bgra_to_string(greenPixel);
    blueStr = bgra_to_string(bluePixel);
    grayStr = bgra_to_string(grayPixel);
    
    if (FALSE) {
      // Write file that contains the results converting from device RGB to sRGB then back to device RGB
      
      if (TRUE) {
        NSString *filename = @"RedGreenBlueGray_Device2SRGB.png";
        
        NSData *pngData = [cgBuffer formatAsPNG];
        
        [pngData writeToFile:filename atomically:NO];
        
        NSLog(@"wrote %@", filename);
      }
      
    }
    
    assert([redStr isEqualToString:@"(255, 0, 0, 255)"]);
    assert([greenStr isEqualToString:@"(0, 255, 0, 255)"]);
    assert([blueStr isEqualToString:@"(0, 0, 255, 255)"]);
    assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
  }
  
  */

  /*
  
  // This test case attempts to work around issues related to conversion from
  // DeviceRGB to sRGB by detecting when DeviceRGB is being used by default
  // for untagged content. First, this code will convert from DeviceRGB
  // to GenericRGB and then to sRGB. If we can then convert from sRGB back
  // to GenericRGB without losing information then that approach could be
  // used to avoid color shift on untagged content.
  
  // This test case was not useful. Conversion from RGB To GenericRGB also
  // changed the RGB values in a non-reversable way.
   
  @autoreleasepool
  {
    int bppNum = 24;
    int width = 4;
    int height = 1;
    
    uint32_t redPixel;
    uint32_t greenPixel;
    uint32_t bluePixel;
    uint32_t grayPixel;
    
    NSString *redStr;
    NSString *greenStr;
    NSString *blueStr;
    NSString *grayStr;
    
    CGColorSpaceRef imageRefColorspace;
    
    CGFrameBuffer *deviceRGBBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    CGColorSpaceRef deviceRGBColorSpace;
    deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB();
    assert(deviceRGBColorSpace);
    deviceRGBBuffer.colorspace = deviceRGBColorSpace;
    CGColorSpaceRelease(deviceRGBColorSpace);
    
    uint32_t *pixels = (uint32_t *)deviceRGBBuffer.pixels;
    
    pixels[0] = rgba_to_bgra(0xFF, 0, 0, 0xFF);
    pixels[1] = rgba_to_bgra(0, 0xFF, 0, 0xFF);
    pixels[2] = rgba_to_bgra(0, 0, 0xFF, 0xFF);
    pixels[3] = rgba_to_bgra(0xFF/2, 0xFF/2, 0xFF/2, 0xFF);
    
    redPixel = pixels[0];
    greenPixel = pixels[1];
    bluePixel = pixels[2];
    grayPixel = pixels[3];
    
    redStr = bgra_to_string(redPixel);
    greenStr = bgra_to_string(greenPixel);
    blueStr = bgra_to_string(bluePixel);
    grayStr = bgra_to_string(grayPixel);
    
    assert([redStr isEqualToString:@"(255, 0, 0, 255)"]);
    assert([greenStr isEqualToString:@"(0, 255, 0, 255)"]);
    assert([blueStr isEqualToString:@"(0, 0, 255, 255)"]);
    assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
    
    // Render deviceRGBBuffer into genericRGBBuffer

    CGFrameBuffer *genericRGBBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    CGColorSpaceRef genericRGBColorSpace;
    genericRGBColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    assert(genericRGBColorSpace);
    genericRGBBuffer.colorspace = genericRGBColorSpace;
    CGColorSpaceRelease(genericRGBColorSpace);
    
    CGImageRef imageRef;
    imageRef = [deviceRGBBuffer createCGImageRef];
    
    // The colorspace defined in the image must match deviceRGBColorSpace
    imageRefColorspace = CGImageGetColorSpace(imageRef);
    assert(deviceRGBColorSpace == imageRefColorspace);
    
    [genericRGBBuffer renderCGImage:imageRef];
    CGImageRelease(imageRef);
    
    uint32_t *genericRGBPixels = (uint32_t *)genericRGBBuffer.pixels;
    
    redPixel = genericRGBPixels[0];
    greenPixel = genericRGBPixels[1];
    bluePixel = genericRGBPixels[2];
    grayPixel = genericRGBPixels[3];
    
    redStr = bgra_to_string(redPixel);
    greenStr = bgra_to_string(greenPixel);
    blueStr = bgra_to_string(bluePixel);
    grayStr = bgra_to_string(grayPixel);
    
    if (FALSE) {
      
//       Unclear why these values come out this way!
//       (lldb) po redStr
//       (NSString *) $7 = 0x001126f0 (225, 39, 40, 255)
//       (lldb) po greenStr
//       (NSString *) $8 = 0x0030dc00 (113, 245, 5, 255)
//       (lldb) po blueStr
//       (NSString *) $9 = 0x001131b0 (0, 41, 250, 255)
//       (lldb) po grayStr
//       (NSString *) $10 = 0x00113350 (108, 108, 108, 255)
      
    assert([redStr isEqualToString:@"(255, 0, 0, 255)"]);
    assert([greenStr isEqualToString:@"(0, 255, 0, 255)"]);
    assert([blueStr isEqualToString:@"(0, 0, 255, 255)"]);
    assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
    }
    
    // Render test image into a new CGFrameBuffer in sRGB colorspace and then examine pixel values.
    
    CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
    
    CGColorSpaceRef srgbColorSpace;
    srgbColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    renderBuffer.colorspace = srgbColorSpace;
    CGColorSpaceRelease(srgbColorSpace);
    
    imageRef = [genericRGBBuffer createCGImageRef];
    
    // The colorspace defined in the image must match genericRGBColorSpace
    imageRefColorspace = CGImageGetColorSpace(imageRef);
    assert(genericRGBColorSpace == imageRefColorspace);
    
    [renderBuffer renderCGImage:imageRef];
    CGImageRelease(imageRef);
    
    uint32_t *renderPixels = (uint32_t *)renderBuffer.pixels;
    
    redPixel = renderPixels[0];
    greenPixel = renderPixels[1];
    bluePixel = renderPixels[2];
    grayPixel = renderPixels[3];
    
    redStr = bgra_to_string(redPixel);
    greenStr = bgra_to_string(greenPixel);
    blueStr = bgra_to_string(bluePixel);
    grayStr = bgra_to_string(grayPixel);
    
    // sRGB values are shifted, not the same as conversion from "Generic RGB"
    
    if (TRUE) {
      assert([redStr isEqualToString:@"(233, 63, 51, 255)"]);
      assert([greenStr isEqualToString:@"(128, 242, 0, 255)"]);
      assert([blueStr isEqualToString:@"(0, 72, 251, 255)"]);
      assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
    }
    
    // Now attempt to convert the sRGB values back to GenericRGB to see if the pixel values match.
    
    assert(genericRGBBuffer.isLockedByDataProvider == FALSE);
    memset(genericRGBBuffer.pixels, 0, genericRGBBuffer.numBytes);
    
    imageRef = [renderBuffer createCGImageRef];
    
    [genericRGBBuffer renderCGImage:imageRef];
    CGImageRelease(imageRef);
    
    redPixel = pixels[0];
    greenPixel = pixels[1];
    bluePixel = pixels[2];
    grayPixel = pixels[3];
    
    redStr = bgra_to_string(redPixel);
    greenStr = bgra_to_string(greenPixel);
    blueStr = bgra_to_string(bluePixel);
    grayStr = bgra_to_string(grayPixel);
    
    if (FALSE) {
      // Write file that contains the results converting from device RGB to sRGB then back to device RGB
      
      if (TRUE) {
        NSString *filename = @"RedGreenBlueGray_Device2SRGB.png";
        
        NSData *pngData = [genericRGBBuffer formatAsPNG];
        
        [pngData writeToFile:filename atomically:NO];
        
        NSLog(@"wrote %@", filename);
      }
      
    }
    
    assert([redStr isEqualToString:@"(255, 0, 0, 255)"]);
    assert([greenStr isEqualToString:@"(0, 255, 0, 255)"]);
    assert([blueStr isEqualToString:@"(0, 0, 255, 255)"]);
    assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
  }
  
  */

  // This test case will create a 1x4 RGB with the pixels (RED, GREEN, BLUE, GRAY)
  // where gray component is 50% gray. These pixels are converted from and to the
  // RGB linear colorspace with a 1.0 gamma.
  
  /*
   @autoreleasepool
   {
   int bppNum = 24;
   int width = 4;
   int height = 1;
   
   CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
   
   CGColorSpaceRef rgbColorSpace;
   rgbColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
   assert(rgbColorSpace);
   cgBuffer.colorspace = rgbColorSpace;
   CGColorSpaceRelease(rgbColorSpace);
   
   uint32_t *pixels = (uint32_t *)cgBuffer.pixels;
   
   pixels[0] = rgba_to_bgra(0xFF, 0, 0, 0xFF);
   pixels[1] = rgba_to_bgra(0, 0xFF, 0, 0xFF);
   pixels[2] = rgba_to_bgra(0, 0, 0xFF, 0xFF);
   pixels[3] = rgba_to_bgra(0xFF/2, 0xFF/2, 0xFF/2, 0xFF);
   
   uint32_t redPixel = pixels[0];
   uint32_t greenPixel = pixels[1];
   uint32_t bluePixel = pixels[2];
   uint32_t grayPixel = pixels[3];
   
   NSString *redStr = bgra_to_string(redPixel);
   NSString *greenStr = bgra_to_string(greenPixel);
   NSString *blueStr = bgra_to_string(bluePixel);
   NSString *grayStr = bgra_to_string(grayPixel);
   
   assert([redStr isEqualToString:@"(255, 0, 0, 255)"]);
   assert([greenStr isEqualToString:@"(0, 255, 0, 255)"]);
   assert([blueStr isEqualToString:@"(0, 0, 255, 255)"]);
   assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
   
   // Create image from test data
   
   CGImageRef imageRef = [cgBuffer createCGImageRef];
   
   // Render test image into a new CGFrameBuffer in sRGB colorspace and then examine pixel values.
   
   CGFrameBuffer *renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:width height:height];
   
   CGColorSpaceRef srgbColorSpace;
   srgbColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
   renderBuffer.colorspace = srgbColorSpace;
   CGColorSpaceRelease(srgbColorSpace);
   
   [renderBuffer renderCGImage:imageRef];
   CGImageRelease(imageRef);
   
   uint32_t *renderPixels = (uint32_t *)renderBuffer.pixels;
   
   redPixel = renderPixels[0];
   greenPixel = renderPixels[1];
   bluePixel = renderPixels[2];
   grayPixel = renderPixels[3];
   
   redStr = bgra_to_string(redPixel);
   greenStr = bgra_to_string(greenPixel);
   blueStr = bgra_to_string(bluePixel);
   grayStr = bgra_to_string(grayPixel);
   
   // sRGB values are shifted
   
   assert([redStr isEqualToString:@"(255, 39, 0, 255)"]);
   assert([greenStr isEqualToString:@"(0, 249, 0, 255)"]);
   assert([blueStr isEqualToString:@"(10, 49, 255, 255)"]);
   assert([grayStr isEqualToString:@"(187, 187, 187, 255)"]);
   
   // Now attempt to convert the sRGB values back to GenericRGBLeanear to see if the pixel values match.
   
   assert(cgBuffer.isLockedByDataProvider == FALSE);
   memset(cgBuffer.pixels, 0, cgBuffer.numBytes);
   
   imageRef = [renderBuffer createCGImageRef];
   
   [cgBuffer renderCGImage:imageRef];
   CGImageRelease(imageRef);
   
   redPixel = pixels[0];
   greenPixel = pixels[1];
   bluePixel = pixels[2];
   grayPixel = pixels[3];
   
   redStr = bgra_to_string(redPixel);
   greenStr = bgra_to_string(greenPixel);
   blueStr = bgra_to_string(bluePixel);
   grayStr = bgra_to_string(grayPixel);
   
   assert([redStr isEqualToString:@"(255, 0, 0, 255)"]);
   assert([greenStr isEqualToString:@"(0, 255, 0, 255)"]);
   assert([blueStr isEqualToString:@"(0, 0, 255, 255)"]);
   assert([grayStr isEqualToString:@"(127, 127, 127, 255)"]);
   }
  */
  
  return;
}
#endif // TESTMODE

#if defined(SPLITALPHA)

void
splitalpha(char *mvidFilenameCstr)
{
	NSString *mvidPath = [NSString stringWithUTF8String:mvidFilenameCstr];
  
  BOOL isMvid = [mvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }

  // Create "xyz_rgb.mvid" and "xyz_alpha.mvid" output filenames
  
  NSString *mvidFilename = [mvidPath lastPathComponent];
  NSString *mvidFilenameNoExtension = [mvidFilename stringByDeletingPathExtension];

  NSString *rgbFilename = [NSString stringWithFormat:@"%@_rgb.mvid", mvidFilenameNoExtension];
  NSString *alphaFilename = [NSString stringWithFormat:@"%@_alpha.mvid", mvidFilenameNoExtension];
  
  // Reconstruct the fully qualified path for the RGB and ALPHA filenames
  
  NSArray *mvidPathComponents = [mvidPath pathComponents];
  assert(mvidPathComponents);
  
  NSArray *pathPrefixComponents = [NSArray array];
  if ([mvidPathComponents count] > 1) {
    NSRange range;
    range.location = 0;
    range.length = [mvidPathComponents count] - 1;
    pathPrefixComponents = [mvidPathComponents subarrayWithRange:range];
  }
  NSString *pathPrefix = nil;
  if ([pathPrefixComponents count] > 0) {
    pathPrefix = [NSString pathWithComponents:pathPrefixComponents];
  }
  
  NSString *rgbPath = rgbFilename;
  if (pathPrefix != nil) {
    rgbPath = [pathPrefix stringByAppendingPathComponent:rgbFilename];
  }
  
  NSString *alphaPath = alphaFilename;
  if (pathPrefix != nil) {
    alphaPath = [pathPrefix stringByAppendingPathComponent:alphaFilename];
  }
  
  // Read in frames from input file, then split the RGB and ALPHA components such that
  // the premultiplied color values are writted to one file and the ALPHA (grayscale)
  // values are written to the other.
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked = [frameDecoder openForReading:mvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open mvid filename \"%s\"\n", mvidFilenameCstr);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  float frameDuration = [frameDecoder frameDuration];
  
  int bpp = [frameDecoder header]->bpp;
  
  int width = [frameDecoder width];
  int height = [frameDecoder height];
  
  if (bpp != 32) {
    fprintf(stderr, "%s\n", "-splitalpha can only be used on a 32BPP MVID movie");
    exit(1);
  }

  // Verify that the input color data has been mapped to the sRGB colorspace.
  
  if (maxvid_file_version([frameDecoder header]) == MV_FILE_VERSION_ZERO) {
    fprintf(stderr, "%s\n", "-splitalpha on MVID is not supported for an old MVID file version 0.");
    exit(1);
  }
    
  fprintf(stdout, "Split %s RGB+A as %s and %s\n", [mvidFilename UTF8String], [rgbFilename UTF8String], [alphaFilename UTF8String]);
  
  // Writer that will write the RGB values
  
  MvidFileMetaData *mvidFileMetaDataRGB = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaDataRGB.bpp = 24;
  mvidFileMetaDataRGB.checkAlphaChannel = FALSE;
  
  AVMvidFileWriter *fileWriter;
  fileWriter = makeMVidWriter(rgbPath, 24, frameDuration, numFrames);
  
  {
    CGFrameBuffer *rgbFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    // Loop over all the frame data and emit RGB values without the alpha channel
    
    for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
      
      AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
      assert(frame);
      
      // Release the NSImage ref inside the frame since we will operate on the CG image directly.
      frame.image = nil;
      
      CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
      assert(cgFrameBuffer);
      
      if (frameIndex == 0) {
        rgbFrameBuffer.colorspace = cgFrameBuffer.colorspace;
      }
      
      NSUInteger numPixels = cgFrameBuffer.width * cgFrameBuffer.height;
      uint32_t *pixels = (uint32_t*)cgFrameBuffer.pixels;
      uint32_t *rgbPixels = (uint32_t*)rgbFrameBuffer.pixels;
      
      for (NSUInteger pixeli = 0; pixeli < numPixels; pixeli++) {
        uint32_t pixel = pixels[pixeli];
        
        // First reverse the premultiply logic so that the color of the pixel is disconnected from
        // the specific alpha value it will be displayed with.
        
        uint32_t rgbPixel = unpremultiply_bgra(pixel);
        
        // Now toss out the alpha value entirely and emit the pixel by itself in 24BPP mode
        
        rgbPixel = rgbPixel & 0xFFFFFF;
        
        rgbPixels[pixeli] = rgbPixel;
      }
      
      // Copy RGB data into a CGImage and apply frame delta compression to output
      
      CGImageRef frameImage = [rgbFrameBuffer createCGImageRef];
      
      BOOL isKeyframe = FALSE;
      if (frameIndex == 0) {
        isKeyframe = TRUE;
      }
      
      process_frame_file(fileWriter, NULL, frameImage, frameIndex, mvidFileMetaDataRGB, isKeyframe, NULL);
      
      if (frameImage) {
        CGImageRelease(frameImage);
      }
      
      [pool release];
    }
    
    [fileWriter rewriteHeader];
    [fileWriter close];
  }
  
  // Now process each of the alpha channel pixels and save to another file.
  
  [frameDecoder rewind];
  
  fileWriter = makeMVidWriter(alphaPath, 24, frameDuration, numFrames);
  
  // If alphaAsGrayscale is TRUE, then emit grayscale RGB values where all the componenets are equal.
  // If alphaAsGrayscale is FASLE, then emit componenet RGB values that are able to make use of
  // threshold RGB values to further correct Alpha values when decoding.
  
  const BOOL alphaAsGrayscale = TRUE;
  
  MvidFileMetaData *mvidFileMetaDataAlpha = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaDataAlpha.bpp = 24;
  mvidFileMetaDataAlpha.checkAlphaChannel = FALSE;
  
  {
    CGFrameBuffer *alphaFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    // Loop over all the frame data and emit RGB values without the alpha channel
    
    for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
      
      AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
      assert(frame);
      
      // Release the NSImage ref inside the frame since we will operate on the CG image directly.
      frame.image = nil;
      
      CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
      assert(cgFrameBuffer);
      
      if (frameIndex == 0) {
        alphaFrameBuffer.colorspace = cgFrameBuffer.colorspace;
      }
      
      NSUInteger numPixels = cgFrameBuffer.width * cgFrameBuffer.height;
      uint32_t *pixels = (uint32_t*)cgFrameBuffer.pixels;
      uint32_t *alphaPixels = (uint32_t*)alphaFrameBuffer.pixels;
      
      for (NSUInteger pixeli = 0; pixeli < numPixels; pixeli++) {
        uint32_t pixel = pixels[pixeli];
        uint32_t alpha = (pixel >> 24) & 0xFF;
        uint32_t alphaPixel;
        if (alphaAsGrayscale) {
          alphaPixel = (alpha << 16) | (alpha << 8) | alpha;
        } else {
          // R = transparent, G = partial transparency, B = opaque.
          // This logic uses the green channel to map partial transparency
          // values since the human visual system is able to descern more
          // precision in the green values and so H264 encoders are more
          // likely to store green with more precision.
          
          uint8_t red = 0x0, green = 0x0, blue = 0x0;
          if (alpha == 0xFF) {
            // Fully opaque pixel
            blue = 0xFF;
          } else if (alpha == 0x0) {
            // Fully transparent pixel
            red = 0xFF;
          } else {
            // Partial transparency
            green = alpha;
          }
          alphaPixel = rgba_to_bgra(red, green, blue, 0xFF);
        }
        alphaPixels[pixeli] = alphaPixel;
      }
      
      // Copy RGB data into a CGImage and apply frame delta compression to output
      
      CGImageRef frameImage = [alphaFrameBuffer createCGImageRef];
      
      BOOL isKeyframe = FALSE;
      if (frameIndex == 0) {
        isKeyframe = TRUE;
      }
      
      process_frame_file(fileWriter, NULL, frameImage, frameIndex, mvidFileMetaDataAlpha, isKeyframe, NULL);
      
      if (frameImage) {
        CGImageRelease(frameImage);
      }
      
      [pool release];
    }
    
    [fileWriter rewriteHeader];
    [fileWriter close];
  }
  
  fprintf(stdout, "Wrote %s\n", [rgbPath UTF8String]);
  fprintf(stdout, "Wrote %s\n", [alphaPath UTF8String]);
  
  return;
}

void
joinalpha(char *mvidFilenameCstr)
{
	NSString *mvidPath = [NSString stringWithUTF8String:mvidFilenameCstr];
  
  BOOL isMvid = [mvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  premultiply_init();

  // The join alpha logic needs to be able to find FILE_rgb.mvid and FILE_alpha.mvid
  // in the same directory as FILE.mvid
  
  NSString *mvidFilename = [mvidPath lastPathComponent];
  NSString *mvidFilenameNoExtension = [mvidFilename stringByDeletingPathExtension];
  
  NSString *rgbFilename = [NSString stringWithFormat:@"%@_rgb.mvid", mvidFilenameNoExtension];
  NSString *alphaFilename = [NSString stringWithFormat:@"%@_alpha.mvid", mvidFilenameNoExtension];
  
  // Reconstruct the fully qualified path for the RGB and ALPHA filenames
  
  NSArray *mvidPathComponents = [mvidPath pathComponents];
  assert(mvidPathComponents);
  
  NSArray *pathPrefixComponents = [NSArray array];
  if ([mvidPathComponents count] > 1) {
    NSRange range;
    range.location = 0;
    range.length = [mvidPathComponents count] - 1;
    pathPrefixComponents = [mvidPathComponents subarrayWithRange:range];
  }
  NSString *pathPrefix = nil;
  if ([pathPrefixComponents count] > 0) {
    pathPrefix = [NSString pathWithComponents:pathPrefixComponents];
  }
  
  NSString *rgbPath = rgbFilename;
  if (pathPrefix != nil) {
    rgbPath = [pathPrefix stringByAppendingPathComponent:rgbFilename];
  }

  NSString *alphaPath = alphaFilename;
  if (pathPrefix != nil) {
    alphaPath = [pathPrefix stringByAppendingPathComponent:alphaFilename];
  }
  
  if (fileExists(rgbPath) == FALSE) {
    fprintf(stderr, "Cannot find input RGB file %s\n", [rgbPath UTF8String]);
    exit(1);
  }

  if (fileExists(alphaPath) == FALSE) {
    fprintf(stderr, "Cannot find input ALPHA file %s\n", [alphaPath UTF8String]);
    exit(1);
  }
  
  // Remove output file if it exists
  
  if (fileExists(mvidPath) == TRUE) {
    [[NSFileManager defaultManager] removeItemAtPath:mvidPath error:nil];
  }
  
  fprintf(stdout, "Combining %s and %s as %s\n", [rgbFilename UTF8String], [alphaFilename UTF8String], [mvidFilename UTF8String]);
  
  // Open both the rgb and alpha mvid files for reading
  
  AVMvidFrameDecoder *frameDecoderRGB = [AVMvidFrameDecoder aVMvidFrameDecoder];
  AVMvidFrameDecoder *frameDecoderAlpha = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked;
  worked = [frameDecoderRGB openForReading:rgbPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open RGB mvid filename \"%s\"\n", [rgbPath UTF8String]);
    exit(1);
  }
  
  worked = [frameDecoderAlpha openForReading:alphaPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open ALPHA mvid filename \"%s\"\n", [alphaPath UTF8String]);
    exit(1);
  }
  
  [frameDecoderRGB allocateDecodeResources];
  [frameDecoderAlpha allocateDecodeResources];
  
  int foundBPP;
  
  foundBPP = [frameDecoderRGB header]->bpp;
  if (foundBPP != 24) {
    fprintf(stderr, "error: RGB mvid file must be 24BPP, found %dBPP\n", foundBPP);
    exit(1);
  }

  foundBPP = [frameDecoderAlpha header]->bpp;
  if (foundBPP != 24) {
    fprintf(stderr, "error: ALPHA mvid file must be 24BPP, found %dBPP\n", foundBPP);
    exit(1);
  }
  
  NSTimeInterval frameRate = frameDecoderRGB.frameDuration;
  NSTimeInterval frameRateAlpha = frameDecoderAlpha.frameDuration;
  if (frameRate != frameRateAlpha) {
    fprintf(stderr, "RGB movie fps %.4f does not match alpha movie fps %.4f\n",
            1.0f/(float)frameRate, 1.0f/(float)frameRateAlpha);
    exit(1);
  }
  
  NSUInteger numFrames = [frameDecoderRGB numFrames];
  NSUInteger numFramesAlpha = [frameDecoderAlpha numFrames];
  if (numFrames != numFramesAlpha) {
    fprintf(stderr, "RGB movie numFrames %d does not match alpha movie numFrames %d\n",
            numFrames, numFramesAlpha);
    exit(1);
  }
  
  int width = [frameDecoderRGB width];
  int height = [frameDecoderRGB height];
  CGSize size = CGSizeMake(width, height);
  
  // Size of Alpha movie must match size of RGB movie
  
  CGSize alphaMovieSize;
  
  alphaMovieSize = CGSizeMake(frameDecoderAlpha.width, frameDecoderAlpha.height);
  if (CGSizeEqualToSize(size, alphaMovieSize) == FALSE) {
    fprintf(stderr, "RGB movie size (%d, %d) does not match alpha movie size (%d, %d)\n",
            (int)width, (int)height,
            (int)alphaMovieSize.width, (int)alphaMovieSize.height);
    exit(1);
  }
  
  // If alphaAsGrayscale is TRUE, then emit grayscale RGB values where all the componenets are equal.
  // If alphaAsGrayscale is FASLE, then emit componenet RGB values that are able to make use of
  // threshold RGB values to further correct Alpha values when decoding.
  
  const BOOL alphaAsGrayscale = TRUE;
  
  MvidFileMetaData *mvidFileMetaData = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaData.bpp = 32;
  mvidFileMetaData.checkAlphaChannel = FALSE;
  
  // Create output file writer object
  
  AVMvidFileWriter *fileWriter = makeMVidWriter(mvidPath, 32, frameRate, numFrames);

  fileWriter.movieSize = size;
  
  CGFrameBuffer *combinedFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:width height:height];
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *frameRGB = [frameDecoderRGB advanceToFrame:frameIndex];
    assert(frameRGB);

    AVFrame *frameAlpha = [frameDecoderAlpha advanceToFrame:frameIndex];
    assert(frameAlpha);
    
    // Release the NSImage ref inside the frame since we will operate on the image data directly.
    frameRGB.image = nil;
    frameAlpha.image = nil;
    
    CGFrameBuffer *cgFrameBufferRGB = frameRGB.cgFrameBuffer;
    assert(cgFrameBufferRGB);
    
    CGFrameBuffer *cgFrameBufferAlpha = frameAlpha.cgFrameBuffer;
    assert(cgFrameBufferAlpha);
    
    // sRGB
    
    if (frameIndex == 0) {
      combinedFrameBuffer.colorspace = cgFrameBufferRGB.colorspace;
    }
    
    // Join RGB and ALPHA
    
    NSUInteger numPixels = width * height;
    uint32_t *combinedPixels = (uint32_t*)combinedFrameBuffer.pixels;
    uint32_t *rgbPixels = (uint32_t*)cgFrameBufferRGB.pixels;
    uint32_t *alphaPixels = (uint32_t*)cgFrameBufferAlpha.pixels;
    
    for (NSUInteger pixeli = 0; pixeli < numPixels; pixeli++) {
      uint32_t pixelAlpha = alphaPixels[pixeli];
      
      if (alphaAsGrayscale) {
        // All 3 components of the ALPHA pixel need to be the same in grayscale mode.
        
        uint32_t pixelAlphaRed = (pixelAlpha >> 16) & 0xFF;
        uint32_t pixelAlphaGreen = (pixelAlpha >> 8) & 0xFF;
        uint32_t pixelAlphaBlue = (pixelAlpha >> 0) & 0xFF;
        
        if (pixelAlphaRed != pixelAlphaGreen || pixelAlphaRed != pixelAlphaBlue) {
          fprintf(stderr, "Input Alpha MVID input movie R G B components do not match at pixel %d in frame %d\n", pixeli, frameIndex);
          exit(1);
        }
        
        pixelAlpha = pixelAlphaRed;
      } else {
        // R = transparent, G = partial transparency, B = opaque.
        
        uint32_t pixelAlphaRed = (pixelAlpha >> 16) & 0xFF;
        uint32_t pixelAlphaGreen = (pixelAlpha >> 8) & 0xFF;
        uint32_t pixelAlphaBlue = (pixelAlpha >> 0) & 0xFF;

        const float thresholdPercent = 0.90;
        const int thresholdValue = (int) (0xFF * thresholdPercent);
        
        // FIXME: threshold should be in terms of 0, X, 255
        
        if (pixelAlphaRed >= thresholdValue) {
          // Fully transparent pixel
          pixelAlpha = 0x0;
        } else if (pixelAlphaBlue >= thresholdValue) {
          // Fully opaque pixel
          pixelAlpha = 0xFF;
        } else {
          // Partial transparency
          pixelAlpha = pixelAlphaGreen;
          assert(pixelAlpha != 0x0);
          assert(pixelAlpha != 0xFF);
        }
      }
      
      // RGB componenets are 24 BPP non pre multiplied values
      
      uint32_t pixelRGB = rgbPixels[pixeli];
      uint32_t pixelRed = (pixelRGB >> 16) & 0xFF;
      uint32_t pixelGreen = (pixelRGB >> 8) & 0xFF;
      uint32_t pixelBlue = (pixelRGB >> 0) & 0xFF;
      
      // Create BGRA pixel that is not premultiplied
      
      uint32_t combinedPixel = premultiply_bgra_inline(pixelRed, pixelGreen, pixelBlue, pixelAlpha);
      
      combinedPixels[pixeli] = combinedPixel;
    }
    
    // Write combined RGBA pixles
    
    // Copy RGB data into a CGImage and apply frame delta compression to output
    
    CGImageRef frameImage = [combinedFrameBuffer createCGImageRef];
    
    BOOL isKeyframe = FALSE;
    if (frameIndex == 0) {
      isKeyframe = TRUE;
    }
    
    process_frame_file(fileWriter, NULL, frameImage, frameIndex, mvidFileMetaData, isKeyframe, NULL);
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
    
    [pool drain];
  }
  
  [fileWriter rewriteHeader];
  [fileWriter close];
  
  fprintf(stdout, "Wrote %s\n", [fileWriter.mvidPath UTF8String]);
  return;
}

// Mix alpha means to split the RGB and Alpha channels into frames and then
// display one RGB frame and then one Alpha frame one after another.

void
mixalpha(char *mvidFilenameCstr)
{
  NSString *mvidPath = [NSString stringWithUTF8String:mvidFilenameCstr];
  
  BOOL isMvid = [mvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  // Create "xyz_mix.mvid" as output filenames
  
  NSString *mvidFilename = [mvidPath lastPathComponent];
  NSString *mvidFilenameNoExtension = [mvidFilename stringByDeletingPathExtension];
  
  NSString *mixFilename = [NSString stringWithFormat:@"%@_mix.mvid", mvidFilenameNoExtension];
  
  // Reconstruct the fully qualified path for the RGB and ALPHA filenames
  
  NSArray *mvidPathComponents = [mvidPath pathComponents];
  assert(mvidPathComponents);
  
  NSArray *pathPrefixComponents = [NSArray array];
  if ([mvidPathComponents count] > 1) {
    NSRange range;
    range.location = 0;
    range.length = [mvidPathComponents count] - 1;
    pathPrefixComponents = [mvidPathComponents subarrayWithRange:range];
  }
  NSString *pathPrefix = nil;
  if ([pathPrefixComponents count] > 0) {
    pathPrefix = [NSString pathWithComponents:pathPrefixComponents];
  }
  
  NSString *mixPath = mixFilename;
  if (pathPrefix != nil) {
    mixPath = [pathPrefix stringByAppendingPathComponent:mixFilename];
  }
  
  // Read in frames from input file, then split the RGB and ALPHA components such that
  // the premultiplied color values are writted to one file and the ALPHA (grayscale)
  // values are written to the other.
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked = [frameDecoder openForReading:mvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open mvid filename \"%s\"\n", mvidFilenameCstr);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  float frameDuration = [frameDecoder frameDuration];
  
  int bpp = [frameDecoder header]->bpp;
  
  int width = [frameDecoder width];
  int height = [frameDecoder height];
  
  if (bpp != 32) {
    fprintf(stderr, "%s\n", "-mixalpha can only be used on a 32BPP MVID movie");
    exit(1);
  }
  
  // Verify that the input color data has been mapped to the sRGB colorspace.
  
  if (maxvid_file_version([frameDecoder header]) == MV_FILE_VERSION_ZERO) {
    fprintf(stderr, "%s\n", "-mixalpha on MVID is not supported for an old MVID file version 0.");
    exit(1);
  }
  
  fprintf(stdout, "Mix %s RGB+A as %s\n", [mvidFilename UTF8String], [mixFilename UTF8String]);
  
  // Writer that will write the RGB values to an output file that is 2 times longer than the input
  
  MvidFileMetaData *mvidFileMetaData = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaData.bpp = 24;
  mvidFileMetaData.checkAlphaChannel = FALSE;
  
  AVMvidFileWriter *fileWriter;
  fileWriter = makeMVidWriter(mixPath, 24, frameDuration, numFrames*2);
  
  // If alphaAsGrayscale is TRUE, then emit grayscale RGB values where all the componenets are equal.
  // If alphaAsGrayscale is FASLE, then emit componenet RGB values that are able to make use of
  // threshold RGB values to further correct Alpha values when decoding.
  
  const BOOL alphaAsGrayscale = TRUE;
  
  {
    CGFrameBuffer *rgbFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    // Loop over all the frame data and emit RGB values without the alpha channel
    
    NSUInteger outFrameIndex = 0;
    
    for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
      
      AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
      assert(frame);
      
      // Release the NSImage ref inside the frame since we will operate on the CG image directly.
      frame.image = nil;
      
      CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
      assert(cgFrameBuffer);
      
      if (frameIndex == 0) {
        rgbFrameBuffer.colorspace = cgFrameBuffer.colorspace;
      }
      
      NSUInteger numPixels = cgFrameBuffer.width * cgFrameBuffer.height;
      uint32_t *pixels = (uint32_t*)cgFrameBuffer.pixels;
      uint32_t *rgbPixels = (uint32_t*)rgbFrameBuffer.pixels;
      
      for (NSUInteger pixeli = 0; pixeli < numPixels; pixeli++) {
        uint32_t pixel = pixels[pixeli];
        
        // First reverse the premultiply logic so that the color of the pixel is disconnected from
        // the specific alpha value it will be displayed with.
        
        uint32_t rgbPixel = unpremultiply_bgra(pixel);
        
        // Now toss out the alpha value entirely and emit the pixel by itself in 24BPP mode
        
        rgbPixel = rgbPixel & 0xFFFFFF;
        
        rgbPixels[pixeli] = rgbPixel;
      }
      
      // Copy RGB data into a CGImage and apply frame delta compression to output
      
      CGImageRef frameImage = [rgbFrameBuffer createCGImageRef];
      
      BOOL isKeyframe = TRUE;
      
      process_frame_file(fileWriter, NULL, frameImage, outFrameIndex, mvidFileMetaData, isKeyframe, NULL);
      outFrameIndex++;
      
      if (frameImage) {
        CGImageRelease(frameImage);
      }
      
      // Emit Alpha frame

      for (NSUInteger pixeli = 0; pixeli < numPixels; pixeli++) {
        uint32_t pixel = pixels[pixeli];
        uint32_t alpha = (pixel >> 24) & 0xFF;
        uint32_t alphaPixel;
        if (alphaAsGrayscale) {
          alphaPixel = (alpha << 16) | (alpha << 8) | alpha;
        } else {
          // R = transparent, G = partial transparency, B = opaque.
          // This logic uses the green channel to map partial transparency
          // values since the human visual system is able to descern more
          // precision in the green values and so H264 encoders are more
          // likely to store green with more precision.
          
          uint8_t red = 0x0, green = 0x0, blue = 0x0;
          if (alpha == 0xFF) {
            // Fully opaque pixel
            blue = 0xFF;
          } else if (alpha == 0x0) {
            // Fully transparent pixel
            red = 0xFF;
          } else {
            // Partial transparency
            green = alpha;
          }
          alphaPixel = rgba_to_bgra(red, green, blue, 0xFF);
        }
        rgbPixels[pixeli] = alphaPixel;
      }
      
      frameImage = [rgbFrameBuffer createCGImageRef];
      
      process_frame_file(fileWriter, NULL, frameImage, outFrameIndex, mvidFileMetaData, isKeyframe, NULL);
      outFrameIndex++;
      
      if (frameImage) {
        CGImageRelease(frameImage);
      }
      
      [pool release];
    }
    
    [fileWriter rewriteHeader];
    [fileWriter close];
  }
  
  fprintf(stdout, "Wrote %s\n", [mixPath UTF8String]);
}

// Undo a mix where RGB and Alpha where split into different H.264 frames

void
unmixalpha(char *mvidFilenameCstr)
{
  NSString *mvidPath = [NSString stringWithUTF8String:mvidFilenameCstr];
  
  BOOL isMvid = [mvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  premultiply_init();
  
  // The join logic accepts a .mvid filename like "low_car.mvid" and looks
  // for an input file "low_car_mix.mvid"
  
  NSString *mvidFilename = [mvidPath lastPathComponent];
  NSString *mvidFilenameNoExtension = [mvidFilename stringByDeletingPathExtension];
  
  NSString *mixFilename = [NSString stringWithFormat:@"%@_mix.mvid", mvidFilenameNoExtension];
  
  // Reconstruct the fully qualified path for the RGB and ALPHA filenames
  
  NSArray *mvidPathComponents = [mvidPath pathComponents];
  assert(mvidPathComponents);
  
  NSArray *pathPrefixComponents = [NSArray array];
  if ([mvidPathComponents count] > 1) {
    NSRange range;
    range.location = 0;
    range.length = [mvidPathComponents count] - 1;
    pathPrefixComponents = [mvidPathComponents subarrayWithRange:range];
  }
  NSString *pathPrefix = nil;
  if ([pathPrefixComponents count] > 0) {
    pathPrefix = [NSString pathWithComponents:pathPrefixComponents];
  }
  
  NSString *mixPath = mixFilename;
  if (pathPrefix != nil) {
    mixPath = [pathPrefix stringByAppendingPathComponent:mixPath];
  }
    
  if (fileExists(mixPath) == FALSE) {
    fprintf(stderr, "Cannot find input RGB file %s\n", [mixPath UTF8String]);
    exit(1);
  }
  
  // Remove output file if it exists
  
  if (fileExists(mvidPath) == TRUE) {
    [[NSFileManager defaultManager] removeItemAtPath:mvidPath error:nil];
  }
  
  fprintf(stdout, "Combine mix %s as %s\n", [mixFilename UTF8String], [mvidFilename UTF8String]);
  
  // Open both the rgb and alpha mvid files for reading
  
  AVMvidFrameDecoder *frameDecoderRGB = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked;
  worked = [frameDecoderRGB openForReading:mixPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open RGB mvid filename \"%s\"\n", [mixPath UTF8String]);
    exit(1);
  }
  
  [frameDecoderRGB allocateDecodeResources];
  
  int foundBPP;
  
  foundBPP = [frameDecoderRGB header]->bpp;
  if (foundBPP != 24) {
    fprintf(stderr, "error: RGB mvid file must be 24BPP, found %dBPP\n", foundBPP);
    exit(1);
  }
  
  NSTimeInterval frameRate = frameDecoderRGB.frameDuration;
  
  NSUInteger numFrames = [frameDecoderRGB numFrames];
  
  int width = [frameDecoderRGB width];
  int height = [frameDecoderRGB height];
  CGSize size = CGSizeMake(width, height);
  
  // If alphaAsGrayscale is TRUE, then emit grayscale RGB values where all the componenets are equal.
  // If alphaAsGrayscale is FALSE, then emit componenet RGB values that are able to make use of
  // threshold RGB values to further correct Alpha values when decoding.
  
  const BOOL alphaAsGrayscale = TRUE;
  
  MvidFileMetaData *mvidFileMetaData = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaData.bpp = 32;
  mvidFileMetaData.checkAlphaChannel = FALSE;
  
  // Create output file writer object
  
  int numOutputFrames = numFrames / 2;
  
  AVMvidFileWriter *fileWriter = makeMVidWriter(mvidPath, 32, frameRate, numOutputFrames);
  
  fileWriter.movieSize = size;
  
  CGFrameBuffer *combinedFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:width height:height];
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex += 2) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *frameRGB = [frameDecoderRGB advanceToFrame:frameIndex];
    assert(frameRGB);
    
    AVFrame *frameAlpha = [frameDecoderRGB advanceToFrame:frameIndex+1];
    assert(frameAlpha);
    
    // Release the NSImage ref inside the frame since we will operate on the image data directly.
    frameRGB.image = nil;
    frameAlpha.image = nil;
    
    CGFrameBuffer *cgFrameBufferRGB = frameRGB.cgFrameBuffer;
    assert(cgFrameBufferRGB);
    
    CGFrameBuffer *cgFrameBufferAlpha = frameAlpha.cgFrameBuffer;
    assert(cgFrameBufferAlpha);
    
    // sRGB
    
    if (frameIndex == 0) {
      combinedFrameBuffer.colorspace = cgFrameBufferRGB.colorspace;
    }
    
    // Join RGB and ALPHA
    
    NSUInteger numPixels = width * height;
    uint32_t *combinedPixels = (uint32_t*)combinedFrameBuffer.pixels;
    uint32_t *rgbPixels = (uint32_t*)cgFrameBufferRGB.pixels;
    uint32_t *alphaPixels = (uint32_t*)cgFrameBufferAlpha.pixels;
    
    for (NSUInteger pixeli = 0; pixeli < numPixels; pixeli++) {
      uint32_t pixelAlpha = alphaPixels[pixeli];
      
      if (alphaAsGrayscale) {
        // All 3 components of the ALPHA pixel need to be the same in grayscale mode.
        
        uint32_t pixelAlphaRed = (pixelAlpha >> 16) & 0xFF;
        uint32_t pixelAlphaGreen = (pixelAlpha >> 8) & 0xFF;
        uint32_t pixelAlphaBlue = (pixelAlpha >> 0) & 0xFF;
        
        if (pixelAlphaRed != pixelAlphaGreen || pixelAlphaRed != pixelAlphaBlue) {
          fprintf(stderr, "Input Alpha MVID input movie R G B components do not match at pixel %d in frame %d\n", pixeli, frameIndex);
          exit(1);
        }
        
        pixelAlpha = pixelAlphaRed;
      } else {
        // R = transparent, G = partial transparency, B = opaque.
        
        uint32_t pixelAlphaRed = (pixelAlpha >> 16) & 0xFF;
        uint32_t pixelAlphaGreen = (pixelAlpha >> 8) & 0xFF;
        uint32_t pixelAlphaBlue = (pixelAlpha >> 0) & 0xFF;
        
        const float thresholdPercent = 0.90;
        const int thresholdValue = (int) (0xFF * thresholdPercent);
        
        if (pixelAlphaRed >= thresholdValue) {
          // Fully transparent pixel
          pixelAlpha = 0x0;
        } else if (pixelAlphaBlue >= thresholdValue) {
          // Fully opaque pixel
          pixelAlpha = 0xFF;
        } else {
          // Partial transparency
          pixelAlpha = pixelAlphaGreen;
          assert(pixelAlpha != 0x0);
          assert(pixelAlpha != 0xFF);
        }
      }
      
      // RGB componenets are 24 BPP non pre multiplied values
      
      uint32_t pixelRGB = rgbPixels[pixeli];
      uint32_t pixelRed = (pixelRGB >> 16) & 0xFF;
      uint32_t pixelGreen = (pixelRGB >> 8) & 0xFF;
      uint32_t pixelBlue = (pixelRGB >> 0) & 0xFF;
      
      // Create BGRA pixel that is not premultiplied
      
      uint32_t combinedPixel = premultiply_bgra_inline(pixelRed, pixelGreen, pixelBlue, pixelAlpha);
      
      combinedPixels[pixeli] = combinedPixel;
    }
    
    // Write combined RGBA pixles
    
    // Copy RGB data into a CGImage and apply frame delta compression to output
    
    CGImageRef frameImage = [combinedFrameBuffer createCGImageRef];
    
    BOOL isKeyframe = FALSE;
    if (frameIndex == 0) {
      isKeyframe = TRUE;
    }
    
    process_frame_file(fileWriter, NULL, frameImage, frameIndex/2, mvidFileMetaData, isKeyframe, NULL);
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
    
    [pool drain];
  }
  
  [fileWriter rewriteHeader];
  [fileWriter close];
  
  fprintf(stdout, "Wrote %s\n", [fileWriter.mvidPath UTF8String]);
  return;
}

// Combine an existing RGB and ALPHA video into an singe interleaved video.
// Typically a mixture would combine RGB and Alpha channel data, but it is
// also possible to combine any type of data as long as the data is each
// channel is represented as pixels. For example, other uses include encoding
// a 24BPP blend amount represented as grayscale pixels. One might also split
// two very large RGB frames into 1/2 frames for display at a very large size.

void
mixstraight(char *rgbMvidFilenameCstr, char *alphaMvidFilenameCstr, char *mixedMvidFilenameCstr)
{
  NSString *rgbMvidPath = [NSString stringWithUTF8String:rgbMvidFilenameCstr];
  NSString *alphaMvidPath = [NSString stringWithUTF8String:alphaMvidFilenameCstr];
  NSString *mixedMvidPath = [NSString stringWithUTF8String:mixedMvidFilenameCstr];
  
  for ( NSString *mvidPath in @[ rgbMvidPath, alphaMvidPath, mixedMvidPath ] ) {
    BOOL isMvid = [mvidPath hasSuffix:@".mvid"];
    
    if (isMvid == FALSE) {
      fprintf(stderr, "not .mvid file \"%s\"\n", [mvidPath UTF8String]);
      fprintf(stderr, "%s", USAGE);
      exit(1);
    }
  }
  
  // Remove output file if it exists
  
  if (fileExists(mixedMvidPath) == TRUE) {
    [[NSFileManager defaultManager] removeItemAtPath:mixedMvidPath error:nil];
  }
  
  // Open 2 input files
  
  if (fileExists(rgbMvidPath) == FALSE) {
    fprintf(stderr, "Cannot find input RGB file %s\n", [rgbMvidPath UTF8String]);
    exit(1);
  }

  if (fileExists(alphaMvidPath) == FALSE) {
    fprintf(stderr, "Cannot find input RGB file %s\n", [alphaMvidPath UTF8String]);
    exit(1);
  }
  
  // Open both the rgb and alpha mvid files for reading
  
  AVMvidFrameDecoder *frameDecoderRGB = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked;
  worked = [frameDecoderRGB openForReading:rgbMvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open RGB mvid filename \"%s\"\n", [rgbMvidPath UTF8String]);
    exit(1);
  }
  
  [frameDecoderRGB allocateDecodeResources];
  
  int foundBPP;
  
  foundBPP = [frameDecoderRGB header]->bpp;
  if (foundBPP != 24) {
    fprintf(stderr, "error: input mvid file must be 24BPP, found %dBPP\n", foundBPP);
    exit(1);
  }
  
  AVMvidFrameDecoder *frameDecoderAlpha = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoderAlpha openForReading:alphaMvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open ALPHA mvid filename \"%s\"\n", [alphaMvidPath UTF8String]);
    exit(1);
  }
  
  [frameDecoderAlpha allocateDecodeResources];
  
  foundBPP = [frameDecoderAlpha header]->bpp;
  if (foundBPP != 24) {
    fprintf(stderr, "error: input mvid file must be 24BPP, found %dBPP\n", foundBPP);
    exit(1);
  }
  
  NSTimeInterval frameRate = frameDecoderRGB.frameDuration;
  
  NSUInteger numFrames = [frameDecoderRGB numFrames];
  NSUInteger numFrames2 = [frameDecoderAlpha numFrames];
  
  if (numFrames != numFrames2) {
    fprintf(stderr, "error:num frames mismatch %d != %d\n", numFrames, numFrames2);
    exit(1);
  }
  
  int width = [frameDecoderRGB width];
  int height = [frameDecoderRGB height];
  CGSize size = CGSizeMake(width, height);
  
  // If alphaAsGrayscale is TRUE, then emit grayscale RGB values where all the componenets are equal.
  // If alphaAsGrayscale is FALSE, then emit componenet RGB values that are able to make use of
  // threshold RGB values to further correct Alpha values when decoding.
  
//  const BOOL alphaAsGrayscale = TRUE;
  
  MvidFileMetaData *mvidFileMetaData = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaData.bpp = 24;
  mvidFileMetaData.checkAlphaChannel = FALSE;
  
  // Create output file writer object
  
  int numOutputFrames = numFrames * 2;
  
  AVMvidFileWriter *fileWriter = makeMVidWriter(mixedMvidPath, 24, frameRate, numOutputFrames);
  
  fileWriter.movieSize = size;
  
  CGFrameBuffer *rgbOutputFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
  
  int outFrameIndex = 0;
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) @autoreleasepool {
    AVFrame *frameRGB = [frameDecoderRGB advanceToFrame:frameIndex];
    assert(frameRGB);
    
    AVFrame *frameAlpha = [frameDecoderAlpha advanceToFrame:frameIndex];
    assert(frameAlpha);
    
    // Release the NSImage ref inside the frame since we will operate on the CG image directly.
    frameRGB.image = nil;
    frameAlpha.image = nil;
    
    assert(frameRGB.cgFrameBuffer);
    assert(frameAlpha.cgFrameBuffer);
    
    if (frameIndex == 0) {
      rgbOutputFrameBuffer.colorspace = frameRGB.cgFrameBuffer.colorspace;
    }
    
    // Straight memcpy into rgbOutputFrameBuffer
    
    [rgbOutputFrameBuffer copyPixels:frameRGB.cgFrameBuffer];
    
    // Copy RGB data into a CGImage and apply frame delta compression to output
    
    CGImageRef frameImage = [rgbOutputFrameBuffer createCGImageRef];
    assert(frameImage);
    
    BOOL isKeyframe = TRUE;
    
    process_frame_file(fileWriter, NULL, frameImage, outFrameIndex, mvidFileMetaData, isKeyframe, NULL);
    outFrameIndex++;
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
    
    // Straight memcpy into rgbOutputFrameBuffer
    
    [rgbOutputFrameBuffer copyPixels:frameAlpha.cgFrameBuffer];
    
    frameImage = [rgbOutputFrameBuffer createCGImageRef];
    assert(frameImage);
    
    process_frame_file(fileWriter, NULL, frameImage, outFrameIndex, mvidFileMetaData, isKeyframe, NULL);
    outFrameIndex++;
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
  }
  
  assert(numOutputFrames == outFrameIndex);
  
  [fileWriter rewriteHeader];
  [fileWriter close];
  
  fprintf(stdout, "Wrote %s\n", [fileWriter.mvidPath UTF8String]);
  return;
}

#endif // SPLITALPHA

// This method provides a command line interface that makes it possible to crop
// each frame of a movie and emit a new file containing the cropped portion
// of each frame. This is a very simple operation, but it can be very difficult
// to do using Quicktime or other command line tools. A high end video editor
// would do this easily, this implementation makes it easy to do on the command line.

void
cropMvidMovie(char *cropSpecCstr, char *inMvidFilenameCstr, char *outMvidFilenameCstr)
{
	NSString *inMvidPath = [NSString stringWithUTF8String:inMvidFilenameCstr];
	NSString *outMvidPath = [NSString stringWithUTF8String:outMvidFilenameCstr];
  
  BOOL isMvid;

  isMvid = [inMvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }

  isMvid = [outMvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  // Check the CROP spec, it should be 4 integer values that indicate the X Y W H
  // for the output movie.
  
	NSString *cropSpec = [NSString stringWithUTF8String:cropSpecCstr];
  NSArray *elements  = [cropSpec componentsSeparatedByString:@" "];
  
  if ([elements count] != 4) {
    fprintf(stderr, "CROP specification must be X Y WIDTH HEIGHT : not %s\n", cropSpecCstr);
    exit(1);
  }

  NSInteger cropX = [((NSString*)[elements objectAtIndex:0]) intValue];
  NSInteger cropY = [((NSString*)[elements objectAtIndex:1]) intValue];
  NSInteger cropW = [((NSString*)[elements objectAtIndex:2]) intValue];
  NSInteger cropH = [((NSString*)[elements objectAtIndex:3]) intValue];
    
  // Read in existing file into from the input file and create an output file
  // that has exactly the same options.
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked = [frameDecoder openForReading:inMvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open input mvid filename \"%s\"\n", [inMvidPath UTF8String]);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  float frameDuration = [frameDecoder frameDuration];
  
  int bpp = [frameDecoder header]->bpp;
  
  int width = [frameDecoder width];
  int height = [frameDecoder height];
  
  // Verify the crop spec info once info from input file is available

  BOOL cropXYInvalid = FALSE;
  BOOL cropWHInvalid = FALSE;

  if (cropX < 0 || cropY < 0) {
    cropXYInvalid = TRUE;
  }

  if (cropW <= 0 || cropW <= 0) {
    cropWHInvalid = TRUE;
  }
  
  // Output size has to be the same or smaller than the input size
  // X,Y must be greater than 0 and smaller than W,H of the input movie
  // W,H must be greater than 0 and smaller than W,H of the input movie
  
  if (cropW > width) {
    cropWHInvalid = TRUE;
  }
  
  if (cropH > height) {
    cropWHInvalid = TRUE;
  }
  
  int outputX2 = cropX + cropW;
  if (outputX2 > width) {
    cropWHInvalid = TRUE;
  }

  int outputY2 = cropY + cropH;
  if (outputY2 > height) {
    cropWHInvalid = TRUE;
  }
  
  if (cropXYInvalid || cropWHInvalid) {
    NSString *movieDimensionsStr = [NSString stringWithFormat:@"%d x %d", width, height];
    fprintf(stderr, "error: invalid -crop specification \"%s\" for movie with dimensions \"%s\"\n", cropSpecCstr, [movieDimensionsStr UTF8String]);
    exit(1);
  }
  
  // Writer that will write the RGB values. Note that invoking process_frame_file()
  // will define the output width/height based on the size of the image passed in.
  
  MvidFileMetaData *mvidFileMetaData = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaData.bpp = bpp;
  mvidFileMetaData.checkAlphaChannel = FALSE;
  
  AVMvidFileWriter *fileWriter = makeMVidWriter(outMvidPath, bpp, frameDuration, numFrames);
  
  CGFrameBuffer *croppedFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:cropW height:cropH];
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
    assert(frame);
    
    // Release the NSImage ref inside the frame since we will operate on the CG image directly.
    frame.image = nil;
    
    CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
    assert(cgFrameBuffer);
        
    // sRGB support
    
    if (frameIndex == 0) {
      croppedFrameBuffer.colorspace = cgFrameBuffer.colorspace;
    }
    
    // Copy cropped area into the croppedFrameBuffer
    
    BOOL worked;
    CGImageRef frameImage = nil;
    
    // Crop pixels from cgFrameBuffer while doing a copy into croppedFrameBuffer. Note that this
    // API currently assumes that input and output are the same BPP.
    
    [croppedFrameBuffer cropCopyPixels:cgFrameBuffer cropX:cropX cropY:cropY];
    
    frameImage = [croppedFrameBuffer createCGImageRef];
    worked = (frameImage != nil);
    assert(worked);
    
    BOOL isKeyframe = FALSE;
    if (frameIndex == 0) {
      isKeyframe = TRUE;
    }
    
    process_frame_file(fileWriter, NULL, frameImage, frameIndex, mvidFileMetaData, isKeyframe, NULL);
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
        
    [pool drain];
  }
  
  [fileWriter rewriteHeader];
  [fileWriter close];
  
  fprintf(stdout, "Wrote: %s\n", [fileWriter.mvidPath UTF8String]);
  return;
}

// This -resize option provides a very handy command line operation that is able to resize
// a movie and write the result to a new file. Any width and height could be set as the
// output dimensions.

void
resizeMvidMovie(char *resizeSpecCstr, char *inMvidFilenameCstr, char *outMvidFilenameCstr)
{
  NSString *inMvidPath = [NSString stringWithUTF8String:inMvidFilenameCstr];
  NSString *outMvidPath = [NSString stringWithUTF8String:outMvidFilenameCstr];
  
  BOOL isMvid;
  
  isMvid = [inMvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  isMvid = [outMvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  // Check the RESIZE spec, it should be 2 integer values that indicate the W H
  // for the output movie. This parameter could also be DOUBLE or HALF to indicate
  // a "double size" operation or a "half size" operation. Note that there is a
  // special case when using "DOUBLE" in that it writes pixels directly to the double
  // size, while indicating the size explicitly will use the core graphics scale op.
  
	NSString *resizeSpec = [NSString stringWithUTF8String:resizeSpecCstr];
  
  NSInteger resizeW = -1;
  NSInteger resizeH = -1;
  
  BOOL doubleSizeFlag = FALSE;
  BOOL halfSizeFlag = FALSE;
  
  if ([resizeSpec isEqualToString:@"DOUBLE"]) {
    // Enable 1 -> 4 pixel logic for DOUBLE resize, the CG render will resample and produce some very strange
    // results that do not produce the identical pixel values when resized back to half the size.
    
    doubleSizeFlag = TRUE;
  } else if ([resizeSpec isEqualToString:@"HALF"]) {
    // Shortcut so that half size operation need not pass the exact sizes, they can be calculated from input movie
    
    halfSizeFlag = TRUE;
  }
  
  if ((doubleSizeFlag == FALSE) && (halfSizeFlag == FALSE)) {
    NSArray *elements  = [resizeSpec componentsSeparatedByString:@" "];
    
    if ([elements count] != 2) {
      fprintf(stderr, "RESIZE specification must be WIDTH HEIGHT : not %s\n", resizeSpecCstr);
      exit(1);
    }
    
    resizeW = [((NSString*)[elements objectAtIndex:0]) intValue];
    resizeH = [((NSString*)[elements objectAtIndex:1]) intValue];
    
    if (resizeW <= 0 || resizeH <= 0) {
      fprintf(stderr, "RESIZE specification must be WIDTH HEIGHT : not %s\n", resizeSpecCstr);
      exit(1);
    }    
  }
  
  // Read in existing file into from the input file and create an output file
  // that has exactly the same options.
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked = [frameDecoder openForReading:inMvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open input mvid filename \"%s\"\n", [inMvidPath UTF8String]);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  float frameDuration = [frameDecoder frameDuration];
  
  int bpp = [frameDecoder header]->bpp;
  
  int width = [frameDecoder width];
  int height = [frameDecoder height];
  assert(width > 0);
  assert(height > 0);
  
  if (doubleSizeFlag) {
    resizeW = width * 2;
    resizeH = height * 2;
  }
  
  if (halfSizeFlag) {
    resizeW = width / 2;
    resizeH = height / 2;
  }
  
  assert(resizeW != -1);
  assert(resizeH != -1);
  
  // Writer that will write the RGB values. Note that invoking process_frame_file()
  // will define the output width/height based on the size of the image passed in.
  
  MvidFileMetaData *mvidFileMetaData = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaData.bpp = bpp;
  mvidFileMetaData.checkAlphaChannel = FALSE;
  
  AVMvidFileWriter *fileWriter = makeMVidWriter(outMvidPath, bpp, frameDuration, numFrames);
  
  CGFrameBuffer *resizedFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:resizeW height:resizeH];
  
  // Resize input image to some other size. Ignore the case where the input is exactly
  // the same size as the output. If the HALF size resize is indicated, use the default
  // interpolation which results in exact half size pixel rendering. Otherwise, use
  // the high quality interpolation.
  
  if (halfSizeFlag == FALSE) {
    resizedFrameBuffer.useHighQualityInterpolation = TRUE;
  }
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
    assert(frame);
    
    // Release the NSImage ref inside the frame since we will operate on the CG image directly.
    frame.image = nil;
    
    CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
    assert(cgFrameBuffer);
    
    // sRGB support
    
    if (frameIndex == 0) {
      resizedFrameBuffer.colorspace = cgFrameBuffer.colorspace;
    }
    
    // Copy/Scale input image into resizedFrameBuffer
    
    BOOL worked;
    CGImageRef frameImage = nil;
    
    if (doubleSizeFlag == TRUE) {
      // Use special case "DOUBLE" logic that will simply duplicate the exact RGB value from the indicated
      // pixel into the 2x sized output buffer.
      
      assert(cgFrameBuffer.bitsPerPixel == resizedFrameBuffer.bitsPerPixel);
      assert(cgFrameBuffer.bitsPerPixel > 16); // FIXME later, add 16 BPP support
      
      int numOutputPixels = resizedFrameBuffer.width * resizedFrameBuffer.height;
      
      uint32_t *inPixels32 = (uint32_t*)cgFrameBuffer.pixels;
      uint32_t *outPixels32 = (uint32_t*)resizedFrameBuffer.pixels;
      
      int outRow = 0;
      int outColumn = 0;
      
      for (int i=0; i < numOutputPixels; i++) {
        if ((i > 0) && ((i % resizedFrameBuffer.width) == 0)) {
          outRow += 1;
          outColumn = 0;
        }
        
        // Divide by 2 to get the column/row in the input framebuffer
        int inColumn = outColumn / 2;
        int inRow = outRow / 2;
        
        // Get the pixel for the row and column this output pixel corresponds to
        int inOffset = (inRow * cgFrameBuffer.width) + inColumn;
        uint32_t pixel = inPixels32[inOffset];
        
        outPixels32[i] = pixel;
        
        //fprintf(stdout, "Wrote 0x%.10X for 2x row/col %d %d (%d), read from row/col %d %d (%d)\n", pixel, outRow, outColumn, i, inRow, inColumn, inOffset);
        
        outColumn += 1;
      }
    } else {
      // USe CG layer to double size and scale the pixels in the original image
      
      frameImage = [cgFrameBuffer createCGImageRef];
      worked = (frameImage != nil);
      assert(worked);
      
      [resizedFrameBuffer clear];
      [resizedFrameBuffer renderCGImage:frameImage];
      
      if (frameImage) {
        CGImageRelease(frameImage);
        assert(cgFrameBuffer.isLockedByDataProvider == FALSE);
      }
    }
  
    frameImage = [resizedFrameBuffer createCGImageRef];
    worked = (frameImage != nil);
    assert(worked);
    
    BOOL isKeyframe = FALSE;
    if (frameIndex == 0) {
      isKeyframe = TRUE;
    }
    
    process_frame_file(fileWriter, NULL, frameImage, frameIndex, mvidFileMetaData, isKeyframe, NULL);
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
    
    [pool drain];
  }
  
  [fileWriter rewriteHeader];
  [fileWriter close];
  
  fprintf(stdout, "Wrote: %s\n", [fileWriter.mvidPath UTF8String]);
  return;
}

// The "-4up IN.mvid" command writes "IN_q1.mvid IN_q2.mvid IN_q3.mvid IN_q4.mvid"
// after splitting each frame up into its own movie.

void
fourupMvidMovie(char *inMvidFilenameCstr)
{
  NSString *inMvidPath = [NSString stringWithUTF8String:inMvidFilenameCstr];
  NSString *prefix;

  // Generate prefix without .mvid
  {
    NSArray *elements = [inMvidPath componentsSeparatedByString:@".mvid"];
    prefix = [NSString stringWithFormat:@"%@", elements[0]];
  }
  
  NSString *outQ1MvidPath = [NSString stringWithFormat:@"%@_q1.mvid", prefix];
  NSString *outQ2MvidPath = [NSString stringWithFormat:@"%@_q2.mvid", prefix];
  NSString *outQ3MvidPath = [NSString stringWithFormat:@"%@_q3.mvid", prefix];
  NSString *outQ4MvidPath = [NSString stringWithFormat:@"%@_q4.mvid", prefix];
  
  BOOL isMvid;
  isMvid = [inMvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  NSArray *outMvidPaths = @[outQ1MvidPath, outQ2MvidPath, outQ3MvidPath, outQ4MvidPath];
  
  // Read in existing file into from the input file and create an output file
  // that has exactly the same options.
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked = [frameDecoder openForReading:inMvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open input mvid filename \"%s\"\n", [inMvidPath UTF8String]);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  float frameDuration = [frameDecoder frameDuration];
  
  int bpp = [frameDecoder header]->bpp;
  
  int width = [frameDecoder width];
  int height = [frameDecoder height];
  assert(width > 0);
  assert(height > 0);
  
  // Make sure the input frame can be split in half both ways
  
  if ((width % 2) != 0) {
    fprintf(stderr, "input width %d must be even number of pxiels", width);
    exit(1);
  }
  if ((height % 2) != 0) {
    fprintf(stderr, "input height %d must be even number of pxiels", height);
    exit(1);
  }
  
  // Writer that will write the RGB values. Note that invoking process_frame_file()
  // will define the output width/height based on the size of the image passed in.

  NSMutableArray *metadataArr = [NSMutableArray array];
  NSMutableArray *writerArr = [NSMutableArray array];
  
  for (int i = 0; i < 4; i++) {
    MvidFileMetaData *mvidFileMetaData = [MvidFileMetaData mvidFileMetaData];
    mvidFileMetaData.bpp = bpp;
    mvidFileMetaData.checkAlphaChannel = FALSE;
    [metadataArr addObject:mvidFileMetaData];
    
    AVMvidFileWriter *fileWriter = makeMVidWriter(outMvidPaths[i], bpp, frameDuration, numFrames);
    [writerArr addObject:fileWriter];
  }
  
  int qWidth = width / 2;
  int qHeight = height / 2;
  assert(width > 0);
  assert(height > 0);
  
  CGFrameBuffer *qFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:qWidth height:qHeight];
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
    assert(frame);
    
    // Release the NSImage ref inside the frame since we will operate on the CG image directly.
    frame.image = nil;
    
    CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
    assert(cgFrameBuffer);
    
    // sRGB support
    
    if (frameIndex == 0) {
      qFrameBuffer.colorspace = cgFrameBuffer.colorspace;
    }
    
    // Copy/Scale input image into resizedFrameBuffer
    
    BOOL worked;
    
    for (int i = 0; i < 4; i++) {
      AVMvidFileWriter *fileWriter = writerArr[i];
      MvidFileMetaData *mvidFileMetaData = metadataArr[i];
      
      int cx;
      int cy;
      
      if (i == 0) {
        cx = 0;
        cy = 0;
      } else if (i == 1) {
        cx = qWidth;
        cy = 0;
      } else if (i == 2) {
        cx = 0;
        cy = qHeight;
      } else if (i == 3) {
        cx = qWidth;
        cy = qHeight;
      } else {
        assert(0);
      }
      
      [qFrameBuffer cropCopyPixels:cgFrameBuffer cropX:cx cropY:cy];
      
      // Render quarter image
      
      CGImageRef qFrameImage = [qFrameBuffer createCGImageRef];
      worked = (qFrameImage != nil);
      assert(worked);
      
      // Force all keyframes
      
      BOOL isKeyframe = TRUE;
      
      process_frame_file(fileWriter, NULL, qFrameImage, frameIndex, mvidFileMetaData, isKeyframe, NULL);
      
      if (qFrameImage) {
        CGImageRelease(qFrameImage);
      }
    }
    
    [pool drain];
  }
  
  for (int i = 0; i < 4; i++) {
    AVMvidFileWriter *fileWriter = writerArr[i];
    
    [fileWriter rewriteHeader];
    [fileWriter close];
    
    fprintf(stdout, "Wrote: %s\n", [fileWriter.mvidPath UTF8String]);
  }
  
  return;
}

// This method provides an easy command line operation that will upgrade from
// v1 to v2. This change is a nasty one because the file format changed in
// a way that makes it impossible to support loading the old format. The
// code that needed to change was duplicated so that only the upgrade
// operation would need to deal with this horror show. The
// new file will be written with the most recent version number. If specific
// file format changes are needed, then will be implemented when the new file
// is written. This method writes to a tmp file and then the existing mvid
// file is replace by the tmp file once the operation is complete.

void
upgradeMvidMovie(char *inMvidFilenameCstr, char *optionalMvidFilenameCstr)
{
	NSString *inMvidPath = [NSString stringWithUTF8String:inMvidFilenameCstr];
	NSString *outMvidPath;
  
  BOOL isMvid;
  
  isMvid = [inMvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  BOOL writingToOptionalFile = FALSE;
  
  if (optionalMvidFilenameCstr != NULL) {
    outMvidPath = [NSString stringWithUTF8String:optionalMvidFilenameCstr];
    
    isMvid = [outMvidPath hasSuffix:@".mvid"];
    
    writingToOptionalFile = TRUE;
  } else {
    outMvidPath = @"tmp.mvid";
  }
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  // Read in existing file into from the input file and create an output file
  // that has exactly the same options.
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  frameDecoder.upgradeFromV1 = TRUE;
  
  BOOL worked = [frameDecoder openForReading:inMvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open input mvid filename \"%s\"\n", [inMvidPath UTF8String]);
    exit(1);
  }
  
  // Check for upgrade from version 1 or 0 to version 2.
  
  MVFileHeader *header = [frameDecoder header];
  int version = maxvid_file_version(header);
  if (version == MV_FILE_VERSION_ZERO || version == MV_FILE_VERSION_ONE) {
    // Success
  } else {
    fprintf(stderr, "error: cannot upgrade mvid file version %d to version 2\n", version);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  float frameDuration = [frameDecoder frameDuration];
  
  int bpp = [frameDecoder header]->bpp;
  
  //int width = [frameDecoder width];
  //int height = [frameDecoder height];
  
  // Writer that will write the RGB values. Note that invoking process_frame_file()
  // will define the width/height on the output.
  
  MvidFileMetaData *mvidFileMetaData = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaData.bpp = bpp;
  mvidFileMetaData.checkAlphaChannel = FALSE;
  
  AVMvidFileWriter *fileWriter = makeMVidWriter(outMvidPath, bpp, frameDuration, numFrames);
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
    assert(frame);
    
    // Release the NSImage ref inside the frame since we will operate on the CG image directly.
    frame.image = nil;
    
    CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
    assert(cgFrameBuffer);
        
    BOOL worked;
    CGImageRef frameImage = nil;
        
    frameImage = [cgFrameBuffer createCGImageRef];
    worked = (frameImage != nil);
    assert(worked);
    
    BOOL isKeyframe = FALSE;
    if (frameIndex == 0) {
      isKeyframe = TRUE;
    }
    
    process_frame_file(fileWriter, NULL, frameImage, frameIndex, mvidFileMetaData, isKeyframe, NULL);
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
    
    [pool drain];
  }
  
  [fileWriter rewriteHeader];
  [fileWriter close];

  // tmp file is written now, remove the original (old) .mvid and replace it with the upgraded file.
  
  if (writingToOptionalFile == FALSE) {
    worked = [[NSFileManager defaultManager] removeItemAtPath:inMvidPath error:nil];
    assert(worked);
    
    worked = [[NSFileManager defaultManager] moveItemAtPath:outMvidPath toPath:inMvidPath error:nil];
    assert(worked);
    
    fprintf(stdout, "Wrote %s\n", [inMvidPath UTF8String]);
  } else {
    fprintf(stdout, "Wrote %s\n", [outMvidPath UTF8String]);
  }
  
  return;
}

// Print the best FPS specification given the floating point framerate.
// For example, 24 FPS is about 0.0417 seconds, this is displayed
// as "24/1" in the output of this method.

void printMvidFPS(NSString *mvidFilename)
{
  BOOL worked;
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:mvidFilename];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open mvid filename \"%s\"\n", [mvidFilename UTF8String]);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  NSTimeInterval framerate = frameDecoder.frameDuration;
  
  // Check for very common framerates
  
  float epsilon = 0.0001f;
  
  char buffer[256];
  
  if (fabs(1.0 - framerate) <= epsilon) {
    // 1 FPS
    snprintf(buffer, sizeof(buffer), "1/1");
  } else if (fabs(1.0f/2.0f - framerate) <= epsilon) {
    // 2 FPS
    snprintf(buffer, sizeof(buffer), "2/1");
  } else if (fabs(1.0f/10.0f - framerate) <= epsilon) {
    // 10 FPS
    snprintf(buffer, sizeof(buffer), "10/1");
  } else if (fabs(1.0f/12.0f - framerate) <= epsilon) {
    // 12 FPS
    snprintf(buffer, sizeof(buffer), "12/1");
  } else if (fabs(1.0f/15.0f - framerate) <= epsilon) {
    // 15 FPS
    snprintf(buffer, sizeof(buffer), "15/1");
  } else if (fabs(1.0f/(1000.0f/1001.0f) - framerate) <= epsilon) {
    // 23.98 FPS = 1000/1001 (NTSC film)
    snprintf(buffer, sizeof(buffer), "1000/1001");
  } else if (fabs(1.0f/24.0f - framerate) <= epsilon) {
    // 24 FPS
    snprintf(buffer, sizeof(buffer), "24/1");
  } else if (fabs(1.0f/(30000.0f/1001.0f) - framerate) <= epsilon) {
    // 29.97 FPS = 30000/1001
    snprintf(buffer, sizeof(buffer), "30000/1001");
  } else if (fabs(1.0f/30.0f - framerate) <= epsilon) {
    // 30 FPS
    snprintf(buffer, sizeof(buffer), "30/1");
  } else if (fabs(1.0f/50.0f - framerate) <= epsilon) {
    // 50 FPS
    snprintf(buffer, sizeof(buffer), "50/1");
  } else if (fabs(1.0f/(60000.0f/1001.0f) - framerate) <= epsilon) {
    // 59.94 FPS = 60000/1001
    snprintf(buffer, sizeof(buffer), "60000/1001");
  } else if (fabs(1.0f/60.0f - framerate) <= epsilon) {
    // 60 FPS
    snprintf(buffer, sizeof(buffer), "60/1");
  } else {
    // Get as close as possible in terms of 1000 units
    float oneThousandth = 1.0f / 1000.0f;
    int i = 0;
    for ( ; (oneThousandth * i) < framerate; i++) {
      //fprintf(stdout, "%0.8f ?< %0.8f\n", (oneThousandth * i), framerate);
    }
    //fprintf(stdout, "%0.8f ?< %0.8f\n", (oneThousandth * i), framerate);
    snprintf(buffer, sizeof(buffer), "%d/1000", i);
  }
  
  fprintf(stdout, "%s\n", buffer);
  
  [frameDecoder close];
  
  return;
}

// Adler for each frame of video

void printMvidFrameAdler(NSString *mvidFilename)
{
	BOOL worked;
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:mvidFilename];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open mvid filename \"%s\"\n", [mvidFilename UTF8String]);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  int isV3 = (maxvid_file_version([frameDecoder header]) == MV_FILE_VERSION_THREE);
  
  //fprintf(stdout, "%s\n", [[mvidFilename lastPathComponent] UTF8String]);
  
  uint32_t lastAdler = 0x0;
  
  if (isV3) {
    for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
      
      MVV3Frame *frame = maxvid_v3_file_frame(frameDecoder.mvFrames, frameIndex);
      assert(frame);
      
      uint32_t currentAdler = frame->adler;
      
#if MV_ENABLE_DELTAS
      if (frameIndex == 0 && [frameDecoder isDeltas]) {
        // A nop delta frame is a special case in that it contains an adler
        // that corresponds to all black pixels.
        
        lastAdler = currentAdler;
      } else // note that the else/if here is only enabled in deltas mode
#endif // MV_ENABLE_DELTAS
        if (maxvid_v3_frame_isnopframe(frame)) {
          currentAdler = lastAdler;
        } else {
          lastAdler = currentAdler;
        }
      
      fprintf(stdout, "0x%X\n", currentAdler);
      
      [pool drain];
    }
  } else {
    for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
      
      MVFrame *frame = maxvid_file_frame(frameDecoder.mvFrames, frameIndex);
      assert(frame);
      
      uint32_t currentAdler = frame->adler;
      
#if MV_ENABLE_DELTAS
      if (frameIndex == 0 && [frameDecoder isDeltas]) {
        // A nop delta frame is a special case in that it contains an adler
        // that corresponds to all black pixels.
        
        lastAdler = currentAdler;
      } else // note that the else/if here is only enabled in deltas mode
#endif // MV_ENABLE_DELTAS
        if (maxvid_frame_isnopframe(frame)) {
          currentAdler = lastAdler;
        } else {
          lastAdler = currentAdler;
        }
      
      fprintf(stdout, "0x%X\n", currentAdler);
      
      [pool drain];
    }
  }
  
  [frameDecoder close];
  
	return;
}

// This method will iterate over each frame, then each row and print the
// pixel values as hex and decoded RGB values. This is useful when debugging
// RGB conversion logic.

void printMvidPixels(NSString *mvidPath)
{
	BOOL worked;
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:mvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open mvid filename \"%s\"\n", [mvidPath UTF8String]);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
    assert(frame);
    
    // Release the NSImage ref inside the frame since we will operate on the CG image directly.
    frame.image = nil;
    
    CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
    assert(cgFrameBuffer);
    
    if (frameIndex == 0) {
      fprintf(stdout, "File %s, %dBPP, %d FRAMES\n", [[mvidPath lastPathComponent] UTF8String], (int)cgFrameBuffer.bitsPerPixel, (int)numFrames);
    }
    
    if (frame.isDuplicate) {
      fprintf(stdout, "FRAME %d (duplicate)\n", frameIndex+1);
    } else {
      fprintf(stdout, "FRAME %d\n", frameIndex+1);
      
      // Iterate over the pixel contents of the framebuffer
      
      int numPixels = cgFrameBuffer.width * cgFrameBuffer.height;
      
      uint16_t *pixel16Ptr = (uint16_t*)cgFrameBuffer.pixels;
      uint32_t *pixel32Ptr = (uint32_t*)cgFrameBuffer.pixels;
      
      int row = 0;
      int column = 0;
      for (int pixeli = 0; pixeli < numPixels; pixeli++) {
        
        if ((pixeli % cgFrameBuffer.width) == 0) {
          // At the first pixel in a new row
          column = 0;
          
          fprintf(stdout, "ROW %d\n", row);
          row += 1;
        }
        
        fprintf(stdout, "COLUMN %d: ", column);
        column += 1;
        
        if (cgFrameBuffer.bitsPerPixel == 16) {
          uint16_t pixel = *pixel16Ptr++;
          
#define CG_MAX_5_BITS 0x1F
          
          uint8_t red = (pixel >> 10) & CG_MAX_5_BITS;
          uint8_t green = (pixel >> 5) & CG_MAX_5_BITS;
          uint8_t blue = pixel & CG_MAX_5_BITS;
          
          fprintf(stdout, "HEX 0x%0.4X, RGB = (%d, %d, %d)\n", pixel, red, green, blue);
        } else if (cgFrameBuffer.bitsPerPixel == 24) {
          uint32_t pixel = *pixel32Ptr++;
          
          uint8_t red = (pixel >> 16) & 0xFF;
          uint8_t green = (pixel >> 8) & 0xFF;
          uint8_t blue = pixel & 0xFF;
          
          fprintf(stdout, "HEX 0x%0.6X, RGB = (%d, %d, %d)\n", pixel, red, green, blue);
        } else {
          uint32_t pixel = *pixel32Ptr++;
          
          uint8_t alpha = (pixel >> 24) & 0xFF;
          uint8_t red = (pixel >> 16) & 0xFF;
          uint8_t green = (pixel >> 8) & 0xFF;
          uint8_t blue = pixel & 0xFF;
          
          fprintf(stdout, "HEX 0x%0.8X, RGBA = (%d, %d, %d, %d)\n", pixel, red, green, blue, alpha);
        }
      }
    }
    
    fflush(stdout);
    
    [pool drain];
  }
  
  [frameDecoder close];
}

// This method will "map" certain alpha values to a new value based on the input
// specification. This operation is not so easy to implement with 3rd party
// software though it is conceptually simple. This method would typically be used
// to "clamp" alpha values near the opaque value to the actual opaque value.
// For example, if a green screen video was processed in a non-optimal way, pixels
// that really should have an alpha value of 255 (opaque) might have the values
// 254, 253, or even 252. This method makes it easy to map these values below
// the opaque value to the opaque value by passing "252,253,254=255" as
// the map spec.

void alphaMapMvid(NSString *inMvidPath,
                  NSString *outMvidPath,
                  NSString *mapSpecStr)
{
  BOOL isMvid;
  
  isMvid = [inMvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  isMvid = [outMvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  // Check the "MAPSPEC". The format is like so:
  //
  // 252=255
  //
  // NUM=VALUE
  //
  // 1 to N
  //
  // Could include multiple mappings
  //
  // 1=0,2=0,253=255,254=255
  
  NSMutableDictionary *mappings = [NSMutableDictionary dictionary];
  
  NSArray *elements = [mapSpecStr componentsSeparatedByString:@","];
  
  for (NSString *element in elements) {
    NSArray *singleSpecElements = [element componentsSeparatedByString:@"="];
    int count = [singleSpecElements count];
    if (count != 2) {
      fprintf(stderr, "MAPSPEC must contain 1 to N integer elements of the form IN=OUT, got \"%s\"\n", [element UTF8String]);
      exit(1);
    }
    // Store the input mapping number and the output number it maps to
    NSString *inNumStr = [singleSpecElements objectAtIndex:0];
    NSString *outNumStr = [singleSpecElements objectAtIndex:1];
    
    NSInteger inInt;
    NSInteger outInt;
    
    if ([inNumStr isEqualToString:@"0"]) {
      inInt = 0;
    } else {
      inInt = [inNumStr integerValue];
      if (inInt == 0) {
        inInt = -1;
      }
    }
    
    if ([outNumStr isEqualToString:@"0"]) {
      outInt = 0;
    } else {
      outInt = [outNumStr integerValue];
      if (outInt == 0) {
        outInt = -1;
      }
    }
    
    if (outInt < 0 || inInt < 0) {
      fprintf(stderr, "MAPSPEC must contain 1 to N integer elements of the form IN=OUT, got \"%s\"\n", [element UTF8String]);
      exit(1);
    }

    if (outInt > 255 || inInt > 255) {
      fprintf(stderr, "MAPSPEC IN=OUT values must be in range 0->255, got \"%s\"\n", [element UTF8String]);
      exit(1);
    }
    
    NSNumber *inNum = [NSNumber numberWithInteger:inInt];
    NSNumber *outNum = [NSNumber numberWithInteger:outInt];
    
    [mappings setObject:outNum forKey:inNum];
  }

  if ([mappings count] == 0) {
    fprintf(stderr, "No MAPSPEC elements parsed\n");
    exit(1);
  }
  
  fprintf(stdout, "processing input file, will apply %d alpha channel mapping(s)\n", (int)[mappings count]);
  
  // Read in existing file into from the input file and create an output file
  // that has exactly the same options.
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked = [frameDecoder openForReading:inMvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open input mvid filename \"%s\"\n", [inMvidPath UTF8String]);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  float frameDuration = [frameDecoder frameDuration];
  
  int bpp = [frameDecoder header]->bpp;
  
  if (bpp != 32) {
    fprintf(stderr, "-alphamap can only be used on a 32BPP mvid file since an alpha channel is required\n");
    exit(1);
  }
  
  int width = [frameDecoder width];
  int height = [frameDecoder height];
    
  // Writer that will write the RGB values. Note that invoking process_frame_file()
  // will define the output width/height based on the size of the image passed in.
  
  MvidFileMetaData *mvidFileMetaData = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaData.bpp = bpp;
  mvidFileMetaData.checkAlphaChannel = FALSE;
  
  AVMvidFileWriter *fileWriter = makeMVidWriter(outMvidPath, bpp, frameDuration, numFrames);
  
  CGFrameBuffer *mappedFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:width height:height];
  
  uint32_t numPixelsModified = 0;
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
    assert(frame);
    
    // Release the NSImage ref inside the frame since we will operate on the CG image directly.
    frame.image = nil;
    
    CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
    assert(cgFrameBuffer);
    
    // sRGB support
    
    if (frameIndex == 0) {
      mappedFrameBuffer.colorspace = cgFrameBuffer.colorspace;
    }
    
    // Copy image area into mappedFrameBuffer
    
    BOOL worked;
    CGImageRef frameImage = nil;
    
    frameImage = [cgFrameBuffer createCGImageRef];
    worked = (frameImage != nil);
    assert(worked);
    
    [mappedFrameBuffer clear];
    worked = [mappedFrameBuffer renderCGImage:frameImage];
    assert(worked);
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
    
    // Do mapping logic by iterating over all the pixels in mappedFrameBuffer
    // and then editing the pixels in place if needed.
    
    int numPixels = mappedFrameBuffer.width * mappedFrameBuffer.height;
    
    uint32_t *pixel32Ptr = (uint32_t*)mappedFrameBuffer.pixels;
    
    for (int pixeli = 0; pixeli < numPixels; pixeli++) {
      uint32_t pixel = pixel32Ptr[pixeli];
      
      uint32_t alpha = (pixel >> 24) & 0xFF;
      uint32_t red = (pixel >> 16) & 0xFF;
      uint32_t green = (pixel >> 8) & 0xFF;
      uint32_t blue = pixel & 0xFF;
      
      // Check to see if the alpha value appears in the map
      
      NSNumber *keyNum = [NSNumber numberWithInteger:(NSInteger)alpha];
      NSNumber *valueNum = [mappings objectForKey:keyNum];
      
      if (valueNum != nil) {
        // This value appears in the mapping, get the new alpha value, combine
        // it with the existing RGB values and write the pixel back into the framebuffer.
        
        NSInteger mappedAlpha = [valueNum integerValue];
        uint32_t mappedUnsigned = (uint32_t)mappedAlpha;
        
        pixel = (mappedUnsigned << 24) | (red << 16) | (green << 8) | blue;
        
        pixel32Ptr[pixeli] = pixel;
        numPixelsModified += 1;
      }
    }
    
    // Now create a UIImage so that the result of this operation can be encoded into the output mvid
    
    frameImage = [mappedFrameBuffer createCGImageRef];
    worked = (frameImage != nil);
    assert(worked);
    
    BOOL isKeyframe = FALSE;
    if (frameIndex == 0) {
      isKeyframe = TRUE;
    }
    
    process_frame_file(fileWriter, NULL, frameImage, frameIndex, mvidFileMetaData, isKeyframe, NULL);
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
    
    [pool drain];
  }
  
  [fileWriter rewriteHeader];
  [fileWriter close];

  fprintf(stdout, "Mapped %d pixels to new values\n", numPixelsModified);
  fprintf(stdout, "Wrote %s\n", [fileWriter.mvidPath UTF8String]);
  return;
}

// Execute rdelta, this is basically a diff of an original (uncompressed) as compared
// to a compressed representation. The compressed implementation uses much less space
// than the original, but how much compression is too much? This logic attempts to
// visually show which pixels have been changed by the compression. The pixels written
// to the output mvid are the same ones in the inModifiedMvidPath argument, except that
// diffs as compared to inOriginalMvidPath will be displayed with a 50% red overlay.

void rdeltaMvidMovie(char *inOriginalMvidPathCstr,
                     char *inModifiedMvidPathCstr,
                     char *outMvidPathCstr)
{
  BOOL isMvid;
  
  NSString *inOriginalMvidPath = [NSString stringWithUTF8String:inOriginalMvidPathCstr];
  NSString *inModifiedMvidPath = [NSString stringWithUTF8String:inModifiedMvidPathCstr];
  NSString *outMvidPath = [NSString stringWithUTF8String:outMvidPathCstr];
  
  isMvid = [inOriginalMvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  isMvid = [inModifiedMvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }

  isMvid = [outMvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
    
  // Read in existing original and compressed files
  
  AVMvidFrameDecoder *frameDecoderOriginal = [AVMvidFrameDecoder aVMvidFrameDecoder];
  AVMvidFrameDecoder *frameDecoderCompressed = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked;
  worked = [frameDecoderOriginal openForReading:inOriginalMvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open input mvid filename \"%s\"\n", inOriginalMvidPathCstr);
    exit(1);
  }
  
  worked = [frameDecoderCompressed openForReading:inModifiedMvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open input mvid filename \"%s\"\n", inModifiedMvidPathCstr);
    exit(1);
  }
  
  worked = [frameDecoderOriginal allocateDecodeResources];
  assert(worked);

  worked = [frameDecoderCompressed allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoderOriginal numFrames];
  assert(numFrames > 0);
  
  NSUInteger compressedNumFrames = [frameDecoderCompressed numFrames];
  if (numFrames != compressedNumFrames) {
    fprintf(stderr, "rdelta failed: original mvid contains %d frames while compressed mvid contains %d frames\n", numFrames, compressedNumFrames);
    exit(1);    
  }
  
  float frameDuration = [frameDecoderOriginal frameDuration];
  float compressedFrameDuration = [frameDecoderCompressed frameDuration];
  
  if (frameDuration != compressedFrameDuration) {
    fprintf(stderr, "rdelta failed: original mvid framerate %.4f while compressed framerate is %.4f\n", frameDuration, compressedFrameDuration);
    exit(1);
  }
  
  int bpp = [frameDecoderOriginal header]->bpp;
  int compressedBpp = [frameDecoderCompressed header]->bpp;
  
  if (bpp != compressedBpp) {
    fprintf(stderr, "rdelta failed: original mvid bpp %d while compressed bpp is %d\n", bpp, compressedBpp);
    exit(1);
  }
  
  int width = [frameDecoderOriginal width];
  int height = [frameDecoderOriginal height];
  
  int compressedWidth = [frameDecoderCompressed width];
  int compressedHeight = [frameDecoderCompressed height];
  
  if ((compressedWidth != width) || (compressedHeight != height)) {
    fprintf(stderr, "rdelta failed: original mvid width x height %d x %d while compressed mvid width x height %d x %d\n", width, height, compressedWidth, compressedHeight);
    exit(1);
  }
  
  // Writer that will write the RGB values. Note that invoking process_frame_file()
  // will define the output width/height based on the size of the image passed in.
  
  MvidFileMetaData *mvidFileMetaData = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaData.bpp = bpp;
  mvidFileMetaData.checkAlphaChannel = FALSE;
  
  AVMvidFileWriter *fileWriter = makeMVidWriter(outMvidPath, bpp, frameDuration, numFrames);
  
  CGFrameBuffer *outFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:width height:height];
  CGFrameBuffer *redFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:width height:height];
  
  uint32_t numPixelsModified = 0;
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *originalFrame = [frameDecoderOriginal advanceToFrame:frameIndex];
    assert(originalFrame);

    AVFrame *compressedFrame = [frameDecoderCompressed advanceToFrame:frameIndex];
    assert(compressedFrame);
    
    // Release the NSImage ref inside the frame since we will operate on the CG image directly.
    originalFrame.image = nil;
    compressedFrame.image = nil;
    
    CGFrameBuffer *originalCgFrameBuffer = originalFrame.cgFrameBuffer;
    assert(originalCgFrameBuffer);

    CGFrameBuffer *compressedCgFrameBuffer = compressedFrame.cgFrameBuffer;
    assert(originalCgFrameBuffer);
    
    // sRGB support
    
    if (frameIndex == 0) {
      outFrameBuffer.colorspace = compressedCgFrameBuffer.colorspace;
      redFrameBuffer.colorspace = compressedCgFrameBuffer.colorspace;
    }
    
    // Copy compressed image data into the output framebuffer
    
    BOOL worked;
    CGImageRef frameImage = nil;
    
    frameImage = [compressedCgFrameBuffer createCGImageRef];
    worked = (frameImage != nil);
    assert(worked);
    
    [outFrameBuffer clear];
    worked = [outFrameBuffer renderCGImage:frameImage];
    assert(worked);
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
    
    // Now iterate over the original and diff pixels and write any diffs to the redFrameBuffer
    
    [redFrameBuffer clear];
    
    int numPixels = width * height;
    
    // FIXME: impl for 16 bpp
    assert(originalCgFrameBuffer.bitsPerPixel != 16);
    
    uint32_t *originalCgFrameBuffer32Ptr = (uint32_t*)originalCgFrameBuffer.pixels;
    uint32_t *compressedCgFrameBuffer32Ptr = (uint32_t*)compressedCgFrameBuffer.pixels;
    uint32_t *redCgFrameBuffer32Ptr = (uint32_t*)redFrameBuffer.pixels;
    
    for (int pixeli = 0; pixeli < numPixels; pixeli++) {
      uint32_t originalPixel = originalCgFrameBuffer32Ptr[pixeli];
      uint32_t compressedPixel = compressedCgFrameBuffer32Ptr[pixeli];
      
      /*
      uint32_t original_alpha = (originalPixel >> 24) & 0xFF;
      uint32_t original_red = (originalPixel >> 16) & 0xFF;
      uint32_t original_green = (originalPixel >> 8) & 0xFF;
      uint32_t original_blue = originalPixel & 0xFF;
      
      uint32_t compressed_alpha = (compressedPixel >> 24) & 0xFF;
      uint32_t compressed_red = (compressedPixel >> 16) & 0xFF;
      uint32_t compressed_green = (compressedPixel >> 8) & 0xFF;
      uint32_t compressed_blue = compressedPixel & 0xFF;
       */
      
      if (originalPixel != compressedPixel) {
        uint32_t redPixel = rgba_to_bgra(0xFF/2, 0, 0, 0xFF/2);
        redCgFrameBuffer32Ptr[pixeli] = redPixel;
        numPixelsModified++;
      }
    }
    
    // Render red pixels over compressed pixels in outFrameBuffer (matte)
    
    frameImage = [redFrameBuffer createCGImageRef];
    worked = (frameImage != nil);
    assert(worked);
    
    worked = [outFrameBuffer renderCGImage:frameImage];
    assert(worked);
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
    
    // Now create a UIImage so that the result of this operation can be encoded into the output mvid
    
    frameImage = [outFrameBuffer createCGImageRef];
    worked = (frameImage != nil);
    assert(worked);
    
    BOOL isKeyframe = FALSE;
    if (frameIndex == 0) {
      isKeyframe = TRUE;
    }
    
    process_frame_file(fileWriter, NULL, frameImage, frameIndex, mvidFileMetaData, isKeyframe, NULL);
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
    
    [pool drain];
  }
  
  [fileWriter rewriteHeader];
  [fileWriter close];
  
  fprintf(stdout, "Found %d modified pixels\n", numPixelsModified);
  fprintf(stdout, "Wrote %s\n", [fileWriter.mvidPath UTF8String]);
  return;
}

// Flatten will read all of the frames from a movie and write all the frames
// into a single PNG image. The output image will be a multiple of the original
// image height based on the number of frames in the movie.

void
flattenMvidMovie(char *inOriginalMvidFilename, char *outFlatPNGFilename)
{
  NSString *mvidPath = [NSString stringWithUTF8String:inOriginalMvidFilename];
  
  BOOL isMvid = [mvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked = [frameDecoder openForReading:mvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open mvid filename \"%s\"\n", inOriginalMvidFilename);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  //float frameDuration = [frameDecoder frameDuration];
  
  int bpp = [frameDecoder header]->bpp;
  
  int width = [frameDecoder width];
  int height = [frameDecoder height];
  
  // Verify that the input color data has been mapped to the sRGB colorspace.
  
  if (maxvid_file_version([frameDecoder header]) == MV_FILE_VERSION_ZERO) {
    fprintf(stderr, "%s\n", "-mixalpha on MVID is not supported for an old MVID file version 0.");
    exit(1);
  }
  
  // Allocate framebuffer large enought to hold all the output frames in a single image
  
  int outHeight = height * numFrames;
  
  CGFrameBuffer *outFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:width height:outHeight];
  uint32_t *outPixelsPtr = (uint32_t*)outFrameBuffer.pixels;
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
    assert(frame);
    
    // Release the NSImage ref inside the frame since we will operate on the CG image directly.
    frame.image = nil;
    
    CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
    assert(cgFrameBuffer);
    
    if (frameIndex == 0) {
      outFrameBuffer.colorspace = cgFrameBuffer.colorspace;
    }
    
    NSUInteger numPixels = cgFrameBuffer.width * cgFrameBuffer.height;
    uint32_t *pixels = (uint32_t*)cgFrameBuffer.pixels;
    
    // Append pixels to outFrameBuffer
    
    int numBytes = numPixels * sizeof(uint32_t);
    memcpy(outPixelsPtr, pixels, numBytes);
    outPixelsPtr += numPixels;
    
    [pool release];
  }
  
  NSString *pngPath = [NSString stringWithFormat:@"%s", outFlatPNGFilename];
  
  NSData *pngData = [outFrameBuffer formatAsPNG];
  
  [pngData writeToFile:pngPath atomically:NO];
  
  fprintf(stdout, "Wrote %s with size %d x %d\n", outFlatPNGFilename, (int)outFrameBuffer.width, (int)outFrameBuffer.height);
  
  return;
}

// Reverse a flatten operation by reading the framerate and BPP info from a MVID
// reading the new image data from a flat PNG, and then writing the pixels from
// the PNG to and output MVID.

void
unflattenMvidMovie(char *inOriginalMvidFilename, char *inFlatPNGFilename, char *outMvidFilename)
{
  NSString *mvidPath = [NSString stringWithUTF8String:inOriginalMvidFilename];
  
  BOOL isMvid = [mvidPath hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  // Open original MVID for reading of header data
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked = [frameDecoder openForReading:mvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open mvid filename \"%s\"\n", inOriginalMvidFilename);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  float frameDuration = [frameDecoder frameDuration];
  
  int bpp = [frameDecoder header]->bpp;
  
  int width = [frameDecoder width];
  int height = [frameDecoder height];
  
  // Verify that the input color data has been mapped to the sRGB colorspace.
  
  if (maxvid_file_version([frameDecoder header]) == MV_FILE_VERSION_ZERO) {
    fprintf(stderr, "%s\n", "-unflatten on MVID is not supported for an old MVID file version 0.");
    exit(1);
  }
  
  // Read input PNG and verify that the size of the input matches the expected size in pixels
  
  CGImageRef imageRef = NULL;
  
  NSString *inFlatPNGFilenameStr = [NSString stringWithFormat:@"%s", inFlatPNGFilename];
  imageRef = createImageFromFile(inFlatPNGFilenameStr);
  
  if (imageRef == NULL) {
    fprintf(stderr, "error: cannot open flat PNG filename \"%s\"\n", inFlatPNGFilename);
    exit(1);
  }
  
  assert(imageRef);
  
  // Copy all pixels in input to a framebuffer
  
  int inHeight = height * numFrames;
  
  // Verify height of PNG

  if (CGImageGetHeight(imageRef) != inHeight) {
    fprintf(stderr, "error: input flat PNG filename \"%s\" must contain image of height %d not %d\n", inFlatPNGFilename, inHeight, (int)CGImageGetHeight(imageRef));
    exit(1);
  }
  
  if (CGImageGetWidth(imageRef) != width) {
    fprintf(stderr, "error: input flat PNG filename \"%s\" must contain image of width %d not %d\n", inFlatPNGFilename, width, (int)CGImageGetWidth(imageRef));
    exit(1);
  }
  
  CGFrameBuffer *inFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:width height:inHeight];
  
  // Explicitly use sRGB
  {
    CGColorSpaceRef colorSpace = NULL;
    colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    assert(colorSpace);
    inFrameBuffer.colorspace = colorSpace;
    CGColorSpaceRelease(colorSpace);
  }

  [inFrameBuffer renderCGImage:imageRef];
  CGImageRelease(imageRef);

  uint32_t *inPixelsPtr = (uint32_t*)inFrameBuffer.pixels;
  
  // Open output MVID and duplicate the header settings from the original MVID
  
  MvidFileMetaData *mvidFileMetaData = [MvidFileMetaData mvidFileMetaData];
  mvidFileMetaData.bpp = bpp;
  mvidFileMetaData.checkAlphaChannel = FALSE;
  
  NSString *outMvidPath = [NSString stringWithFormat:@"%s", outMvidFilename];
  
  AVMvidFileWriter *fileWriter = makeMVidWriter(outMvidPath, bpp, frameDuration, numFrames);
  
  fileWriter.movieSize = CGSizeMake(width, height);
  
  // Allocate framebuffer for one frame from the input PNG
  
  CGFrameBuffer *currentFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:width height:height];
  assert(currentFrameBuffer);
  
  // Explicitly use sRGB
  {
    CGColorSpaceRef colorSpace = NULL;
    colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    assert(colorSpace);
    currentFrameBuffer.colorspace = colorSpace;
    CGColorSpaceRelease(colorSpace);
  }
  
  uint32_t *currentPixelsPtr = (uint32_t*)currentFrameBuffer.pixels;
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    int numBytes = width * height * sizeof(uint32_t);
    memcpy(currentPixelsPtr, inPixelsPtr, numBytes);
    
    inPixelsPtr += (width * height);
    
    CGImageRef frameImage = [currentFrameBuffer createCGImageRef];
    
    BOOL isKeyframe = FALSE;
    if (frameIndex == 0) {
      isKeyframe = TRUE;
    }
    
    // When original video is marked as "all keyframes" then retain this property in the output MVID
    
    if (frameDecoder.isAllKeyframes) {
      isKeyframe = TRUE;
    }
    
    process_frame_file(fileWriter, NULL, frameImage, frameIndex, mvidFileMetaData, isKeyframe, NULL);
    
    if (frameImage) {
      CGImageRelease(frameImage);
    }
    
    [pool drain];
  }
  
  [fileWriter rewriteHeader];
  [fileWriter close];
  
  fprintf(stdout, "Wrote %s\n", [fileWriter.mvidPath UTF8String]);
  return;
}

// main() Entry Point

int main (int argc, const char * argv[]) {
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
  
	if ((argc == 3 || argc == 4) && (strcmp(argv[1], "-extract") == 0)) {
		// mvidmoviemaker -extract FILE.mvid ?FILEPREFIX?

    char *mvidFilename = (char *)argv[2];
    char *framesFilePrefix;
    
    if (argc == 3) {
      framesFilePrefix = "Frame";
    } else {
      framesFilePrefix = (char*)argv[3];
    }
    
		extractFramesFromMvidMain(mvidFilename, framesFilePrefix, EXTRACT_FRAMES_TYPE_PNG);
	} else if ((argc == 3 || argc == 4) && (strcmp(argv[1], "-extractpixels") == 0)) {
		// mvidmoviemaker -extractpixels FILE.mvid ?FILEPREFIX?

    char *mvidFilename = (char *)argv[2];
    char *framesFilePrefix;
    
    if (argc == 3) {
      framesFilePrefix = "Frame";
    } else {
      framesFilePrefix = (char*)argv[3];
    }
    
		extractFramesFromMvidMain(mvidFilename, framesFilePrefix, EXTRACT_FRAMES_TYPE_PIXELS);
	} else if ((argc == 3 || argc == 4) && (strcmp(argv[1], "-extractcodec") == 0)) {
		// mvidmoviemaker -extractcodec FILE.mvid ?FILEPREFIX?
    
    char *mvidFilename = (char *)argv[2];
    char *framesFilePrefix;
    
    if (argc == 3) {
      framesFilePrefix = "Frame";
    } else {
      framesFilePrefix = (char*)argv[3];
    }
    
		extractFramesFromMvidMain(mvidFilename, framesFilePrefix, EXTRACT_FRAMES_TYPE_CODEC);
	} else if ((argc == 5) && (strcmp(argv[1], "-crop") == 0)) {
    // mvidmoviemaker -crop "X Y WIDTH HEIGHT" INMOVIE.mvid OUTMOVIE.mvid
    
    char *cropSpec = (char *)argv[2];
    char *inMvidFilename = (char *)argv[3];
    char *outMvidFilename = (char *)argv[4];
    
    cropMvidMovie(cropSpec, inMvidFilename, outMvidFilename);
	} else if ((argc == 5) && (strcmp(argv[1], "-resize") == 0)) {
    // mvidmoviemaker -resize OPTIONS_RESIZE INMOVIE.mvid OUTMOVIE.mvid
    
    char *resizeSpec = (char *)argv[2];
    char *inMvidFilename = (char *)argv[3];
    char *outMvidFilename = (char *)argv[4];
    
    resizeMvidMovie(resizeSpec, inMvidFilename, outMvidFilename);
	} else if ((argc == 3) && (strcmp(argv[1], "-4up") == 0)) {
    // mvidmoviemaker -4up INMOVIE.mvid

    char *inMvidFilenameCstr = (char *)argv[2];
    fourupMvidMovie(inMvidFilenameCstr);
	} else if ((argc == 5) && (strcmp(argv[1], "-rdelta") == 0)) {
    // mvidmoviemaker -rdelta INORIG.mvid INMOD.mvid OUTFILE.mvid
    
    char *inOriginalMvidFilename = (char *)argv[2];
    char *inModifiedMvidFilename = (char *)argv[3];
    char *outMvidFilename = (char *)argv[4];
    
    rdeltaMvidMovie(inOriginalMvidFilename, inModifiedMvidFilename, outMvidFilename);
	} else if (((argc == 3) || (argc == 4)) && (strcmp(argv[1], "-upgrade") == 0)) {
    // mvidmoviemaker -upgrade FILE.mvid ?OUTFILE.mvid?
    
    char *inMvidFilename = (char *)argv[2];
    char *optionalMvidFilename = NULL;
    if (argc == 4) {
      optionalMvidFilename = (char *)argv[3];
    }
    
    upgradeMvidMovie(inMvidFilename, optionalMvidFilename);
  } else if ((argc == 4) && (strcmp(argv[1], "-flatten") == 0)) {
    // mvidmoviemaker -flatten INORIG.mvid FLAT.png
    
    char *inOriginalMvidFilename = (char *)argv[2];
    char *outFlatPNGFilename = (char *)argv[3];
    
    flattenMvidMovie(inOriginalMvidFilename, outFlatPNGFilename);

  } else if ((argc == 5) && (strcmp(argv[1], "-unflatten") == 0)) {
    // mvidmoviemaker -unflatten INORIG.mvid FLAT.png OUT.mvid
    
    char *inOriginalMvidFilename = (char *)argv[2];
    char *inFlatPNGFilename = (char *)argv[3];
    char *outMvidFilename = (char *)argv[4];
    
    unflattenMvidMovie(inOriginalMvidFilename, inFlatPNGFilename, outMvidFilename);
	} else if ((argc == 3) && (strcmp(argv[1], "-info") == 0)) {
    // mvidmoviemaker -info movie.mvid
    
    char *mvidFilename = (char *)argv[2];
    
    printMovieHeaderInfo(mvidFilename);
	} else if ((argc == 3) && (strcmp(argv[1], "-adler") == 0)) {
    // mvidmoviemaker -info movie.mvid
    
    char *firstFilenameCstr = (char*)argv[2];
    NSString *firstFilenameStr = [NSString stringWithUTF8String:firstFilenameCstr];
    
    if ([firstFilenameStr hasSuffix:@".mvid"])
    {
      printMvidFrameAdler(firstFilenameStr);
      exit(0);
    } else {
      fprintf(stderr, "error: FILENAME must be a .mvid file : %s\n", firstFilenameCstr);
      exit(1);
    }
	} else if ((argc == 5) && (strcmp(argv[1], "-alphamap") == 0)) {
    // mvidmoviemaker -alphamap INPUT.mvid OUTPUT.mvid MAPSPEC
    
    char *firstFilenameCstr = (char*)argv[2];
    NSString *firstFilenameStr = [NSString stringWithUTF8String:firstFilenameCstr];
    
    char *secondFilenameCstr = (char*)argv[3];
    NSString *secondFilenameStr = [NSString stringWithUTF8String:secondFilenameCstr];

    char *mapSpecCstr = (char*)argv[4];
    NSString *mapSpecStr = [NSString stringWithUTF8String:mapSpecCstr];
    alphaMapMvid(firstFilenameStr, secondFilenameStr, mapSpecStr);
	} else if ((argc == 3) && (strcmp(argv[1], "-pixels") == 0)) {
    // mvidmoviemaker -pixels movie.mvid
    
    char *firstFilenameCstr = (char*)argv[2];
    NSString *firstFilenameStr = [NSString stringWithUTF8String:firstFilenameCstr];
    
    if ([firstFilenameStr hasSuffix:@".mvid"])
    {
      printMvidPixels(firstFilenameStr);
      exit(0);
    } else {
      fprintf(stderr, "error: FILENAME must be a .mvid file : %s\n", firstFilenameCstr);
      exit(1);
    }
  } else if ((argc == 3) && (strcmp(argv[1], "-fps") == 0)) {
    // Return a FRAME/SEC specification that most closely matches the
    // exact framerate of the video for known values.
    //
    // mvidmoviemaker -fps movie.mvid
    
    char *firstFilenameCstr = (char*)argv[2];
    NSString *firstFilenameStr = [NSString stringWithUTF8String:firstFilenameCstr];
    
    if ([firstFilenameStr hasSuffix:@".mvid"])
    {
      printMvidFPS(firstFilenameStr);
      exit(0);
    } else {
      fprintf(stderr, "error: FILENAME must be a .mvid file : %s\n", firstFilenameCstr);
      exit(1);
    }
#if defined(TESTMODE)
	} else if (argc == 2 && (strcmp(argv[1], "-test") == 0)) {
    testmode();
#endif // TESTMODE
#if defined(SPLITALPHA)
	} else if (argc == 3 && (strcmp(argv[1], "-splitalpha") == 0)) {
    // mvidmoviemaker -splitalpha INFILE.mvid
    char *mvidFilenameCstr = (char*)argv[2];
    splitalpha(mvidFilenameCstr);
	} else if (argc == 3 && (strcmp(argv[1], "-joinalpha") == 0)) {
    // mvidmoviemaker -joinalpha OUTFILE.mvid
    char *mvidFilenameCstr = (char*)argv[2];
    joinalpha(mvidFilenameCstr);
  } else if (argc == 3 && (strcmp(argv[1], "-mixalpha") == 0)) {
    // mvidmoviemaker -mixalpha INFILE.mvid
    char *mvidFilenameCstr = (char*)argv[2];
    mixalpha(mvidFilenameCstr);
  } else if (argc == 3 && (strcmp(argv[1], "-unmixalpha") == 0)) {
    // mvidmoviemaker -unmixalpha INFILE.mvid
    char *mvidFilenameCstr = (char*)argv[2];
    unmixalpha(mvidFilenameCstr);
  } else if (argc == 5 && (strcmp(argv[1], "-mixstraight") == 0)) {
    // mvidmoviemaker -mixstraight RGB.mvid ALPHA.mvid MIXED.mvid
    char *rgbMvidFilenameCstr = (char*)argv[2];
    char *alphaMvidFilenameCstr = (char*)argv[3];
    char *mixedMvidFilenameCstr = (char*)argv[4];
    mixstraight(rgbMvidFilenameCstr, alphaMvidFilenameCstr, mixedMvidFilenameCstr);
#endif // SPLITALPHA
  } else if (argc >= 3) {
    // Either:
    //
    // mvidmoviemaker FIRSTFRAME.png OUTFILE.mvid ?OPTIONS?
    
    char *firstFilenameCstr = (char*)argv[1];
    char *secondFilenameCstr = (char*)argv[2];
    
    if (TRUE) {
      fprintf(stderr, "%s\n", firstFilenameCstr);
      fprintf(stderr, "%s\n", secondFilenameCstr);
    }
    
    NSString *firstFilenameStr = [NSString stringWithUTF8String:firstFilenameCstr];
    NSString *secondFilenameStr = [NSString stringWithUTF8String:secondFilenameCstr];
    
    // If the arguments are INFILE.mvid OUTFILE.mvid, then convert video data
    // back to Quicktime format and write to a new movie file.
    
    if ([firstFilenameStr hasSuffix:@".mvid"] && [secondFilenameStr hasSuffix:@".mov"])
    {
      fprintf(stderr, "converting from .mvid to .mov no longer supported (thanks Apple)\n");
      exit(1);
    }

    char *mvidFilenameCstr = secondFilenameCstr;
    
    // The second argument has to be "*.mvid"
    
    NSString *mvidFilename = [NSString stringWithUTF8String:mvidFilenameCstr];
    
    BOOL isMvid = [mvidFilename hasSuffix:@".mvid"];
    
    if (isMvid == FALSE) {
      fprintf(stderr, "%s", USAGE);
      exit(1);
    }

    // If the first argument is a .mov file, then this must be
    // a .mov -> .mvid conversion.
    
    NSString *movFilename = [NSString stringWithUTF8String:firstFilenameCstr];
    
    BOOL isMov = [movFilename hasSuffix:@".mov"];
    
    // Both forms support 1 to N arguments like "-fps 15"
    
    MovieOptions options;
    options.framerate = 0.0f;
    options.bpp = -1;
    options.keyframe = 10000;
    
    if ((argc > 3) && (((argc - 3) % 2) != 0)) {
      // Uneven number of options
      fprintf(stderr, "error: OPTIONS must be an even number arguments of the form -name value\n");
      exit(1);
    } else if (argc > 3) {
      // Parse OPTIONS
      
      int pairCount = (argc - 3) / 2;
      
      for (int i=0; i<pairCount; i++) {
        int offset = 3 + (i * 2);
        char *optionCstr = (char*)argv[offset];
        char *valueCstr = (char*)argv[offset+1];
        
        NSString *optionStr = [NSString stringWithUTF8String:optionCstr];
        NSString *valueStr = [NSString stringWithUTF8String:valueCstr];
        
        NSLog(@"option \"%s\" -> \"%s\"", optionCstr, valueCstr);
        
        if ([optionStr isEqualToString:@"-fps"]) {
          // Valid input:
          // -fps 24
          // -fps 0.5  (1 frame every 2 seconds)
          // -fps 24/1 (24 frames per second)

          NSString *fpsInputStr = [valueStr stringByReplacingOccurrencesOfString:@" " withString:@""];
          NSString *fpsPairStr = [fpsInputStr stringByReplacingOccurrencesOfString:@"/" withString:@" "];
          
          float fps = 0.0;
          
          if ([fpsPairStr isEqualToString:fpsInputStr] == FALSE) {
            // -fps "24/1" -> "24/1"
            
            NSArray *values = [fpsInputStr componentsSeparatedByString:@"/"];
            
            if (values.count != 2) {
              fprintf(stderr, "-fps \"%s\" is invalid, must be an int value or FRAMES/SECONDS", (char*)[optionStr UTF8String]);
              exit(1);
            }
            
            float frames = [values[0] floatValue];
            float second = [values[1] floatValue];
            
            if (frames == 0.0f) {
              fprintf(stderr, "-fps \"%s\" is zero", (char*)[optionStr UTF8String]);
              exit(1);
            }
            
            float framerate = second / frames;
            options.framerate = framerate;
          } else {
            fps = [valueStr floatValue];
            
            if ((fps <= 0.0f) || (fps >= 90.0f)) {
              fprintf(stderr, "%s", USAGE);
              exit(1);
            }
            
            options.framerate = 1.0f / fps;
          }
        } else if ([optionStr isEqualToString:@"-framerate"]) {
          // Valid input:
          // -framerate 0.0417 (24 FPS)
          // -framerate 0.5    (2 FPS)
          
          float framerate = [valueStr floatValue];
                    
          if (framerate <= 0.0f || framerate >= 90.0f) {
            fprintf(stderr, "error: -framerate is invalid \"%f\"\n", framerate);
            exit(1);
          }

          options.framerate = framerate;
        } else if ([optionStr isEqualToString:@"-bpp"]) {
          int bpp = [valueStr intValue];
          
          if ((bpp == 16) || (bpp == 24) || (bpp == 32)) {
            // No-op
          } else {
            fprintf(stderr, "error: -bpp is invalid \"%s\"\n", valueCstr);
            exit(1);
          }
          
          options.bpp = bpp;
        } else if ([optionStr isEqualToString:@"-keyframe"]) {
          int keyframe = [valueStr intValue];
          
          if (keyframe <= 0) {
            fprintf(stderr, "%s", USAGE);
            exit(1);
          }
          
          options.keyframe = keyframe;
        } else if ([optionStr isEqualToString:@"-deltas"]) {
          if ([valueStr isEqualToString:@"true"] ||
              [valueStr isEqualToString:@"TRUE"] ||
              [valueStr isEqualToString:@"1"]) {
            options.deltas = 1;
          } else if ([valueStr isEqualToString:@"false"] ||
                     [valueStr isEqualToString:@"FALSE"] ||
                     [valueStr isEqualToString:@"0"]) {
            options.deltas = 0;
          } else {
            fprintf(stderr, "error: option %s is invalid\n", optionCstr);
            exit(1);
          }
        } else {
          // Unmatched option
          
          fprintf(stderr, "error: option %s is invalid\n", optionCstr);
          exit(1);
        }
      }
    }    
    
    if (isMov) {
      // INFILE.mov : name of input Quicktime .mov file
      // OUTFILE.mvid : name of output .mvid file
      //
      // When converting, the original BPP and framerate are copied
      // but only the initial keyframe remains a keyframe in the .mvid
      // file for reasons of space savings.
      
      fprintf(stderr, "converting from .mvid to .mov no longer supported (thanks Apple)\n");
      exit(1);
    } else {
      // Otherwise, generate a .mvid from a series of images
      
      // FIRSTFRAME.png : name of first frame file of input PNG files. All
      //   video frames must exist in the same directory      
      // FILE.mvid : name of output file that will contain all the video frames
      
      // Either -framerate FLOAT or -fps FLOAT is required when build from frames.
      // -fps 15, -fps 29.97, -fps 30 are common values.
      
      // -bpp is optional, the default is 24 but 32 bpp will be detected if used.
      // If -bpp 16 is indicated then the result pixels will be downsamples from
      // 24 bpp to 16 bpp if the input source is in 24 bpp.
      
      encodeMvidFromFramesMain(mvidFilenameCstr,
                               firstFilenameCstr,
                               &options);
      
      if (TRUE) {
        printMovieHeaderInfo(mvidFilenameCstr);
      }
    }
	} else {
    fprintf(stderr, "%s", USAGE);
    exit(1);
  }
  
  [pool drain];
  return 0;
}

