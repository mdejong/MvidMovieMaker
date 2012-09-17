#import <Cocoa/Cocoa.h>

#import "CGFrameBuffer.h"

#import "AVMvidFileWriter.h"

#import "AVMvidFrameDecoder.h"

#include "maxvid_encode.h"

#import <QTKit/QTKit.h>

#import <QuickTime/Movies.h>

CGSize _movieDimensions;

NSString *movie_prefix;

CGFrameBuffer *prevFrameBuffer = nil;

#define EMIT_DELTA

#ifdef EMIT_DELTA
NSString *delta_directory = nil;
#endif

// ------------------------------------------------------------------------
//
// mvidmoviemaker
//
// To convert a .mov to .mvid (Quicktime to optimized .mvid) execute.
//
// mvidmoviemaker movie.mov movie.mvid
//
// To create a .mvid video file from a series of PNG images
// with a 15 FPS framerate and 32BPP "Millions+" (24 BPP plus alpha channel)
//
// mvidmoviemaker movie.mvid FRAMES/Frame001.png 15 32
//
// To extract the contents of an .mvid movie to PNG images:
//
// mvidmoviemaker -extract out.mvid ?FILEPREFIX?"
//
// The optional FILEPREFIX should be specified as "DumpFile" to get
// frames files named "DumpFile0001.png" and "DumpFile0002.png" and so on.
// ------------------------------------------------------------------------

#define USAGE \
"usage: mvidmoviemaker FILE.mov FILE.mvid" "\n" \
"usage: mvidmoviemaker FILE.mvid FIRSTFRAME.png FRAMERATE BITSPERPIXEL ?KEYFRAME?" "\n" \
"or   : mvidmoviemaker -extract FILE.mvid ?FILEPREFIX?" "\n"


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
  
	NSData *image_data = [NSData dataWithContentsOfFile:filenameStr];
	if (image_data == nil) {
		fprintf(stderr, "can't read image data from file \"%s\"\n", [filenameStr UTF8String]);
		exit(1);
	}
  
	// Create image object from src image data.
  
  sourceRef = CGImageSourceCreateWithData((CFDataRef)image_data, NULL);
  
  // Make sure the image source exists before continuing
  
  if (sourceRef == NULL) {
    fprintf(stderr, "CGImageSourceCreateWithData returned NULL.");
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
  
  BOOL worked = [mvidWriter open];
  if (worked == FALSE) {
    fprintf(stderr, "error: Could not open .mvid output file \"%s\"", (char*)[mvidFilename UTF8String]);        
    exit(1);
  }
  
  return mvidWriter;
}

// This method is invoked with a path that contains the frame
// data and the offset into the frame array that this specific
// frame data is found at.
//
// mvidWriter  : Output destination for MVID frame data.
// filenameStr : Name of .png file that contains the frame data
// existingImageRef : If NULL, image is loaded from filenameStr instead
// frameIndex  : Frame index (starts at zero)
// bppNum      : 16, 24, or 32 BPP
// checkAlphaChannel : If bpp is 24 and this argument is TRUE, scan output pixels for non-opaque image.
// isKeyframe  : TRUE if this specific frame should be stored as a keyframe (as opposed to a delta frame)

