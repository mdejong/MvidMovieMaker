#import <Foundation/Foundation.h>

@interface NSData (NSDataExtension)

// ZLIB
- (NSData *) zlibInflate;
- (NSData *) zlibDeflate;

- (void)zlibInflateIntoBuffer:(void*)buffer numBytes:(int)numBytes;

// CRC32
- (unsigned int)crc32;

+ (BOOL) compressFileToBZ2File:(NSString*)uncompressedPath bzPath:(NSString*)bzPath;

+ (BOOL) uncompressBZ2FileToFile:(NSString*)bzPath uncompressedPath:(NSString*)uncompressedPath;

// uncompress the contents of a bzip2 file and write the decompressed bytes to a
// file in the tmp dir. This logic remove the .bz2 extension from the filename
// and saves the result to a file without the .bz2 extension.

+ (NSString*) uncompressBZ2FileToTmpFile:(NSString*)bzPath;

// Get last path component for either a URL string or a filename.

+ (NSString*) lastURLOrPathComponent:(NSString*)path;

// Trim extenson off the filename. For example, a "foo.bar.bz2" path without
// the extension would be "foo.bar".

+ (NSString*) filenameWithoutExtension:(NSString*)filename extension:(NSString*)extension;	

@end