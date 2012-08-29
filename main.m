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

int process_frame_file(NSString *filenameStr, int frameIndex) {
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
// To create a .mvid video file from a series of PNG images:
//
// mvidmoviemaker out.mvid FRAMES/Frame001.png
//
// To extract the contents of an .mvid movie to PNG images:
//
// mvidmoviemaker --extract out.mvid

int main (int argc, const char * argv[]) {
  NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

	if (argc == 3 && strcmp(argv[1], "-extract") == 0) {
		// Extract movie frames from an existing archive

    char *mvidFilename = (char *)argv[2];
		extract_movie_frames(mvidFilename);
	} else if (argc == 3) {
    // User will pass in the name of the output movie and the name
    // of the first file in the image sequence. This makes it posible
    // to know the format of the frame numbers because all the filenames
    // need to match the format of the first frame filename.

    char *mvidFilenameCstr = (char*)argv[1];
    char *firstFilenameCstr = (char*)argv[2];
    
    NSString *mvidFilename = [NSString stringWithCString:mvidFilenameCstr];
    
    BOOL isMvid = [mvidFilename hasSuffix:@".mvid"];
    
    if (isMvid == FALSE) {
      fprintf(stderr, "usage mvidmoviemaker FILE.mvid FIRSTFRAME.png");
      exit(1);
    }
    
    // Given the first frame image filename, build and array of filenames
    // by checking to see if files exist up until we find one that does not.
    // This makes it possible to pass the 25th frame ofa 50 frame animation
    // and generate an animation 25 frames in duration.
    
    NSString *firstFilename = [NSString stringWithCString:firstFilenameCstr];
    
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

    // We now know the start and end integer values of the frame filename range.

		int frameIndex = 0;

    for (NSString *framePath in inFramePaths) {
      fprintf(stdout, "loading %s as frame %d\n", [framePath UTF8String], frameIndex+1);
			fflush(stdout);
      
			process_frame_file(framePath, frameIndex++);
      
    }

    // Done writing .mvid file
    
    fprintf(stdout, "done loading %d frames\n", frameIndex);
    fflush(stdout);
    
	} else if (argc == 2) {
    fprintf(stderr, "usage mvidmoviemaker FILE.mvid FIRSTFRAME.png");
    exit(1);
  }
  
  [pool drain];
  return 0;
}

