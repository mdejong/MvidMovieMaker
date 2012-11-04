//
//  qtencode.h
//
//  Created by Moses DeJong on 11/3/12.
//
//  License terms defined in License.txt.

#import "qtencode.h"

#import "AVMvidFrameDecoder.h"

#import "CGFrameBuffer.h"

#import <QTKit/QTKit.h>

#import <QuickTime/Movies.h>

#import "movdata.h"

// static data

Media writingMovMedia = NULL;
BOOL initImageDescription = FALSE;
int imageDescriptionBPP = 0;

// Note that this pixel buffer is non-NULL when the writeEncodedFrameToMovie method is about to
// be invoked. This is a workaround for a bug in the encoder for 16BPP data.

static
CVPixelBufferRef currentPixelBuffer = NULL;

// callback to write frames to movie

static
OSStatus
writeEncodedFrameToMovie(void *encodedFrameOutputRefCon,
                         ICMCompressionSessionRef session,
                         OSStatus err,
                         ICMEncodedFrameRef encodedFrame,
                         void *reserved )
{
	if (err) {
		fprintf( stderr, "writeEncodedFrameToMovie received an error (%d)\n", (int)err );
		goto bail;
	}
  
  ImageDescriptionHandle imageDesc = NULL;
  
  // Note that frame description is the same as the session description
  
  err = ICMEncodedFrameGetImageDescription(encodedFrame, &imageDesc);
  if (err) {
    fprintf( stderr, "ICMEncodedFrameGetImageDescription() failed (%d)\n", (int)err );
    goto bail;
  }
  
  assert((**imageDesc).depth == imageDescriptionBPP);
  assert((**imageDesc).spatialQuality == codecMaxQuality);
  
  if (initImageDescription == FALSE)
  {
    initImageDescription = TRUE;
    
    // Add 'gama' 2.2 atom to make sure to avoid gamma shift when reading this MOV
    
    Fixed gammav = kQTCCIR601VideoGammaLevel;
    err = ICMImageDescriptionSetProperty(imageDesc,
                                         kQTPropertyClass_ImageDescription,
                                         kICMImageDescriptionPropertyID_GammaLevel,
                                         sizeof(Fixed),
                                         &gammav);
    
    if (err) {
      fprintf(stderr, "Count not set gamma property for MOV : %d\n", (int)err);
      goto bail;
    }
    
    // Embed sRGB color profile
    
    CGColorSpaceRef srgbColorspace;
    srgbColorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    assert(srgbColorspace);
    
    CFDataRef srgbColorspaceICC = CGColorSpaceCopyICCProfile(srgbColorspace);
    assert(srgbColorspaceICC);
    
    err = ICMImageDescriptionSetProperty(imageDesc,
                                         kQTPropertyClass_ImageDescription,
                                         kICMImageDescriptionPropertyID_ICCProfile,
                                         sizeof(CFDataRef),
                                         &srgbColorspaceICC);
    CFRelease(srgbColorspaceICC);
    
    CGColorSpaceRelease(srgbColorspace);
    
    if (err) {
      fprintf(stderr, "Count not set colorspace property for MOV : %d\n", (int)err);
      goto bail;
    }
  }
  
  /*
   (**desc).idSize = sizeof(ImageDescription);
   (**desc).cType = kAnimationCodecType;
   (**desc).vendor = kAppleManufacturer;
   (**desc).version = 0;
   (**desc).spatialQuality = codecLosslessQuality;
   (**desc).width = width;
   (**desc).height = height;
   (**desc).hRes = 72 << 16; // 72 DPI as a fixed-point number
   (**desc).vRes = 72 << 16; // 72 DPI as a fixed-point number
   (**desc).frameCount = 1;
   (**desc).depth = qtBPP;
   (**desc).dataSize = pixelsNumBytes;
   (**desc).clutID = -1;
   */
  
  /*
   // additional properties
   
   
   
   */
  
  // Check frame duration
  
  TimeValue64 decodeDuration;
  decodeDuration = ICMEncodedFrameGetDecodeDuration(encodedFrame);
  assert(decodeDuration >= 1);
  
  /*
   MungDataPtr pMungData = encodedFrameOutputRefCon;
   
   TimeValue64 decodeDuration;
   
   if( err ) {
   fprintf( stderr, "writeEncodedFrameToMovie received an error (%d)\n", err );
   goto bail;
   }
   
   err = ICMEncodedFrameGetImageDescription( encodedFrame, &imageDesc );
   if( err ) {
   fprintf( stderr, "ICMEncodedFrameGetImageDescription() failed (%d)\n", err );
   goto bail;
   }
   
   if( ! pMungData->outputVideoMedia ) {
   err = createVideoMedia( pMungData, imageDesc, ICMEncodedFrameGetTimeScale( encodedFrame ) );
   if( err )
   goto bail;
   }
   
   decodeDuration = ICMEncodedFrameGetDecodeDuration( encodedFrame );
   if( decodeDuration == 0 ) {
   // You can't add zero-duration samples to a media.  If you try you'll just get invalidDuration back.
   // Because we don't tell the ICM what the source frame durations are,
   // the ICM calculates frame durations using the gaps between timestamps.
   // It can't do that for the final frame because it doesn't know the "next timestamp"
   // (because in this example we don't pass a "final timestamp" to ICMCompressionSessionCompleteFrames).
   // So we'll give the final frame our minimum frame duration.
   decodeDuration = pMungData->minimumFrameDuration * ICMEncodedFrameGetTimeScale( encodedFrame ) / pMungData->timeScale;
   }
   
   if( pMungData->verbose ) {
   printf( "adding %ld byte sample: decode duration %ld, display offset %ld, flags %#lx",
   (long)ICMEncodedFrameGetDataSize( encodedFrame ),
   (long)decodeDuration,
   (long)ICMEncodedFrameGetDisplayOffset( encodedFrame ),
   (long)ICMEncodedFrameGetMediaSampleFlags( encodedFrame ) );
   if( true ) {
   ICMValidTimeFlags validTimeFlags = ICMEncodedFrameGetValidTimeFlags( encodedFrame );
   if( kICMValidTime_DecodeTimeStampIsValid & validTimeFlags )
   printf( ", decode time stamp %ld", (long)ICMEncodedFrameGetDecodeTimeStamp( encodedFrame ) );
   if( kICMValidTime_DisplayTimeStampIsValid & validTimeFlags )
   printf( ", display time stamp %ld", (long)ICMEncodedFrameGetDisplayTimeStamp( encodedFrame ) );
   }
   printf( "\n" );
   }
   
   err = AddMediaSample2(
   pMungData->outputVideoMedia,
   ICMEncodedFrameGetDataPtr( encodedFrame ),
   ICMEncodedFrameGetDataSize( encodedFrame ),
   decodeDuration,
   ICMEncodedFrameGetDisplayOffset( encodedFrame ),
   (SampleDescriptionHandle)imageDesc,
   1,
   ICMEncodedFrameGetMediaSampleFlags( encodedFrame ),
   NULL );
   if( err ) {
   fprintf( stderr, "AddMediaSample2() failed (%d)\n", err );
   goto bail;
   }
   */
  
  assert(writingMovMedia);
  
  if (imageDescriptionBPP == 16) {
    // When in 16BPP mode, the encoder logic fails to actually encode 16bpp pixel data
    // correctly. This corruption creates output data that is unusable. Work around
    // the problem by taking the original input 16BPP data and encoding it explicitly
    // as a buffer of raw Animation codec data.
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    assert(currentPixelBuffer);
    
    NSMutableData *mData = [NSMutableData dataWithCapacity:1024];
    
    if (TRUE) {
      // Encode Frame data as COPY operations. Note that the currentPixelBuffer
      // must be set before this method is invoked, and it is already locked.
    
      void *baseAddr = CVPixelBufferGetBaseAddress(currentPixelBuffer);      
      uint16_t *pixels = baseAddr;
      int width = CVPixelBufferGetWidth(currentPixelBuffer);
      int height = CVPixelBufferGetHeight(currentPixelBuffer);
      
      NSMutableData *encodedPixelData = [NSMutableData dataWithCapacity:1024];
      
      uint8_t skipCode = 0;
      int8_t rleCode = 0;
      
      int max7Bits = 0x7F;
      int pixelCount = 0;
      int pixelsEncoded = 0;
      
      // One "copy" rle operation can contain up to max7Bits 16 bit pixels
      
      NSMutableData *copyPixels = [NSMutableData dataWithCapacity:1024];
            
      for (int row=0; row < height; row++) {
        // Encode "skip 0 pixels" before the RLE codes
        
        skipCode = 1; // always 1 to indicate "do not skip any pixels"
        [encodedPixelData appendBytes:&skipCode length:sizeof(skipCode)];
        
        for (int column=0; column < width; column++) {
          if (pixelCount == max7Bits) {
            int numPixels = copyPixels.length / 2;
            assert(numPixels == pixelCount);
            rleCode = numPixels; // positive value indicates number of pixels to copy
            assert(rleCode != 0);
            assert(rleCode > 0);
            assert(rleCode <= max7Bits);
            [encodedPixelData appendBytes:&rleCode length:sizeof(rleCode)];
            [encodedPixelData appendData:copyPixels];
            pixelsEncoded += numPixels;
            
            [copyPixels setLength:0];
            pixelCount = 0;
          }
          
          // Pixel is already in BE format at this point
          uint16_t pixel = *pixels++;
          [copyPixels appendBytes:&pixel length:sizeof(pixel)];
          pixelCount += 1;
        }
        
        // At the end of one line, emit any unwritten pixels and then write -1 as the rle code
        
        if (copyPixels.length > 0) {
          int numPixels = copyPixels.length / 2;
          assert(numPixels == pixelCount);
          rleCode = numPixels; // positive value indicates number of pixels to copy
          assert(rleCode != 0);
          assert(rleCode > 0);
          assert(rleCode <= max7Bits);
          [encodedPixelData appendBytes:&rleCode length:sizeof(rleCode)];
          [encodedPixelData appendData:copyPixels];
          pixelsEncoded += numPixels;
          
          [copyPixels setLength:0];
          pixelCount = 0;
        }
        
        rleCode = -1;
        [encodedPixelData appendBytes:&rleCode length:sizeof(rleCode)];
      }
      
      assert(copyPixels.length == 0);      
      assert(pixelsEncoded = (width * height));
      
      // After all the normal codes, a zero skip pixel appears to indicate the end of the sample.
      
      skipCode = 0;
      [encodedPixelData appendBytes:&skipCode length:sizeof(skipCode)];
      
      // All data has been appended to the sample buffer at this point, it is now possible
      // to fill in the header information for the sample record.
      
      // Emit 1 set of compressed sample data for each row in the image. This should
      // avoid any limit issues with COPY or DUP frames.
      
      // http://wiki.multimedia.cx/index.php?title=Apple_QuickTime_RLE
      //
      // sample size : 4 bytes
      // header : 2 bytes
      // optional : 8 bytes
      //  starting line at which to begin updating frame : 2 bytes
      //  unknown : 2 bytes
      //  the number of lines to update : 2 bytes
      //  unknown
      // compressed lines : ?

      // Sample size, this field looks like a 1 byte flags value and then a 24 bit length
      // value (size & 0xFFFFFF) results in a correct 24 bit length. The flag element seems to
      // be 0x1 when set. But, this field is undocumented and can be safely skipped because
      // the sample length is already known.
      
      // 4 bytes for int32 header
      
      uint32_t sampleSize = encodedPixelData.length + 4 + 2; // data plus header size
      
      [mData appendBytes:&sampleSize length:sizeof(sampleSize)];
      
      // 2 bytes header is either 0x0 or 0x0008 to indicate if the optional larger header
      // is included. Emit 0 here to indicate a keyframe of RLE data.
      
      uint16_t header = 0x0;
      
      [mData appendBytes:&header length:sizeof(header)];
      
      // Append all the pixel data after the header info
      
      [mData appendData:encodedPixelData];
    }
    
    NSData *data = [NSData dataWithData:mData];
    
    // FIXME: Now that we have sample data in a buffer, need to run decoding logic to make sure
    // that when this sample buffer is decoded, that the same pixels are extracted.
    
    if (TRUE) {      
      void *sampleBuffer = (void*)data.bytes;
      uint32_t sampleBufferSize = data.length;
      uint32_t isKeyframe = TRUE;
      
      int width = CVPixelBufferGetWidth(currentPixelBuffer);
      int height = CVPixelBufferGetHeight(currentPixelBuffer);
      
      int numBytes = width * height * sizeof(uint16_t);
      uint16_t *frameBuffer = malloc(numBytes);
      assert(frameBuffer);
      memset(frameBuffer, 0, numBytes);
                                    
      exported_decode_rle_sample16(sampleBuffer, sampleBufferSize, isKeyframe, frameBuffer, width, height);
      
      // Data in frameBuffer should be the same as the data in original image data
      
      void *baseAddr = CVPixelBufferGetBaseAddress(currentPixelBuffer);
      int result = memcmp(baseAddr, frameBuffer, numBytes);
      
      // FIXME: Why do these not match?
      assert(result == 0);
      
      free(frameBuffer);
    }
    
    const UInt8 *dataIn = data.bytes;
    ByteCount byteCount = data.length;
    
    MediaSampleFlags sampleFlags = ICMEncodedFrameGetMediaSampleFlags(encodedFrame);
    TimeValue64 displayOffset = ICMEncodedFrameGetDisplayOffset(encodedFrame);
    
    err = AddMediaSample2(writingMovMedia,
                          dataIn,
                          byteCount,
                          decodeDuration,
                          displayOffset,
                          (SampleDescriptionHandle)imageDesc,
                          1, // numberOfSamples
                          sampleFlags,
                          NULL );
    
    [pool drain];
    
    if( err ) {
      fprintf( stderr, "AddMediaSample2() failed (%d)\n", (int)err );
      goto bail;
    }
  } else {
    err = AddMediaSampleFromEncodedFrame(writingMovMedia, encodedFrame, NULL);
    if( err ) {
      fprintf( stderr, "AddMediaSampleFromEncodedFrame() failed (%d)\n", (int)err );
      goto bail;
    }
  }
  
bail:
	return err;
}

