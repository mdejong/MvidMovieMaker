//
//  qtdecode.m
//
//  Created by Moses DeJong on 11/3/12.
//
//  License terms defined in License.txt.

#import "qtdecode.h"

#import "AVMvidFrameDecoder.h"

#import "CGFrameBuffer.h"

#import "movdata.h"

#import <CoreFoundation/CoreFoundation.h>

#import <QuickTime/QuickTimeErrors.h>

// This implementation attempts to use QTKit's basic decode logic, but this code is broken
//#define QTKIT_FRAME_IMAGE_AT_TIME_IMPL

// This decoder implementation makes use of session APIs to decode whatever codec data is
// found inside the .mov file. This implementation has the advantage that it should work
// with any codec that Quicktime supports.
//#define QTKIT_DECODE_SESSION_IMPL

// This implementation would decode Animation codec directly with known working Animation codec logic.
// Bypassing the session APIs would be needed in the case where the session APIs contain bugs.
#define QTKIT_DECODE_ANIMATION_IMPL

static
QTMovie *movieRef = NULL;

static
QTMedia *mediaRef = NULL;


#if defined(QTKIT_DECODE_SESSION_IMPL)

static
ICMDecompressionSessionRef decompressionSession = NULL;

#endif // QTKIT_DECODE_SESSION_IMPL


#if defined(QTKIT_DECODE_SESSION_IMPL) || defined(QTKIT_DECODE_ANIMATION_IMPL)

static
CGFrameBuffer *renderBuffer = NULL;

#endif // QTKIT_DECODE_SESSION_IMPL || QTKIT_DECODE_ANIMATION_IMPL

static
void frameImageAtTime_setupMovFrameAtTime(QTMovie *movie, QTMedia *trackMedia, int expectedBpp)
{
  movieRef = movie;
  mediaRef = trackMedia;
}

static
CGImageRef frameImageAtTime_getMovFrameAtTime(QTTime atTime)
{
  CGImageRef frameImage;
  NSError *errState;
  
  assert(movieRef);
  
  // Passing QTMovieFrameImagePixelFormat for type
  
  NSDictionary *attributes = [[[NSDictionary alloc] initWithObjectsAndKeys:
                               QTMovieFrameImageTypeCGImageRef, QTMovieFrameImageType,
                               [NSNumber numberWithBool:YES], QTMovieFrameImageHighQuality,
                               nil]
                              autorelease];
  
  frameImage = [movieRef frameImageAtTime:atTime withAttributes:attributes error:&errState];
  
  // Add extra retain, since this one is in the autorelease pool already
  
  frameImage = CGImageRetain(frameImage);
  
  return frameImage;
}

static
void frameImageAtTime_cleanupMovFrameAtTime()
{
  movieRef = NULL;
  mediaRef = NULL;
}

// ---------------------------------

// Use decoder session APIs

// Other options: http://docs.thefoundry.co.uk/nuke/63/ndkreference/examples/movReader.cpp

static
void addIntToDictionary(CFMutableDictionaryRef dictionary,
                        CFStringRef key,
                        SInt32 number)
{
  CFNumberRef numObj = CFNumberCreate(NULL, kCFNumberSInt32Type, &number);
  assert(numObj);
  CFDictionaryAddValue(dictionary, key, numObj);
  CFRelease(numObj);
}

// Create a copy of the pixel data and use it as a CGImageRef source

