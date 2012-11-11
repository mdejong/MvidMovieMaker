//
//  qtdecode.m
//
//  Created by Moses DeJong on 11/3/12.
//
//  License terms defined in License.txt.

#import "qtdecode.h"

#import "AVMvidFrameDecoder.h"

#import "CGFrameBuffer.h"

#import "movdata.h"


CGImageRef getMovFrameAtTime(
                             QTMovie *movie,
                             QTTime atTime
                             )
{
  CGImageRef frameImage;
  NSError *errState;
  //BOOL worked;
  
  // Passing QTMovieFrameImagePixelFormat for type
  
  NSDictionary *attributes = [[[NSDictionary alloc] initWithObjectsAndKeys:
                               QTMovieFrameImageTypeCGImageRef, QTMovieFrameImageType,
                               [NSNumber numberWithBool:YES], QTMovieFrameImageHighQuality,
                               nil]
                              autorelease];
  
  frameImage = [movie frameImageAtTime:atTime withAttributes:attributes error:&errState];
  //worked = (frameImage != nil);
  
  return frameImage;
}

// Other options: http://docs.thefoundry.co.uk/nuke/63/ndkreference/examples/movReader.cpp
