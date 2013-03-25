//
//  MvidFileMetaData.h
//
//  Created by Moses DeJong on 3/25/13.
//
//  License terms defined in License.txt.
//
//  This file is a container object that is filled in with
//  meta data about a file as the input contents are scanned.
//  This object can hold information that corresponds to the
//  whole movie file or one specific frame or subframe.
//
//  In the case of input with unknown BPP values (like a .mov or series of images)
//  it is impossible to know key information about a file until all pixels have
//  been scanned. This record holds data that is discovered during a scan so that
//  it can be inspected by the caller after scanning is complete.

#import <Foundation/Foundation.h>

@interface MvidFileMetaData : NSObject
{
  NSUInteger m_bpp;
  BOOL m_checkAlphaChannel;
}

// The BPP value the caller assumes. Can be 16, 24, or 32 BPP. In the
// case where the BPP is assumed to be 24 BPP but scanning shows that
// 24 BPP pixels are used, the assumed value is 24 and the actual
// value will be set to 32.

@property (nonatomic, assign) NSUInteger bpp;

// Set to TRUE if the bpp value is 24 (assumed) but we want to scan to
// determine if any non-opaque pixels appear in the input.

@property (nonatomic, assign) BOOL checkAlphaChannel;

+ (MvidFileMetaData*) mvidFileMetaData;

@end
