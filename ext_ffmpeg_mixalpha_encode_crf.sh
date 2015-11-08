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

# ext_ffmpeg_mixalpha_encode_crf.sh MVID CRF

# FIXME: MVID cannot be a qualified path, it must just be a filename

MVID=$1
if test "$MVID" = ""; then
  echo "ext_ffmpeg_splitalpha_encode_crf.sh MVID CRF : INPUT MVID ARGUMENT MISSING"
  exit 1
fi

CRF=$2
if test "$CRF" = ""; then
  echo "ext_ffmpeg_splitalpha_encode_crf.sh MVID CRF : INPUT CRF ARGUMENT MISSING"
  exit 1
fi

#PROFILE=baseline
PROFILE=main

# Create the subdirectory

SUBDIR="MVID_ENCODE_CRF_${CRF}_${PROFILE}"
rm -rf "$SUBDIR"
mkdir "$SUBDIR"
cd "$SUBDIR"
cp ../$MVID .

# Convert 32BPP movie into RGB+Alpha split a frame at a time
mvidmoviemaker -mixalpha $MVID
MIX=`ls *_mix.mvid`
MIX_MOV=`echo "$MIX" | sed -e s/.mvid/.mov/g`
MIX_M4V=`echo "$MIX_MOV" | sed -e s/.mov/.m4v/g`

mvidmoviemaker $MIX $MIX_MOV

# Convert .mov to .m4v file using ffmpeg and x264 with main profile

#echo "exec ext_ffmpeg_encode_main_crf.sh \"$MIX_MOV\" \"$MIX_M4V\" $CRF $PROFILE"
ext_ffmpeg_encode_crf.sh $MIX_MOV $MIX_M4V $CRF $PROFILE

# Stopping at this point is significantly faster
exit 0

# Convert the encoded h264 video back to MOV with Animation codec and then
# unmix the RGB and alpha frames so that the compressed output can be seen
# with the lossy encoding applied.

MIX_ENCODED_MOV=`echo "$MIX_M4V" | sed -e s/.m4v/.mov/g`

echo "exec ffmpeg -y -i $MIX_M4V $MIX_ENCODED_MOV"
ffmpeg -y -i $MIX_M4V -vcodec qtrle $MIX_ENCODED_MOV

echo "exec mvidmoviemaker $MIX_ENCODED_MOV encoded_mix.mvid -bpp 24"
mvidmoviemaker $MIX_ENCODED_MOV encoded_mix.mvid -bpp 24

echo "exec mvidmoviemaker -unmixalpha encoded.mvid"
mvidmoviemaker -unmixalpha encoded.mvid

echo "Rewrote MVID $MVID with video encoded as H264"
mvidmoviemaker -info encoded.mvid

# FIXME: could cleanup large tmp files here

exit 0

