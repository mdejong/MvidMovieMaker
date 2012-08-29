//
//  EasyArchive.m
//  EasyArchiveUtil
//
//  Created by Moses DeJong on 2/10/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "EasyArchive.h"

#import "BufferedFileHandle.h"
#import "NSDataFileHandle.h"

// Support Class EasyArchiveEntry

@interface EasyArchiveEntry : NSObject {
	NSString *archivePath;
	NSURL *dataURL;
}
@property (nonatomic, retain) NSString *archivePath;
@property (nonatomic, retain) NSURL *dataURL;
@end

@implementation EasyArchiveEntry

@synthesize archivePath, dataURL;

- (void)dealloc {
	[archivePath release];
	[dataURL release];
    [super dealloc];
}

@end // class EasyArchiveEntry


// Types used to access short and long values as an array of bytes

typedef union {
	unsigned short int sval;
	uint8_t buffer[2];
} shortStruct;

typedef union {
	unsigned long int lval;
	uint8_t buffer[4];
} longStruct;

@class EasyArchiveEntry;

typedef enum {
	INIT_OR_READ_WROTE_LAST_ENTRY = 0,
	OPENED_FOR_READING,
	OPENED_FOR_WRITING
} EasyArchiveOpenType;


// Main class implementation

#define EASY_ARCHIVE_HEADER_SIZE 32

@implementation EasyArchive

@synthesize archiveFilename, archiveFilenameTail, bhandle;
@synthesize writeMD5Header, validateMD5Header, isMD5Valid, hasMD5Header;
@synthesize numEntries, length;
@synthesize coder, buildFileDataOffsets, useMappedFile;

- initWithFilename:(NSString*)inFilename {
	self = [super init];
	if (self == nil)
		return nil;

	self->archiveFilename = [inFilename copy];
	self.archiveFilenameTail = [archiveFilename lastPathComponent];
//	self->handle = nil;
//	self->isOpen = FALSE;
//	self->validateMD5Header = FALSE;
//	self->isMD5Valid = FALSE;
//	self->numEntries = 0;
//	self->fileDataOffsets = NULL;
//	self.buildFileDataOffsets = nil;

	return self;
}

- (void) close
{
	if (isOpen) {
		[self wroteLastEntry];
		[bhandle closeFile];
	}

	isOpen = FALSE;
}

+ (void) truncateFileAtPath:(NSString*)inFilePath
{
	NSOutputStream *touchStream = [[NSOutputStream alloc] initToFileAtPath:inFilePath append:NO];
	[touchStream open];
	[touchStream close];
	[touchStream release];
}

- (void)dealloc {
	if (isOpen) {
		[self close];
	}

	if (fileDataOffsets != NULL)
		free(fileDataOffsets);

	[buildFileDataOffsets release];

	[archiveFilename release];
	[archiveFilenameTail release];

	[bhandle release];	
    [super dealloc];
}

- (BOOL) openForWriting
{
	if (isOpen)
		return FALSE;

	self.bhandle = [[BufferedFileHandle alloc] initWithFilename:archiveFilename readonly:FALSE];
	[bhandle release];

	self->isOpen = TRUE;
	self->openedFor = OPENED_FOR_WRITING;

	if (writeMD5Header) {
		self->hasMD5Header = TRUE;
		CC_MD5_Init(&self->ctxt);
	}

	// Write empty MD5 header at the front of the file, note that we want
	// the MD5 to be calculated as if the leading 32 bytes are zeros,
	// since the MD5 can't include the MD5 bytes in it.

	uint8_t md5_header[EASY_ARCHIVE_HEADER_SIZE];
	memset(md5_header, 0, EASY_ARCHIVE_HEADER_SIZE);

	[self _writeBytes:md5_header length:EASY_ARCHIVE_HEADER_SIZE];

	// Record file offsets as entries are written

	self.buildFileDataOffsets = [NSMutableArray arrayWithCapacity:256];

	return TRUE;
}

