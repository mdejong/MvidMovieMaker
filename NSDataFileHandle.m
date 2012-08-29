//
//  NSDataFileHandle.m
//  EasyArchiveDemo
//
//  Created by Moses DeJong on 3/8/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "NSDataFileHandle.h"

@implementation NSDataFileHandle

@synthesize fileData, offset, isOpen;

- (id) initWithData:(NSData*)inFileData;
{
	self = [super init];
	if (self == nil)
		return nil;

	self.fileData = inFileData;
	//self.offset = 0;
	self.length = [inFileData length];

	return self;
}

- (void)dealloc {
	[fileData release];
    [super dealloc];
}

- (NSData*) readDataOfLength:(NSUInteger)numBytes
{
	NSRange subRange;
	subRange.location = offset;
	subRange.length = numBytes;

	// Can't read past end of buffer

	int lastOffset = (offset + numBytes);
	if (lastOffset > [fileData length]) {
		subRange.length = [fileData length] - offset;
	}

	// FIXME: it seems that subdataWithRange makes a copy of the data instead of just
	// reusing the original pointer. We likely need another object that can hold
	// a ref to the memory mapped NSData until done with all the data objects.
	
	NSData *subData = [fileData subdataWithRange:subRange];

	assert([subData length] == subRange.length);

	offset += subRange.length;

	return subData;
}

- (void) closeFile
{
	self.fileData = nil;
	self.isOpen = FALSE;
}

- (void) writeData:(NSData*)data
{
	assert(0);
}

- (unsigned long long) offsetInFile
{
	return offset;
}

- (void) seekToFileOffset:(unsigned long long)offsetInFile
{
	off_t _offset = offsetInFile;

	if (_offset >= INT_MAX) {
		assert(0);
	}

	self.offset = (NSUInteger) _offset;
}

- (unsigned long long) seekToEndOfFile
{
	self.offset = [fileData length];
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
	// no-op
}

- (void) truncateFileAtOffset:(unsigned long long)offsetInFile
{
	assert(0);
}

@end // class BufferedFileHandle
