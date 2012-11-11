//
//  qtdecode.h
//
//  Created by Moses DeJong on 11/3/12.
//
//  License terms defined in License.txt.
//
//  This module implements utility functions that read from a Quicktime file and
//  return a frame of image data formatted as a CoreGraphics image.

#import <Foundation/Foundation.h>

#import <QTKit/QTKit.h>

#import <QuickTime/Movies.h>

#import <CoreGraphics/CoreGraphics.h>

// Decode a frame at a specific time, note that this CGImageRef must be placed in the
// autorelease pool.

CGImageRef getMovFrameAtTime(
                      QTMovie *movie,
                      QTTime atTime
                      );
