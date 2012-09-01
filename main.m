#import <Cocoa/Cocoa.h>

#import "CGFrameBuffer.h"

int _imageWidth = -1;
int _imageHeight = -1;

CGSize _movieDimensions;

NSString *movie_prefix;

#define EMIT_DELTA

#ifdef EMIT_DELTA
NSString *delta_directory = nil;
#endif

// This method is invoked with a path that contains the frame
// data and the offset into the frame array that this specific
// frame data is found at.
//
// filenameStr : Name of .png file that contains the frame data
// frameIndex  : Frame index (starts at zero)
// bppNum      : 16, 24, or 32 BPP
// isKeyframe  : TRUE if this specific frame should be stored as a keyframe (as opposed to a delta frame)

int process_frame_file(NSString *filenameStr, int frameIndex, int bppNum, BOOL isKeyframe) {
	// Push pool after creating global resources

  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	//BOOL success;

	NSData *image_data = [NSData dataWithContentsOfFile:filenameStr];
	if (image_data == nil) {
		fprintf(stderr, "can't read image data from file \"%s\"\n", [filenameStr UTF8String]);
		exit(1);
	}

	// Create image object from src image data. If the image is the
	// exact size of the iPhone display in portrait mode (320x480) then
	// render into a view of that exact size. If the image is the
	// exact size of landscape mode (480x320) then render with a
	// 90 degree clockwise rotation so that the rendered result
	// can be displayed with no transformation applied to the
	// UIView. If the image dimensions are smaller than the
	// width and height in portrait mode, render at the exact size
	// of the image. Otherwise, the image is larger than the
	// display size in portrait mode, so scale it down to the
	// largest dimensions that can be displayed in portrait mode.

	NSImage *img = [[NSImage alloc] initWithData:image_data];

	CGSize imageSize = NSSizeToCGSize(img.size);
	int imageWidth = imageSize.width;
	int imageHeight = imageSize.height;
	assert(imageWidth > 0);
	assert(imageHeight > 0);

	int renderWidth;
	int renderHeight;
	int isLandscapeOrientation = FALSE;
	int initMovieDimensions = FALSE;

	if (imageWidth == 320 && imageHeight == 480) {
		// Image is the exact size of the frame buffer in portrait mode
		renderWidth = 320;
		renderHeight = 480;
	} else if (imageWidth == 480 && imageHeight == 320) {
		// Image is the exact size of the frame buffer in landscape mode,
		// render in a buffer the exact size of the image, it will be
		// rotated to portrait orientation in a moment.
		renderWidth = 480;
		renderHeight = 320;
		isLandscapeOrientation = TRUE;
	} else if (imageWidth < 320 && imageHeight < 480) {
		// Image is smaller than the frame buffer, encode with
		// the exact size of the image.
		renderWidth = imageWidth;
		renderHeight = imageHeight;
	} else {
		// Image is larger than the frame buffer, scale that largest dimension
		// down to fit into either portrait or landscape mode.

		if (imageWidth > imageHeight) {
			// image is wider than it is tall, must be landscape orientation
			renderWidth = 480;
			renderHeight = 320;
			isLandscapeOrientation = TRUE;
		} else {
			// portrait orientation
			renderWidth = 320;
			renderHeight = 480;
		}
	}

	NSRect viewRect;
	viewRect.origin.x = 0.0;
	viewRect.origin.y = 0.0;
	viewRect.size.width = renderWidth;
	viewRect.size.height = renderHeight;

	if (_imageWidth == -1) {
		// Init width and height globals
		_imageWidth = imageWidth;
		_imageHeight = imageHeight;
		
		initMovieDimensions = TRUE;
	} else if ((imageWidth != _imageWidth) || (imageHeight != _imageHeight)) {
		// Each input image should match in terms of width and height
		fprintf(stderr, "input image dimensions did not match previous image dimensions\n");
		exit(1);
	}

	// Render NSImageView into core graphics buffer that is limited
	// to the max size of the iPhone frame buffer. Only scaling
	// is handled in this render operation, no rotation issues
	// are handled here.

	NSImageView *imageView = [[NSImageView alloc] initWithFrame:viewRect];
	imageView.image = img;

	CGFrameBuffer *cgBuffer = [[CGFrameBuffer alloc] initWithDimensions:renderWidth height:renderHeight];	
	[cgBuffer renderView:imageView];
 
	if (initMovieDimensions) {
		_movieDimensions.width = renderWidth;
		_movieDimensions.height = renderHeight;
	}

  /*
	// RLE encode the RAW data and save to the RLE directory.

	NSString *rleFilename = [NSString stringWithFormat:@"%@%@%@",
							 @"F",
							 format_frame_number(frameIndex+1),
							 @".rle"];
	NSString *rlePath = [rle_directory stringByAppendingPathComponent:rleFilename];

	NSData *rleData = [cgBuffer runLengthEncode];

	success = [rleData writeToFile:rlePath atomically:FALSE];
	assert(success);

	[rle_filenames addObject:rlePath];
   */
    
	// free up resources
  
	[img release];
	[imageView release];
	[cgBuffer release];
  [pool drain];
	
	return 0;
}