// Done writing entries to the archive

- (void) wroteLastEntry
{
	if (openedFor == INIT_OR_READ_WROTE_LAST_ENTRY) {
		// If this method is invoked more than once, ignore
		// addition invocations
		return;
	}	

	[self _checkDataOffsets];

	// Query total number of bytes in file

	self->length = [bhandle offsetInFile];

	// Finish calculating MD5 digest and write it back over the front of
	// the archive, if needed.

	if (writeMD5Header) {
		[bhandle seekToFileOffset:0];
		NSData *headerData = [EasyArchive _finishMD5:&self->ctxt];
		[self _writeDataIgnoreMD5:headerData];
		self->writeMD5Header = FALSE;
	}

	self->openedFor = INIT_OR_READ_WROTE_LAST_ENTRY;
}

+ (void) addToArchiveEntriesArray:(NSMutableArray*)entries
			 archivePath:(NSString*)archivePath
				 dataURL:(NSURL*)dataURL
{
	EasyArchiveEntry *entry = [[EasyArchiveEntry alloc] init];
	
	entry.archivePath = archivePath;
	entry.dataURL = dataURL;
	
	[entries addObject:entry];
	[entry release];
}

- (BOOL) addArchiveEntries:(NSArray*)inEntries
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	if ([self openForWriting] == FALSE) {
		[pool release];
		return FALSE;
	}

	// Iterate over each file path and load file
	// data into the archive file.

	for (EasyArchiveEntry *entry in inEntries) {
		NSString *entryPath = entry.archivePath;
		NSURL *entryURL = entry.dataURL;

		[self writeEntry:entryPath entryURL:entryURL];
	}

	[self wroteLastEntry];

	// Now read to read archive data back from the file channel if needed.

	[pool release];

	return TRUE;
}

- (void) writeEntry:(NSString*)entryPath entryURL:(NSURL*)entryURL
{
	NSAssert(entryPath == nil || [entryPath length] == 0, @"entry path in nil or \"\"");

	NSData *entryData = [NSData dataWithContentsOfURL:entryURL];
	NSAssert(entryData != nil, @"entry data could not be read from URL");

	[self writeEntry:entryPath entryData:entryData];
}

- (void) writeEntry:(NSString*)entryPath entryData:(NSData*)entryData
{
	if (!isOpen)
		NSAssert(FALSE, @"archive is not open");

	NSAssert(entryPath != nil || [entryPath length] >= 0, @"entry path in nil or \"\"");
	NSAssert(entryData != nil, @"entry data in nil");

	// Allocate a pool at the start of a write operation since
	// we don't want a lot of memory to get allocated but not
	// released in a loop of writeEntry calls.

	NSAutoreleasePool *entry_pool = [[NSAutoreleasePool alloc] init];

	// Write FILENAME_LENGTH as 2 byte unsigned integer (big endian)

	char *utf8Str = (char *) [entryPath UTF8String];
	unsigned short int utf8Str_length = strlen(utf8Str);
	
	shortStruct sb;
	sb.sval = htons(utf8Str_length);
	
	[self _writeBytes:sb.buffer length:2];
	
	// Write FILENAME as UTF8 encoded string

	[self _writeBytes:(unsigned char *)utf8Str length:utf8Str_length];

	// Query the file position before writing the file size so
	// as to maintain an quick index to support lookup of entries
	// in the archive based on an integer index. It is unlikely that
	// the entry name will need to be looked up often, but the file
	// data may need to be accessed in a random fashion. The archive
	// does not support file sizes over 2 gigs.

	unsigned long long fileOffset = [bhandle offsetInFile];

	if (fileOffset > INT_MAX)
		NSAssert(FALSE, @"file offset exceeded INT_MAX");

	if (buildFileDataOffsets != nil) {
		[buildFileDataOffsets addObject:[NSNumber numberWithUnsignedInt:((NSUInteger) fileOffset)]];
	}

	// Run through entry encoder if there is one

	if (coder != nil)
		entryData = (NSData*) [(id)coder encodeEntryData:entryData];

	// Write length of file data as 32bit unsigned integer

	long long entry_length = [entryData length];
	NSAssert(entry_length <= INT_MAX, @"file size is larger than INT_MAX");

	longStruct lb;
	lb.lval = htonl((unsigned long) entry_length);

	[self _writeBytes:lb.buffer length:4];

	// Write entry data as binary

	[self _writeData:entryData];

	[entry_pool release];

	self->numEntries++;
}