static
CGImageRef createCGImageRefFromPixelBuffer(CVPixelBufferRef pixelBuffer)
{
  int width = CVPixelBufferGetWidth(pixelBuffer);
  int height = CVPixelBufferGetHeight(pixelBuffer);
  assert(width > 0 && height > 0);
  
  size_t bitsPerComponent;
  size_t numComponents;
  size_t bitsPerPixel;
  size_t bytesPerRow;
  
  OSType pixelType = CVPixelBufferGetPixelFormatType(pixelBuffer);
  
  CGBitmapInfo bitmapInfo;
  
  if (pixelType == kCVPixelFormatType_32ARGB) {
    bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedFirst;
  } else if (pixelType == kCVPixelFormatType_32BGRA) {
    bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
  } else {
    assert(0);
  }
  
  int bpp = 32;
  
  if (bpp == 16) {
    // Unused for now
    bitsPerComponent = 5;
    //    numComponents = 3;
    bitsPerPixel = 16;
    bytesPerRow = width * (bitsPerPixel / 8);
  } else if (bpp == 24 || bpp == 32) {
    bitsPerComponent = 8;
    numComponents = 4;
    bitsPerPixel = bitsPerComponent * numComponents;
    //bytesPerRow = width * (bitsPerPixel / 8);
    bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
  } else {
    assert(0);
  }
  
  // Copy pixel buffer data into a CFData
  
  OSErr osError;
  osError = CVPixelBufferLockBaseAddress(pixelBuffer, 0);
  assert( osError == 0 );
  void *baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer);
  
  size_t numBytes = CVPixelBufferGetDataSize(pixelBuffer);
  
  CFDataRef copyOfBufferData = CFDataCreate(kCFAllocatorDefault, baseAddr, numBytes);
  
  // Unlock baseAddr, data was just copied into the copyOfBufferData object
  
  CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
  CGDataProviderRef dataProviderRef = CGDataProviderCreateWithCFData(copyOfBufferData);
  
  CFRelease(copyOfBufferData);
  
  BOOL shouldInterpolate = FALSE; // images at exact size already
  
  CGColorRenderingIntent renderIntent = kCGRenderingIntentDefault;
  
  // FIXME: We have no idea what colorspace the incoming pixels are in ?
  
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
  CGImageRef inImageRef = CGImageCreate(width, height, bitsPerComponent, bitsPerPixel, bytesPerRow,
                                        colorSpace, bitmapInfo, dataProviderRef, NULL,
                                        shouldInterpolate, renderIntent);
  
  CGDataProviderRelease(dataProviderRef);
  
  CGColorSpaceRelease(colorSpace);
  
  return inImageRef;
}

#if defined(QTKIT_DECODE_SESSION_IMPL)

// This tracking callback is invoked as frames are decoded

static void TrackingDecodeCallback(
                                   void *decompressionTrackingRefCon,
                                   OSStatus result,
                                   ICMDecompressionTrackingFlags decompressionTrackingFlags,
                                   CVPixelBufferRef pixelBuffer,
                                   TimeValue64 displayTime,
                                   TimeValue64 displayDuration,
                                   ICMValidTimeFlags validTimeFlags,
                                   void *reserved,
                                   void *sourceFrameRefCon )
{
  assert(result == noErr);
  
  // Create an image provider using the data in the CVPixelBufferRef and then
  // use that data to render into a pixel buffer with a know good format.
  // This method operates assuming 32BPP.
  
  // FIXME: should we print "CVImageBufferGammaLevel" as 1.8 or 2.2 ? Might help user when debugging?

  assert(renderBuffer);
  
  CGImageRef imageRef = nil;
  
  imageRef = createCGImageRefFromPixelBuffer(pixelBuffer);
  
  BOOL worked;
  worked = [renderBuffer renderCGImage:imageRef];
  assert(worked);

  CGImageRelease(imageRef);
  
  return;
}

// Init the movie and decoder session