/*
// Return 0 if the indicated frame is an exact duplicate of the
// previous frame indicated by prevFrameIndex. If the frames
// don't match, then 1 will be returned.

int compare_frames(int frameIndex, int prevFrameIndex) {
	assert(frameIndex > 0);
	assert(prevFrameIndex >= 0);
	assert(prevFrameIndex < frameIndex);

	int prev_crc = crcs[prevFrameIndex];
	int crc = crcs[frameIndex];

	if (prev_crc != crc)
		return 1;

	// if the crcs do match, it is still possible that
	// the two frames are not exactly the same. Need to
	// pull in the binary data and compare it in this
	// case to be sure that the frames actually match.

	NSString *prev_raw_filename = [raw_filenames objectAtIndex:prevFrameIndex];
	NSString *raw_filename = [raw_filenames objectAtIndex:frameIndex];

	NSData *prev_raw_data = [NSData dataWithContentsOfFile:prev_raw_filename];
	NSData *raw_data = [NSData dataWithContentsOfFile:raw_filename];
	
	if ([raw_data isEqualToData:prev_raw_data]) {
		return 0;
	} else {
		return 1;
	}
}

// Return true if the indicated frame is an exact duplicate of the
// one just before it. A frame is a duplicate if the pixels all match.

int is_duplicate_of_previous_frame(int frameIndex)
{
	if (frameIndex == 0)
		return FALSE;

	int cmp = compare_frames(frameIndex, frameIndex - 1);
	return (cmp == 0);
}
 
*/


// Extract all the frames of movie data from an archive file into
// the current directory.

void extract_movie_frames(char *archive_filename) {
	BOOL worked;
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

// main() Entry Point
//
// To create a .mvid video file from a series of PNG images
// with a 15 FPS framerate and 32BPP "Millions+" (24 BPP plus alpha channel)
//
// mvidmoviemaker movie.mvid FRAMES/Frame001.png 15 32
//
// To extract the contents of an .mvid movie to PNG images:
//
// mvidmoviemaker --extract out.mvid

#define USAGE \
  "usage: mvidmoviemaker FILE.mvid FIRSTFRAME.png FRAMERATE BITSPERPIXEL ?KEYFRAME?" "\n" \
  "or   : mvidmoviemaker -extract FILE.mvid" "\n"

int main (int argc, const char * argv[]) {
  NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

	if (argc == 3 && strcmp(argv[1], "-extract") == 0) {
		// Extract movie frames from an existing archive

    char *mvidFilename = (char *)argv[2];
		extract_movie_frames(mvidFilename);
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
    
    for (int i = [firstFilenameTailNoExtension length] - 1; i > 0; i--) {
      unichar c = [firstFilenameTailNoExtension characterAtIndex:i];
      if (c >= '0' && c <= '9') {
        numericStartIndex = i;
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
    
    // FIXME: Open .mvid and pass in the framerate to setup the header.
    
    // We now know the start and end integer values of the frame filename range.

		int frameIndex = 0;

    for (NSString *framePath in inFramePaths) {
      fprintf(stdout, "loading %s as frame %d\n", [framePath UTF8String], frameIndex+1);
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
      
			process_frame_file(framePath, frameIndex, bppNum, isKeyframe);
      frameIndex++;
    }

    // Done writing .mvid file
    
    fprintf(stdout, "done loading %d frames\n", frameIndex);
    fflush(stdout);
    
	} else if (argc == 2) {
    fprintf(stderr, USAGE);
    exit(1);
  }
  
  [pool drain];
  return 0;
}