- (void) _writeBytes:(uint8_t*)bytes length:(NSInteger)inLength
{
	NSData *data = [[NSData alloc] initWithBytes:bytes length:inLength];
	[self _writeData:data];
	[data release];
}

- (void) _writeData:(NSData*)data
{
	[bhandle writeData:data];

	if (writeMD5Header) {
		CC_MD5_Update(&self->ctxt, [data bytes], [data length]);
	}
}

- (void) _writeDataIgnoreMD5:(NSData*)data
{
	[bhandle writeData:data];
}

+ (NSData*) _finishMD5:(CC_MD5_CTX*)digestCtxPtr
{
//	CC_MD5_CTX *digestCtxPtr = &self->ctxt;
	unsigned char digestBytes[CC_MD5_DIGEST_LENGTH];
	char digestChars[CC_MD5_DIGEST_LENGTH * 2 + 1];

	CC_MD5_Final(digestBytes, digestCtxPtr);

	for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
		sprintf(&digestChars[2 * i], "%02x", digestBytes[i]);
	}

	NSString *digestStr = [NSString stringWithUTF8String:digestChars];
	NSData *digestData = [digestStr dataUsingEncoding:NSASCIIStringEncoding];

	NSAssert(([digestData length] == EASY_ARCHIVE_HEADER_SIZE), @"MD5 digest should be 32 bytes");

	return digestData;
}

- (NSString*) readEntryFilename
{
	if (!isOpen)
		NSAssert(FALSE, @"archive is not open");

	// Read FILENAME_LENGTH as 2 byte unsigned integer (big endian)

	NSData *filenameLengthData = [self _readData:2];
	if ([filenameLengthData length] == 0) {
		// Read EOF, all entries have now been read
		[self readLastEntry];
		return nil;
	}

	shortStruct sb;
	memcpy(sb.buffer, [filenameLengthData bytes], 2);
	int filename_len = ntohs(sb.sval);
	NSAssert(filename_len > 0, @"read zero for filename length");

	// Read FILENAME as UTF8 encoded string

	NSData *filenameData = [self _readData:filename_len];
	NSAssert([filenameData length] > 0, @"read empty filename string");

	// Add \0 at end of UTF8 string

	NSMutableData *dataWithNull = [NSMutableData dataWithCapacity:([filenameData length]+1)];
	[dataWithNull appendData:filenameData];
	[dataWithNull appendBytes:"\0" length:1];
	char *dataWithNullBytes = (char *) [dataWithNull bytes];
	NSString *filenameStr = [NSString stringWithUTF8String:dataWithNullBytes];
	NSAssert(filenameStr != nil, @"filenameStr can't be nil");
	return filenameStr;
}

