//
//  qtencode.h
//
//  Created by Moses DeJong on 11/3/12.
//
//  License terms defined in License.txt.
//
//  This module implements utility functions the write movie data to a Quicktime
//  formatted .mov file. This file writing logic is concerned only with generating
//  a .mov file that can be read by Quicktime or other tools that support the .mov
//  format. It is not important that the generated .mov files be the smallest
//  possible size. Data is written as lossless Animation codec data.

#import <Foundation/Foundation.h>

void convertMvidToMov(
                      NSString *mvidFilename,
                      NSString *movFilename
                      );

uint32_t unpremultiply_bgra(uint32_t premultPixelBGRA);

// Defined in movdata.c since alpha table is in that module

void premultiply_init();

uint32_t premultiply_bgra(uint32_t unpremultPixelBGRA);
