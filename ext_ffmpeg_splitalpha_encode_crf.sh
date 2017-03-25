#!/bin/sh
#
# Encode a video file at a certain CRF setting.
# This script will create a subdirectory in the
# current directory, copy the indicated MVID file
# there and then split the alpha channel and rgb channel
# into 2 different movies. These split videos will
# then be compressed using a specific CRF setting
# and then the results will be recombined back together
# to create a new "compressed" mvid which contains
# just the compressed pixels.

# ext_ffmpeg_splitalpha_encode_crf.sh MVID CRF

# FIXME: MVID cannot be a qualified path, it must just be a filename

MVID=$1
if test "$MVID" = ""; then
  echo "INPUT MVID ARGUMENT MISSING"
  exit 1
fi

CRF=$2
if test "$CRF" = ""; then
  echo "INPUT CRF ARGUMENT MISSING"
  exit 1
fi

PROFILE=baseline
#PROFILE=main

# Create the subdirectory

SUBDIR="MVID_ENCODE_CRF_${CRF}_${PROFILE}"
rm -rf "$SUBDIR"
mkdir "$SUBDIR"
cd "$SUBDIR"
cp ../$MVID .

mvidmoviemaker -splitalpha $MVID
ALPHA=`ls *_alpha.mvid`
RGB=`ls *_rgb.mvid`

ALPHA_MOV=`echo "$ALPHA" | sed -e s/.mvid/.mov/g`
RGB_MOV=`echo "$RGB" | sed -e s/.mvid/.mov/g`

ALPHA_M4V=`echo "$ALPHA_MOV" | sed -e s/.mov//g`
ALPHA_M4V="${ALPHA_M4V}_CRF_${CRF}_24BPP.m4v"
RGB_M4V=`echo "$RGB_MOV" | sed -e s/.mov//g`
RGB_M4V="${RGB_M4V}_CRF_${CRF}_24BPP.m4v"

# convert RGB and ALPHA .mvid to .mov
#mvidmoviemaker $RGB $RGB_MOV
#mvidmoviemaker $ALPHA $ALPHA_MOV
ext_ffmpeg_convert_mvid_to_mov.sh $RGB $RGB_MOV
ext_ffmpeg_convert_mvid_to_mov.sh $ALPHA $ALPHA_MOV

# Convert .mov to .m4v files using ffmpeg and x264

#sh -x ~/bin/ext_ffmpeg_encode_crf.sh $RGB_MOV $RGB_M4V $CRF
#sh -x ~/bin/ext_ffmpeg_encode_crf.sh $ALPHA_MOV $ALPHA_M4V $CRF
ext_ffmpeg_encode_crf.sh $RGB_MOV $RGB_M4V $CRF $PROFILE
ext_ffmpeg_encode_crf.sh $ALPHA_MOV $ALPHA_M4V $CRF $PROFILE

# Stopping at this point is significantly faster
exit 0

# The ext_ffmpeg_encode_crf.sh also implicitly decodes the
# emitted .m4v data back into .mov format so that the
# calling script need not know hwo ffmpeg handles that.
# We just decode the .mov back into .mvid so that the
# two alpha and rgb files can be merged back together
# to test out the split/join logic.

RGB_ENCODED_MOV=`echo "$RGB_M4V" | sed -e s/.m4v/.mov/g`
ALPHA_ENCODED_MOV=`echo "$ALPHA_M4V" | sed -e s/.m4v/.mov/g`

# Replace _alpha.mvid and _rgb.mvid files with versions
# created from the compressed H264 data. The -bpp flag
# is passed just to optimize the conversion, it is not required.

#DURATION=`mvidmoviemaker -info $MVID | grep FrameDuration`
#DURATION=`echo $DURATION | sed s/FrameDuration://g | sed s/s//g`

mvidmoviemaker $RGB_ENCODED_MOV $RGB -bpp 24
mvidmoviemaker $ALPHA_ENCODED_MOV $ALPHA -bpp 24

# Now join the alpha and rgb components back together into a 32BPP movie
mvidmoviemaker -joinalpha $MVID

echo "Rewrote MVID $MVID with video encoded as H264"
mvidmoviemaker -info $MVID

# FIXME: could cleanup large tmp files here

exit 0

