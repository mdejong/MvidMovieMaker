//
//  EasyArchive.h
//  EasyArchiveUtil
//
//  Created by Moses DeJong on 2/10/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//
// The class implements logic for dealing with a very simplified
// binary archive file format. The only thing this archive format
// does is concat a set of files together into one big file. It will
// also stick a 32 bit MD5 hash on the front of the file so that
// a simple integrity check can be done when extracting. Files
// are not compressed in any way.

#import <Foundation/Foundation.h>

#include <CommonCrypto/CommonDigest.h> // MD5

@class BufferedFileHandle;

@interface EasyArchive : NSObject {
@public
	NSString *archiveFilename;

	BOOL writeMD5Header;
	BOOL validateMD5Header;
	BOOL hasMD5Header;
	BOOL isMD5Valid;

	BOOL useMappedFile;

	BOOL isOpen;

	NSUInteger numEntries;

	NSUInteger length;

@private
	NSString *archiveFilenameTail;

	BufferedFileHandle *bhandle;

	CC_MD5_CTX ctxt;

	NSUInteger *fileDataOffsets;

// FIXME: Create a way to set a flag so that file offsets are not
// built unless the user wants them. The user should need to
// request that they be built when reading or writing entries.
	
	NSMutableArray *buildFileDataOffsets;

	NSObject *coder;

	uint8_t openedFor;
}

@property (readonly) NSString *archiveFilename;

@property (nonatomic, retain) NSString *archiveFilenameTail;

// If this flag is set to TRUE, then a MD5
// header will be generated when creating
// a new archive file from a set of files.
// If the archive is going to be generated
// and then read back in place, then there
// is no reason to enable this flag.
// Be aware that this flag must be set
// *BEFORE* the archive is opened.
// Default is FALSE

@property (nonatomic, assign) BOOL writeMD5Header;

// If this flag is set to TRUE, then the
// contents of an archive will be validated
// as files are read from or extracted
// from the archive. The entire archive
// must be read before the validity of
// the the files is known. This method will
// slow down extraction slightly, so it
// should only be enabled when needed.
// Be aware that this flag must be set
// *BEFORE* the archive is opened.
// Default is FALSE

@property (nonatomic, assign) BOOL validateMD5Header;

// Will be set to TRUE if the archive contains
// a non-zero MD5 header and the validateMD5Header
// was set to TRUE before openForReading was invoked.

@property (readonly) BOOL hasMD5Header;

// Will be set to TRUE if hasMD5Header is TRUE and
// the contents of all entries matches the
// contents indicated by the MD5. If all the
// MD5 header bytes are zero, then isMD5Valid
// is FALSE.

@property (readonly) BOOL isMD5Valid;

// The number of entries in this archive.
// This value is set as a result of reading
// an archive file or calling addArchiveEntries
// to explicitly set the entries. This property
// can be read from another thread safely.

@property (readonly) NSUInteger numEntries;

// The total number of bytes in the file

@property (readonly) NSUInteger length;

@property (nonatomic, retain) BufferedFileHandle *bhandle;

@property (nonatomic, retain) NSObject *coder;

@property (nonatomic, retain) NSMutableArray *buildFileDataOffsets;

// If this property is set to TRUE, then memory mapped IO
// will be used when reading from an archive file. The
// contents of the archive will be mapped into memory
// before being read. Data objects read from the archive
// will be created from the mapped memory region in
// a space efficient way.

@property (nonatomic, assign) BOOL useMappedFile;

// init archive object and indicate the name
// or the archive file. An archive can be
// both written and read from, so we don't
// know at init time what kind of operations
// will be done.

- initWithFilename:(NSString*)inArchiveFilename;

// Close the archive file and flush data to the
// filesystem.

- (void) close;

// Truncate archive file and load all the data
// from the entries with the indicates URLs.
// This is a easy way to create an archive
// instead of invoking writeEntry directly.
// Returns TRUE on success or FALSE on error.

- (BOOL) addArchiveEntries:(NSArray*)inEntries;

// This method is a utility function used to add an
// entry to an array of entries that will be
// used to populate an archive via addArchiveEntries.

+ (void) addToArchiveEntriesArray:(NSMutableArray*)entries
			 archivePath:(NSString*)archivePath
				 dataURL:(NSURL*)dataURL;

// open existing archive file and read in header
// information if the verifyMD5Header is set.
// returns TRUE on success, or FALSE on failure.

- (BOOL) openForReading;

// open a new archive, truncate file if it exists.

- (BOOL) openForWriting;

// Read filename of entry at current position,
// if at EOF then null will be returned.

- (NSString*) readEntryFilename;

// Read data for file at current position.
// Note that numEntries is incremented each
// time an entry filename is read (until EOF
// or explicit call to readLastEntry)

- (NSData*) readEntryData;

// Write an entry that reads data already in memory

- (void) writeEntry:(NSString*)entryPath entryData:(NSData*)entryData;

// Write an entry that reads data from a URL (can be file URL)

- (void) writeEntry:(NSString*)entryPath entryURL:(NSURL*)entryURL;

// Seek the file position to the location where the file data begins for
// the entry at index. The call following this seek should be an
// invocation of readEntryData. Note that for an archive opened from a file,
// all the entries must be read in before one can seek to a specific index.
// Returns TRUE on success, FALSE on failure.

- (BOOL) seekToIndex:(NSInteger)entryIndex;

// Rewind file position to the first entry filename.

- (void) rewind;

// This method is typically invoked automatically
// after EOF has been read from the stream at the
// last entry position. If user code uses isAtEOF
// to test for the end of file position, then
// invoke this method after exiting the entry read loop.
// Reading only some of the entries and then invoking
// this method is not supported.

- (void) readLastEntry;

// Invoked after writing the last entry to an archive.
// After invoking wroteLastEntry, an archive can be
// read but no more entries can be written.

- (void) wroteLastEntry;

// Returns true if the file pointer is at the end of the file.

- (BOOL) isAtEOF;

// Invoke these method to define an entry encoder/decoder.

- (void) setEntryEncoderDecoder:(id)coder;

+ (NSData*) encodeShortInt:(uint16_t)value;

+ (NSData*) encodeInt:(uint32_t)value;

+ (uint16_t) decodeShortInt:(NSData*)data;

+ (uint32_t) decodeInt:(NSData*)data;

// Private helpers

- (void) _writeBytes:(uint8_t*)bytes length:(NSInteger)length;

- (void) _writeData:(NSData*)data;

- (void) _writeDataIgnoreMD5:(NSData*)data;

- (NSData*) _readData:(NSInteger)length;

- (NSData*) _readDataIgnoreMD5:(NSInteger)length;

+ (NSData*) _finishMD5:(CC_MD5_CTX*)digestCtxPtr;

- (void) _checkDataOffsets;

@end

// If a custom encoder/decoder is needed for entries in the archive,
// then implement this protocol on an object and tell the archive
// how to encode or decode data in the archive.

@protocol EasyArchiveEntryEncoderDecoderProtocol

- (NSData*) encodeEntryData:(NSData*)entryData;

- (NSData*) decodeEntryData:(NSData*)entryData;

@end
