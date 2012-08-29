//
//  NSDataFileHandle.h
//  EasyArchiveDemo
//
//  Created by Moses DeJong on 3/8/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//
//
// This class implements a non-async IO that reads
// data from a NSData object. It can easily
// be used with a NSData created from a
// memory mapped file.

#import <Foundation/Foundation.h>

#include "BufferedFileHandle.h"

@interface NSDataFileHandle : BufferedFileHandle {
@private
	NSData *fileData;
	NSUInteger offset;
}

@property (nonatomic, retain) NSData *fileData;
@property (nonatomic, assign) NSUInteger offset;

- (id) initWithData:(NSData*)inFileData;

- (void) dealloc;

- (NSData*) readDataOfLength:(NSUInteger)length;

- (void) closeFile;

- (void) writeData:(NSData*)data;

- (unsigned long long) offsetInFile;

- (void) seekToFileOffset:(unsigned long long)offset;

- (unsigned long long) seekToEndOfFile;

- (NSData *)availableData;

- (NSData *)readDataToEndOfFile;

- (void) synchronizeFile;

- (void) truncateFileAtOffset:(unsigned long long)offset;

@end