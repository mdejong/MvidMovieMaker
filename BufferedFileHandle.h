//
//  BufferedFileHandle.h
//  EasyArchiveDemo
//
//  Created by Moses DeJong on 3/8/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//
//
// Buffered IO wrapper for NSFileHandle. Note that this
// implementation does not support async IO.

#import <Foundation/Foundation.h>
#include <stdio.h>

@interface BufferedFileHandle : NSObject {
@protected
	NSString *filePath;
	NSString *fileName;
	FILE *file;
	unsigned long long length;
	BOOL isOpen;
}

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) NSString *fileName;

@property (nonatomic, assign) unsigned long long length;
@property (nonatomic, assign) BOOL isOpen;

- (id) initWithFilename:(NSString*)inFilePath readonly:(BOOL)readonly;

- (void)dealloc;

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