static
void decodeSession_setupMovFrameAtTime(QTMovie *movie, QTMedia *trackMedia, int expectedBpp)
{
  OSStatus err = noErr;
  ICMDecompressionSessionOptionsRef sessionOptions = NULL;
  CodecQ codecAccuracy = codecMaxQuality;
  ICMFieldMode fieldMode = kICMFieldMode_DeinterlaceFields;
  int width = -1;
  int height = -1;
  
  ICMDecompressionTrackingCallbackRecord trackingCallbackRecord;

  assert(movie);
  movieRef = movie;
  assert(trackMedia);
  mediaRef = trackMedia;
  
  ImageDescriptionHandle imageDesc = (ImageDescriptionHandle)NewHandle(0);
  
  {
    // Run phony call to GetMediaSample2 to query sample description from media track
    
    TimeValue64 decodeTime;
    
    MediaSampleFlags sampleFlags = 0;
    
    SampleNumToMediaDecodeTime(trackMedia.quickTimeMedia, 1, &decodeTime, NULL);
    
    err = GetMediaSample2(trackMedia.quickTimeMedia,
                           NULL, //data out
                           0,   //max data size
                           NULL, //bytes
                           decodeTime, //decode time
                           NULL, //returned decode time
                           NULL, //duration per sample
                           NULL, //offset
                           (SampleDescriptionHandle) imageDesc,
                           NULL, //sample description index
                           1, //max number of samples
                           NULL, //number of samples
                           &sampleFlags //flags
                           );
    assert(err == noErr);
    
    width = (*imageDesc)->width;
    height = (*imageDesc)->height;
    
    // FIXME: Capture the image data colorspace if there is one and save it.
  }
  
  // Setup render buffer, this object will be the destination where the CoreVideo buffer
  // will be rendered out as 32BPP BGRA data.
  
  if (renderBuffer == NULL)
  {
    renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:width height:height];
    [renderBuffer retain];
  }
  
  // we also need to create a ICMDecompressionSessionOptionsRef to fill in codec quality
  err = ICMDecompressionSessionOptionsCreate(NULL, &sessionOptions);
  assert(err == noErr);
  assert(sessionOptions);
    
  // Technical Q&A QA1460
  
  err = ICMDecompressionSessionOptionsSetProperty(sessionOptions,
                                                  kQTPropertyClass_ICMDecompressionSessionOptions,
                                                  kICMDecompressionSessionOptionsPropertyID_Accuracy,
                                                  sizeof(CodecQ),
                                                  &codecAccuracy);
  assert(err == noErr);
  
  err = ICMDecompressionSessionOptionsSetProperty(sessionOptions,
                                                  kQTPropertyClass_ICMDecompressionSessionOptions,
                                                  kICMDecompressionSessionOptionsPropertyID_FieldMode,
                                                  sizeof(ICMFieldMode),
                                                  &fieldMode);
  assert(err == noErr);

  // Decompression depth does not seem to exist as a concept ?
  
  /*
  
  // (**desc).depth = bpp;
  UInt32 depth;
  if (expectedBpp == 32) {
    depth = k32ARGBPixelFormat;
  } else if (expectedBpp == 24) {
    depth = k24RGBPixelFormat;
  } else if (expectedBpp == 16) {
    depth = k16BE555PixelFormat;
  } else {
    assert(0);
  }
  err = ICMDecompressionSessionOptionsSetProperty(sessionOptions,
                                                kQTPropertyClass_ICMDecompressionSessionOptions,
                                                kICMDecompressionSessionOptionsPropertyID_Depth,
                                                sizeof(depth),
                                                &depth);
  assert(err == 0);
   
  */

  // CVPixelBuffer attributes

  CFMutableDictionaryRef pixelAttributes;
  pixelAttributes = CFDictionaryCreateMutable( kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks );
  assert(pixelAttributes);
  
  addIntToDictionary(pixelAttributes, kCVPixelBufferWidthKey, width);
  addIntToDictionary(pixelAttributes, kCVPixelBufferHeightKey, height);
  
	CFDictionaryAddValue( pixelAttributes, kCVPixelBufferCGBitmapContextCompatibilityKey, kCFBooleanTrue );
	CFDictionaryAddValue( pixelAttributes, kCVPixelBufferCGImageCompatibilityKey, kCFBooleanTrue );

  // Setup tracking callback (invoked when frame is decoded)
  
  trackingCallbackRecord.decompressionTrackingCallback = TrackingDecodeCallback;
  trackingCallbackRecord.decompressionTrackingRefCon = NULL;

  
  // Create decompression session from passed in settings
  
  err = ICMDecompressionSessionCreate(kCFAllocatorDefault,
                                      imageDesc,
                                      sessionOptions,
                                      pixelAttributes,
                                      &trackingCallbackRecord,
                                      &decompressionSession);
  assert(err == noErr);
  
  ICMDecompressionSessionOptionsRelease(sessionOptions);
  
  DisposeHandle((Handle)imageDesc);
  
  CFRelease(pixelAttributes);

  return;
}