// convertMvidToMov
//
// This method will encode the contents of a .mvid file as a Quicktime .mov using
// the Animation codec. This method supports 24BPP and 32BPP pixel modes.
// Note that this method will reject an old "non-sRGB" MVID file since we do
// not know exactly what the RGB and gamma values in that type of file might be.

void convertMvidToMov(
                      NSString *mvidFilename,
                      NSString *movFilename
                      )
{
  QTMovie *outMovie;
  NSError *error;
  
  // Open up the .mvid file and read settings
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  BOOL worked = [frameDecoder openForReading:mvidFilename];
  
  if (worked == FALSE) {
    fprintf(stderr, "error: cannot open mvid filename \"%s\"\n", [mvidFilename UTF8String]);
    exit(1);
  }
  
  worked = [frameDecoder allocateDecodeResources];
  assert(worked);
  
  NSUInteger numFrames = [frameDecoder numFrames];
  assert(numFrames > 0);
  
  float frameDuration = [frameDecoder frameDuration];
  
  long timeScale      = 600; // 600 "clicks" in a clock second
  long long timeValue;
  
  timeValue = (long long) round(frameDuration * timeScale);
  
  //QTTime frameDurationTime = QTMakeTime(timeValue, timeScale);
  
  int bpp = [frameDecoder header]->bpp;
  
  int width = [frameDecoder width];
  int height = [frameDecoder height];
  
  // Note that a 16BPP input .mvid will be converted to 24BPP implicitly
  
  // Verify that the input color data has been mapped to the sRGB colorspace.
  
  if ([frameDecoder isSRGB] == FALSE) {
    fprintf(stderr, "%s\n", "converting MVID to MOV is only support for MVID in sRGB colorspace");
    exit(1);
  }
  
  // Open up the .mov
  
  outMovie = [[QTMovie alloc] initToWritableFile:movFilename error:&error];
  
  if (outMovie == NULL) {
    fprintf(stderr, "Could not create Quicktime mov \"%s\" : %s\n", [movFilename UTF8String], [[error description] UTF8String]);
    exit(1);
  }
  
  [outMovie setAttribute:[NSNumber numberWithBool:YES] forKey:QTMovieEditableAttribute];
  
  // Create a QT Track handle
  
  Movie qtMovie = outMovie.quickTimeMovie;
  assert(qtMovie);
  Track qtTrack = NewMovieTrack(qtMovie, FixRatio(width, 1), FixRatio(height, 1), (short)0);
  
	OSErr osError = GetMoviesError();
  if (osError) {
    fprintf(stderr, "Create Quicktime mov track error %d\n", osError);
    exit(1);
  }
  assert(qtTrack);
  
  // http://developer.apple.com/library/mac/#documentation/QuickTime/Reference/QTRef_TrackAndMedia/Reference/reference.html
  //
  // Add video media (images) to a track
  
  OSType mediaType = VideoMediaType;
  Handle dataRef = NULL;
  OSType dataRefType = 0;
  
  Media qtMedia = NewTrackMedia(qtTrack, mediaType, (TimeScale)timeScale, dataRef, dataRefType);
  writingMovMedia = qtMedia;
  
  BeginMediaEdits(qtMedia);
  
  // Image compression setup
  
	ICMCompressionSessionRef compressionSession;
  {
    OSStatus err = noErr;
    ICMEncodedFrameOutputRecord encodedFrameOutputRecord = {0};
    ICMCompressionSessionOptionsRef sessionOptions = NULL;
    
    // Setup compression options
    
    err = ICMCompressionSessionOptionsCreate(NULL, &sessionOptions);
    assert(err == 0);
    
    err = ICMCompressionSessionOptionsSetMaxKeyFrameInterval(sessionOptions, 30);
    assert(err == 0);
    
    // Setup compression session
    
    CodecType					codecType;	// codec
    
    codecType = kAnimationCodecType;
    
    // Class identifier for compression session options object properties
    // kICMCompressionSessionOptionsPropertyID_CompressorSettings (setting for compressor)
    // kICMCompressionSessionOptionsPropertyID_Depth => 24 BPP
    // kICMCompressionSessionOptionsPropertyID_Quality => "Best"
    
    // (**desc).spatialQuality = codecMaxQuality;
    CodecQ quality = codecMaxQuality;
    err = ICMCompressionSessionOptionsSetProperty(sessionOptions,
                                                  kQTPropertyClass_ICMCompressionSessionOptions,
                                                  kICMCompressionSessionOptionsPropertyID_Quality,
                                                  sizeof(quality),
                                                  &quality);
    assert(err == 0);
    
    // (**desc).depth = bpp;
    UInt32 depth;
    if (bpp == 32) {
      depth = k32ARGBPixelFormat;
    } else if (bpp == 24) {
      depth = k24RGBPixelFormat;
    } else if (bpp == 16) {
      depth = k16BE555PixelFormat;
    } else {
      assert(0);
    }
    err = ICMCompressionSessionOptionsSetProperty(sessionOptions,
                                                  kQTPropertyClass_ICMCompressionSessionOptions,
                                                  kICMCompressionSessionOptionsPropertyID_Depth,
                                                  sizeof(depth),
                                                  &depth);
    assert(err == 0);
    
    ICMEncodedFrameOutputCallback outputCallback = writeEncodedFrameToMovie;
    
  	encodedFrameOutputRecord.encodedFrameOutputCallback = outputCallback;
    encodedFrameOutputRecord.encodedFrameOutputRefCon = NULL; // void* to pass to func
    encodedFrameOutputRecord.frameDataAllocator = NULL;
    
    err = ICMCompressionSessionCreate(NULL,
                                      width, height,
                                      codecType,
                                      timeScale,
                                      sessionOptions,
                                      NULL, // sourcePixelBufferAttributes
                                      &encodedFrameOutputRecord,
                                      &compressionSession);
    
    assert(err == 0);
    
    ICMCompressionSessionOptionsRelease(sessionOptions);
    assert(err == 0);
  }
  
  // Note that these flags describe the format of the pixel buffer passed to the compression module.
  // The compressed frames are able to write in a more space optimal format
  // (for example 32 BPP can be written as 24 BPP since the alpha channel is known to be unused)
  
  uint32_t qtBPP;
  OSType osType;
  
  if (bpp == 32) {
    qtBPP = 32;
    osType = kCVPixelFormatType_32ARGB; // was kCVPixelFormatType_32BGRA
  } else if (bpp == 24) {
    qtBPP = 24;
    osType = kCVPixelFormatType_32ARGB;
  } else if (bpp == 16) {
    qtBPP = 16;
    osType = kCVPixelFormatType_16BE555;
  } else {
    assert(0);
  }
  imageDescriptionBPP = qtBPP;
  
  // graphics buffer data is copied to when writing
  
  CVPixelBufferRef pixelBuffer = NULL;
  NSDictionary *pixelBufferAttributes = nil;
  
  pixelBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                           [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                           nil];
  
  CVReturn cvReturn;
  cvReturn = CVPixelBufferCreate(NULL,
                                 width,
                                 height,
                                 osType,
                                 (CFDictionaryRef)pixelBufferAttributes,
                                 &pixelBuffer);
  assert(cvReturn == 0);
  
  // Add media samples, 1 sample for each frame image
  
  for (int frame = 0; frame < numFrames; frame++)
  {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AVFrame *frameObj = [frameDecoder advanceToFrame:frame];
    assert(frameObj);
    frameObj.image = nil;
    
    CGFrameBuffer *frameBuffer = frameObj.cgFrameBuffer;
    assert(frameBuffer);
    
    if (TRUE) {
      // Dump the image data rendered into PNG format before converting
      // to CVPixelBuffer
      
      NSString *dumpFilename = [NSString stringWithFormat:@"QTEncodeDumpPreCVFrame%0.4d.png", frame+1];
      
      NSData *pngData = [frameBuffer formatAsPNG];
      
      [pngData writeToFile:dumpFilename atomically:NO];
      
      NSLog(@"wrote %@", dumpFilename);
    }
    
    // Image data has now been rendered into buffer of pixels
    
    void *pixels = (void*)frameBuffer.pixels;
    
    osError = CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    assert( osError == 0 );
    void *baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer);
    
    if (bpp == 16) {
      // Copy rgb555 from LE to BE
      //
      // Swap byte[0] and byte[1]
      //
      // RGB555 (LE) => gggbbbbb arrrrrgg
      // RGB555 (BE) => arrrrrgg gggbbbbb
      
      // XRRRRRGGGGGBBBBB => XRRRRRGG (high) GGGBBBBB (low)
      
      NSUInteger numPixels = width * height;
      uint16_t *inPixels = (uint16_t*)pixels;
      uint8_t  *outPixels = (uint8_t*)baseAddr;
      
      for (NSUInteger pixeli = 0; pixeli < numPixels; pixeli++) {
        uint16_t pixel = inPixels[pixeli];
        
        if (pixeli == 1) {
          assert(pixeli == 1); // useful when debugging
        }
        
        // Write LE 16 bit value as BE 16 bit value
        
        // LE[0] = LOW
        // LE[1] = HIGH
        
        uint8_t b1 = (pixel >> 8) & 0xFF;
        uint8_t b2 = pixel & 0xFF;
        
        // BE[0] = HIGH
        // BE[1] = LOW
        
        *outPixels++ = b1;
        *outPixels++ = b2;
      }
    } else if ((bpp == 24) || (bpp == 32)) {
      // In BGRA : Out ARGB
      
      // Either 24BPP BGRA or BGRX in LE format is written as BE
      // Both pixel formats are premultiplied when 32BPP.
      
      //int pixelsNumBytes = width * height * sizeof(uint32_t);
      //memcpy(baseAddr, pixels, pixelsNumBytes);
      
      NSUInteger numPixels = width * height;
      uint32_t *inPixels = (uint32_t*)pixels;
      uint8_t  *outPixels = (uint8_t*)baseAddr;
      
      for (NSUInteger pixeli = 0; pixeli < numPixels; pixeli++) {
        uint32_t pixel = inPixels[pixeli];
        
        if (pixeli == 1) {
          assert(pixeli == 1); // useful when debugging
        }
        
        // Write each byte of LE 32BPP pixel as BE 32BPP
        
        for (int byteIndex = 3; byteIndex >= 0; byteIndex--) {
          uint8_t b = (pixel >> (8 * byteIndex)) & 0xFF;
          *outPixels++ = b;
        }
      }
      
    } else {
      assert(0);
    }
    
    // Once the CVPixelBuffer has been filled in, render it as a CIImage so that
    // the resulting pixels can be written as a PNG
    
    if (TRUE) {
      CGFrameBuffer *beFramebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:width height:height];
      beFramebuffer.usesBigEndianData = TRUE;
      beFramebuffer.colorspace = frameBuffer.colorspace;
      
      int pixelsNumBytes = width * height * beFramebuffer.bytesPerPixel;
      memcpy(beFramebuffer.pixels, baseAddr, pixelsNumBytes);
      
      // Dump image data rendered as Big Endian data into a PNG
      
      NSString *dumpFilename = [NSString stringWithFormat:@"QTEncodeDumpPostCVFrame%0.4d.png", frame+1];
      
      NSData *pngData = [beFramebuffer formatAsPNG];
      
      [pngData writeToFile:dumpFilename atomically:NO];
      
      NSLog(@"wrote %@", dumpFilename);
    }
    
    // encode specific frames
    
    currentPixelBuffer = pixelBuffer;
    osError = ICMCompressionSessionEncodeFrame(compressionSession,
                                               pixelBuffer,
                                               0, // timeStamp
                                               timeValue, // TimeValue64 displayDuration
                                               kICMValidTime_DisplayDurationIsValid,
                                               NULL, NULL, NULL);
    currentPixelBuffer = NULL;
    assert(osError == 0);
    
    osError = CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    assert(osError == 0);
    
    /*
     
     osError = AddMediaSample(qtMedia,
     pixlesHandle,
     pixelsOffset,
     pixelsNumBytesOutput,
     (TimeValue)timeValue, // durationPerSample
     (SampleDescriptionHandle) desc, // sample description
     1, // numberOfSamples
     0,
     (TimeValue*)NULL);
     
     if (osError) {
     fprintf(stderr, "Insert Quicktime media segment error %d\n", osError);
     exit(1);
     }
     
     */
    
    [pool drain];
  }
  
  // It is important to push out any remaining frames before we release the compression session.
  // If we knew the timestamp following the last source frame, you should pass it in here.
  
  ICMCompressionSessionCompleteFrames(compressionSession, TRUE, 0, 0);
  ICMCompressionSessionRelease(compressionSession);
  
  CVPixelBufferRelease(pixelBuffer);
  
  writingMovMedia = NULL;
  
  // FIXME: can we query media handle here and add additional color parameters like sRGB and so on?
  
  // ------------------------------------------------------
  
  // Add 1 media sample (image)
  
  /*
   
   if (TRUE) {
   NSString *inFilename = @"Colorbands_sRGB.png";
   CGImageRef cgImage = createImageFromFile(inFilename);
   assert(cgImage);
   
   // Render into sRGB (no colorspace conversion)
   CGColorSpaceRef colorSpace = CGImageGetColorSpace(cgImage);
   conversionFramebuffer.colorspace = colorSpace;
   CGColorSpaceRelease(colorSpace);
   
   [conversionFramebuffer renderCGImage:cgImage];
   CGImageRelease(cgImage);
   
   // Image data has now been rendered into buffer of pixels
   
   void *pixels = (void*)conversionFramebuffer.pixels;
   int pixelsOffset = 0;
   int pixelsNumBytesOutput;
   Handle pixlesHandle;
   
   if (bpp == 24) {
   // FIXME: Copy 24BPP pixels to output buffer
   
   pixelsNumBytesOutput = outputBufferSize;
   pixlesHandle = (Handle) &outputBuffer;
   } else {
   pixlesHandle = (Handle) &pixels;
   pixelsNumBytesOutput = pixelsNumBytes;
   }
   
   osError = AddMediaSample(qtMedia,
   pixlesHandle,
   pixelsOffset,
   pixelsNumBytesOutput,
   (TimeValue)timeValue, // durationPerSample
   (SampleDescriptionHandle) desc, // sample description
   1, // numberOfSamples
   0,
   (TimeValue*)NULL);
   
   if (osError) {
   fprintf(stderr, "Insert Quicktime media segment error %d\n", osError);
   exit(1);
   }
   }
   
   */
  
  EndMediaEdits(qtMedia);
  
  // Query current track duration
  
  TimeValue mediaDuration = GetMediaDuration(qtMedia);
  osError = InsertMediaIntoTrack(qtTrack, (TimeValue)0, (TimeValue)0, mediaDuration, fixed1);
  if (osError) {
    fprintf(stderr, "Insert Quicktime media track error %d\n", osError);
    exit(1);
  }
  
  // Query track timescale and duration
  
  TimeValue trackOffset = GetTrackOffset(qtTrack);
  TimeValue trackDuration = GetTrackDuration(qtTrack);
  
  assert(trackOffset == 0);
  assert(trackDuration == mediaDuration);
  
  
  [outMovie updateMovieFile];
  
  // Export the completed movie and convert to using the Animation codec
  
  fprintf(stdout, "wrote %s\n", [movFilename UTF8String]);
  
  
  // Deallocate movie
  
  [outMovie release];
  
  return;
}

