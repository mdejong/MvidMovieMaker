//
//  MvidFileMetaData.m
//  MvidMovieMaker
//
//  Created by Moses DeJong on 3/25/13.

#import "MvidFileMetaData.h"

@implementation MvidFileMetaData

@synthesize bpp = m_bpp;

@synthesize checkAlphaChannel = m_checkAlphaChannel;

+ (MvidFileMetaData*) mvidFileMetaData
{
  MvidFileMetaData *obj = [[MvidFileMetaData alloc] init];
  return [obj autorelease];
}

- (void)dealloc
{
  [super dealloc];
}

@end
