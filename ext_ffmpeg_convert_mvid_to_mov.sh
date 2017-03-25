#!/bin/sh
#
# This shell script will convert a MVID file to Quicktime .mov
# that internally uses the lossless Animation codec at 24 or 32 BPP.
#
# ext_ffmpeg_convert_mvid_to_mov.sh IN.mvid OUT.mov
#
# IN.mvid : name of input .mvid file
# OUT.mov : name of output .mov file using Quicktime Animation codec

INPUT=$1
OUTPUT=$2

FRAMES="ffmpeg_FRAMES"

USAGE="usage : ext_ffmpeg_convert_mvid_to_mov.sh IN.mvid OUT.mov"

if test "$INPUT" = ""; then
  echo "$USAGE : INPUT MVID ARGUMENT MISSING"
  exit 1
fi

if test "$OUTPUT" = ""; then
  echo "$USAGE : OUTPUT MOV ARGUMENT MISSING"
  exit 1
fi

# Extract FPS from mvid

MVID_FPS=`mvidmoviemaker -fps ${INPUT}`
echo "MVID_FPS=\"${MVID_FPS}\""

if echo ${MVID_FPS} | grep "cannot open mvid" - ; then
  echo "${MVID_INFO}"
  exit 1
fi

# Extract all the frames from the mvid into the indicated directory

echo "rm -rf ${FRAMES}"
rm -rf ${FRAMES}
echo "mkdir ${FRAMES}"
mkdir ${FRAMES}
cd ${FRAMES}
mvidmoviemaker -extract ../${INPUT}
cd ..

# Generate .mov from frame images and pass -framerate to ffmpeg indicate framerate

echo "ffmpeg -y -framerate ${MVID_FPS} -i ${FRAMES}/Frame%04d.png -c:v qtrle ${OUTPUT}"
ffmpeg -y -framerate ${MVID_FPS} -i ${FRAMES}/Frame%04d.png -c:v qtrle ${OUTPUT}
rm -rf ${FRAMES}

echo "wrote ${OUTPUT}"
exit 0

