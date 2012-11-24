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

//#define QTKIT_FRAME_IMAGE_AT_TIME_IMPL

#define QTKIT_DECODE_SESSION_IMPL

static
QTMovie *movieRef = NULL;

static
QTMedia *mediaRef = NULL;


#if defined(QTKIT_DECODE_SESSION_IMPL)

static
ICMDecompressionSessionRef decompressionSession = NULL;

static
CGFrameBuffer *renderBuffer = NULL;

#endif // QTKIT_DECODE_SESSION_IMPL

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
  
  if (TRUE) {
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
  
  // cleanup decompressionSession
  
  assert(decompressionSession);
  ICMDecompressionSessionRelease(decompressionSession);
  
  if (renderBuffer) {
    [renderBuffer release];
    renderBuffer = NULL;
  }
}

// -----------------------------------------

// Primary module entry point for decode of a specific frame

void setupMovFrameAtTime(QTMovie *movie, QTMedia *trackMedia, int expectedBpp)
{
#if defined(QTKIT_FRAME_IMAGE_AT_TIME_IMPL)
  return frameImageAtTime_setupMovFrameAtTime(movie, trackMedia, expectedBpp);
#elif defined(QTKIT_DECODE_SESSION_IMPL)
  return decodeSession_setupMovFrameAtTime(movie, trackMedia, expectedBpp);
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
#else
# error "no impl found"
#endif
}