int process_frame_file(AVMvidFileWriter *mvidWriter,
                       NSString *filenameStr,
                       CGImageRef existingImageRef,
                       int frameIndex,
                       int bppNum,
                       BOOL checkAlphaChannel,
                       BOOL isKeyframe)
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
  
  // FIXME: if the input image in the generic RGB colorspace, but the output is in
  // the SRGB colorspace, then the input will not equal the output? Is it possible
  // to implicitly assign the sRGB colorspace to the input "generic" or unspecificed PNG?
  //
  // SRGB
  // https://gist.github.com/1130831
  // http://www.mailinglistarchive.com/html/quartz-dev@lists.apple.com/2010-04/msg00076.html
  // http://www.w3.org/Graphics/Color/sRGB.html (see alpha masking topic)
  //
  // Render from input (RGB or whatever) into sRGB, this could involve conversions
  // but it makes the results portable and it basically better because it is still as
  // lossless as possible given the constraints. Only output sRGB and only work with
  // sRGB formatted data, perhaps a flag would be needed to reject images created by
  // earlier versions that don't use sRGB directly.
    
  CGSize imageSize = CGSizeMake(CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));
  int imageWidth = imageSize.width;
  int imageHeight = imageSize.height;

  assert(imageWidth > 0);
  assert(imageHeight > 0);
  
  // If this is the first frame, set the movie size based on the size of the first frame
  
  if (frameIndex == 0) {
    mvidWriter.movieSize = imageSize;
    _movieDimensions = imageSize;
  } else if (CGSizeEqualToSize(imageSize, _movieDimensions) == FALSE) {
    // Size of next frame must exactly match the size of the previous one
    
    fprintf(stderr, "error: frame file \"%s\" size %d x %d does not match initial frame size %d x %d",
            [filenameStr UTF8String],
            (int)imageSize.width, (int)imageSize.height,
            (int)_movieDimensions.width, (int)_movieDimensions.height);
    exit(2);
  }
    
  // Render input image into a CGFrameBuffer at a specific BPP. If the input buffer actually contains
  // 16bpp pixels expanded to 24bpp, then this render logic will resample down to 16bpp.

  if (bppNum == 24 && checkAlphaChannel) {
    bppNum = 32;
  }
  
  CGFrameBuffer *cgBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bppNum width:imageWidth height:imageHeight];
  
  // Query the colorspace identified in the input PNG image
  
  CGColorSpaceRef inputColorspace = CGImageGetColorSpace(imageRef);
  // Should default to RGB is nothing is specified
  assert(inputColorspace);

  //cgBuffer.colorspace = inputColorspace;
  
  // Use sRGB colorspace when reading input pixels into format that will be written to
  // the .mvid file. This is needed when using a custom color space to avoid problems
  // related to storing the exact original input pixels.
  
  CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  cgBuffer.colorspace = colorspace;
  CGColorSpaceRelease(colorspace);
  
  BOOL worked = [cgBuffer renderCGImage:imageRef];
  assert(worked);
  
  CGImageRelease(imageRef);
    
  // Copy the pixels from the cgBuffer into a NSImage
  
  if (FALSE) {
    NSString *dumpFilename = [NSString stringWithFormat:@"WriteDumpFrame%0.4d.png", frameIndex+1];
    
    NSData *pngData = [cgBuffer formatAsPNG];
    
    [pngData writeToFile:dumpFilename atomically:NO];
    
    NSLog(@"wrote %@", dumpFilename);
  }
  
  // The CGFrameBuffer now contains the rendered pixels in the expected output format. Write to MVID frame.

  if (isKeyframe) {
    // Emit Keyframe
    
    char *buffer = cgBuffer.pixels;
    int numBytesInBuffer = cgBuffer.numBytes;
    
    worked = [mvidWriter writeKeyframe:buffer bufferSize:numBytesInBuffer];
    
    if (worked == FALSE) {
      fprintf(stderr, "can't write keyframe data to mvid file \"%s\"\n", [filenameStr UTF8String]);
      exit(1);
    }
  } else {
    // Calculate delta pixels by comparing the previous frame to the current frame.
    // Once we know specific delta pixels, then only those pixels that actually changed
    // can be stored in a delta frame.
    
    assert(prevFrameBuffer);
    
    NSData *encodedDeltaData;
    
    assert(prevFrameBuffer.width == cgBuffer.width);
    assert(prevFrameBuffer.height == cgBuffer.height);
    assert(prevFrameBuffer.bitsPerPixel == cgBuffer.bitsPerPixel);
    
    void *prevPixels = (void*)prevFrameBuffer.pixels;
    void *currentPixels = (void*)cgBuffer.pixels;
    int numWords;
    int width = cgBuffer.width;
    int height = cgBuffer.height;
    
    if (prevFrameBuffer.bitsPerPixel == 16) {
      numWords = cgBuffer.numBytes / sizeof(uint16_t);
      encodedDeltaData = maxvid_encode_generic_delta_pixels16(prevPixels,
                                                              currentPixels,
                                                              numWords,
                                                              width,
                                                              height);
      
    } else {
      numWords = cgBuffer.numBytes / sizeof(uint32_t);
      encodedDeltaData = maxvid_encode_generic_delta_pixels32(prevPixels,
                                                              currentPixels,
                                                              numWords,
                                                              width,
                                                              height);
    }
    
    if (encodedDeltaData == nil) {
      // The two frames are pixel identical, this is a no-op delta frame
      
      [mvidWriter writeNopFrame];
      worked = TRUE;
    } else {
      // Convert generic maxvid codes to c4 codes and emit as a data buffer
      
      void *pixelsPtr = (void*)cgBuffer.pixels;
      int inputBufferNumBytes = cgBuffer.numBytes;
      NSUInteger frameBufferNumPixels = width * height;
      
      worked = maxvid_write_delta_pixels(mvidWriter,
                                         encodedDeltaData,
                                         pixelsPtr,
                                         inputBufferNumBytes,
                                         frameBufferNumPixels);
    }
    
    if (worked == FALSE) {
      fprintf(stderr, "can't write deltaframe data to mvid file \"%s\"\n", [filenameStr UTF8String]);
      exit(1);
    }
  }

  // Wrote either keyframe, nop delta, or delta frame. In the case where we need to scan the pixels
  // to determine if any alpha channel pixels are used we might change the write bpp from 24 to 32 bpp.
  
  if (checkAlphaChannel) {
    uint32_t *currentPixels = (uint32_t*)cgBuffer.pixels;
    int width = cgBuffer.width;
    int height = cgBuffer.height;
    
    BOOL allOpaque = TRUE;
    
    for (int i=0; i < (width * height); i++) {
      uint32_t currentPixel = currentPixels[i];
      // ABGR
      uint8_t alpha = (currentPixel >> 24) & 0xFF;
      if (alpha != 0xFF) {
        allOpaque = FALSE;
        break;
      }
    }
    
    if (allOpaque == FALSE) {
      mvidWriter.bpp = 32;
    }
  }
  
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