void oldExport()
{
  /*
   
   // Add frames to track
   
   NSString *codec;
   
   //codec = @"rle "; // Animation codec
   //codec = @"jpeg"; // MJPEG codec
   //codec = @"ap4h"; // Apple ProRes 4444
   codec = @"png ";   // Apple PNG
   
   long quality;
   //quality = codecLosslessQuality;
   quality = codecMaxQuality;
   //quality = codecHighQuality;
   
   NSDictionary *outputMovieAttribs = [NSDictionary dictionaryWithObjectsAndKeys:
   codec, QTAddImageCodecType,
   [NSNumber numberWithLong:quality], QTAddImageCodecQuality,
   [NSNumber numberWithLong:timeScale], QTTrackTimeScaleAttribute,
   nil];
   
   CGFrameBuffer *conversionFramebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:width height:height];
   
   for (int frame = 0; frame < numFrames; frame++)
   {
   NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
   NSImage *image;
   
   if (FALSE) {
   NSString *inFilename = @"Colorbands_sRGB.png";
   CGImageRef cgImage = createImageFromFile(inFilename);
   assert(cgImage);
   CGSize cgSize = CGSizeMake(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
   image = [[[NSImage alloc] initWithCGImage:cgImage size:NSSizeFromCGSize(cgSize)] autorelease];
   assert(image);
   CGImageRelease(cgImage);
   } else if (FALSE) {
   NSString *inFilename = @"Colorbands_sRGB.png";
   NSURL *fileUrl = [NSURL fileURLWithPath:inFilename];
   image = [[[NSImage alloc] initWithContentsOfURL:fileUrl] autorelease];
   } else {
   AVFrame *frameObj = [frameDecoder advanceToFrame:frame];
   assert(frameObj);
   frameObj.image = nil;
   
   // http://www.planet1107.net/blog/tips-tutorials/ios5-core-image-filters/
   // https://svn.blender.org/svnroot/bf-blender/branches/bge_eigen2/source/blender/quicktime/apple/qtkit_export.m
   
   // http://bitfilms.blogspot.com/2011/08/final-cut-exports-look-different-from.html (read about nclc atom)
   
   // http://developer.apple.com/library/mac/#technotes/tn2227/_index.html
   
   // Convert frame pixel from sRGB (gamma 2.2) to device colorspace (gamma 1.8) so that the RGB values
   // and in a format expected by Quicktime. The Quicktime support for colorspace is spotty
   // so we need to avoid sending sRGB data otherwise the gamma will be wrong.
   
   CGImageRef cgImage = [frameObj.cgFrameBuffer createCGImageRef];
   assert(cgImage);
   
   // FIXME : would convertion to "GenericRGB" add a profile to the QT file (not a nclc)
   
   CGColorSpaceRef colorSpace;
   colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
   assert(colorSpace);
   conversionFramebuffer.colorspace = colorSpace;
   CGColorSpaceRelease(colorSpace);
   
   [conversionFramebuffer renderCGImage:cgImage];
   CGImageRelease(cgImage);
   
   if (TRUE) {
   NSString *dumpFilename = [NSString stringWithFormat:@"QTEncodeDumpFrame%0.4d.png", frame+1];
   
   NSData *pngData = [conversionFramebuffer formatAsPNG];
   
   [pngData writeToFile:dumpFilename atomically:NO];
   
   NSLog(@"wrote %@", dumpFilename);
   }
   
   CGImageRef conversionColorspaceImage = [conversionFramebuffer createCGImageRef];
   
   CGColorSpaceRef conversionColorspace = CGImageGetColorSpace(conversionColorspaceImage);
   assert(conversionColorspace);
   
   NSSize size = NSMakeSize(width, height);
   image = [[[NSImage alloc] initWithCGImage:conversionColorspaceImage size:size] autorelease];
   assert(image);
   
   CGImageRelease(conversionColorspaceImage);
   
   assert(image);
   }
   
   // Adds an image for the specified duration to the QTMovie
   [outMovie addImage:image
   forDuration:frameDurationTime
   withAttributes:outputMovieAttribs];
   
   [pool drain];
   }
   
   */
  
}

