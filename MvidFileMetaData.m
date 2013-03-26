//
//  MvidFileMetaData.m
//  MvidMovieMaker
//
//  Created by Moses DeJong on 3/25/13.

#import "MvidFileMetaData.h"

@implementation MvidFileMetaData

@synthesize bpp = m_bpp;

@synthesize checkAlphaChannel = m_checkAlphaChannel;

@synthesize recordFramePixelValues = m_recordFramePixelValues;

@synthesize allPixelOccurances = m_allPixelOccurances;

+ (MvidFileMetaData*) mvidFileMetaData
{
  MvidFileMetaData *obj = [[MvidFileMetaData alloc] init];
  return [obj autorelease];
}

- (void)dealloc
{
  self.allPixelOccurances = nil;
  [super dealloc];
}

// FIXME: currently this table based logic only works with 32BPP pixels. Need
// to find a way to support either 32 or 16 BPP with one function, otherwise
// write 2 different ones.

- (void) doneRecordingFramePixelValues
{
  NSAssert(self.recordFramePixelValues, @"recording frame pixels must have been enabled");
  self.recordFramePixelValues = FALSE;

  if (self.checkAlphaChannel && self.bpp == 24) @autoreleasepool {
    // In this case, the BPP of the input was unknown but now it is known to be 24BPP.
    // When rendered, each pixel will have the alpha channel set to zero instead of 0xFF
    // since that compresses better. But, we need to update each key and value in the
    // allPixelOccurances dictionary since these values include a 0xFF alpha channel value.
    
    NSArray *allKeys = [self.allPixelOccurances allKeys];
    NSAssert(allKeys, @"must be at least 1 pixel in allPixelOccurances");
    
    for (NSNumber *key in allKeys) {
      NSNumber *countThisPixel = [self.allPixelOccurances objectForKey:key];
      NSAssert(countThisPixel != nil, @"countThisPixel is nil");
            
      uint32_t pixel = [key unsignedIntValue];
      assert((pixel >> 24) == 0xFF || (pixel >> 24) == 0x0);
      pixel = pixel & 0xFFFFFF;

      key = [NSNumber numberWithUnsignedInt:pixel];
      
      [self.allPixelOccurances setObject:countThisPixel forKey:key];
      
      // Remove the previous key to value mapping after adding the new mapping
      // so that the value object is not deallocated.
      
      [self.allPixelOccurances removeObjectForKey:key];
    }
  }
  
  // Once all pixel are ready, sort the pixel by the number of times each
  // is found in the file to create a list of keys sorted by frequency.
  
  // Now iterate over the sorted counts from largest to smallest to see the values in terms
  // of the most frequently used pixels.
  
  NSArray *pixelsSortedByDescendingCount = [self sortPixelOccurances:self.allPixelOccurances];
  NSAssert([pixelsSortedByDescendingCount count] > 0, @"pixelsSortedByDescendingCount");
  
  return;
}

- (void) foundPixel32:(uint32_t)pixel
{
  if (self.allPixelOccurances == nil) {
    self.allPixelOccurances = [NSMutableDictionary dictionaryWithCapacity:(1024*4)*1024];
  }
  
  NSNumber *pixelNum = [NSNumber numberWithUnsignedInt:pixel];
  
  NSNumber *countThisPixel = [self.allPixelOccurances objectForKey:pixelNum];
  
  if (countThisPixel == nil) {
    // First time this pixel has been seen
    
    countThisPixel = [NSNumber numberWithUnsignedInt:1];
  } else {
    // Add 1 to the existing pixel count
    
    uint32_t currentCount = [countThisPixel unsignedIntValue];
    
    currentCount++;
    
    countThisPixel =[NSNumber numberWithUnsignedInt:currentCount];
  }
  
  [self.allPixelOccurances setObject:countThisPixel forKey:pixelNum];
}