// Extract all the frames of movie data from an archive file into
// files indicated by a path prefix.

void extractFramesFromMvidMain(char *mvidFilename, char *extractFramesPrefix) {
	BOOL worked;
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];

	NSString *mvidPath = [NSString stringWithUTF8String:mvidFilename];
  
  worked = [frameDecoder openForReading:mvidPath];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open mvid filename \"%s\"", mvidFilename);
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
    
    CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    cgFrameBuffer.colorspace = colorspace;
    CGColorSpaceRelease(colorspace);
    
    NSData *pngData = [cgFrameBuffer formatAsPNG];
    assert(pngData);
    
    NSString *pngFilename = [NSString stringWithFormat:@"%s%0.4d%s", extractFramesPrefix, frameIndex+1, ".png"];
    
    [pngData writeToFile:pngFilename atomically:NO];
    
    NSString *dupString = @"";
    if (frame.isDuplicate) {
      dupString = @" (duplicate)";
    }
    
    NSLog(@"wrote %@%@", pngFilename, dupString);
    
    [pool drain];
  }

  [frameDecoder close];
  
	return;
}

// Calculate the standard deviation and the mean

void calc_std_dev(int *sizes, int numFrames, float *std_dev, float *mean, int *maxPtr) {
	int i;

	int sum = 0;
	int max = 0;

	for (i = 0; i < numFrames; i++) {
		sum += sizes[i];

		if (sizes[i] > max)
			max = sizes[i];
	}

	*mean = ((float)sum) / numFrames;

	float sum_of_squares = 0.0;

	for (i = 0; i < numFrames; i++) {
		float diff = (sizes[i] - *mean);
		sum_of_squares += (diff * diff);
	}

	float numerator = sqrt(sum_of_squares);
	float denominator = sqrt(numFrames - 1);

	*std_dev = numerator / denominator;
	*maxPtr = max;
}

// Return TRUE if file exists, FALSE otherwise

BOOL fileExists(NSString *filePath) {
  if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
    return TRUE;
	} else {
    return FALSE;
  }
}

// Entry point for logic that will extract video frames from a Quicktime .mov file
// and then write the frames as a .mvid file.