// This logic is out of date and never worked in the first place, but might be useful for reference purposes

void oldQueryComponents()
{
  
  /*
  
  // Grab availableComponents
  
  NSMutableArray *availableComponents = nil;
  
  if (FALSE)
  {
    // Print availableComponents
    
    availableComponents = [NSMutableArray array];
    
    ComponentDescription cd;
    Component c = NULL;
    
    cd.componentType = MovieExportType;
    cd.componentSubType = 0;
    cd.componentManufacturer = 0;
    cd.componentFlags = canMovieExportFiles;
    cd.componentFlagsMask = canMovieExportFiles;
    
    while((c = FindNextComponent(c, &cd)))
    {
      Handle name = NewHandle(4);
      ComponentDescription exportCD;
      
      if (GetComponentInfo(c, &exportCD, name, nil, nil) == noErr)
      {
        unsigned char *namePStr = (unsigned char *)name;
        NSString *nameStr = [[NSString alloc] initWithBytes:&namePStr[1]
                                                     length:namePStr[0]
                                                   encoding:NSUTF8StringEncoding];
        
        NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                    nameStr, @"name",
                                    [NSData dataWithBytes:&c length:sizeof(c)], @"component",
                                    [NSNumber numberWithLong:exportCD.componentType], @"type",
                                    [NSNumber numberWithLong:exportCD.componentSubType], @"subtype",
                                    [NSNumber numberWithLong:exportCD.componentManufacturer], @"manufacturer", nil];
        
        [availableComponents addObject:dictionary];
        [nameStr release];
      }
      
      DisposeHandle(name);
    }
    
    NSLog(@"availableComponents : %@", availableComponents);
  }
  
//   From Above:
//   
//   {
//   component = <06010100>;
//   manufacturer = 1634758764;
//   name = "QuickTime Movie";
//   subtype = 1299148630;
//   type = 1936746868;
//   }
  
  NSDictionary *movComponent = [availableComponents objectAtIndex:9];
  
  if (FALSE)
  {
    // Get export settings for a specific component
    
    NSData *exportSettings = nil;
    
    Component c = NULL;
    memcpy(&c, [[movComponent objectForKey:@"component"] bytes], sizeof(c));
    
    MovieExportComponent exporter = OpenComponent(c);
    Boolean canceled;
    ComponentResult err = MovieExportDoUserDialog(exporter, NULL, NULL, 0, 0, &canceled);
    if(err) {
      NSLog(@"Got error %d when calling MovieExportDoUserDialog", (int)err);
      CloseComponent(exporter);
      //return nil;
      assert(0);
    }
    if(canceled) {
      CloseComponent(exporter);
      //return nil;
      assert(0);
    }
    QTAtomContainer settings; err = MovieExportGetSettingsAsAtomContainer(exporter, &settings);
    if(err) {
      NSLog(@"Got error %d when calling MovieExportGetSettingsAsAtomContainer",(int)err);
      CloseComponent(exporter);
      //return nil;
      assert(0);
    }
    
    NSData *data = [NSData dataWithBytes:settings length:GetHandleSize(settings)];
    DisposeHandle(settings);
    
    CloseComponent(exporter);
    
    //return data;
  }
  
  if (FALSE) {
    NSError *error = NULL;
    
    QTMovie *compressedMovie = [[QTMovie alloc] initToWritableFile:@"OutWritable.mov" error:&error];
    
    QTTimeRange timeRange = QTMakeTimeRange(QTZeroTime, [outMovie duration]);
    QTTime insertionTime = QTMakeTime(0, timeScale);
    [compressedMovie insertSegmentOfMovie:outMovie timeRange:timeRange atTime:insertionTime];
    
    NSDictionary *writeAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSNumber numberWithBool:YES], QTMovieFlatten,
                                     nil];
    
    NSString *exportFilename = @"Out_Ani.mov";
    
    BOOL worked = [compressedMovie writeToFile:exportFilename withAttributes:writeAttributes error:&error];
    
    if (worked == FALSE) {
      fprintf(stderr, "failed to export to Animation codec %s", [@"OutWritable.mov" UTF8String]);
      
      exit(1);
    }
  }
  
  // Perhaps whole movie can be included by ref, then flattened on export?
  
  if (FALSE) {
    // Still does not work
    
    NSData *exportSettings = nil;
    
    exportSettings = [NSData dataWithContentsOfFile:@"/Users/mo/Ani24BPP.data"];
    assert(exportSettings);
    
    NSNumber *exportType = [NSNumber numberWithLong:kQTFileTypeMovie];
    NSNumber *manufacturer = [NSNumber numberWithLong:MovieMediaType];
    
    // kQTFileTypeMovie = 1299148630
    // MovieMediaType   = 1836019574
    // AliasDataHandlerSubType = 1634494835
    
    // subtype = 1299148630; -> kQTFileTypeMovie
    // type = 1936746868;
    // What is 1634758764 ?
    // VideoMediaType ?
    
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithBool:YES], QTMovieExport,
                           exportType, QTMovieExportType,
                           manufacturer, QTMovieExportManufacturer,
                           exportSettings, QTMovieExportSettings,
                           nil];
    
    NSString *exportFilename = @"Out_Ani.mov";
    
    NSError *error = NULL;
    
    if (fileExists(exportFilename) == TRUE) {
      fprintf(stderr, "export file exists : %s\n", [exportFilename UTF8String]);
    }
    
    BOOL worked = [outMovie writeToFile:exportFilename withAttributes:attrs error:&error];
    
    if (worked == FALSE) {
      fprintf(stderr, "failed to export to Animation codec %s", [exportFilename UTF8String]);
      
      exit(1);
    }
    
    fprintf(stdout, "exported %s\n", [exportFilename UTF8String]);
  }
  
  if (FALSE) {
    // Does not change the encoding type (still None)
    
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"jpeg", QTAddImageCodecType,
                           [NSNumber numberWithInt: codecNormalQuality], QTAddImageCodecQuality,
                           nil];
    
    NSString *exportFilename = @"Out_Ani.mov";
    
    NSError *error = NULL;
    
    if (fileExists(exportFilename) == TRUE) {
      fprintf(stderr, "export file exists : %s\n", [exportFilename UTF8String]);
    }
    
    BOOL worked = [outMovie writeToFile:exportFilename withAttributes:attrs error:&error];
    
    if (worked == FALSE) {
      fprintf(stderr, "failed to export to Animation codec %s", [exportFilename UTF8String]);
      exit(1);
    }
    
    fprintf(stdout, "exported %s\n", [exportFilename UTF8String]);
  }
  
  if (FALSE) {
    // Does not work
    
    NSData *exportSettings = nil;
    
    exportSettings = [NSData dataWithContentsOfFile:@"/Users/mo/Ani24BPP.data"];
    assert(exportSettings);
    
    //NSNumber *exportType = [NSNumber numberWithLong:kAnimationCodecType];
    //NSNumber *manufacturer = [NSNumber numberWithLong:kAppleManufacturer];
    
    NSNumber *exportType = [NSNumber numberWithLong:1299148630]; // Quicktime Movie ( )
    NSNumber *manufacturer = [NSNumber numberWithLong:1634758764]; // Apple ( )
    
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithBool:YES], QTMovieExport,
                           exportType, QTMovieExportType,
                           manufacturer, QTMovieExportManufacturer,
                           exportSettings, QTMovieExportSettings,
                           nil];
    
    NSString *exportFilename = @"Out_Ani.mov";
    
    NSError *error = NULL;
    
    if (fileExists(exportFilename) == TRUE) {
      fprintf(stderr, "export file exists : %s\n", [exportFilename UTF8String]);
    }
    
    BOOL worked = [outMovie writeToFile:exportFilename withAttributes:attrs error:&error];
    
    if (worked == FALSE) {
      fprintf(stderr, "failed to export to Animation codec %s", [exportFilename UTF8String]);
      exit(1);
    }
    
    fprintf(stdout, "exported %s\n", [exportFilename UTF8String]);
  }
  
  // Export with just the "rle" type (does not work)
  
  if (FALSE) {
    //NSData *exportSettings = nil;
    NSNumber *exportType = [NSNumber numberWithLong:kAnimationCodecType];
    NSNumber *manufacturer = [NSNumber numberWithLong:kAppleManufacturer];
    
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithBool:YES], QTMovieExport,
                           exportType, QTMovieExportType,
                           manufacturer, QTMovieExportManufacturer,
                           //exportSettings, QTMovieExportSettings,
                           nil];
    
    NSString *exportFilename = @"Out_Ani.mov";
    
    NSError *error = NULL;
    
    if (fileExists(exportFilename) == TRUE) {
      fprintf(stderr, "export file exists : %s\n", [exportFilename UTF8String]);
    }
    
    BOOL worked = [outMovie writeToFile:exportFilename withAttributes:attrs error:&error];
    
    if (worked == FALSE) {
      fprintf(stderr, "failed to export to Animation codec %s", [exportFilename UTF8String]);
      exit(1);
    }
    
    fprintf(stdout, "exported %s\n", [exportFilename UTF8String]);
  }
  
  
  // kPNGCodecType
  // kH264CodecType
  // kAnimationCodecType
  
  if (FALSE) {
    //NSData *exportSettings = nil;
    NSNumber *exportType = [NSNumber numberWithLong:kAnimationCodecType];
    NSNumber *manufacturer = [NSNumber numberWithLong:kAppleManufacturer];
    
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithBool:YES], QTMovieExport,
                           exportType, QTMovieExportType,
                           manufacturer, QTMovieExportManufacturer,
                           //exportSettings, QTMovieExportSettings,
                           nil];
    
    NSString *exportFilename = @"Out_Ani.mov";
    
    NSError *error = NULL;
    
    if (fileExists(exportFilename) == TRUE) {
      fprintf(stderr, "export file exists : %s\n", [exportFilename UTF8String]);
    }
    
    BOOL worked = [outMovie writeToFile:exportFilename withAttributes:attrs error:&error];
    
    if (worked == FALSE) {
      fprintf(stderr, "failed to export to Animation codec %s", [exportFilename UTF8String]);
      exit(1);
    }
    
    fprintf(stdout, "exported %s\n", [exportFilename UTF8String]);
  }
  
  if (FALSE) {
    // Attempt to open a new movie ref to the finished .mov file (does not fix export)
    
    NSError *error = NULL;
    QTMovie *inputMovie;
    
    inputMovie = [[[QTMovie alloc] initWithFile:movFilename error:&error] autorelease];
    
    //NSData *exportSettings = nil;
    NSNumber *exportType = [NSNumber numberWithLong:kAnimationCodecType];
    NSNumber *manufacturer = [NSNumber numberWithLong:kAppleManufacturer];
    
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithBool:YES], QTMovieExport,
                           exportType, QTMovieExportType,
                           manufacturer, QTMovieExportManufacturer,
                           //exportSettings, QTMovieExportSettings,
                           [NSNumber numberWithLong:codecMaxQuality], QTAddImageCodecQuality,
                           nil];
    
    NSString *exportFilename = @"Out_Ani.mov";
    
    if (fileExists(exportFilename) == TRUE) {
      fprintf(stderr, "export file exists : %s\n", [exportFilename UTF8String]);
    }
    
    BOOL worked = [inputMovie writeToFile:exportFilename withAttributes:attrs error:&error];
    
    if (worked == FALSE) {
      fprintf(stderr, "failed to export to Animation codec %s", [exportFilename UTF8String]);
      exit(1);
    }
   
    fprintf(stdout, "exported %s\n", [exportFilename UTF8String]);
  }
   
   */
}
