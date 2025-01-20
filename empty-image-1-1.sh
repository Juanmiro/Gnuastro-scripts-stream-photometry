#!/bin/bash
set -e
# High-level script to create images with realistic DES background noise,
# as a basis for mock images of host galaxies with streams.
#
# Run `./project --help' for a description of how to use it.
#
# Copyright (C) 2020-2021 Mohammad Akhlaghi <mohammad@akhlaghi.org>
# Copyright (C) 2023 Juan Miro <miro.juan@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#=========================== HELP =======================================

[ "$1" == "-h" -o "$1" == --help ] && echo "
This script uses Gnuastro programs to subtract the central galaxy of images
and replace it by a patch of bakground extracted from the same image.

To execute this script you use a command like the following:

 ./detecting-generic-stream-x-x.sh  argument-1 argument-2 argument-3

argument-1: the directory where the input images are located.
(the name of the input files must start with the name of the host galaxy
(see below) and end with the name of the passband and the extension .fits,
for exmple, for passband r:

   <NGC922-*-*-r.fits>

argument-2: the directory where all output files shall be written to.

argument-3: the directory where all the aperture files will be located
(only needed for step=2, see below).
The aperture file contained, e.g., for NGC922-*-r.fits, must be named:

   <NGC922-physical-apertures.reg>

In this version of the script, the following input parameters are asked
interactively to the user:

For step 1 Detection+Segmentation:

- Name of host galaxy in input image (e.g. NGC922)
- The execution step required: 1
    1 = Detection+Segmentation 
    2 = Mock image generation
- The filter to be used for the masking
 
 For step 2 Mockimage generation:

- Name of host galaxy in input image (e.g. NGC922)
- The execution step required: 2
    2 = Mock image generation
- The filter to be used for the masking 
- irun : execution run id (e.g. Run01a)
 
"&& exit

#=========================== INPUT ======================================

# The directory where the input images are located.
DATADIR=$1

# The directory where all output files will be written to.
BDIR=$2

# Name of host galaxy in input image.

read -rp "Enter a galaxy name , like NGC922: " NAME

# has there been an entry?
if [ -z "$NAME" ]
then
  echo "You must enter a galaxy name."
  exit 1
fi

read -rp "Enter execution step   \
1: Detection + Segmentation 2: Empty Sky image generation " step

# is it a valid step?
if (( "$step" < 1 || "$step" > 2)); then
  echo "The step must be a number between 1 and 2."
  exit 0
fi

# All the passband filters (g, r, z) are processed in this script 
# The filter to be used for the masking is determined here
#filter=r

if [ $step -ne 1 ]; then

read -rp "Enter filter to be used for masking (g,r,z): " filter

fi

if [ $step -eq 2 ]; then

# The directory where all the aperture files will be located
APDIR=$3

if [ -z "$APDIR" ]
then
  echo "You must give as 3rd argument the drirectory with the aperture files."
  exit 1
fi

imask=1

read -rp "Execution run id (e.g. Run01a): " irun

fi

#=========================== CONFIGURATION =====================================


# Automatic ellipse mask of the host
automatic=$imask

# Survey
survey=DES

# zeropint for this image
zeropoint=22.5

# Since the feature we want is very diffuse and large, we can use a
# slightly wider kernel, let's try a Gaussian with a FWHM of 3 pixels,
# truncated at 4 times the FWHM. The default kernel has a FWHM of 2.
#

# Run NoiseChisel (tested for version 0.14 and later), here is a
# description of the parameters and why I chose them.
#
#  --kernel: to use our newly built kernel (discussed above).
#  --tilesize: slightly larger (default is 30x30), because its mostly flat.
#  --detgrowmaxholesize: larger, to allow filling larger "holes" in
#                        the detection.


# Detection parameters and default values for streams:
blocksize=8
interpngb=10
nc_tilesize=40
nc_kernel_fwhm=3
#nc_kernel_fwhm=3 default
nc_holesize=10000
#nc_holesize=10000 default
nc_kernel_trunc=4
seg_kernel_fwhm=3
#seg_kernel_fwhm=5 in original script
#seg_kernel_fwhm=1.5 default in Gnuastro?
qthreshold=0.3
#qthreshold=0.4 default, but 0.3 for all DES streams
#detgrowquant=0.9 default set in code
#detgrowquant=0.8 to grow detections
gthreshold=0.5
#gthreshold=0.5 default value
segbordersn=1
#segbordersn=1 default value

# Make the build-directory (if it doesn't already exist).
curdir=$(pwd)
tmpdir=$BDIR/tmp
jpgdir=$BDIR/jpg
texdir=$BDIR/tex
tikzdir=$texdir/tikz
figdir=$texdir/figures
if ! [ -d $BDIR    ]; then mkdir $BDIR; fi
if ! [ -d $tmpdir  ]; then mkdir $tmpdir;  fi
if ! [ -d $jpgdir  ]; then mkdir $jpgdir;  fi
if ! [ -d $texdir  ]; then mkdir $texdir;  fi
if ! [ -d $figdir  ]; then mkdir $figdir; fi
if ! [ -d $tikzdir ]; then mkdir $tikzdir; fi

# Summary output data is output.txt
output=$tmpdir/$NAME-output.txt
#results=Results/$survey-results.txt

#================= DETECTION AND SEGMENTATION ===========================

# The kernel's center is built with Monte-carlo integration (using
# random numbers), so to avoid reproducibility problems, we'll fix the
# random number generator (RNG) seed.
export GSL_RNG_SEED=1599251212
if ! [ -f $tmpdir/kernel.fits ]; then
    astmkprof --kernel=gaussian,$nc_kernel_fwhm,$nc_kernel_trunc \
	      --oversample=1 --envseed --output=$tmpdir/kernel.fits
fi
if ! [ -f $tmpdir/kernel-seg.fits ]; then
    astmkprof --kernel=gaussian,$seg_kernel_fwhm,$nc_kernel_trunc \
	      --oversample=1 --envseed --output=$tmpdir/kernel-seg.fits
fi



# For 'r' band 
#image_r=$NAME-custom-image-r.fits
image_r=$NAME-*-r.fits
imagehdu=0
if ! [ -f $tmpdir/nc-r.fits ]; then
    astnoisechisel $DATADIR/$image_r -h$imagehdu \
		   --kernel=$tmpdir/kernel.fits \
		   --tilesize=$nc_tilesize,$nc_tilesize \
		   --detgrowmaxholesize=$nc_holesize \
       --qthresh=$qthreshold \
		   --output=$tmpdir/nc-r.fits
fi

# For 'g' band 
#image_g=$NAME-custom-image-g.fits
image_g=$NAME-*-g.fits
if ! [ -f $tmpdir/nc-g.fits ]; then
    astnoisechisel $DATADIR/$image_g -h$imagehdu \
		   --kernel=$tmpdir/kernel.fits \
		   --tilesize=$nc_tilesize,$nc_tilesize \
		   --detgrowmaxholesize=$nc_holesize \
       --qthresh=$qthreshold \
		   --output=$tmpdir/nc-g.fits
fi

# For 'z' band 
#image_z=$NAME-custom-image-z.fits
image_z=$NAME-*-z.fits
if ! [ -f $tmpdir/nc-z.fits ]; then
    astnoisechisel $DATADIR/$image_z -h$imagehdu \
		   --kernel=$tmpdir/kernel.fits \
		   --tilesize=$nc_tilesize,$nc_tilesize \
		   --detgrowmaxholesize=$nc_holesize \
       --qthresh=$qthreshold \
		   --output=$tmpdir/nc-z.fits
fi



## Do segmentation to identify all the objects and clumps
# For 'r' band
if ! [ -f $tmpdir/seg-r.fits ]; then
    astsegment $tmpdir/nc-r.fits \
	       --kernel=$tmpdir/kernel-seg.fits \
               --gthresh=$gthreshold \
               --objbordersn=$segbordersn \
	       --output=$tmpdir/seg-r.fits
fi

# For 'g' band
if ! [ -f $tmpdir/seg-g.fits ]; then
    astsegment $tmpdir/nc-g.fits \
	       --kernel=$tmpdir/kernel-seg.fits \
               --gthresh=$gthreshold \
               --objbordersn=$segbordersn \
	       --output=$tmpdir/seg-g.fits
fi

# For 'z' band 
if ! [ -f $tmpdir/seg-z.fits ]; then
    astsegment $tmpdir/nc-z.fits \
	       --kernel=$tmpdir/kernel-seg.fits \
               --gthresh=$gthreshold \
               --objbordersn=$segbordersn \
	       --output=$tmpdir/seg-z.fits
fi



echo detection and segmentation completed



# end of first step
if [ $step -eq 1 ]; then
echo end step 1
exit 0
fi


#=================== GENERATION OF SKY EMPTY IMAGE =============================


echo "GENERATION OF SKY EMPTY IMAGE FOR HOST" $NAME >> $output
echo "SCRIPT VERSION: <mock-image-1-0.sh> "   >> $output
echo "RUN IDENTIFIER "  $irun >> $output
echo "INPUT IMAGES: "$DATADIR"/"$image_r "/" $image_g "/" $image_z    >> $output
RA=$(astfits $DATADIR/$image_r -h$imagehdu --skycoverage --quiet | awk 'NR==1{print $1}')
Dec=$(astfits $DATADIR/$image_r -h$imagehdu --skycoverage --quiet | awk 'NR==1{print $2INPUT_NO_SKY}')
FoVRA=$(astfits $DATADIR/$image_r -h$imagehdu --skycoverage --quiet | awk 'NR==2{print ($2-$1)*60}')
FoVDec=$(astfits $DATADIR/$image_r -h$imagehdu --skycoverage --quiet | awk 'NR==2{print ($4-$3)*60}')
echo "IMAGE CENTRE RA, Dec (degrees): " $RA "," $Dec "FoV (arcmin): " $FoVRA "x" $FoVDec >> $output
pixscale=$(astfits $tmpdir/nc-$filter.fits --key=CDELT1 -q)
xaxispix=$(astfits $tmpdir/nc-$filter.fits --key=NAXIS1 -q)
yaxispix=$(astfits $tmpdir/nc-$filter.fits --key=NAXIS2 -q)
echo "PIXEL SCALE (deg/pixel): " $pixscale "IMAGE DIMENSIONS (pixels): " $xaxispix " x " $yaxispix >> $output  
echo "SELECTED IMAGE FOR MASKING: " $image_$filter          >> $output
echo "ZERO POINT = " $zeropoint >> $output
echo "NOISECHISEL DETECTION CONFIGURATION PARAMETERS-----------------------------------------------" >> $output
echo "qthresh = " $qthreshold >> $output
echo "blocksize = " $blocksize >> $output
echo "interpngb = " $interpngb >> $output
echo "nc_tilesize = " $nc_tilesize >> $output
echo "nc_kernel_fwhm = " $nc_kernel_fwhm >> $output
echo "nc_holesize = " $nc_holesize >> $output
echo "nc_kernel_trunc = " $nc_kernel_trunc >> $output
echo "seg_kernel_fwhm = " $seg_kernel_fwhm >> $output
echo "gthresh  = " $gthreshold >> $output
echo "objbordersn  = " $segbordersn >> $output

echo "=============================================================================================" >> $output

# Find the largest detection label (assumed to be the host galaxy).
if ! [ -f $tmpdir/cat.fits ]; then
    astarithmetic $tmpdir/nc-$filter.fits -hDETECTIONS 2 connected-components \
		  --output=$tmpdir/nc-lab.fits
    astmkcatalog $tmpdir/nc-lab.fits -h1 --ids --geo-area --output=$tmpdir/cat.fits
fi
label=$(asttable $tmpdir/cat.fits --sort=AREA_FULL --column=OBJ_ID --tail=1)



echo largest detection label
echo $label



# Mask all other detected objects and the clumps (to help highlight
# the diffuse components).
if ! [ -f $tmpdir/masked-$filter.fits ]; then

    # Generate the grown clumps image again and label them to find the
    # largest.
    allclumps=$tmpdir/masked-large-clumps.fits
    astarithmetic $tmpdir/seg-$filter.fits -hCLUMPS 0 gt 2 dilate 2 fill-holes \
		  2 connected-components -o$allclumps

    # Find the largest grown clump (which is the center of the galaxy).
    allclumpscat=$tmpdir/masked-large-clumps-cat.fits
    astmkcatalog $allclumps -h1 --ids --geo-area -o$allclumpscat
    largest=$(asttable $allclumpscat --sort=AREA_FULL -cOBJ_ID --tail=1)

    # Mask the clumps except the largest (galaxy center)
    # for the r band
    astarithmetic $tmpdir/nc-r.fits -hINPUT-NO-SKY set-conv \
		  $tmpdir/nc-lab.fits -h1 $label ne 2 erode set-det \
		  $allclumps set-i i i $largest eq 0 where set-clumps \
		  conv det clumps or nan where \
		  --output=$tmpdir/masked-r.fits
    # To mask also all detections except the host galaxy and surroundings 
    # conv det clumps or nan where \
    # To mask only the clumps except the one in the centre of the galaxy
    # conv clumps clumps or nan where \



    # Mask the clumps except the largest (galaxy center)
    # for the g band 
    astarithmetic $tmpdir/nc-g.fits -hINPUT-NO-SKY set-conv \
		  $tmpdir/nc-lab.fits -h1 $label ne 2 erode set-det \
		  $allclumps set-i i i $largest eq 0 where set-clumps \
		  conv det clumps or nan where \
		  --output=$tmpdir/masked-g.fits
        
        
        
    # Mask the clumps except the largest (galaxy center)
    # for the z band 
    astarithmetic $tmpdir/nc-z.fits -hINPUT-NO-SKY set-conv \
		  $tmpdir/nc-lab.fits -h1 $label ne 2 erode set-det \
		  $allclumps set-i i i $largest eq 0 where set-clumps \
		  conv det clumps or nan where \
		  --output=$tmpdir/masked-z.fits

    # Clean up.
    rm $allclumps $allclumpscat
fi


## Mask only the clumps to measure photometry on apertures placed on the stream
##
# Mask clumps in INPUT-NO-SKY for r band
if ! [ -f $tmpdir/clumps-masked-r.fits ]; then
astarithmetic $tmpdir/nc-r.fits -hINPUT-NO-SKY \
              $tmpdir/seg-$filter.fits -hCLUMPS  \
              0 gt 2 dilate nan where \
              -o$tmpdir/clumps-masked-r.fits

# Mask clumps in INPUT-NO-SKY for g band
astarithmetic $tmpdir/nc-g.fits -hINPUT-NO-SKY \
              $tmpdir/seg-$filter.fits -hCLUMPS  \
              0 gt 2 dilate nan where \
              -o$tmpdir/clumps-masked-g.fits

# Mask clumps in INPUT-NO-SKY for z band
astarithmetic $tmpdir/nc-z.fits -hINPUT-NO-SKY \
              $tmpdir/seg-$filter.fits -hCLUMPS  \
              0 gt 2 dilate nan where \
              -o$tmpdir/clumps-masked-z.fits

fi

echo masking completed



if [ $automatic -eq 1 ]; then
############## AUTOMATIC MASKING OF HOST WITH AN ELLIPSE #####################

echo "AUTOMATIC MASKING OF HOST WITH AN ELLIPSE" >> $output

## Create a mask of the galaxy automatically

   # create a file whose pixels have the value of the SNR
   astarithmetic $tmpdir/nc-$filter.fits $tmpdir/nc-$filter.fits / -hINPUT-NO-SKY -hSKY_STD \
                 --output=$tmpdir/SNR.fits

   # detect pixels with SNR > 10 and connect components
   astarithmetic $tmpdir/SNR.fits 10 gt 2 connected-components \
                 --output=$tmpdir/SNRgt.fits

    # find the largest component with SNR > 10, which should be the galaxy
    astmkcatalog $tmpdir/SNRgt.fits  -h1 --ids --geo-area \
                 --output=$tmpdir/SNRgt-cat.fits 
    galaxylabel=$(asttable $tmpdir/SNRgt-cat.fits --sort=AREA_FULL -cOBJ_ID --tail=1)

echo galaxylabel
echo  $galaxylabel

    # create a mask for the galaxy
    astarithmetic $tmpdir/SNRgt.fits -h1 $galaxylabel eq 2 fill-holes 2 dilate \
                  --output=$tmpdir/galaxy-mask.fits


  
    # Find the centre and dimensions of the galaxy mask corresponding ellipse 
    astmkcatalog $tmpdir/galaxy-mask.fits -h1 --ids --geo-area \
                 --geo-x --geo-y --geo-axis-ratio --geo-position-angle \
                 --geo-semi-major --geo-semi-minor \
                 --output=$tmpdir/galaxy-mask-cat.fits
    ellcenterx=$(asttable $tmpdir/galaxy-mask-cat.fits -cGEO_X)
    ellcentery=$(asttable $tmpdir/galaxy-mask-cat.fits -cGEO_Y)
    ellincline=$(asttable $tmpdir/galaxy-mask-cat.fits -cGEO_POSITION_ANGLE)
    ellaxratio=$(asttable $tmpdir/galaxy-mask-cat.fits -cGEO_AXIS_RATIO)
    ellsamajor=$(asttable $tmpdir/galaxy-mask-cat.fits -cGEO_SEMI_MAJOR)
    ellsaminor=$(asttable $tmpdir/galaxy-mask-cat.fits -cGEO_SEMI_MINOR)

echo automask   
echo ellcenterx ellcentery ellincline ellaxratio ellsamajor ellsaminor
echo $ellcenterx $ellcentery $ellincline $ellaxratio $ellsamajor $ellsaminor

#
# initial iteration values
factor=2
SB_g=21
SB_r=21
SB_z=21
itend=0
itend_r=0
itend_g=0
itend_z=0
SB_r_lim=25
ilim_r=0
ellsamajor0=$ellsamajor

echo factor SB_g SB_r SB_z itend
echo $factor $SB_g $SB_r $SB_z $itend 


#### beginning of loop to grow ellipse to galaxy size and measure photometry#######
#
while [ $itend -ne 1 ] || [ $ilim_r -ne 1 ]; do



factor=$(echo $factor | awk '{print $1 + 0.25}')
#factor=$(awk 'BEGIN {print '$factor' + 0.5}')

echo factor
echo $factor



ellsamajor=$(awk 'BEGIN {print '$ellsamajor0' * '$factor'}')
  
echo ellcenterx ellcentery ellincline ellaxratio ellsamajor ellsaminor
echo $ellcenterx $ellcentery $ellincline $ellaxratio $ellsamajor $ellsaminor



# Create an ellipse profile to mask the galaxy
#if ! [ -f $tmpdir/ellipse.fits ]; then

     echo "1 $ellcenterx $ellcentery 5 $ellsamajor 0 $ellincline $ellaxratio 1 1" \
         | astmkprof --background=$tmpdir/nc-$filter.fits --backhdu=INPUT-NO-SKY \
                     --clearcanvas \
                     --mode=img --oversample=1 --mforflatpix \
                     --type=uint8 --output=$tmpdir/ellipse.fits
#fi



# Mask the galaxy
#if ! [ -f $tmpdir/stream.fits ]; then

   astarithmetic $tmpdir/masked-$filter.fits -h1 set-mask \
                 $tmpdir/ellipse.fits -h1 set-ellipse \
                 mask ellipse nan where \
                 --output=$tmpdir/stream.fits
#fi



## Identify the stream within the remaining detections
#
# Create a labeled stream image
#if ! [ -f $tmpdir/labeled-stream.fits ]; then

   astarithmetic $tmpdir/stream.fits -h1 isblank not 1 connected-components \
                 --output=$tmpdir/labeled-stream.fits
#fi



# Find the largest detection label (assumed to be the stream).
#if ! [ -f $tmpdir/cat-labeled-stream.fits ]; then
    astmkcatalog $tmpdir/labeled-stream.fits -h1 --ids --geo-area \
                 --output=$tmpdir/cat-labeled-stream.fits
#fi
streamlabel=$(asttable $tmpdir/cat-labeled-stream.fits --sort=AREA_FULL --column=OBJ_ID --tail=1)

echo streamlabel
echo  $streamlabel


# Create an image of the stream label
#if ! [ -f $tmpdir/stream-footprint.fits ]; then

   astarithmetic $tmpdir/labeled-stream.fits -h1 $streamlabel ne \
                 --output=$tmpdir/nostream-label.fits

   astarithmetic $tmpdir/stream.fits -h1 set-stream \
                 $tmpdir/nostream-label.fits -h1 set-nolable \
                 stream nolable nan where \
                 --output=$tmpdir/stream-final.fits

#fi


 
# Convert stream into a binary image

   astarithmetic $tmpdir/stream-final.fits isblank not \
                 --output=$tmpdir/stream-footprint.fits


 
# Make a catalog with measurements for r band
# For the whole stream with automatic masking
numrandom=10000
astmkcatalog $tmpdir/stream-footprint.fits -h1 --valuesfile=$tmpdir/clumps-masked-r.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-regions-r.fits \
	         --ids --sum --magnitude --magnitude-error --area \
                 --area-arcsec2 --upperlimit-sigma --sn --sb \
                 --sb-error

echo "ITERATION FACTOR" >> $output
echo $factor >> $output
asttable $tmpdir/cat-regions-r.fits >> $output
#
# check convergence
#
SB_r_new=$(asttable $tmpdir/cat-regions-r.fits  -cSURFACE_BRIGHTNESS)
SB_r_delta=$(awk 'BEGIN {print '$SB_r_new' - '$SB_r'}')
SB_r=$SB_r_new
itend_r=$(awk 'BEGIN {if ('$SB_r_delta' <= 0.01 ) print 1; else print 0 }')

#correction of artifact in image
#itend_r=1

#check that we are out of the host 
SB_r_delim=$(awk 'BEGIN {print '$SB_r_lim' - '$SB_r'}')
ilim_r=$(awk 'BEGIN {if ('$SB_r_delim' <= 0.0 ) print 1; else print 0 }')

#correction of artifact in image
#ilim_r=1

echo SB_r_new SB_r_delta itend_r ilim
echo $SB_r_new $SB_r_delta $itend_r $ilim_r



# Make a catalog with measurements for g band
# For the whole stream with automatic masking
astmkcatalog $tmpdir/stream-footprint.fits -h1 --valuesfile=$tmpdir/clumps-masked-g.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
	         --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-g.fits \
	         --zeropoint=$zeropoint -o$tmpdir/cat-regions-g.fits \
                 --ids --sum --magnitude --magnitude-error --area \
                 --area-arcsec2 --upperlimit-sigma --sn --sb \
                 --sb-error

asttable $tmpdir/cat-regions-g.fits >> $output
#
# check convergence
#
SB_g_new=$(asttable $tmpdir/cat-regions-g.fits  -cSURFACE_BRIGHTNESS)
SB_g_delta=$(awk 'BEGIN {print '$SB_g_new' - '$SB_g'}')
SB_g=$SB_g_new
itend_g=$(awk 'BEGIN {if ('$SB_g_delta' <= 0.01 ) print 1; else print 0 }')

echo SB_g_new SB_g_delta itend_g
echo $SB_g_new $SB_g_delta $itend_g
 
 


# end of iteration?
if [ $itend_g -eq 1 ] && [ $itend_r -eq 1 ]; then
itend=1
else
itend=0
fi

echo SB_r_new SB_g_new SB_r_delta SB_g_delta
echo $SB_r_new $SB_g_new $SB_r_delta $SB_g_delta
echo itend_r itend_g itend
echo $itend_r $itend_g $itend

# end of the loop to grow the ellipse and measure photometry
done



   astarithmetic $tmpdir/labeled-stream.fits -h1 0 eq \
                 --output=$tmpdir/nostream.fits


# Select the resulting stream by filtering SNR on the diffuse area
  # create file with SNR vslues in the diffuse zone
   astarithmetic $tmpdir/SNR.fits -h1 set-streamSNR \
                 $tmpdir/nostream.fits -h1 set-nostream \
                 streamSNR nostream nan where \
                 --output=$tmpdir/SNR-stream.fits                
                 
   # create file with SNR > SNRcutoff and connect components
SNRcutoff=1.5
   astarithmetic $tmpdir/SNR-stream.fits $SNRcutoff lt 2 connected-components \
                 --output=$tmpdir/SNR-stream-lt-$SNRcutoff.fits

  # create stream with SNR > SNRcutoff
  # for r band
  astarithmetic $tmpdir/nc-r.fits -hINPUT-NO-SKY set-input \
                 $tmpdir/SNR-stream-lt-$SNRcutoff.fits -h1 set-cutoff \
                 input cutoff cutoff or nan where \
                 --output=$tmpdir/stream-SNR-gt-$SNRcutoff-r.fits   

  # for g band
  astarithmetic $tmpdir/nc-g.fits -hINPUT-NO-SKY set-input \
                 $tmpdir/SNR-stream-lt-$SNRcutoff.fits -h1 set-cutoff \
                 input cutoff cutoff or nan where \
                 --output=$tmpdir/stream-SNR-gt-$SNRcutoff-g.fits   

  # for z band
  astarithmetic $tmpdir/nc-z.fits -hINPUT-NO-SKY set-input \
                 $tmpdir/SNR-stream-lt-$SNRcutoff.fits -h1 set-cutoff \
                 input cutoff cutoff or nan where \
                 --output=$tmpdir/stream-SNR-gt-$SNRcutoff-z.fits   

# Photometry measurement in the stream with SNR > SNR cutoff
  # Make a catalog with measurements for r band
numrandom=10000
astmkcatalog $tmpdir/stream-footprint.fits -h1 --valuesfile=$tmpdir/stream-SNR-gt-$SNRcutoff-r.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-autostream-r.fits \
	         --ids --sum --magnitude --magnitude-error --area \
                 --area-arcsec2 --upperlimit-sigma --sn --sb \
                 --sb-error

echo "FINAL RESULTS WITH SNR-CUTOFF" >> $output
echo $SNRcutoff >> $output
asttable $tmpdir/cat-autostream-r.fits >> $output



  # Make a catalog with measurements for g band
astmkcatalog $tmpdir/stream-footprint.fits -h1 --valuesfile=$tmpdir/stream-SNR-gt-$SNRcutoff-g.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
	         --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-g.fits \
	         --zeropoint=$zeropoint -o$tmpdir/cat-autostream-g.fits \
                 --ids --sum --magnitude --magnitude-error --area \
                 --area-arcsec2 --upperlimit-sigma --sn --sb \
                 --sb-error

asttable $tmpdir/cat-autostream-g.fits >> $output

  # Make a catalog with measurements for z band
astmkcatalog $tmpdir/stream-footprint.fits -h1 --valuesfile=$tmpdir/stream-SNR-gt-$SNRcutoff-z.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
  	         --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-z.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-autostream-z.fits \
	         --ids --sum --magnitude --magnitude-error --area \
                 --area-arcsec2 --upperlimit-sigma --sn --sb \
                 --sb-error

asttable $tmpdir/cat-autostream-z.fits >> $output



fi


############## END OF AUTOMATIC MASKING OF HOST WITH AN ELLIPSE #####################################



# Mask the host galaxy with the ellipse mask calculated in the AUTOMATIC option 

   astarithmetic $tmpdir/nc-r.fits -hINPUT-NO-SKY set-image \
                 $tmpdir/ellipse.fits -h1 set-ellipse \
                 image ellipse nan where \
                 --output=$tmpdir/image-host-masked-r.fits
                 
   astarithmetic $tmpdir/nc-g.fits -hINPUT-NO-SKY set-image \
                 $tmpdir/ellipse.fits -h1 set-ellipse \
                 image ellipse nan where \
                 --output=$tmpdir/image-host-masked-g.fits
                 
   astarithmetic $tmpdir/nc-z.fits -hINPUT-NO-SKY set-image \
                 $tmpdir/ellipse.fits -h1 set-ellipse \
                 image ellipse nan where \
                 --output=$tmpdir/image-host-masked-z.fits




#ellcenterx='1146'
#ellcentery='1150.8265'
#ellincline='93.102259'
#ellsamajor='279.28523'
#ellsaminor='99.259282'
#ellaxratio='0.3554047'


     echo "1 $ellcenterx $ellcentery 5 $ellsamajor 0 $ellincline $ellaxratio 1 1" \
         | astmkprof --background=$tmpdir/nc-r.fits --backhdu=INPUT-NO-SKY \
                     --clearcanvas \
                     --mode=img --oversample=1 --mforflatpix \
                     --type=uint8 --output=$tmpdir/ellipse-on-host.fits


# end of first step
if [ $step -eq 1 ]; then
echo end step 1
exit 0
fi

######### STEP 2 GENERATE AN EMPTYNSKY IMAGE ###################



# Create an ellipse mask with the displaced host aperture
# This should be done by creating a region identical to the ellipse
# mask covering the central galaxy but placed in a part of the
# image with only sky (no significant sources). This is to be done 
# manually in ds9, and the region file input here directly.
# BUT for this test run the coordinates of the displaced ellipse 
# region are input here manually 

# ellipse on host
#1146,1150.8265,279.28523,99.259282,93.102259

# ellipse displaced
#1458.1166,1311.7113,279.28523,99.259282,93.102259

ellcenter='1458.1166 1311.7113'
ellincline='93.102259'
ellsamajor='279.28523'
ellsaminor='99.259282'
ellaxratio='0.3554047'

echo stream ellipse aperture
echo ellcenter ellincline ellaxratio ellsamajor ellsaminor
echo $ellcenter $ellincline $ellaxratio $ellsamajor $ellsaminor

     echo "1 $ellcenter 5 $ellsamajor 0 $ellincline $ellaxratio 1 1" \
         | astmkprof --background=$tmpdir/nc-r.fits --backhdu=INPUT-NO-SKY  \
                     --clearcanvas \
                     --mode=img --oversample=1 --mforflatpix \
                     --type=uint8 --output=$tmpdir/ellipse-displaced.fits
# this file is actually not being used


### begin input from Mohammad
#astwarp image.fits --translate=X,Y --output=translated.fits

#sec=$(astfits nogalaxy.fits --keyvalue=NAXIS1,NAXIS2 --quiet |    awk
#'{printf ":%s,:%s", $1, $2}')

#astcrop translated.fits --mode=img --section=$sec -ocropped.fits

#astarithmetic nogalaxy.fits set-i i i isblank cropped.fits where -g1
#--output=filled.fits

### end inoput from Mohammad


# translate image by the centre distance between ellipse-on-host and ellipse-displaced
#    astwarp --matrix="0.785945376,0,0,0.877347401" $tmpdir/nc-$filter.fits -hINPUT-NO-SKY \
#
# for r band
    astwarp --translate=-312,-161 $tmpdir/nc-r.fits -hINPUT-NO-SKY \
	    --output=$tmpdir/translated-r.fits
         
# for g band
    astwarp --translate=-312,-161 $tmpdir/nc-g.fits -hINPUT-NO-SKY \
	    --output=$tmpdir/translated-g.fits
         
# for z band
    astwarp --translate=-312,-161 $tmpdir/nc-z.fits -hINPUT-NO-SKY \
	    --output=$tmpdir/translated-z.fits



#sec=$(astfits $tmpdir/image-host-masked-r.fits --keyvalue=NAXIS1,NAXIS2 --quiet |    awk
#'{printf ":%s,:%s", $1, $2}')

#astcrop $tmpdir/translated-$filter.fits --mode=img --section='1:2290,1:2290' \
astcrop $tmpdir/translated-r.fits --mode=img --section='314:2603,163:2452' \
    --output=$tmpdir/translated-cropped-r.fits
    
astcrop $tmpdir/translated-g.fits --mode=img --section='314:2603,163:2452' \
    --output=$tmpdir/translated-cropped-g.fits
    
astcrop $tmpdir/translated-z.fits --mode=img --section='314:2603,163:2452' \
    --output=$tmpdir/translated-cropped-z.fits       



astarithmetic $tmpdir/nc-r.fits -hINPUT-NO-SKY set-image \
                 $tmpdir/ellipse-on-host.fits -h1 set-ellipse \
                 $tmpdir/translated-cropped-r.fits -h1 set-displaced \
                 image ellipse displaced where \
                 --output=$tmpdir/image-emptysky-r.fits

astcrop $tmpdir/translated-$filter.fits --mode=img --section='314:2603,163:2452' \
    --output=$tmpdir/translated-cropped-$filter.fits

astarithmetic $tmpdir/nc-g.fits -hINPUT-NO-SKY set-image \
                 $tmpdir/ellipse-on-host.fits -h1 set-ellipse \
                 $tmpdir/translated-cropped-g.fits -h1 set-displaced \
                 image ellipse displaced where \
                 --output=$tmpdir/image-emptysky-g.fits
                 
astcrop $tmpdir/translated-$filter.fits --mode=img --section='314:2603,163:2452' \
    --output=$tmpdir/translated-cropped-z.fits

astarithmetic $tmpdir/nc-z.fits -hINPUT-NO-SKY set-image \
                 $tmpdir/ellipse-on-host.fits -h1 set-ellipse \
                 $tmpdir/translated-cropped-$filter.fits -h1 set-displaced \
                 image ellipse displaced where \
                 --output=$tmpdir/image-emptysky-z.fits

############### END EMPTY SKY IMAGE GENERATION ######################################## 


#=================== UPPER LIMIT MEASUREMENT ============================


if [ $step -eq 2 ]; then
############ UPPER LIMIT SURFACE BRIGHTNESS  ################################

echo "=============================================================================================" >> $output
echo "SURFACE BRIGHTNESS LIMIT and UPPER LIMIT SURFACE BRIGHTNESS" >> $output


# Build aperture of 100 arcsec2 to measure UL-SB 
rarcsec=5.64
numrandom=10000
CRA=$(astfits $tmpdir/masked-$filter.fits -h1 --keyvalue=CRVAL1 --quiet)
CDEC=$(astfits $tmpdir/masked-$filter.fits -h1 --keyvalue=CRVAL2 --quiet)
apcenter="$CRA $CDEC"
#apcenter="27.6086924,-12.6765205"

    aper=$tmpdir/aperture-ULSB.fits
    rpix=$(astfits $tmpdir/nc-r.fits --pixelscale -q \
	       | awk '{print '$rarcsec'/($1*3600)}')
    echo "1 $apcenter 5 $rpix 0 0 1 1 1" \
	| astmkprof --background=$tmpdir/nc-r.fits --clearcanvas \
		    --mode=wcs --oversample=1 --mforflatpix \
		    --type=uint8 -o$aper

# Make a catalog with upper-limit measurements for the r band.
if ! [ -f $tmpdir/cat-region-r-ULSB.fits ]; then

    astmkcatalog $aper -h1 --valuesfile=$tmpdir/nc-r.fits --envseed \
		 --valueshdu=INPUT-NO-SKY --checkuplim=1 --upnum=$numrandom \
     --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
		 --zeropoint=$zeropoint -o$tmpdir/cat-region-r-ULSB.fits \
		 --ids --sum --sum-error --magnitude --magnitude-error --area --area-arcsec2 \
		 --upperlimit-sigma --sn --sb --sb-error --upperlimit-sb

echo "SURFACE BRIGHTNESS LIMIT---------------------------------------------------------------------" >> $output

   # Write results to a file
echo "r band" >> $output  
#    asttable $tmpdir/cat-region-r-ULSB.fits >> $output
    ulsbr=$(asttable $tmpdir/cat-region-r-ULSB.fits -cUPPERLIMIT_SB)
    astfits $tmpdir/cat-region-r-ULSB.fits -h1 | grep ^SBL >> $output
    sblimr=$(astfits $tmpdir/cat-region-r-ULSB.fits -h1 --keyvalue=SBLMAG --quiet)
#   astfits $tmpdir/cat-region-r-ULSB.fits -h1 | grep ^UP >> $output

fi

# Make a catalog with upper-limit measurements for the g band.
if ! [ -f $tmpdir/cat-region-g-ULSB.fits ]; then

    astmkcatalog $aper -h1 --valuesfile=$tmpdir/nc-g.fits --envseed \
		 --valueshdu=INPUT-NO-SKY --checkuplim=1 --upnum=$numrandom \
     --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
		 --zeropoint=$zeropoint -o$tmpdir/cat-region-g-ULSB.fits \
		 --ids --sum --sum-error --magnitude --magnitude-error --area --area-arcsec2 \
		 --upperlimit-sigma --sn --sb --sb-error --upperlimit-sb

   # Write results to a file
echo "g band" >> $output  
#     asttable $tmpdir/cat-region-g-ULSB.fits >> $output
     ulsbg=$(asttable $tmpdir/cat-region-g-ULSB.fits -cUPPERLIMIT_SB)
     astfits $tmpdir/cat-region-g-ULSB.fits -h1 | grep ^SBL >> $output
     sblimg=$(astfits $tmpdir/cat-region-g-ULSB.fits -h1 --keyvalue=SBLMAG --quiet)
#   astfits $tmpdir/cat-region-g-ULSB.fits -h1 | grep ^UP >> $output

fi

# Make a catalog with upper-limit measurements for the z band.
if ! [ -f $tmpdir/cat-region-z-ULSB.fits ]; then

    astmkcatalog $aper -h1 --valuesfile=$tmpdir/nc-z.fits --envseed \
		 --valueshdu=INPUT-NO-SKY --checkuplim=1 --upnum=$numrandom \
     --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
		 --zeropoint=$zeropoint -o$tmpdir/cat-region-z-ULSB.fits \
		 --ids --sum --sum-error --magnitude --magnitude-error --area --area-arcsec2 \
		 --upperlimit-sigma --sn --sb --sb-error --upperlimit-sb

   # Write results to a file
echo "z band" >> $output  
#     asttable $tmpdir/cat-region-z-ULSB.fits >> $output
     ulsbz=$(asttable $tmpdir/cat-region-z-ULSB.fits -cUPPERLIMIT_SB)
     astfits $tmpdir/cat-region-z-ULSB.fits -h1 | grep ^SBL >> $output
     sblimz=$(astfits $tmpdir/cat-region-z-ULSB.fits -h1 --keyvalue=SBLMAG --quiet)
#   astfits $tmpdir/cat-region-z-ULSB.fits -h1 | grep ^UP >> $output


echo "UPPER LIMIT MEASUREMENT----------------------------------------------------------------------" >> $output
echo "# Column 1: UPPERLIMIT_SB-r [mag/arcsec^2, float32] Upper limit surface brightness for r band, 3-sigma, 100 arcsec^2." >> $output
echo "# Column 2: UPPERLIMIT_SB-g [mag/arcsec^2, float32] Upper limit surface brightness for g band, 3-sigma, 100 arcsec^2." >> $output
echo "# Column 3: UPPERLIMIT_SB-z [mag/arcsec^2, float32] Upper limit surface brightness for z band, 3-sigma, 100 arcsec^2." >> $output
echo "---------------------------------------------------------------------------------------------" >> $output
#echo "# Column 12: SB-LIMIT-r [mag/arcsec^2, float32] surface brightness limit for r band." >> $output
#echo "# Column 23: SB-LIMIT-g [mag/arcsec^2, float32] surface brightness limit for g band." >> $output
#echo "# Column 24: SB-LIMIT-z [mag/arcsec^2, float32] surface brightness limit for g band." >> $output



echo $ulsbr $ulsbg $ulsbz >> $output
#echo $sblimr >> $output
#echo $sblimg >> $output
#echo $sblimz >> $output


fi

echo "end measurements"
############ END MEASUREMENTS #####################################

# end of second step
echo end step 2
exit 1
fi