static
CGImageRef decodeSession_getMovFrameAtTime(QTTime atTime)
{
  CGImageRef frameImage = NULL;

  OSStatus err = noErr;
  
  assert(mediaRef != NULL);
  
  // Get the encoded buffer info before actually extracing the encoded sample data
  
  ByteCount sampleDataSize = 0;
  TimeValue64 decodeTime = atTime.timeValue;
  TimeValue64 duration;
  MediaSampleFlags sampleFlags;
  void *sampleData = NULL;
  
  err = GetMediaSample2(
                        mediaRef.quickTimeMedia,
                        NULL,
                        0,
                        &sampleDataSize,
                        decodeTime,
                        NULL, NULL, NULL, NULL, NULL, 1, NULL,
                        &sampleFlags);
  assert(err == noErr);
  
  sampleData = malloc(sampleDataSize);
  assert(sampleData);
  memset(sampleData, 0, sampleDataSize);
  
  // Now invoke GetMediaSample2() again to really read the data
  
  err = GetMediaSample2(
                        mediaRef.quickTimeMedia,
                        sampleData, //data out
                        sampleDataSize, //max data size
                        NULL, // bytes
                        decodeTime, //decodeTime
                        NULL, //sampledecodetime
                        &duration, //sample duration
                        NULL,
                        NULL,
                        NULL, //sampledescription index
                        1, //max number of samples
                        NULL, //number of samples
                        &sampleFlags //flags
                        );
  assert(err == noErr);
  
  // Push media sample data into decoder API
  
  ICMFrameTimeRecord timeRecord;
  memset(&timeRecord, 0, sizeof(ICMFrameTimeRecord));
  
  TimeValue timeValue = (TimeValue)atTime.timeValue;
  long scale = atTime.timeScale;
  
  timeRecord.recordSize = sizeof(ICMFrameTimeRecord);
  //timeRecord.value = timeValue;
  *((TimeValue64*) &timeRecord.value) = timeValue;
  timeRecord.scale = scale;
  timeRecord.rate  = fixed1;
  timeRecord.frameNumber = 0; // FIXME: ???
  timeRecord.flags = icmFrameTimeIsNonScheduledDisplayTime;
  
  //timeRecord.flags = icmFrameTimeDecodeImmediately;
  
  err = ICMDecompressionSessionDecodeFrame(decompressionSession,
                                           (UInt8 *)sampleData, // Pass in encoded data frame
                                           sampleDataSize,
                                           NULL, // frame options
                                           &timeRecord, // frameTime
                                           NULL);
  assert(err == noErr);
  
  err = ICMDecompressionSessionSetNonScheduledDisplayTime(decompressionSession,
                                                          timeValue,
                                                          timeRecord.scale,
                                                          0);
  assert(err == noErr);
  
  free(sampleData);
 
  // The statis renderBuffer object would have been updated by the frame callback, so
  // it is now safe to use this rendered data as a know format.
  
  if (FALSE) {
    NSString *dumpFilename = [NSString stringWithFormat:@"RenderDumpFrame.png"];
    
    NSData *pngData = [renderBuffer formatAsPNG];
    
    [pngData writeToFile:dumpFilename atomically:NO];
    
    NSLog(@"wrote %@", dumpFilename);
  }
  
  // Now create CGImageRef from the rendered buffer sent to the other function.
  
  frameImage = [renderBuffer createCGImageRef];
  
  assert(frameImage);
  
  return frameImage;
}

static
void decodeSession_cleanupMovFrameAtTime()
{
  movieRef = NULL;
  mediaRef = NULL;
  
  // cleanup decompressionSession
  
  assert(decompressionSession);
  ICMDecompressionSessionRelease(decompressionSession);
  
  if (renderBuffer) {
    [renderBuffer release];
    renderBuffer = NULL;
  }
}

#endif // QTKIT_DECODE_SESSION_IMPL

// -----------------------------------------