void encodeMvidFromMovMain(char *movFilenameCstr,
                           char *mvidFilenameCstr)
{
  NSString *movFilename = [NSString stringWithUTF8String:movFilenameCstr];
  
  BOOL isMov = [movFilename hasSuffix:@".mov"];
  
  if (isMov == FALSE) {
    fprintf(stderr, USAGE);
    exit(1);
  }
  
  NSString *mvidFilename = [NSString stringWithUTF8String:mvidFilenameCstr];
  
  BOOL isMvid = [mvidFilename hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, USAGE);
    exit(1);
  }
  
  if (fileExists(movFilename) == FALSE) {
    fprintf(stderr, "input quicktime movie file not found : %s", movFilenameCstr);
    exit(2);
  }

  BOOL worked;
  NSError *errState;  
  QTTime duration;
  QTTime startTime;
  QTTime currentTime;
  QTTime frameTime;
  CGImageRef frameImage;
  //int frameNum = 1;
  NSTimeInterval timeInterval;
  int mvidBPP = 24; // assume 24BPP at first, up to 32bpp if non-opaque pixels are found
  
  QTMovie *movie = [QTMovie movieWithFile:movFilename error:&errState];
  assert(movie);

  NSDictionary *movieAttributes = [movie movieAttributes];
  fprintf(stdout, "movieAttributes : %s", [[movieAttributes description] UTF8String]);
  
  // Passing QTMovieFrameImagePixelFormat for type 
  
  NSDictionary *attributes = [[[NSDictionary alloc] initWithObjectsAndKeys:
                               QTMovieFrameImageTypeCGImageRef, QTMovieFrameImageType,
                               [NSNumber numberWithBool:YES], QTMovieFrameImageHighQuality,
                               nil]
                              autorelease];
  
  BOOL done = FALSE;
  BOOL extractedFirstFrame = FALSE;
  
  duration = [[movie attributeForKey:QTMovieDurationAttribute] QTTimeValue];
  startTime = QTMakeTime(0, duration.timeScale);
  currentTime = startTime;
  
  // Iterate over the "interesting" times in the movie and calculate framerate.
  // Typically, the first couple of frames appear at the exact frame bound,
  // but then the times can be in flux depending on the movie. If the movie starts
  // with a very long frame display time but then a small frame rate appears
  // later on, we need to adjust the whole movie framerate to match the shortest
  // interval.

  TimeValue lastInteresting = 0;
  TimeValue nextInteresting;
	TimeValue nextInterestingDuration;
  short nextTimeFlags = nextTimeStep;
  QTTimeRange startEndRange = QTMakeTimeRange(startTime, duration);
  
  NSArray *tracks = [movie tracksOfMediaType:QTMediaTypeVideo];
  if ([tracks count] == 0) {
    fprintf(stderr, "Could not find any video tracks in movie file %s", movFilenameCstr);
    exit(2);
  }
  
  // FIXME: only descend into track looking for Animation codec if there is 1 video track
  
  QTTrack *firstTrack = [tracks objectAtIndex:0];
  QTMedia *firstTrackMedia = [firstTrack media];
  Media firstTrackQuicktimeMedia = [firstTrackMedia quickTimeMedia];
  assert(firstTrackQuicktimeMedia);

  NSDictionary *firstTrackAttributes = [firstTrack trackAttributes];
  fprintf(stdout, "firstTrackAttributes : %s\n", [[firstTrackAttributes description] UTF8String]);

  NSDictionary *firstTrackMediaAttributes = [firstTrackMedia mediaAttributes];
  fprintf(stdout, "firstTrackMediaAttributes : %s\n", [[firstTrackMediaAttributes description] UTF8String]);
  
  NSMutableArray *durations = [NSMutableArray array];
  
  if (TRUE) {
    // Drop into QT to determine what kind of samples are inside of the Media object
    
    ImageDescriptionHandle desc = (ImageDescriptionHandle)NewHandleClear(sizeof(ImageDescription));
        
    GetMediaSampleDescription(firstTrackQuicktimeMedia, 1, (SampleDescriptionHandle)desc);
    
    CodecType cType =(*desc)->cType;
    
    BOOL isAnimationCodec = FALSE;
    
    // Animation
    // 1919706400 ?= 'rle '
    char qtAniFourCC[] = { 'r', 'l', 'e', ' ' };
    uint32_t fourCC = qtAniFourCC[0] << 24 | qtAniFourCC[1] << 16 | qtAniFourCC[2] << 8 | qtAniFourCC[3];
    if (cType == fourCC) {
      isAnimationCodec = TRUE;
    }
    
    int depth = (*desc)->depth;
    
    // 16
    
    assert(depth == 16 || depth == 24 || depth == 32);
    
    // For 16BPP Animation, we need to get at the data directly?
    
    // http://www.mailinglistarchive.com/quicktime-api@lists.apple.com/msg06593.html
    
    DisposeHandle((Handle)desc);
  }
  
  fprintf(stdout, "extracting framerate from QT Movie\n");
    
  while (!done) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
    GetMediaNextInterestingTime(firstTrackQuicktimeMedia,
                                nextTimeFlags,
                                currentTime.timeValue,
                                1,
                                &nextInteresting,
                                &nextInterestingDuration);
    
    if (nextInteresting == -1) {      
      done = TRUE;
    } else {
      TimeValue interestingDuration = nextInteresting - lastInteresting;
      
      [durations addObject:[NSNumber numberWithInt:(int)interestingDuration]];
      
      currentTime = QTMakeTime(nextInteresting, duration.timeScale);
      
      worked = QTGetTimeInterval(currentTime, &timeInterval);
      assert(worked);
      
      fprintf(stdout, "found delta at time %f with duration %d\n", (float)timeInterval, (int)interestingDuration);
    }
    
    [pool drain];
  }
  if ([durations count] == 0) {
    // If one single frame is displayed for the entire length of the movie, then the
    // duration is the actual frame rate. The trouble with that approach is that
    // an animation is assumed to have at least 2 frames. Work around the assumption
    // by creating a framerate that is exactly half of the duration in this case.
    
    int halfDuration = (int)duration.timeValue / (int)2;
    NSNumber *halfDurationNum = [NSNumber numberWithInt:halfDuration];
    
    [durations addObject:halfDurationNum];
    [durations addObject:halfDurationNum];
  }
  
  assert([durations count] > 0);
  
  // First check for the easy case, where all the durations are the exact same number.
  
  int firstDuration = [[durations objectAtIndex:0] intValue];
  BOOL allSame = TRUE;
  for (NSNumber *durationNumber in durations) {
    int currentDuration = [durationNumber intValue];
    if (currentDuration != firstDuration) {
      allSame = FALSE;
    }
  }
  
  if (allSame) {
    frameTime = QTMakeTime(firstDuration, duration.timeScale);
  } else {
    assert(0);
  }
  
  // The frame interval is now known, so recalculate the total number of frames
  // by counting how many frames of the indicated interval fit into the movie duration.
    
  int totalNumFrames = 1;
  done = FALSE;
  currentTime = startTime;
  
  while (!done) {
    currentTime = QTTimeIncrement(currentTime, frameTime);
    
    // Done once at the end of the movie
    
    if (!QTTimeInTimeRange(currentTime, startEndRange)) {
      done = TRUE;
    } else {
      totalNumFrames++;
    }
  }
  
  // Now that we know the framerate, iterate through visual
  // display at the indicated framerate.
  // Calculate framerate in terms of clock time
  
  worked = QTGetTimeInterval(frameTime, &timeInterval);
  assert(worked);

  fprintf(stdout, "extracting %d frame(s) from QT Movie\n", totalNumFrames);
  fprintf(stdout, "frame duration is %f seconds\n", (float)timeInterval);
  
  AVMvidFileWriter *mvidWriter = makeMVidWriter(mvidFilename, mvidBPP, timeInterval, totalNumFrames);
  
  done = FALSE;
  currentTime = startTime;
  int frameIndex = 0;
  
  while (!done) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    worked = QTGetTimeInterval(currentTime, &timeInterval);
    assert(worked);

    // Note that the CGImageRef here has been placed in the autorelease pool automatically
    frameImage = [movie frameImageAtTime:currentTime withAttributes:attributes error:&errState];
    worked = (frameImage != nil);
        
    if (worked == FALSE) {
      done = TRUE;
      
      fprintf(stdout, "failed to extract frame %d at time %f\n", frameIndex+1, (float)timeInterval);
    } else {
      extractedFirstFrame = TRUE;
      
      fprintf(stdout, "extracted frame %d at time %f\n", frameIndex+1, (float)timeInterval);
      
      int width = CGImageGetWidth(frameImage);
      int height = CGImageGetHeight(frameImage);
      // Note that this value will always be 32bpp for a rendered movie frame, we need to
      // actually scan the pixels composited here to figure out if the alpha channel is used.
      int bpp = CGImageGetBitsPerPixel(frameImage);
      
      fprintf(stdout, "width x height : %d x %d at bpp %d\n", width, height, bpp);
      
      // FIXME: need to scan all pixels to see if all the ALPHA is set to 0xFF since
      // this CGImage does not know if it is 24BPP or 32BPP

      // Write frame data to MVID
      
      BOOL isKeyframe = FALSE;
      if (frameIndex == 0) {
        isKeyframe = TRUE;
      }
      
      BOOL checkAlphaChannel = FALSE;
      if (mvidBPP != 16) {
        checkAlphaChannel = TRUE;
      }
      process_frame_file(mvidWriter, NULL, frameImage, frameIndex, mvidBPP, checkAlphaChannel, isKeyframe);
      frameIndex++;
    }
    
    currentTime = QTTimeIncrement(currentTime, frameTime);
    
    // Done once at the end of the movie
    
    if (!QTTimeInTimeRange(currentTime, startEndRange)) {
      done = TRUE;
    }
    
    //CGImageRelease(frameImage);
        
    [pool drain];
  }
  
  if (extractedFirstFrame == FALSE) {
    fprintf(stderr, "Could not extract initial frame from movie file %s", movFilenameCstr);
    exit(2);
  }
  
  assert(frameIndex == totalNumFrames);
  
  // Note that the process_frame_file() method could have modified the bpp field by changing it
  // from 24bpp to 32bpp in the case where alpha channel usage was found in the image data.
  // This call will rewrite the header with that updated info along with other data.
  
  [mvidWriter rewriteHeader];
  
  [mvidWriter close];
  
  fprintf(stdout, "done writing %d frames to %s\n", totalNumFrames, mvidFilenameCstr);
  fflush(stdout);
  
  // cleanup
  
  if (prevFrameBuffer) {
    [prevFrameBuffer release];
  }
  
  return;
}

