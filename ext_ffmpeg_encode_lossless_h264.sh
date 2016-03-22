#!/bin/sh
#
# Transcode a MOV and store as lossless H264.
# This encode depends on converting the RGB
# to YUV444 format pixels first and then the
# lossless YUV444 pixels are encoded as
# lossless H264 in a MOV container.

# ext_ffmpeg_encode_lossless_h264.sh MVID

MOV=$1
if test "$MOV" = ""; then
  echo "ext_ffmpeg_encode_lossless_h264.sh MOV"
  exit 1
fi

PROFILE=high444

Y4M=`echo "$MOV" | sed -e s/.mov/.y4m/g`
M4V=`echo "$MOV" | sed -e s/.mov/.m4v/g`

ffmpeg -y -i "$MOV" -vcodec rawvideo -pix_fmt yuv444p "$Y4M"

# encode to lossless H.264, video header info stored in Y4M already

#echo "ffmpeg -y -i $Y4M -c:v libx264 -pix_fmt yuv444p -profile:v high444 -crf 0 -preset:v slow $M4V"
ffmpeg -y -i "$Y4M" -c:v libx264 -pix_fmt yuv444p -profile:v high444 -crf 0 -preset:v slow "$M4V"

rm "$Y4M"

exit 0