static
void decodeAnimation_setupMovFrameAtTime(QTMovie *movie, QTMedia *trackMedia, int expectedBpp)
{
  
  assert(movie);
  assert(trackMedia);
  movieRef = movie;
  mediaRef = trackMedia;

  int width = -1;
  int height = -1;
  OSStatus err = noErr;
  
  // Note that while expectedBpp
  
  assert(expectedBpp == 16 || expectedBpp == 24 || expectedBpp == 32);
  
  // Note that we ignore expectedBpp here since the actualy BPP detected inside the MOV
  // file is used no matter what. It is possible that 32BPP pixels contain 24BPP data,
  // but that logic is handled when writing frames to detect when a 32BPP Animation codec
  // movie does not actually make use of an alpha channel. Explicitly set the BPP
  // of the render buffer to track the detected MOV BPP.
  
  // Drop into QT to determine what kind of samples are inside of the Media object
  
  ImageDescriptionHandle desc = (ImageDescriptionHandle)NewHandleClear(sizeof(ImageDescription));
  
  Media firstTrackQuicktimeMedia = [trackMedia quickTimeMedia];
  
  GetMediaSampleDescription(firstTrackQuicktimeMedia, 1, (SampleDescriptionHandle)desc);
  
  width = (*desc)->width;
  height = (*desc)->height;
  
  int depth = (*desc)->depth;
  
  // When Animation codec declares the BPP as 32BPP, it is possible that an alpha channel will
  // be used. But it is also possible that the data could have been exported as "Millions+"
  // but it might not actually use the alpha channel. In this case, attempt to detect the
  // case of 24BPP in 32BPP pixels.
  
  if (depth == 16 || depth == 24 || depth == 32) {
    // No-op
  } else {
    assert(FALSE);
  }
  
  // Setup render buffer, this object will be the destination where the CoreVideo buffer
  // will be rendered out as 32BPP BGRA data.
  
  if (renderBuffer == NULL)
  {
    renderBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:depth width:width height:height];
    [renderBuffer retain];
  }
  
  // Test the image description to determine if the codec has an associated color profile.
  // If the color profile is SRGB, then we know that this .mov file can be marked as
  // SRGB data so that no color conversion will be done automatically when writing color
  // data into the .mvid file.
  
  CFDataRef movColorspaceICC = NULL;
  
  err = ICMImageDescriptionGetProperty(desc,
                                       kQTPropertyClass_ImageDescription,
                                       kICMImageDescriptionPropertyID_ICCProfile,
                                       sizeof(CFDataRef),
                                       &movColorspaceICC,
                                       NULL);
  
  // err will be kQTPropertyNotSupportedErr if the .mov does not contain an ICC profile.
  
  if (err == kQTPropertyNotSupportedErr) {
    // No ICC profile in the .mov, default mov input to sRGB since that is the only common sense "default".
    // Note that defaulting to "generic RGB" is not an option since that would involve a lossy generic -> sRGB
    // conversion and the generic profile is defined as 1.8 gamma which would cause an unwanted shift.
    
    fprintf(stdout, "treating input pixels as sRGB since .mov does not define an ICC color profile\n");
    
    CGColorSpaceRef colorSpace = NULL;
    colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    assert(colorSpace);
    renderBuffer.colorspace = colorSpace;
    CGColorSpaceRelease(colorSpace);
  } else if (err == noErr) {
    // Could be SRGB color profile, or might be another profile. We want to just grab
    // the profile and assign it to the framebuffer so that the next stage will detect
    // a nop for the case where SRGB is the input pixel format.
    
    CGColorSpaceRef colorspace = NULL;
    err = ICMImageDescriptionGetProperty(desc,
                                         kQTPropertyClass_ImageDescription,
                                         kICMImageDescriptionPropertyID_CGColorSpace,
                                         sizeof(CGColorSpaceRef),
                                         &colorspace,
                                         NULL);
    assert(err == noErr);
    
    assert(renderBuffer);
    renderBuffer.colorspace = colorspace;
    
    if (colorspace) {
      CGColorSpaceRelease(colorspace);
    }
    
  } else {
    assert(FALSE);
  }
  
  if (movColorspaceICC) {
    CFRelease(movColorspaceICC);
  }
  
  DisposeHandle((Handle)desc);

  return;
}

