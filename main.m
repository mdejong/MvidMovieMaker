#import <Cocoa/Cocoa.h>

#import "CGFrameBuffer.h"

int _imageWidth = -1;
int _imageHeight = -1;

CGSize _movieDimensions;

NSMutableArray *src_filenames;

NSString *movie_prefix;

#define EMIT_DELTA

#ifdef EMIT_DELTA
NSString *delta_directory = nil;
#endif

// This method will format a frame number integer like "1" into a string like "0001"
// so that file names are ordered by the frame number.

int frame_number_zeros = 4;

NSString* format_frame_number(int frameIndex) {
	if (frame_number_zeros == 3) {
		return [NSString stringWithFormat:@"%03d", frameIndex];
	} else if (frame_number_zeros == 4) {
		return [NSString stringWithFormat:@"%04d", frameIndex];
	} else if (frame_number_zeros == 5) {
		return [NSString stringWithFormat:@"%05d", frameIndex];		
	} else {
		assert(0);
	}
}

int process_frame_file(char *filename, int frameIndex) {

	// Push pool after creating global resources

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	BOOL success;

	NSString *filenameStr = [NSString stringWithCString:filename];

	[src_filenames addObject:filenameStr];

	NSData *image_data = [NSData dataWithContentsOfFile:filenameStr];
	if (image_data == nil) {
		fprintf(stderr, "can't read image data from file \"%s\"\n", filename);
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

#ifdef REWRITE_WHITE_PIXLES
	// Scan all the pixels we just rendered looking for the value 0x7FFF and rewrite it
	// as 0xFFFF. This enables an optimization in the RLE logic so that fills of
	// 0xFFFF are converted into a memset. This optimizaton only makes sense when
	// the decoder is setup to ignore the first high bit (no alpha).
	int x, y;
	uint16_t *pixels = (uint16_t*) cgBuffer->pixels;
	int rewroteWhitePixels = 0;

	for (y = 0; y < renderHeight ; y++) {
		for (x = 0; x < renderWidth; x++) {
			uint16_t *pixelPtr = &pixels[(y * renderWidth) + x];

			if (*pixelPtr == 0x7FFF) {
				*pixelPtr = 0xFFFF;
				rewroteWhitePixels++;
			}
		}
	}
	printf("rewrote %d white pixels as 0xFFFF\n", rewroteWhitePixels);
#endif // REWRITE_WHITE_PIXLES

	// Save rendered 16bit pixels

	NSData *rawBytes = [cgBuffer copyData];

	// Find the last '/' in the string, then use everything after that as the entry name
	
	NSString *tail;
	NSRange lastSlash = [filenameStr rangeOfString:@"/" options:NSBackwardsSearch];
	
	if (lastSlash.location == NSNotFound) {
		tail = filenameStr;
	} else {
		NSRange restOfPathRange;
		restOfPathRange.location = lastSlash.location + 1;
		restOfPathRange.length = [filenameStr length] - restOfPathRange.location;
		tail = [filenameStr substringWithRange:restOfPathRange];
	}

	// Find the last '.' in the string and use everything up to it

	NSRange lastDot = [tail rangeOfString:@"." options:NSBackwardsSearch];

	if (lastDot.location == NSNotFound) {
		// no-op
	} else {
		NSRange beforeDotRange;
		beforeDotRange.location = 0;
		beforeDotRange.length = lastDot.location;
		tail = [tail substringWithRange:beforeDotRange];
	}

	// For a frame file like "Lesson_Animation_Frames001.png" save Lesson_Animation_Frames
	// as the movie prefix without the frame number at the end.

	if (movie_prefix == NULL) {
		// Find the last character that is not a number, range [0-9]

		int movie_prefix_end = -1;
		for (int i = 0 ; i < [tail length]; i++) {
			int c = [tail characterAtIndex:i];
			if (c >= '0' && c <= '9') {
				// no-op
			} else {
				movie_prefix_end = i;				
			}
		}
		assert(movie_prefix_end != -1);

		NSRange prefixRange;
		prefixRange.location = 0;
		prefixRange.length = movie_prefix_end + 1;
		movie_prefix = [tail substringWithRange:prefixRange];

		[movie_prefix retain];

		fprintf(stderr, "found movie filename prefix \"%s\"\n", [movie_prefix UTF8String]);
	}
	else {
		// Verify that this filename starts with the same movie prefix string

		NSRange prefixRange = [tail rangeOfString:movie_prefix options:NSLiteralSearch];

		if (prefixRange.location == NSNotFound || prefixRange.location != 0) {
			// filename does not start with identical movie prefix
			fprintf(stderr, "frame filename \"%s\" must start with movie prefix \"%s\"\n",
					[tail UTF8String], [movie_prefix UTF8String]);
			exit(1);
		}
	}

	// Write file to RAW directory, this contains just the 16 bit pixel values
	// and it has a filename like "F0001.raw"

	NSString *rawFilename = [NSString stringWithFormat:@"%@%@%@",
							 @"F",
							 format_frame_number(frameIndex+1),
							 @".raw"];
	NSString *rawPath = [raw_directory stringByAppendingPathComponent:rawFilename];

	[raw_filenames addObject:rawPath];	

	success = [rawBytes writeToFile:rawPath atomically:FALSE];
	assert(success);

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

	// create NSImage object from the existing graphics context!

#ifdef EMIT_RLE_TIFF

	CGImageRef cgImageRef = [cgBuffer createCGImageRef];
	
	NSBitmapImageRep *newImg = [[NSBitmapImageRep alloc] initWithCGImage:cgImageRef];


	// Write out a tiff in pack bits format
	
	NSString *tiffFilename_PackBits = [NSString stringWithFormat:@"%@%@%@",
							 @"F",
							 format_frame_number(frameIndex+1),
							 @"_PB.tiff"];

	NSString *tiffPath = [tiff_directory stringByAppendingPathComponent:tiffFilename_PackBits];
	
	NSData *tiffData_PackBits = [newImg TIFFRepresentationUsingCompression:NSTIFFCompressionPackBits factor:0.0];
	
	CGImageRelease(cgImageRef);
	
	[newImg release];

	success = [tiffData_PackBits writeToFile:tiffPath atomically:NO];
	assert(success);

#endif // EMIT_RLE_TIFF
	
	
	// Write out a CRC checksum of the raw data, this is much quicker to compare
	// to than the data itself.
	
	int crc32 = [rawBytes crc32];

	crcs[frameIndex] = crc32;

	// free up resources

	[img release];
	[imageView release];
	[cgBuffer release];
	
    [pool drain];
	
	return 0;
}

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

// search through frames 0 to N-2 looking for a duplicate frame. This
// method is invoked after we know that the frame is not a duplicate
// of the one just before it.

int search_repeated_frame(int frameIndex) {
	int i;
	int startIndex = 0;
	int endIndex = frameIndex - 2;
	
	for (i = startIndex; i <= endIndex; i++) {
		//fprintf(stdout, "comparing frame %d to %d\n", frameIndex, i);

		int cmp = compare_frames(frameIndex, i);
		
		if (cmp == 0) {
			return i;
		}
	}
	
	return -1;
}

// Return 0 if the patch data is exactly the same as the
// patch data from an earlier diff operation.

int compare_patches(int patchIndex, NSData *patchData) {
	assert(patchIndex >= 0);
	assert(patchData != nil);
	assert([patchData length] > 0);

	int crc = all_patch_crcs[patchIndex];

	if (crc == 0)
		return 1;

	int crc_patchData = [patchData crc32];

	if (crc_patchData != crc)
		return 2;

	// if the crcs do match, it is still possible that
	// the two patches are not exactly the same. Need to
	// pull in the binary data and compare it in this
	// case to be sure that the patches actually match.
	
	NSString *repeated_patch_filename = [all_patch_filenames objectAtIndex:patchIndex];
	NSData *repeated_patch_data_obj = [NSData dataWithContentsOfFile:repeated_patch_filename];

	if ([repeated_patch_data_obj isEqualToData:patchData]) {
		return 0;
	} else {
		return 1;
	}
}

// search through all the patches to see if patch data exactly matches
// one or more other patches in the movie. The patch data always
// matches itself, so ignore that match. Also ignore patches
// of length zero. Return the frame index for the first other match
// found. When no other patches exactly match the given patch
// data, -1 is returned to indicate that this patch appears only
// once in the archive.

int search_repeated_patch_data(int frameIndex, NSData *patchData) {
	int i;
	int lastIndex = [all_patch_filenames count];

	int firstMatchingIndex = -1;
	int secondMatchingIndex = -1;

	assert(frameIndex > 0);

	for (i = 1; i < lastIndex; i++) {
//		fprintf(stdout, "comparing patch to patch index %d\n", i);

		int cmp = compare_patches(i, patchData);

		if (cmp == 0) {
			if (firstMatchingIndex == -1) {
				firstMatchingIndex = i;
			} else {
				if (secondMatchingIndex == -1) {
					secondMatchingIndex = i;
				}
			}
		}
	}

	if (secondMatchingIndex == -1)
		return -1;
	else
		return firstMatchingIndex;
}

// Add a record for a patch generated by computing the
// delta between two frames.

void add_patch(NSString *patchFilename, NSData *patchData)
{
	int count = [all_patch_filenames count];

	if (count == 0) {
		// Add empty filename for initial keyframe
		[all_patch_filenames addObject:@""];
		all_patch_crcs[count] = 0;
		count = 1;
	}

	[all_patch_filenames addObject:patchFilename];

	if ([patchData length] == 0) {
		all_patch_crcs[count] = 0;
	} else {
		all_patch_crcs[count] = [patchData crc32];
		assert(all_patch_crcs[count] != 0);
	}

	return;
}

// Lookup patch filename/data for a given index. The caller
// should avoid invoking this method for patchIndex
// 0 since the first frame is always a keyframe.

NSString* get_patch_filename(NSUInteger patchIndex) {
	assert(patchIndex > 0);
	
	NSString *patchPath = [all_patch_filenames objectAtIndex:patchIndex];
	assert(patchPath);
	assert([patchPath length] > 0);

	return [patchPath lastPathComponent];
}

NSData* get_patch_data(NSUInteger patchIndex) {
	assert(patchIndex > 0);

	NSString *patchPath = [all_patch_filenames objectAtIndex:patchIndex];
	assert(patchPath);
	assert([patchPath length] > 0);

	NSData *patchData = [NSData dataWithContentsOfFile:patchPath];
	assert(patchData);

	return patchData;
}

// Extract all the frames of movie data from an archive file into
// the current directory.

void extract_movie_frames(char *archive_filename) {
	BOOL worked;

	if (raw_directory == nil) {
		raw_directory = [NSString stringWithFormat:@"RAW"];
		[[NSFileManager defaultManager] createDirectoryAtPath:raw_directory attributes:nil];
	}
	if (rle_directory == nil) {
		rle_directory = [NSString stringWithFormat:@"RLE"];
		[[NSFileManager defaultManager] createDirectoryAtPath:rle_directory attributes:nil];
	}

#ifdef EMIT_RLE_TIFF
	if (tiff_directory == nil) {
		tiff_directory = [NSString stringWithFormat:@"TIFF"];
		[[NSFileManager defaultManager] createDirectoryAtPath:tiff_directory attributes:nil];
	}
#endif // EMIT_RLE_TIFF
	
#ifdef EMIT_PNG
	if (png_directory == nil) {
		png_directory = [NSString stringWithFormat:@"PNG"];
		[[NSFileManager defaultManager] createDirectoryAtPath:png_directory attributes:nil];
	}
#endif // EMIT_PNG

	if (delta_directory == nil) {
		delta_directory = [NSString stringWithFormat:@"DELTA"];
		[[NSFileManager defaultManager] createDirectoryAtPath:delta_directory attributes:nil];
	}

	NSString *archivePath = [[NSString alloc] initWithUTF8String:archive_filename];

	// If archive file is in another directory, copy it to the current directory
	// before decompressing.

	NSString *archiveTail = [archivePath lastPathComponent];
	if (![[NSFileManager defaultManager] fileExistsAtPath:archiveTail]) {
		[[NSFileManager defaultManager] copyItemAtPath:archivePath toPath:archiveTail error:nil];
	}

	NSString *tmpPath = [NSData uncompressBZ2FileToTmpFile:archivePath];
	assert(tmpPath);
	NSString *uncompressedFilename = [tmpPath lastPathComponent];
	
	[[NSFileManager defaultManager] copyItemAtPath:tmpPath toPath:uncompressedFilename error:nil];
	[[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];

	NSString *extractedArchive = uncompressedFilename;

	NSLog([NSString stringWithFormat:@"decompressed %@", extractedArchive]);

	// Create archive object and extract all the archive entries into the
	// curret directory. Fill in repeated frames with the actual data.

	NSString *archiveFilename = extractedArchive;
	
	NSRange lastDot = [archiveFilename rangeOfString:@"." options:NSBackwardsSearch];

	if (lastDot.location == NSNotFound) {
		movie_prefix = archiveFilename;
	} else {
		NSRange beforeDotRange;
		beforeDotRange.location = 0;
		beforeDotRange.length = lastDot.location;
		movie_prefix = [archiveFilename substringWithRange:beforeDotRange];
	}
	
	EasyArchive *archive = [[EasyArchive alloc] initWithFilename:archiveFilename];

	archive.validateMD5Header = TRUE;
	worked = [archive openForReading];
	if (!worked) {
		fprintf(stderr, "could not find archive file \"%s\"\n", [archiveFilename UTF8String]);
		exit(1);
	}
	assert(worked);

	MovieArchive *movieArchive = [[MovieArchive alloc] initWithArchive:archive];

	NSData *frameData;

	// Read all entries

	while ((frameData = [movieArchive nextFrameData]) != nil) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

		// Write the .rle data for this frame

		NSString *write_rleFilename = [NSString stringWithFormat:@"F%@.rle", format_frame_number(movieArchive.frameIndex+1)];

		NSString *write_rlePath = [rle_directory stringByAppendingPathComponent:write_rleFilename];

		[frameData writeToFile:write_rlePath atomically:FALSE];

		NSLog([NSString stringWithFormat:@"wrote %@", write_rlePath]);

		[movieArchive updateOutputMD5:frameData];

		// Convert rle encoded data into RAW data

		NSString *write_rawFilename = [NSString stringWithFormat:@"F%@.raw", format_frame_number(movieArchive.frameIndex+1)];
		NSString *write_rawPath = [raw_directory stringByAppendingPathComponent:write_rawFilename];

		CGFrameBuffer *cgBuffer = [[CGFrameBuffer alloc] initWithDimensions:movieArchive.width height:movieArchive.height];

		[cgBuffer runLengthDecode:frameData numEncodedBytes:[frameData length]];

		NSData *rawBytes = [cgBuffer copyData];

		[rawBytes writeToFile:write_rawPath atomically:FALSE];

		// Create UIImage from RAW data

		CGImageRef cgImageRef = [cgBuffer createCGImageRef];
		
		NSBitmapImageRep *newImg = [[NSBitmapImageRep alloc] initWithCGImage:cgImageRef];

		CGImageRelease(cgImageRef);

#ifdef EMIT_RLE_TIFF

		// Write out a tiff in pack bits format
		
		NSString *write_tiffFilename = [NSString stringWithFormat:@"F%@%@",
										   format_frame_number(movieArchive.frameIndex+1),
										   @"_PB.tiff"];

		NSString *write_tiffPath = [tiff_directory stringByAppendingPathComponent:write_tiffFilename];

		NSData *write_tiffData = [newImg TIFFRepresentationUsingCompression:NSTIFFCompressionPackBits factor:0.0];
		
		[write_tiffData writeToFile:write_tiffPath atomically:FALSE];

#endif // EMIT_RLE_TIFF


#ifdef EMIT_PNG
		NSString *write_pngFilename = [NSString stringWithFormat:@"F%@%@",
								 format_frame_number(movieArchive.frameIndex+1),
								 @".png"];

		NSString *write_pngPath = [png_directory stringByAppendingPathComponent:write_pngFilename];

		NSData *write_pngData = [newImg representationUsingType: NSPNGFileType properties: nil];
		[write_pngData writeToFile:write_pngPath atomically:NO];

#endif // EMIT_PNG

		[newImg release];

		[pool release];
	}

	// Verify MD5 for the whole archive

	[archive readLastEntry];

	// If there was no checksum for the archive, then print that

	if (!archive.hasMD5Header) {
		fprintf(stdout, "archive has no MD5 header\n");
		fflush(stdout);		
	} else {
		// Print result of MD5 header check

		fprintf(stdout, "archive.isMD5Valid is %d\n", archive.isMD5Valid);
		fflush(stdout);		
	}

	// Verify the RLE output data MD5 contained in the movie header.
	// The MD5 for the archive checks that the data contained in
	// the archive was not corrupted, but this MD5 is for the original
	// RLE encoded data. Generate an MD5 from the RLE encoded bytes
	// we extrated via the patching process and use those bytes
	// to generate a MD5 to compare against.

	BOOL outputValidated = [movieArchive validateOutputMD5];
	fprintf(stdout, "RLE output MD5 validated is %d\n", outputValidated);
	fflush(stdout);


	[archive close];
	[archive release];
	[movieArchive release];
	
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

// Given a set of extracted RAW files, create an image sequence archive
// in the current directory. Data for each of the movie frames has been
// extracted to file once this method is called.

void create_movie_archive() {
	NSMutableString *report = [NSMutableString stringWithCapacity:3000];
	int numUniqueFrames = 0;

	BOOL emitUNIQUE = TRUE;
	if (emitUNIQUE) {
		[[NSFileManager defaultManager] createDirectoryAtPath:@"UNIQUE" attributes:nil];	
	}

	BOOL emitZLIB = TRUE;
	NSString *zlib_directory;
	if (emitZLIB) {
		zlib_directory = @"ZLIB";
		[[NSFileManager defaultManager] createDirectoryAtPath:zlib_directory attributes:nil];
	}

	// Iterate through the movie data examining and comparing the data to
	// discover repeated frames and duplicate frames.

	NSString *moviePathPrefix = @"MOVIE";
	[[NSFileManager defaultManager] createDirectoryAtPath:moviePathPrefix attributes:nil];

	int frameIndex = 1;
	int numFrames = [rle_filenames count];

	for ( ; frameIndex < numFrames; frameIndex++) {
		NSAutoreleasePool *loop_pool = [[NSAutoreleasePool alloc] init];

		int is_dup_of_prev_frame = is_duplicate_of_previous_frame(frameIndex);
		
		int repeated_frame_index = -1;
		
		// If this frame is not a duplicate of the previous frame, but it does duplicate
		// an earlier frame, then indicate that.
		
		if (!is_dup_of_prev_frame) {
			repeated_frame_index = search_repeated_frame(frameIndex);
		}
		
		if (is_dup_of_prev_frame) {
			// Write a zero length file indicating that this frame is an exact
			// duplicate of the previous frame. For example: "F0002.dup"
			// indicates that frame 2 is an exact duplicate of frame 1.

			NSString *dup_filename = [NSString stringWithFormat:@"%@%@.dup", @"F", format_frame_number(frameIndex+1)];
			NSData *dupData = [NSData data];
			
			NSString *path = [moviePathPrefix stringByAppendingPathComponent:dup_filename];
			[dupData writeToFile:path atomically:FALSE];

			if (emitZLIB) {
				// Zlib compress the RLE data and write to ZLIB directory
				
				NSString *zlib_path = [zlib_directory stringByAppendingPathComponent:dup_filename];
				
				[dupData writeToFile:zlib_path atomically:FALSE];
			}				
		} else if (repeated_frame_index != -1) {
			// Write a zero length file indicating that this frame repeats a frame
			// from earlier in the animation. For example, "F0003_0001.rep"
			// indicates that frame 3 repeats frame 1.

			NSString *repeat_filename = [NSString stringWithFormat:@"%@%@_%@.rep",
										 @"F",
										 format_frame_number(frameIndex+1),
										 format_frame_number(repeated_frame_index+1)];
			NSData *repeatData = [NSData data];

			NSString *path = [moviePathPrefix stringByAppendingPathComponent:repeat_filename];
			[repeatData writeToFile:path atomically:FALSE];

			if (emitZLIB) {
				// Zlib compress the RLE data and write to ZLIB directory
				
				NSString *zlib_path = [zlib_directory stringByAppendingPathComponent:repeat_filename];
				
				[repeatData writeToFile:zlib_path atomically:FALSE];
			}			
		} else {
			// Not a repeated frame and not a duplicate of an earlier frame.

			NSString *rlePath = [rle_filenames objectAtIndex:frameIndex];
			NSString *rleFilename = [rlePath lastPathComponent];

			NSData *orig_rle_data = [NSData dataWithContentsOfFile:rlePath];

			if (emitZLIB) {
				// Zlib compress the RLE data and write to ZLIB directory

				NSString *zlib_path = [NSString stringWithFormat:@"%@/%@.zlib", zlib_directory, rleFilename];
				
				NSData *zibData = [orig_rle_data zlibDeflate];

				[zibData writeToFile:zlib_path atomically:FALSE];				
			}			
		}
		
		
		// Emit report data
		NSString *dupFrameMsg = @"";
		
		// If this frame is not a duplicate of the previous frame, but it does duplicate
		// an earlier frame, then indicate that.
		
		if (!is_dup_of_prev_frame) {
			if (repeated_frame_index != -1) {
				dupFrameMsg = [NSString stringWithFormat:@"(repeats frame %d)", repeated_frame_index+1];
			}
		}

		// Make a copy of the unique frames in UNIQUE/
		// Note that the first frame is always unique

		if (!is_dup_of_prev_frame && repeated_frame_index == -1 && emitUNIQUE) {
			numUniqueFrames++;
			
			NSString *rlePath = [rle_filenames objectAtIndex:frameIndex];
			NSString *rleFilename = [rlePath lastPathComponent];

			NSString *uniquePath = [NSString stringWithFormat:@"UNIQUE/%@", rleFilename];
			
			[[NSFileManager defaultManager] copyItemAtPath:rlePath toPath:uniquePath error:nil];
		}

		[report appendFormat:@"Frame %d: is dup prev frame %d %@\n",
		 frameIndex+1, is_dup_of_prev_frame+1, dupFrameMsg];

		[loop_pool release];
	} // end report for loop


	// Loop over each frame comparing one frame to the next and generating
	// delta patches that transform one frame to the next. We know that
	// the first frame is always a keyframe, so start generating deltas
	// from frame 1 to frame 2.

	frameIndex = 1;

	for ( ; frameIndex < numFrames; frameIndex++) {
		NSAutoreleasePool *loop_pool = [[NSAutoreleasePool alloc] init];

		int is_dup_of_prev_frame = is_duplicate_of_previous_frame(frameIndex);
		
#ifdef NO_DUPLICATE_FRAMES
		is_dup_of_prev_frame = FALSE;
#endif
		
		if (is_dup_of_prev_frame)
		{
			// Write a zero length patch file

			NSString *dup_filename = [NSString stringWithFormat:@"F%@.dup",
									  format_frame_number(frameIndex+1)];
			NSData *dupData = [NSData data];

			NSString *path = [moviePathPrefix stringByAppendingPathComponent:dup_filename];

			[dupData writeToFile:path atomically:FALSE];

			NSString *delta_filename = [NSString stringWithFormat:@"F%@.patch",
										format_frame_number(frameIndex+1)];

			NSString *delta_path = [delta_directory stringByAppendingPathComponent:delta_filename];

			[dupData writeToFile:delta_path atomically:FALSE];			

			add_patch(delta_path, dupData);

			NSLog([NSString stringWithFormat:@"wrote dup patch file %@", dup_filename]);
		} else {
			// This frame is not an exact duplicate of the previous frame, so create
			// a delta. A delta between frames is typically much smaller than
			// the frame data itself. This logic will check for the case where a
			// delta is exactly the same as a delta computer earlier.
			
			NSString *rlePath = [rle_filenames objectAtIndex:frameIndex];
			NSUInteger prev_frameIndex = frameIndex-1;
			NSString *prev_rlePath = [rle_filenames objectAtIndex:prev_frameIndex];

			NSString *delta_filename = [NSString stringWithFormat:@"F%@.patch",
										format_frame_number(frameIndex+1)];
			NSString *delta_path = [delta_directory stringByAppendingPathComponent:delta_filename];
			
			NSData *delta_data = exec_diff_or_patch(prev_rlePath, rlePath, delta_path, 0);

			[delta_data writeToFile:delta_path atomically:FALSE];

			// Double check that this patch actually creates the same output file when applied
			// to the original data.
			
			NSString *prev_rleFilename = [prev_rlePath lastPathComponent];
			NSString *validate_prev_rleFilename = [NSString stringWithFormat:@"validate_%@", prev_rleFilename];
			[[NSFileManager defaultManager] copyItemAtPath:prev_rlePath toPath:validate_prev_rleFilename error:nil];
			
			NSString *rleFilename = [rlePath lastPathComponent];
			NSString *validate_rleFilename = [NSString stringWithFormat:@"validate_%@", rleFilename];
			[[NSFileManager defaultManager] copyItemAtPath:rlePath toPath:validate_rleFilename error:nil];
			
			NSString *validate_deltaFilename = [NSString stringWithFormat:@"validate_%@", delta_filename];
			[delta_data writeToFile:validate_deltaFilename atomically:FALSE];
			
			NSData *patched_data = exec_diff_or_patch(validate_prev_rleFilename, validate_rleFilename, validate_deltaFilename, 1);
			assert(patched_data != nil);
			
			NSData *orig_rle_data = [NSData dataWithContentsOfFile:rlePath];
			
			assert([patched_data isEqualToData:orig_rle_data] == TRUE);
			
			// Remove temp files after data passed validity check, if this assert crashed out
			// then the temp file are left on disk to aid in debugging.
			
			[[NSFileManager defaultManager] removeItemAtPath:validate_prev_rleFilename error:nil];
			[[NSFileManager defaultManager] removeItemAtPath:validate_rleFilename error:nil];
			[[NSFileManager defaultManager] removeItemAtPath:validate_deltaFilename error:nil];

			// Copy patch data to MOVIE

			NSString *movie_delta_path = [NSString stringWithFormat:@"MOVIE/%@", delta_filename];

			[delta_data writeToFile:movie_delta_path atomically:FALSE];

			NSLog([NSString stringWithFormat:@"wrote patch file %@ (%d bytes)", delta_filename, [delta_data length]]);

			add_patch(delta_path, delta_data);
		}
		
		[loop_pool release];
	} // end patch create for loop


	// All frame and all deltas between frames have been saved to files. Loop over the
	// generated data and save the results to an archive. It is important to calculate
	// all the deltas before writing to an archive so that we can tell when a patch
	// exactly matches the same patch later in the archive. The special case of a
	// patch that is repeated later in the archive needs to be handled differently
	// that a patch that only appears once so that the archive reader logic does
	// not need to have access to all generated patch data.

	NSString *archiveFilename = [NSString stringWithFormat:@"%@.bar", movie_prefix];
	NSString *flatFilename = [NSString stringWithFormat:@"%@.flat", movie_prefix];
	
	EasyArchive *archive = [[EasyArchive alloc] initWithFilename:archiveFilename];
	
	archive.writeMD5Header = TRUE;
	BOOL worked = [archive openForWriting];
	assert(worked);
	
	// The first frame is always the key frame. It is stored as RLE encoded
	// data. Also, before adding the first frame, create a special HEADER
	// entry named "F0000.hdr" that contains movie wide information like
	// width and height. Also create a file name "F0001.rle" that
	// corresponds to the key frame.

	NSString *headerFilename = [NSString stringWithFormat:@"F%@.hdr", format_frame_number(0)];
	
	// Create an array that holds all of the RLE encoded data. A large
	// md5 is calculated from the RLE encoded data and then used to
	// verify the RLE output after the patches have been applied.

// FIXME: For a really large movie, this might run out of memory. Rework the
// MD5 calculation so that it can be done one file at a time.

	NSAutoreleasePool *all_rle_pool = [[NSAutoreleasePool alloc] init];
	NSMutableArray *allRLEDataObjs = [NSMutableArray arrayWithCapacity:1024];

	for (NSString *rle_path in rle_filenames) {
		NSData *rle_data = [NSData dataWithContentsOfFile:rle_path];
		[allRLEDataObjs addObject:rle_data];
	}
	NSData *rleMD5Data = [MovieArchive calcMD5ForData:allRLEDataObjs];
	[rleMD5Data retain];

	[all_rle_pool release];
	all_rle_pool = [[NSAutoreleasePool alloc] init];

	// Calculate sum and std dev for keyframe and patch data sizes

	int *rle_buffer_sizes = malloc(sizeof(int) * numFrames);
	int *patch_buffer_sizes = malloc(sizeof(int) * (numFrames-1));

	int i = 0;

	for (NSString *rle_path in rle_filenames) {
		NSData *rle_data = [NSData dataWithContentsOfFile:rle_path];

		rle_buffer_sizes[i] = [rle_data length];

//		NSLog([NSString stringWithFormat:@"rle_buffer_sizes[%d] = %d", i, rle_buffer_sizes[i]]);
		i++;
	}

	[all_rle_pool release];
	all_rle_pool = [[NSAutoreleasePool alloc] init];

	i = 0;

	for ( frameIndex = 1 ; frameIndex < numFrames; frameIndex++) {
		NSData *patchData = get_patch_data(frameIndex);

		patch_buffer_sizes[i] = [patchData length];

//		NSLog([NSString stringWithFormat:@"patch_buffer_sizes[%d] = %d", i, patch_buffer_sizes[i]]);
		i++;
	}

	float rle_stddev, rle_mean;
	int rle_max_buffer_size;
	calc_std_dev(rle_buffer_sizes, numFrames, &rle_stddev, &rle_mean, &rle_max_buffer_size);

	float patch_stddev, patch_mean;
	int patch_max_buffer_size;
	calc_std_dev(patch_buffer_sizes, numFrames-1, &patch_stddev, &patch_mean, &patch_max_buffer_size);

	free(rle_buffer_sizes);
	free(patch_buffer_sizes);

	NSLog([NSString stringWithFormat:@"rle_mean = %f", rle_mean]);
	NSLog([NSString stringWithFormat:@"rle_stddev = %f", rle_stddev]);

	NSLog([NSString stringWithFormat:@"patch_mean = %f", patch_mean]);
	NSLog([NSString stringWithFormat:@"patch_stddev = %f", patch_stddev]);	

	// Compute the difference between the largest buffer size
	// and (mean + stddev). If the largest buffer size is not
	// much larger then use the largest buffer size then
	// use the largest buffer size. If the largest buffer
	// size is significantly larger, then use mean+2*stddev.

	// frame buffers

	int rle_buffer_size;

	int reasonable_buffer_size_delta = 1024 * 200;

	int rle_buffer_size_one_stddevs = rle_mean + rle_stddev;
	int rle_buffer_size_two_stddevs = rle_mean + (rle_stddev * 2);
	int rle_delta_between_max_and_stddev = rle_max_buffer_size - rle_buffer_size_one_stddevs;

	if (rle_delta_between_max_and_stddev < reasonable_buffer_size_delta) {
		NSLog([NSString stringWithFormat:@"max frame buffer size %d is not much larger than mean + stddev size %d",
			   rle_max_buffer_size, rle_buffer_size_one_stddevs]);

		rle_buffer_size = rle_max_buffer_size;
	} else {
		NSLog([NSString stringWithFormat:@"max frame buffer size %d is significantly larger mean + stddev size %d",
			   rle_max_buffer_size, rle_buffer_size_two_stddevs]);

		rle_buffer_size = rle_buffer_size_two_stddevs;
	}

	// patch buffers

	int patch_buffer_size;
	int patch_buffer_size_one_stddevs = patch_mean + patch_stddev;
	int patch_buffer_size_two_stddevs = patch_mean + (patch_stddev * 2);
	int patch_delta_between_max_and_stddev = patch_max_buffer_size - patch_buffer_size_one_stddevs;

	if (patch_delta_between_max_and_stddev < reasonable_buffer_size_delta) {
		NSLog([NSString stringWithFormat:@"max patch buffer size %d is not much larger than mean + stddev size %d",
			   patch_max_buffer_size, patch_buffer_size_one_stddevs]);
	
		patch_buffer_size = patch_max_buffer_size;
	} else {
		NSLog([NSString stringWithFormat:@"max patch buffer size %d is significantly larger than mean + stddev size %d",
			   patch_max_buffer_size, patch_buffer_size_one_stddevs]);
		
		patch_buffer_size = patch_buffer_size_two_stddevs;
	}

	NSLog([NSString stringWithFormat:@"standard rle_buffer_size = %d", rle_buffer_size]);
	NSLog([NSString stringWithFormat:@"standard patch_buffer_size = %d", patch_buffer_size]);

	uint32_t rle_buffer_size_num_words = (rle_buffer_size / 4) + 1;
	uint32_t patch_buffer_size_num_words = (patch_buffer_size / 4) + 1;

	NSData *headerData = [MovieArchive formatMovieHeaderData:_movieDimensions
												  rleMD5Data:rleMD5Data
										 patchBufferNumWords:patch_buffer_size_num_words
										 frameBufferNumWords:rle_buffer_size_num_words];

	NSLog([NSString stringWithFormat:@"encoded rle_buffer_size as %d words", rle_buffer_size_num_words]);
	NSLog([NSString stringWithFormat:@"encoded patch_buffer_size as %d words", patch_buffer_size_num_words]);

	[rleMD5Data release];
	[headerData retain];
	[all_rle_pool release];
	[headerData autorelease];

	[archive writeEntry:headerFilename entryData:headerData];
	NSLog([NSString stringWithFormat:@"added archive entry %@", headerFilename]);
	NSString *headerPath = [moviePathPrefix stringByAppendingPathComponent:headerFilename];
	[headerData writeToFile:headerPath atomically:FALSE];
	
	frameIndex = 0;
	NSString *rleFilename = [rle_filenames objectAtIndex:frameIndex];
	NSData *rle_data = [NSData dataWithContentsOfFile:rleFilename];
	NSString *frameFilename = [NSString stringWithFormat:@"F%@.rle", format_frame_number(frameIndex+1)];
	NSString *keyframePath = [moviePathPrefix stringByAppendingPathComponent:frameFilename];
	[rle_data writeToFile:keyframePath atomically:FALSE];

	[archive writeEntry:frameFilename entryData:rle_data];
	NSLog([NSString stringWithFormat:@"added archive entry %@", frameFilename]);

	frameIndex++;

	for ( ; frameIndex < numFrames; frameIndex++) {
		NSAutoreleasePool *loop_pool = [[NSAutoreleasePool alloc] init];

		NSString *entryFilename;
		NSData *entryData;

		NSString *patchFilename = get_patch_filename(frameIndex);
		NSData *patchData = get_patch_data(frameIndex);

		NSLog([NSString stringWithFormat:@"examining patch %@ (%d bytes)", patchFilename, [patchData length]]);
		
		BOOL is_dup_of_prev_frame = FALSE;

		if ([patchData length] == 0) {
			is_dup_of_prev_frame = TRUE;
		}

#ifdef NO_DUPLICATE_FRAMES
		is_dup_of_prev_frame = FALSE;
#endif

		if (is_dup_of_prev_frame)
		{
			// When a zero length patch is found, it indicates that the current
			// frame is exactly the same as the previous frame. For example:
			// "F0002.dup" indicates that frame 2 is an exact duplicate of frame 1.
			// The decoder can take advantage of a significant optimization by
			// simply not updating the display when the a duplicate frame is
			// found. Emit a dup entry so that the decoder knows when the use
			// this optimization.

			patchFilename = [NSString stringWithFormat:@"F%@.dup",
							 format_frame_number(frameIndex+1)];

			entryFilename = patchFilename;
			entryData = patchData;
		} else if ([patchData length] == 0) {
			// No delta data, write a regular patch file like "F0001.patch"
			// so that the decoder does not optimize the duplicated frame.

			entryFilename = patchFilename;
			entryData = patchData;
		} else {
			// Non-zero length patch. If the patch is used more than once
			// then emit with a special entry name to indicate that.
			// A patch that is applied more than once might be named
			// "F0001.rpatch" to indicate that it is a repeated patch.
			// When a repeated patch is applied, it might be named
			// "F0002.rapatch" to indicate that it is a repeated
			// application of a patch. This logic is important because
			// it means the decoder need only retain patch data for
			// patches that will be applied again. Otherwise, the
			// decoder would need to retain all the patches.

			int match_patch_index = search_repeated_patch_data(frameIndex, patchData);

			if (match_patch_index == -1) {
				// This patch is unique, emit with normal patch filename.
				// Check for the case where the patch is actually larger
				// than the RLE encoded data for the frame. Emit a keyframe
				// in that case. This case is only checked when the patch
				// is unique since a repeating patch that is larger than
				// the RLE size could be repeated and that could save
				// space in the archive.

				NSString *rlePath = [rle_filenames objectAtIndex:frameIndex];
				NSData *rleData = [NSData dataWithContentsOfFile:rlePath];
				assert(rleData);
				assert([rleData length] > 0);				

				if ([patchData length] >= [rleData length]) {
					// Emit a keyframe instead of a patch

					entryFilename = [rlePath lastPathComponent];
					entryData = rleData = [NSData dataWithContentsOfFile:rlePath];			
				} else {
					entryFilename = patchFilename;
					entryData = patchData;
				}
			} else {
				// This patch appears more than once in the archive, determine
				// if this is the first occurrence of the repeated patch.
				// The first time a repeated patch is seen, it could be named
				// "F0022.rpatch". The second time a repeated patch is
				// seen it is named "F0044_1.rapatch". The "_1" suffix indicates
				// an integer index that identifies the repeated patch. If
				// the same patch is seen again, it might be named "F0048_1.repatch".

				if (match_patch_index == frameIndex) {
					patchFilename = [NSString stringWithFormat:@"F%@.rpatch",
									 format_frame_number(frameIndex+1)];

					NSUInteger objectIndex = [repeated_patch_data indexOfObject:patchData];
					assert(objectIndex == NSNotFound);

					[repeated_patch_data addObject:patchData];
				} else {
					// Not the first time a repeated patch is seen, calculate
					// a repeat table offset for the patch.

					NSUInteger objectIndex = [repeated_patch_data indexOfObject:patchData];
					assert(objectIndex != NSNotFound);

					patchFilename = [NSString stringWithFormat:@"F%@_%d.rapatch",
									 format_frame_number(frameIndex+1),
									 objectIndex+1];

					patchData = [NSData data];
				}

				entryFilename = patchFilename;
				entryData = patchData;
			}
		}

		[archive writeEntry:entryFilename entryData:entryData];

		NSLog([NSString stringWithFormat:@"added archive entry %@ (%d bytes)", entryFilename, [entryData length]]);

		[loop_pool release];
	} // end archive write for loop

	[archive wroteLastEntry];
	[archive close];
	[archive release];

	// use bzip2 library to compress patch archive, this will find common blocks
	// in deltas and compress them significantly

	NSString *compressedArchiveFilename = [NSString stringWithFormat:@"%@.bz2", archiveFilename];

	NSLog([NSString stringWithFormat:@"compressing %@", compressedArchiveFilename]);

	worked = run_bzip2(compressedArchiveFilename, archiveFilename, FALSE);
	assert(worked);

	// Print out the filename and how many K bytes it is
	
	NSData *archiveData = [NSData dataWithContentsOfFile:archiveFilename];
	NSData *archiveBzipData = [NSData dataWithContentsOfFile:compressedArchiveFilename];
	
	int archiveKBytes = ([archiveData length] / 1000);
	int archiveBzipKBytes = ([archiveBzipData length] / 1000);
	
	printf("wrote %s (%d K)\n", [archiveFilename UTF8String], archiveKBytes);
	printf("wrote %s (%d K)\n", [compressedArchiveFilename UTF8String], archiveBzipKBytes);

	// Flatten the generated archive to make sure it works as expected

	archive = [[EasyArchive alloc] initWithFilename:archiveFilename];

	worked = [archive openForReading];
	assert(worked);

	MovieArchive *mArchive = [[MovieArchive alloc] initWithArchive:archive];

	NSLog(@"about to flatten archive");

	worked = [FlatMovieFile flattenMovie:mArchive flatMoviePath:flatFilename];
	assert(worked);

	NSLog(@"done with flatten archive, validating");

	FlatMovieFile *flatFile = [[FlatMovieFile alloc] init];
	
	worked = [flatFile validateFlattenedMovie:mArchive flatMoviePath:flatFilename];
	assert(worked);

	[flatFile dealloc];

	NSLog(@"validated");
	
	[mArchive release];
	[archive release];

	// Compress .flat file to .flat.bz2

	NSString *flatBZFile = [NSString stringWithFormat:@"%@.bz2", flatFilename];

	worked = [NSData compressFileToBZ2File:flatFilename bzPath:flatBZFile];
	assert(worked);

	NSLog([NSString stringWithFormat:@"wrote %@", flatBZFile]);
	
	// Emit report data

	[report appendFormat:@"Found %d unique frames out of %d, %d duplicates\n",
	 numUniqueFrames, numFrames, (numFrames - numUniqueFrames)];
	
	NSData * reportData = [NSData dataWithBytes:[report UTF8String] length:[report length]];
	
	[reportData writeToFile:@"report.txt" atomically:FALSE];		
		
}

int main (int argc, const char * argv[]) {
  NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	crcs = NULL;

	if (argc == 3 && strcmp(argv[1], "-extract") == 0) {
		// Extract movie frames from an existing archive

		extract_movie_frames((char *)argv[2]);
	} else {
		// Create a new movie archive from existing frames

		int numFrames = (argc - 1);
		int frameIndex = 0;

		crcs = malloc(sizeof(NSUInteger) * numFrames);
		all_patch_crcs = malloc(sizeof(NSUInteger) * numFrames);
		src_filenames = [NSMutableArray arrayWithCapacity:numFrames];
		raw_filenames = [NSMutableArray arrayWithCapacity:numFrames];
		rle_filenames = [NSMutableArray arrayWithCapacity:numFrames];
		all_patch_filenames = [NSMutableArray arrayWithCapacity:numFrames];
		repeated_patch_data = [NSMutableArray arrayWithCapacity:numFrames];		

		for (int i = 1; i < argc; i++) {
			fprintf(stdout, "loading %s\n", argv[i]);
			fflush(stdout);

			process_frame_file((char*) argv[i], frameIndex++);
		}

		create_movie_archive();
	}

	if (crcs != NULL) {
		free(crcs);
  }
  
  [pool drain];
  return 0;
}

