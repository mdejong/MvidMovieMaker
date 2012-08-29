//
//  BufferedFileHandle.m
//  EasyArchiveDemo
//
//  Created by Moses DeJong on 3/8/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "BufferedFileHandle.h"

// virtual memory page size on MacOSX and iPhone

#define BufferedFileHandleBufferSize 4096

@implementation BufferedFileHandle

@synthesize isOpen, filePath, fileName, length;

- (id) initWithFilename:(NSString*)inFilePath readonly:(BOOL)readonly
{
	self = [super init];
	if (self == nil)
		return nil;

	self.filePath = inFilePath;
	self.fileName = [inFilePath lastPathComponent];

	char *filename = (char*) [inFilePath UTF8String];
	char *mode;
	if (readonly)
		mode = "r";
	else
		mode = "w+";

	self->file = fopen(filename, mode);
	if (file == NULL) {
		return nil;
	}

	self->length = [self seekToEndOfFile];
	[self seekToFileOffset:0];

	return self;
}

- (void)dealloc {
	if (self->file != NULL)
		fclose(file);

	[filePath release];
	[fileName release];
	
    [super dealloc];
}

- (NSData*) readDataOfLength:(NSUInteger)numBytes
{
	char *buffer = malloc(numBytes);

	size_t numBytesRead = fread(buffer, 1, numBytes, self->file);

	NSData *data = [NSData dataWithBytesNoCopy:buffer length:numBytesRead];

	return data;
}

- (void) closeFile
{
	if (file != NULL) {
		fclose(file);
		self->file = NULL;
	}
}

- (void) writeData:(NSData*)data
{
	char *ptr = (char*) [data bytes];
	int numBytes = [data length];

	int numWritten = fwrite(ptr, 1, numBytes, file);

	NSAssert((numWritten == numBytes), @"did not write all bytes");
}

- (unsigned long long) offsetInFile
{
	off_t offset = ftello(file);
	return offset;
}

- (void) seekToFileOffset:(unsigned long long)offsetInFile
{
	off_t offset = offsetInFile;
	int status = fseeko(file, offset, SEEK_SET);
	NSAssert((status == 0), @"fseeko error");
}

- (unsigned long long) seekToEndOfFile
{
	int status = fseeko(file, 0, SEEK_END);
	NSAssert((status == 0), @"fseeko error");
	return [self offsetInFile];
}

- (NSData*) availableData
{
	// read all data until the end of the file

	unsigned long long remaining = length - [self offsetInFile];
	return [self readDataOfLength:remaining];
}

- (NSData *)readDataToEndOfFile
{
	return [self availableData];
}

- (void) synchronizeFile
{
	fflush(file);
}

- (void) truncateFileAtOffset:(unsigned long long)offsetInFile
{
	int fd = fileno(file);
	off_t offset = offsetInFile;
	ftruncate(fd, offset);
}

@end // class BufferedFileHandle
