/*
 *  bzlib.h
 *  ImageSeqMovieMaker
 *
 *  Created by Moses DeJong on 3/9/09.
 *  Copyright 2009 __MyCompanyName__. All rights reserved.
 *
 */

// For unknown reasons, the libbz2.dylib implementation for the iPhone OS target
// does not include a header file. Define headers here to work around it.

#define BZ_RUN               0
#define BZ_FLUSH             1
#define BZ_FINISH            2

#define BZ_OK                0
#define BZ_RUN_OK            1
#define BZ_FLUSH_OK          2
#define BZ_FINISH_OK         3
#define BZ_STREAM_END        4
#define BZ_SEQUENCE_ERROR    (-1)
#define BZ_PARAM_ERROR       (-2)
#define BZ_MEM_ERROR         (-3)
#define BZ_DATA_ERROR        (-4)
#define BZ_DATA_ERROR_MAGIC  (-5)
#define BZ_IO_ERROR          (-6)
#define BZ_UNEXPECTED_EOF    (-7)
#define BZ_OUTBUFF_FULL      (-8)
#define BZ_CONFIG_ERROR      (-9)


#define BZ_API(func) func
#define BZ_EXTERN extern

typedef void BZFILE;

BZ_EXTERN int BZ_API(BZ2_bzBuffToBuffCompress) ( 
												char*         dest, 
												unsigned int* destLen,
												char*         source, 
												unsigned int  sourceLen,
												int           blockSize100k, 
												int           verbosity, 
												int           workFactor 
												);

BZ_EXTERN int BZ_API(BZ2_bzBuffToBuffDecompress) ( 
												  char*         dest, 
												  unsigned int* destLen,
												  char*         source, 
												  unsigned int  sourceLen,
												  int           small, 
												  int           verbosity 
												  );


BZ_EXTERN BZFILE* BZ_API(BZ2_bzReadOpen) ( 
										  int*  bzerror,   
										  FILE* f, 
										  int   verbosity, 
										  int   small,
										  void* unused,    
										  int   nUnused 
										  );

BZ_EXTERN void BZ_API(BZ2_bzReadClose) (
										int*    bzerror, 
										BZFILE* b 
										);

BZ_EXTERN int BZ_API(BZ2_bzRead) ( 
								  int*    bzerror, 
								  BZFILE* b, 
								  void*   buf, 
								  int     len 
								  );