- (void) foundPixel16:(uint16_t)pixel
{
  if (self.allPixelOccurances == nil) {
    self.allPixelOccurances = [NSMutableDictionary dictionaryWithCapacity:(1024*4)*1024];
  }
  
  NSNumber *pixelNum = [NSNumber numberWithUnsignedShort:pixel];
  
  NSNumber *countThisPixel = [self.allPixelOccurances objectForKey:pixelNum];
  
  if (countThisPixel == nil) {
    // First time this pixel has been seen
    
    countThisPixel = [NSNumber numberWithUnsignedInt:1];
  } else {
    // Add 1 to the existing pixel count
    
    uint32_t currentCount = [countThisPixel unsignedIntValue];
    
    currentCount++;
    
    countThisPixel =[NSNumber numberWithUnsignedInt:currentCount];
  }
  
  [self.allPixelOccurances setObject:countThisPixel forKey:pixelNum];
}

// Sort pixels in a dictionary of pixel value (NSNumber) to occurance count (NSNumber).
// The sort order is always descending, so that the list of returned keys indicates
// the pixel values in terms of most to least number of pixels in the table.

- (NSArray*) sortPixelOccurances:(NSDictionary*)dict
{
  NSMutableArray *pixelsSortedByDescendingCount = nil;
  
  @autoreleasepool {
    NSArray *allKeys = [self.allPixelOccurances allKeys];
    NSAssert(allKeys, @"must be at least 1 pixel in allPixelOccurances");
    
    NSArray *allValues = [self.allPixelOccurances allValues];
    
    // Sort the values in the table in terms of descending cound number
    
    NSArray *sortedValues = [allValues sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
      NSNumber *first = (NSNumber*)a;
      NSNumber *second = (NSNumber*)b;
      return [second compare:first];
    }];
    
    // Create a new table that maps the pixel count to an array of pixel
    // values for this specific count.
    
    NSMutableDictionary *countToPixels = [NSMutableDictionary dictionaryWithCapacity:[allKeys count]];
    
    for (NSNumber *key in allKeys) {
      NSNumber *countThisPixel = [self.allPixelOccurances objectForKey:key];
      
      NSMutableArray *arrayOfPixels = [countToPixels objectForKey:countThisPixel];
      
      if (arrayOfPixels == nil) {
        arrayOfPixels = [NSMutableArray array];
      }
      
      // Add this pixel to the list of pixels for this count
      [arrayOfPixels addObject:key];
      
      [countToPixels setObject:arrayOfPixels forKey:countThisPixel];
    }
    
    // Now iterate over the sorted counts from largest to smallest to see the values in terms
    // of the most frequently used pixels.
    
    pixelsSortedByDescendingCount = [[NSMutableArray alloc] initWithCapacity:[allKeys count]];
    
    for (NSNumber *sortedValue in sortedValues) {
      NSMutableArray *arrayOfPixels = [countToPixels objectForKey:sortedValue];
      
      //uint32_t count = [sortedValue unsignedIntValue];
      
      // Note that we need to empty out the pixel array after seeing it once
      // to avoid duplicates for the same count number.
      
      if ([arrayOfPixels count] > 0) {
        //NSLog(@"Count: %d, pixels %@", count, arrayOfPixels);
        
        for (NSNumber *pixelKey in arrayOfPixels) {
          [pixelsSortedByDescendingCount addObject:pixelKey];
        }
        
        [arrayOfPixels removeAllObjects];
      }
    }
    
    // Finally we have a deduped list of keys in descending sorted order
    
    NSLog(@"pixelsSortedByDescendingCount table has %d entries", [pixelsSortedByDescendingCount count]);
    
    for (NSNumber *pixelKey in pixelsSortedByDescendingCount) {
      NSNumber *countThisPixel = [self.allPixelOccurances objectForKey:pixelKey];
      uint32_t count = [countThisPixel unsignedIntValue];
      
      if (self.bpp == 16) {
        uint32_t pixel16 = [pixelKey unsignedShortValue];
        NSLog(@"pixel 0x%.04X, %d", pixel16, count);
      } else {
        uint32_t pixel32 = [pixelKey unsignedIntValue];
        NSLog(@"pixel 0x%.06X, %d", pixel32, count);
      }
    }
  }
  
  return [pixelsSortedByDescendingCount autorelease];
}

@end
