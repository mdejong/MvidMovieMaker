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

// Primary module entry points for decode of a specific frame logic

void setupMovFrameAtTime(QTMovie *movie, QTMedia *trackMedia, int expectedBpp);

void cleanupMovFrameAtTime();

// Decode a frame at a specific time. The returned CGImageRef must be released explicitly

CGImageRef getMovFrameAtTime(QTTime atTime);