- (NSData*) readEntryData
{
	if (!isOpen)
		NSAssert(FALSE, @"archive is not open");

	// Save file offset before reading file data

	if (buildFileDataOffsets != nil) {
		unsigned long long fileOffset = [bhandle offsetInFile];

		if (fileOffset > INT_MAX)
			NSAssert(FALSE, @"file offset exceeded INT_MAX");		

		[buildFileDataOffsets addObject:[NSNumber numberWithUnsignedInt:((NSUInteger) fileOffset)]];

		self->numEntries++;
	}

	// Read length of file data as 32bit unsigned integer

	NSData *data = [self _readData:4];
	if ([data length] != 4) {
		NSString *err = [NSString stringWithFormat:@"%@%d%@%d/%d%@%d",
						 @"Unable to read FILENAME_LENGTH bytes, read returned ",
						 [data length],
						 @" bytes, file offset is ",
						 (NSUInteger)[bhandle offsetInFile],
						 self->length,
						 @", isAtEOF is ",
						 [self isAtEOF]
						 ];
		NSLog(err);
		NSAssert(FALSE, err);
	}

	longStruct lb;
	memcpy(lb.buffer, [data bytes], 4);
	NSUInteger file_len = ntohl(lb.lval);

	// read the actual file data as NSData object.
	// If the length is zero do nothing.

	if (file_len == 0) {
		return [NSData data];
	}

	NSData *entryData = [self _readData:file_len];

	// Run through entry decoder if there is one

	if (coder != nil)
		entryData = (NSData*) [(id)coder decodeEntryData:entryData];

	return entryData;
}

- (BOOL) openForReading
{
	if (isOpen)
		return FALSE;

	if (useMappedFile) {
		NSData *fileData = [NSData dataWithContentsOfMappedFile:archiveFilename];
		self.bhandle = [[NSDataFileHandle alloc] initWithData:fileData];
		[bhandle release];		
	} else {
		self.bhandle = [[BufferedFileHandle alloc] initWithFilename:archiveFilename readonly:TRUE];
		[bhandle release];
	}

	self->isOpen = TRUE;
	self->openedFor = OPENED_FOR_READING;
	self->numEntries = 0;

	// Query total number of bytes in file

	self->length = bhandle.length;

	self.buildFileDataOffsets = [NSMutableArray arrayWithCapacity:256];

	if (validateMD5Header) {
		uint8_t md5_header[EASY_ARCHIVE_HEADER_SIZE];
		memset(md5_header, 0, EASY_ARCHIVE_HEADER_SIZE);

		// Read MD5 header bytes, be careful to not
		// include these bytes in the MD5.

		NSData *header = [self _readDataIgnoreMD5:EASY_ARCHIVE_HEADER_SIZE];
		NSAssert(header && [header length] == EASY_ARCHIVE_HEADER_SIZE, @"header");

		if (memcmp([header bytes], md5_header, EASY_ARCHIVE_HEADER_SIZE) == 0) {
			// Empty header, no MD5 signature found.
			self.validateMD5Header = FALSE;
			self->hasMD5Header = FALSE;
			self->isMD5Valid = FALSE;
		} else {
			// non-zero MD5 header found
			self->hasMD5Header = TRUE;
		}

		if (validateMD5Header) {
			CC_MD5_Init(&self->ctxt);

			// Pretend intial header is actually 32 bytes of zeros.
			// To actually verify the bytes later we need to calculate
			// a MD5 that does not include the MD5 itself.

			CC_MD5_Update(&self->ctxt, &md5_header, EASY_ARCHIVE_HEADER_SIZE);
		}
	}

	[bhandle seekToFileOffset:EASY_ARCHIVE_HEADER_SIZE];

	return TRUE;
}

// If building data offsets, then convert the temp array of objects
// into a C array of integers.

- (void) _checkDataOffsets
{
	if (buildFileDataOffsets != nil) {
		NSAssert(numEntries == [buildFileDataOffsets count], @"mismatched numEntries");

		if (numEntries > 0) {
			self->fileDataOffsets = (NSUInteger *) malloc(sizeof(NSInteger) * numEntries);
			NSAssert(fileDataOffsets, @"fileDataOffsets malloc failed");
		}

		NSUInteger i = 0;
		for (NSNumber *nsNum in buildFileDataOffsets) {
			fileDataOffsets[i++] = [nsNum unsignedIntValue];
		}
		self.buildFileDataOffsets = nil;
	}	
}

