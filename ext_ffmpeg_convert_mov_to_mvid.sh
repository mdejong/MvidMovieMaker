#!/bin/sh
#
# This shell script will convert a Quicktime input movie to
# a .mvid format video file. The MVID file is lossless
# and does not compress the video data from the original video.
#
# ext_ffmpeg_convert_mov_to_mvid.sh IN.mov OUT.mvid
#
# IN.mov : name of Quicktime Animation codec .mov file
# OUT.mvid : name of output MVID file

INPUT=$1
OUTPUT=$2

FRAMES="ffmpeg_FRAMES"

USAGE="usage : ext_ffmpeg_convert_mov_to_mvid.sh IN.mov OUT.mvid"

if test "$INPUT" = ""; then
  echo "$USAGE : INPUT MOV ARGUMENT MISSING"
  exit 1
fi

if test "$OUTPUT" = ""; then
  echo "$USAGE : OUTPUT MVID ARGUMENT MISSING"
  exit 1
fi

PROBE=`ffprobe -v 0 -of compact=p=0 -select_streams 0 -show_entries stream=r_frame_rate ${INPUT}`
echo "PROBE=\"${PROBE}\""

FPS_SPEC=`echo $PROBE | cut -d = -f 2`
echo "FPS_SPEC=\"${FPS_SPEC}\""

# Extract all the frames from the video to specific files

echo "rm -rf ${FRAMES}"
rm -rf ${FRAMES}
echo "mkdir ${FRAMES}"
mkdir ${FRAMES}
echo "ffmpeg -y -i $INPUT ${FRAMES}/Frame%04d.png"
ffmpeg -y -i $INPUT ${FRAMES}/Frame%04d.png

# Create .mvid in current directory by reading all frames
# Pass -fps 24 to indicate 24 frames per second

echo "mvidmoviemaker ${FRAMES}/Frame0001.png ${OUTPUT} -fps ${FPS_SPEC}"
mvidmoviemaker ${FRAMES}/Frame0001.png ${OUTPUT} -fps ${FPS_SPEC}
rm -rf ${FRAMES}

echo "wrote ${OUTPUT}"
mvidmoviemaker -info ${OUTPUT}

exit 0