// Entry point for logic that encodes a .mvid from a series of frames.

void encodeMvidFromFramesMain(char *mvidFilenameCstr,
                              char *firstFilenameCstr,
                              char *framerateCstr,
                              char *bppCstr,
                              char *keyframeCstr)
{
  NSString *mvidFilename = [NSString stringWithUTF8String:mvidFilenameCstr];
  
  BOOL isMvid = [mvidFilename hasSuffix:@".mvid"];
  
  if (isMvid == FALSE) {
    fprintf(stderr, USAGE);
    exit(1);
  }
  
  // Given the first frame image filename, build and array of filenames
  // by checking to see if files exist up until we find one that does not.
  // This makes it possible to pass the 25th frame ofa 50 frame animation
  // and generate an animation 25 frames in duration.
  
  NSString *firstFilename = [NSString stringWithUTF8String:firstFilenameCstr];
  
  if (fileExists(firstFilename) == FALSE) {
    fprintf(stderr, "error: first filename \"%s\" does not exist", firstFilenameCstr);
    exit(1);
  }
  
  NSString *firstFilenameExt = [firstFilename pathExtension];
  
  if ([firstFilenameExt isEqualToString:@"png"] == FALSE) {
    fprintf(stderr, "error: first filename \"%s\" must have .png extension", firstFilenameCstr);
    exit(1);
  }
  
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
    fprintf(stderr, "error: could not find frame number in first filename \"%s\"", firstFilenameCstr);
    exit(1);
  }
  
  // Extract the numeric portion of the first frame filename
  
  NSString *namePortion = [firstFilenameTailNoExtension substringToIndex:numericStartIndex];
  NSString *numberPortion = [firstFilenameTailNoExtension substringFromIndex:numericStartIndex];
  
  if ([namePortion length] < 1 || [numberPortion length] == 0) {
    fprintf(stderr, "error: could not find frame number in first filename \"%s\"", firstFilenameCstr);
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
    [frameNumberWithLeadingZeros appendString:@".png"];
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
    fprintf(stderr, "error: at least 2 input frames are required");
    exit(1);    
  }
  
  if ((startingFrameNumber == endingFrameNumber) || (endingFrameNumber == CRAZY_MAX_FRAMES-1)) {
    fprintf(stderr, "error: could not find last frame number");
    exit(1);
  }
  
  // FRAMERATE is a floating point number that indicates the delay between frames.
  // This framerate value is a constant that does not change over the course of the
  // movie, though it is possible that a certain frame could repeat a number of times.
  
  NSString *framerateStr = [NSString stringWithUTF8String:framerateCstr];
  
  if ([framerateStr length] == 0) {
    fprintf(stderr, "error: FRAMERATE is invalid \"%s\"", firstFilenameCstr);
    exit(1);
  }
  
  float framerateNum = [framerateStr floatValue];
  if (framerateNum <= 0.0f || framerateNum >= 90.0f) {
    fprintf(stderr, "error: FRAMERATE is invalid \"%f\"", framerateNum);
    exit(1);
  }
  
  // BITSPERPIXEL : 16, 24, or 32 BPP.
  
  NSString *bppStr = [NSString stringWithUTF8String:bppCstr];
  int bppNum = [bppStr intValue];
  if (bppNum == 16 || bppNum == 24 || bppNum == 32) {
    // Value is valid
  } else {
    fprintf(stderr, "error: BITSPERPIXEL is invalid \"%s\"", bppCstr);
    exit(1);
  }
  
  // KEYFRAME : integer that indicates a keyframe should be emitted every N frames
  
  NSString *keyframeStr = [NSString stringWithUTF8String:keyframeCstr];
  
  if ([keyframeStr length] == 0) {
    fprintf(stderr, "error: KEYFRAME is invalid \"%s\"", keyframeCstr);
    exit(1);
  }
  
  int keyframeNum = [keyframeStr intValue];
  if (keyframeNum == 0) {
    // All frames as stored as keyframes. This takes up more space but the frames can
    // be blitted into graphics memory directly from mapped memory at runtime.
    keyframeNum = 0;
  } else if (keyframeNum < 0) {
    // Just revert to the default
    keyframeNum = 10000;
  }
  
  AVMvidFileWriter *mvidWriter = makeMVidWriter(mvidFilename, bppNum, framerateNum, [inFramePaths count]);
  
  // We now know the start and end integer values of the frame filename range.
  
  int frameIndex = 0;
  
  for (NSString *framePath in inFramePaths) {
    fprintf(stdout, "saved %s as frame %d\n", [framePath UTF8String], frameIndex+1);
    fflush(stdout);
    
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
    
    process_frame_file(mvidWriter, framePath, NULL, frameIndex, bppNum, FALSE, isKeyframe);
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

// main() Entry Point

int main (int argc, const char * argv[]) {
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
  
	if ((argc == 3 || argc == 4) && (strcmp(argv[1], "-extract") == 0)) {
		// Extract movie frames from an existing archive

    char *mvidFilename = (char *)argv[2];
    char *framesFilePrefix;
    
    if (argc == 3) {
      framesFilePrefix = "Frame";
    } else {
      framesFilePrefix = (char*)argv[3];
    }
    
		extractFramesFromMvidMain(mvidFilename, framesFilePrefix);
  } else if (argc == 3) {
    // FILE.mov : name of input Quicktime file
    // FILE.mvid : name of output .mvid file
    //
    // When converting, the original BPP and framerate are copied
    // but only the initial keyframe remains a keyframe in the .mvid
    // file for reasons of space savings.
    
    char *movFilenameCstr = (char*)argv[1];
    char *mvidFilenameCstr = (char*)argv[2];
    
    encodeMvidFromMovMain(movFilenameCstr, mvidFilenameCstr);
    
    if (TRUE) {
      // Extract frames we just encoded into the .mvid file for debug purposes
      
      extractFramesFromMvidMain(mvidFilenameCstr, "ExtractedFrame");
    }
	} else if (argc == 5 || argc == 6) {
    // FILE.mvid : name of output file that will contain all the video frames
    // FIRSTFRAME.png : name of first frame file of input PNG files. All
    //   video frames must exist in the same directory
    // FRAMERATE is a floating point framerate value. Common values
    // include 1.0 FPS, 15 FPS, 29.97 FPS, and 30 FPS.
    // BITSPERPIXEL : 16, 24, or 32 BPP
    // KEYFRAME is the number of frames until the next keyframe in the
    //   resulting movie file. The default of 10,000 ensures that
    //   the resulting movie would only contain the initial keyframe.

    char *mvidFilenameCstr = (char*)argv[1];
    char *firstFilenameCstr = (char*)argv[2];
    char *framerateCstr = (char*)argv[3];
    char *bppCstr = (char*)argv[4];
    char *keyframeCstr = "10000";
    if (argc == 6) {
      keyframeCstr = (char*)argv[5];
    }
    
    encodeMvidFromFramesMain(mvidFilenameCstr,
                            firstFilenameCstr,
                            framerateCstr,
                            bppCstr,
                             keyframeCstr);
    
    if (TRUE) {
      // Extract frames we just encoded into the .mvid file for debug purposes
      
      extractFramesFromMvidMain(mvidFilenameCstr, "ExtractedFrame");
    }
	} else {
    fprintf(stderr, USAGE);
    exit(1);
  }
  
  [pool drain];
  return 0;
}