- (void) readLastEntry
{
	if (openedFor == INIT_OR_READ_WROTE_LAST_ENTRY) {
		// If this method is invoked more than once, ignore
		// addition invocations
		return;
	}

	// After reading EOF, the index lookup table can be created
	// and the numEntries property can be set.

	[self _checkDataOffsets];

	// Validate MD5 if a non-zero header was found and the
	// user requested validation by setting validateMD5Header

	if (validateMD5Header) {
		self.validateMD5Header = FALSE;

		NSData *md5Data = [EasyArchive _finishMD5:&self->ctxt];

		[bhandle seekToFileOffset:0];

		NSData *md5Header = [self _readDataIgnoreMD5:EASY_ARCHIVE_HEADER_SIZE];
		NSAssert(md5Header && [md5Header length] == EASY_ARCHIVE_HEADER_SIZE, @"md5Header");

		uint8_t empty_md5_header[EASY_ARCHIVE_HEADER_SIZE];
		memset(empty_md5_header, 0, EASY_ARCHIVE_HEADER_SIZE);

		// The MD5 header can't be all zeros since openForReading would have turned
		// off the validateMD5Header flag in that case.
		
		if (memcmp([md5Header bytes], empty_md5_header, EASY_ARCHIVE_HEADER_SIZE) == 0) {
			NSAssert(FALSE, @"empty header with validateMD5Header set");
		}

		// Either the bytes match exactly, or the header is not valid

		self->isMD5Valid = [md5Header isEqualToData:md5Data];

		[bhandle seekToEndOfFile];
	}

	self->openedFor = INIT_OR_READ_WROTE_LAST_ENTRY;
}

- (NSData*) _readData:(NSInteger)inLength
{
	NSData *data = [bhandle readDataOfLength:inLength];
	NSAssert(data != nil, @"readDataOfLength returned nil");

	if (validateMD5Header) {
		CC_MD5_Update(&self->ctxt, [data bytes], [data length]);
	}

	return data;
}

- (NSData*) _readDataIgnoreMD5:(NSInteger)inLength
{
	NSData *data = [bhandle readDataOfLength:inLength];
	NSAssert(data != nil, @"readDataOfLength returned nil");	
	return data;
}

- (BOOL) seekToIndex:(NSInteger)entryIndex
{
	if (entryIndex < 0 || entryIndex >= numEntries || fileDataOffsets == NULL)
		return FALSE;

	NSUInteger offset = fileDataOffsets[entryIndex];
	[bhandle seekToFileOffset:offset];

	return TRUE;
}

- (void) rewind
{
	[bhandle seekToFileOffset:EASY_ARCHIVE_HEADER_SIZE];
}

- (BOOL) isAtEOF
{
	NSUInteger fileOffset = (NSUInteger) [bhandle offsetInFile];

	return (fileOffset >= self->length);
}

- (void) setEntryEncoderDecoder:(id)coderObj
{
	if (![coderObj conformsToProtocol:@protocol(EasyArchiveEntryEncoderDecoderProtocol)]) {
		NSString *errMsg = @"Coder does not conform to EasyArchiveEntryEncoderDecoderProtocol";
		NSAssert(FALSE, errMsg); // Raise error here		
	}

	self.coder = coderObj;
}

+ (NSData*) encodeShortInt:(uint16_t)value
{
	shortStruct sb;
	sb.sval = htons(value);

	return [NSData dataWithBytes:sb.buffer length:2];
}

+ (NSData*) encodeInt:(uint32_t)value
{
	longStruct lb;
	lb.lval = htonl((unsigned long) value);

	return [NSData dataWithBytes:lb.buffer length:4];
}

+ (uint16_t) decodeShortInt:(NSData*)data
{
	shortStruct sb;
	memcpy(sb.buffer, [data bytes], 2);
	return ntohs(sb.sval);
}

+ (uint32_t) decodeInt:(NSData*)data
{
	longStruct lb;
	memcpy(lb.buffer, [data bytes], 4);
	return ntohl(lb.lval);	
}

@end // class EasyArchive
