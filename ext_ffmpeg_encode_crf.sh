# vi ext_ffmpeg_encode_crf.sh
#
# This shell script will encode a specific video file using
# ffmpeg and the x264 library to generate a .m4v video file
# that contains compressed H264 encoded video output. The
# .m4v video file format can be read natively in iOS.
#
# ext_ffmpeg_mvidmoviemaker_crf_encode.sh IN.mov OUT.m4v CRF
#
# IN.mov : name of Quicktime Animation codec .mov file
# OUT.m4v : name of output H264 file
# CRF : Quality integer value in range 1 to 50. 1 is max quality, 50 is lowest
#  while the default quality is 23.

INPUT=$1
OUTPUT=$2
CRF=$3

if test "$INPUT" = ""; then
  echo "INPUT ARGUMENT MISSING"
  exit 1
fi

if test "$OUTPUT" = ""; then
  echo "OUTPUT ARGUMENT MISSING"
  exit 1
fi

PRESET="-preset:v veryslow"
PIXFMT=yuv420p
PROFILE="-profile:v baseline"
#TUNE="-tune:v animation"

# 1 Pass encoding with a "Constant Rate Factor"
# CFR range: 0 -> 51 (0 = lossless, 23 default, 51 lowest quality)

if test "$CRF" = ""; then
  CRF=23
fi

ffmpeg -y -i $INPUT -c:v libx264 -pix_fmt $PIXFMT $PRESET $PROFILE $TUNE -crf $CRF \
$OUTPUT

# Once conversion to .m4v is completed, do another conversion of the H264
# encoded data back to uncompressed Animation codec.

OUTMOV=`echo $OUTPUT | sed -e s/.m4v/.mov/g`

ffmpeg -y -i "$OUTPUT" -vcodec qtrle "$OUTMOV"

exit 0

