# ext_ffmpeg_mvidmoviemaker_encode_crf.sh
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

# ext_ffmpeg_mvidmoviemaker_encode_crf.sh MVID CRF

# FIXME: MVID cannot be a qualified patch, it must just be a filename

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

# Create the subdirectory

SUBDIR="MVID_ENCODE_CRF_$CRF"
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
mvidmoviemaker $RGB $RGB_MOV 
mvidmoviemaker $ALPHA $ALPHA_MOV

# Convert .mov to .m4v files using ffmpeg and x264

#sh -x ~/bin/ext_ffmpeg_encode_crf.sh $RGB_MOV $RGB_M4V $CRF
#sh -x ~/bin/ext_ffmpeg_encode_crf.sh $ALPHA_MOV $ALPHA_M4V $CRF
ext_ffmpeg_encode_crf.sh $RGB_MOV $RGB_M4V $CRF
ext_ffmpeg_encode_crf.sh $ALPHA_MOV $ALPHA_M4V $CRF

# The ext_ffmpeg_encode_crf.sh also implicitly decodes the
# emitted .m4v data back into .mov format so that the
# calling script need not know hwo ffmpeg handles that.
# We just decode the .mov back into .mvid so that the
# two alpha and rgb files can be merged back together
# to test out the split/join logic.

RGB_ENCODED_MOV=`echo "$RGB_M4V" | sed -e s/.m4v/.mov/g`
ALPHA_ENCODED_MOV=`echo "$ALPHA_M4V" | sed -e s/.m4v/.mov/g`

# Replace _alpha.mvid and _rgb.mvid files
# Note that we explicitly pass a -framerate option because the
# x264 encoder cannot be trusted to maintain the same consistent
# framerate as was used in the input .mov file. So, we simply
# use the original input framerate and ignore the framerate
# values. The -bpp flag just avoid autodetection of 32BPP vs
# 24BPP when we know the data is in 24BPP format.

# FIXME: the encoding process can make the input movie longer.
# Need to be able to pass a "-maxtime 5.006" type option so
# that even if the movie is made longer, it will be clipped
# when importing back from .mov.

DURATION=`mvidmoviemaker -info $MVID | grep FrameDuration`
DURATION=`echo $DURATION | sed s/FrameDuration://g | sed s/s//g`

mvidmoviemaker $RGB_ENCODED_MOV $RGB -bpp 24 -framerate $DURATION
mvidmoviemaker $ALPHA_ENCODED_MOV $ALPHA -bpp 24 -framerate $DURATION

# Now join the alpha and rgb components back together into a 32BPP movie
mvidmoviemaker -joinalpha $MVID

echo "Rewrote MVID $MVID with video encoded as H264"
mvidmoviemaker -info $MVID

# FIXME: could cleanup large tmp files here

exit 0