static
CGImageRef decodeAnimation_getMovFrameAtTime(QTTime atTime)
{
  CGImageRef frameImage = NULL;
  
  OSStatus err = noErr;
  
  assert(mediaRef != NULL);
  
  // It is possible that the media timescale does not match the track/movie timescale.
  // We need to map the "clock time" to the media time in this case.

  NSNumber *movieTimeScale = [movieRef attributeForKey:QTMovieTimeScaleAttribute];
  NSNumber *mediaTimeScale = [mediaRef attributeForKey:QTMediaTimeScaleAttribute];

  if ([movieTimeScale isEqualToNumber:mediaTimeScale] == FALSE) {
    //NSTimeInterval timeInterval;
    //BOOL worked = QTGetTimeInterval(atTime, &timeInterval);
    //assert(worked);
   
    QTTime scaledTime = QTMakeTimeScaled(atTime, [mediaTimeScale longValue]);
    atTime = scaledTime;
  }
  
  // Get the encoded buffer info before actually extracing the encoded sample data
  
  ByteCount sampleDataSize = 0;
  TimeValue64 decodeTime = atTime.timeValue;
  TimeValue64 duration;
  MediaSampleFlags sampleFlags;
  void *sampleData = NULL;
  
  err = GetMediaSample2(
                        mediaRef.quickTimeMedia,
                        NULL,
                        0,
                        &sampleDataSize,
                        decodeTime,
                        NULL, NULL, NULL, NULL, NULL, 1, NULL,
                        &sampleFlags);
  assert(err == noErr);
  
  sampleData = malloc(sampleDataSize);
  assert(sampleData);
  memset(sampleData, 0, sampleDataSize);
  
  // Now invoke GetMediaSample2() again to really read the data
  
  err = GetMediaSample2(
                        mediaRef.quickTimeMedia,
                        sampleData, //data out
                        sampleDataSize, //max data size
                        NULL, // bytes
                        decodeTime, //decodeTime
                        NULL, //sampledecodetime
                        &duration, //sample duration
                        NULL,
                        NULL,
                        NULL, //sampledescription index
                        1, //max number of samples
                        NULL, //number of samples
                        &sampleFlags //flags
                        );
  assert(err == noErr);
  
  // Decode Animation codec data using movdata module. Note that the colorspace could have been
  // defined on the renderBuffer already as either SRGB or some other colorspace.
  
  {
    void *sampleBuffer = sampleData;
    uint32_t sampleBufferSize = sampleDataSize;
    
    void *decodedFrameBuffer = renderBuffer.pixels;
    int bpp = renderBuffer.bitsPerPixel;
    int width = renderBuffer.width;
    int height = renderBuffer.height;
    uint32_t isKeyframe = FALSE; // unused unless printing log messages
    
    if (bpp == 16) {
      exported_decode_rle_sample16(sampleBuffer, sampleBufferSize, isKeyframe, decodedFrameBuffer, width, height);
    } else if (bpp == 24) {
      exported_decode_rle_sample24(sampleBuffer, sampleBufferSize, isKeyframe, decodedFrameBuffer, width, height);
    } else {
      exported_decode_rle_sample32(sampleBuffer, sampleBufferSize, isKeyframe, decodedFrameBuffer, width, height);
    }
  }

  free(sampleData);
  
  if (FALSE) {
    NSString *dumpFilename = [NSString stringWithFormat:@"RenderDumpFrame.png"];
    
    NSData *pngData = [renderBuffer formatAsPNG];
    
    [pngData writeToFile:dumpFilename atomically:NO];
    
    NSLog(@"wrote %@", dumpFilename);
  }
  
  // Now create CGImageRef from the rendered buffer sent to the other function.
  
  frameImage = [renderBuffer createCGImageRef];
  
  assert(frameImage);
  
  return frameImage;
}

static
void decodeAnimation_cleanupMovFrameAtTime()
{
  movieRef = NULL;
  mediaRef = NULL;
  
  if (renderBuffer) {
    [renderBuffer release];
    renderBuffer = NULL;
  }
}

// -----------------------------------------

// Primary module entry point for decode of a specific frame. These functions will
// invoke specific implementation functions based on the #define constants earlier in the file.

void setupMovFrameAtTime(QTMovie *movie, QTMedia *trackMedia, int expectedBpp)
{
#if defined(QTKIT_FRAME_IMAGE_AT_TIME_IMPL)
  return frameImageAtTime_setupMovFrameAtTime(movie, trackMedia, expectedBpp);
#elif defined(QTKIT_DECODE_SESSION_IMPL)
  return decodeSession_setupMovFrameAtTime(movie, trackMedia, expectedBpp);
#elif defined(QTKIT_DECODE_ANIMATION_IMPL)
  return decodeAnimation_setupMovFrameAtTime(movie, trackMedia, expectedBpp);
#else
# error "no impl found"
#endif
}

// Primary module entry point for decode of a specific frame

CGImageRef getMovFrameAtTime(QTTime atTime)
{
#if defined(QTKIT_FRAME_IMAGE_AT_TIME_IMPL)
  return frameImageAtTime_getMovFrameAtTime(atTime);
#elif defined(QTKIT_DECODE_SESSION_IMPL)
  return decodeSession_getMovFrameAtTime(atTime);
#elif defined(QTKIT_DECODE_ANIMATION_IMPL)
  return decodeAnimation_getMovFrameAtTime(atTime);
#else
# error "no impl found"
#endif
}

// Primary module entry point for decode of a specific frame

void cleanupMovFrameAtTime()
{
#if defined(QTKIT_FRAME_IMAGE_AT_TIME_IMPL)
  return frameImageAtTime_cleanupMovFrameAtTime();
#elif defined(QTKIT_DECODE_SESSION_IMPL)
  return decodeSession_cleanupMovFrameAtTime();
#elif defined(QTKIT_DECODE_ANIMATION_IMPL)
  return decodeAnimation_cleanupMovFrameAtTime();
#else
# error "no impl found"
#endif
}
