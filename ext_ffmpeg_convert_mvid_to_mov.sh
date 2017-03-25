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

MVID_INFO=`mvidmoviemaker -info ${INPUT} > mvid.info 2>&1`
MVID_INFO=`cat mvid.info`
echo "MVID_INFO=\"${MVID_INFO}\""

if grep "cannot open mvid" mvid.info; then
  echo "${MVID_INFO}"
  rm mvid.info
  exit 1
fi

echo "MVID_INFO=\"${MVID_INFO}\""
FPS=`cat mvid.info| grep FrameDuration | sed -e 's/[^0-9.]//g'`
echo "FPS=\"${FPS}\""

rm mvid.info

#FPS_SPEC=`echo $PROBE | cut -d = -f 2`
#echo "FPS_SPEC=\"${FPS_SPEC}\""

# Extract all the frames from the mvid into the indicated directory

echo "rm -rf ${FRAMES}"
rm -rf ${FRAMES}
echo "mkdir ${FRAMES}"
mkdir ${FRAMES}
cd ${FRAMES}
mvidmoviemaker -extract ../${INPUT}
cd ..

# Generate .mov from frame images and pass -fps to indicate framerate

echo "ffmpeg -y -framerate 1/${FPS} -i ${FRAMES}/Frame%04d.png -c:v qtrle ${OUTPUT}"
ffmpeg -y -framerate 1/${FPS} -i ${FRAMES}/Frame%04d.png -c:v qtrle ${OUTPUT}
rm -rf ${FRAMES}

echo "wrote ${OUTPUT}"
exit 0

