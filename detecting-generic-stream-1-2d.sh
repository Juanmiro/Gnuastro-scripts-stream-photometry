#!/bin/bash
set -e
# High-level script to calculate the photometry of tidal streams.
#
# Scriot version 1.2 with the following additions wrt the previous version:
# - galactic extinction corrected magnitudes and colours (based on ned) 
# - measurement of photometry on the host galaxy if selected (ihost = 1)
# - measurement of photometry on the progenitor if detected (iprog = 1)
# - all output in one file <HOSTNAME-output.txt>
# - output file for color/SB gradient plots (TopCat) <HOSTNAME-output-apertures.txt>
# - one line per host in the global output Results/<SURVEYNAME-results.txt>
# - results include distance of stream and progetitor to the host's centre
# 
# Scriot version 1.2a with the following additions wrt the previous version:
# - polynomial aperture in addition to circular apertures if selcted (ipoly=1)
#
# Scriot version 1.2b with the following additions wrt the previous version:
# - additional line of output from polynomial apertures, extinction corrected
# - execution run identifier requested as input to be added to output (e.g. Run01a)
#
# Scriot version 1.2c with the following additions wrt the previous version:
# - commented the call to astwarp
#
# Run `./project --help' for a description of how to use it.
#
# Copyright (C) 2020-2021 Mohammad Akhlaghi <mohammad@akhlaghi.org>
# Copyright (C) 2021 Juan Miro <miro.juan@gmail.com>
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
This script uses Gnuastro programs to measure the photometry of stellar
tidal streams based on circular apertures placed on the stream with ds9.

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
- The execution step required: 
    1 = Detection+Segmentation 
    2 = Photometry
    3 = PDF generation
    4 = LaTex plots + documen 
- The filter to be used for the masking
 
 For step 2 Photometry:

in addition 

- ihost: measure the photometry of the host? if yes enter 1, if no enter 0
- iprog: measure the photometry of the progenitor? if yes enter 1, if no enter 0
- ipoly: measure the photometry in a polygonal aperture? if yes enter 1, if no enter 0
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

# The execution step required: 
#    1 = Detection+Segmentation 
#    2 = Photometry
#    3 = PDF generation
#    4 = LaTex plots + document
#step=1

read -rp "Enter execution step   \
1: Detection + Segmentation 2: Photometry 3: PDF generation 4: LaTex: " step

# is it a valid step?
if (( "$step" < 1 || "$step" > 4)); then
  echo "The step must be a number between 1 and 4."
  exit 0
fi


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

read -rp "Measure the photometry of the host? if yes enter 1, if no enter 0: " ihost

read -rp "Measure the photometry of the progenitor? if yes enter 1, if no enter 0: " iprog

read -rp "Measure the photometry in a polygonal aperture? if yes enter 1, if no enter 0: " ipoly

#read -rp "Mask the host galaxy influence? if yes enter 1, if no enter 0: " imask
imask=0

read -rp "Execution run id (e.g. Run01a): " irun

fi

#=========================== CONFIGURATION =====================================

# Automatic conversion of aperture.reg to XYR.txt
apertureconv=1

# One line per run in the global output Results/<SURVEYNAME-results.txt> 
iglobalresults=0

# Method to use to measure the photometry
# automatic: photometry is measured on the difuse region detected by Gnuastro
automatic=$imask
# apertures: photometry is meaured on manually placed circular apertures
apertures=1
# ellipse: photometry is meaured on a manually placed elliptical aperture
ellipse=0
# polygon: photometry is meaured on a manually placed polygonal aperture
polygon=$ipoly

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
outputaper=$tmpdir/$NAME-output-apertures.txt
results=Results/$survey-results.txt

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

#to limit the size/number of clumps
#        --clumpsnthresh=1 \

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


#=================== PHOTOMETRY MEASUREMENT =============================


echo "PHOTOMETRY MEASUREMENT OF STREAM AROUND GALAXY" $NAME >> $output
echo "SCRIPT VERSION: <detecting-generic-stream-1-2.sh> "   >> $output
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
    astmkcatalog $tmpdir/nc-lab.fits -h1 --ids --area --output=$tmpdir/cat.fits
fi
label=$(asttable $tmpdir/cat.fits --sort=AREA --column=OBJ_ID --tail=1)



echo largest detection label
echo $label



# Warp (block) the image.
#if ! [ -f $tmpdir/warped.fits ]; then
#    astwarp --scale=1/$blocksize --centeroncorner $tmpdir/nc-$filter.fits -hINPUT-NO-SKY \
#	    --output=$tmpdir/warped.fits
#fi



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
    astmkcatalog $allclumps -h1 --ids --area -o$allclumpscat
    largest=$(asttable $allclumpscat --sort=AREA -cOBJ_ID --tail=1)

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

## Test to check the masking of the clumps
# Interpolate over the clumps and check interpolated image is smooth
#if ! [ -f $tmpdir/interpolated.fits ]; then
#    echo;
#    echo "Doing interpolation, this may take a minute or two...";
#    echo
#    astarithmetic $tmpdir/masked-r.fits set-i \
#                    i $tmpdir/nc-lab.fits -h1 \
#		    $label ne 2 erode \
#		    i minvalue \
#		  where $interpngb interpolate-medianngb \
#		  --output=$tmpdir/interpolated-r.fits
#fi


if [ $automatic -eq 1 ]; then
############## AUTOMATIC ######################################################
##This option is not working generally; to activate it imask must be set to 1##

echo "PHOTOMETRY MEASURED ON DIFUSE REGION DETECTED BY NOISECHISEL" >> $output

## Create a mask of the galaxy automatically

   # create a file whose pixels have the value of the SNR
   astarithmetic $tmpdir/nc-$filter.fits $tmpdir/nc-$filter.fits / -hINPUT-NO-SKY -hSKY_STD \
                 --output=$tmpdir/SNR.fits

   # detect pixels with SNR > 10 and connect components
   astarithmetic $tmpdir/SNR.fits 10 gt 2 connected-components \
                 --output=$tmpdir/SNRgt.fits

    # find the largest component with SNR > 10, which should be the galaxy
    astmkcatalog $tmpdir/SNRgt.fits  -h1 --ids --area \
                 --output=$tmpdir/SNRgt-cat.fits 
    galaxylabel=$(asttable $tmpdir/SNRgt-cat.fits --sort=AREA -cOBJ_ID --tail=1)

echo galaxylabel
echo  $galaxylabel

    # create a mask for the galaxy
    astarithmetic $tmpdir/SNRgt.fits -h1 $galaxylabel eq 2 fill-holes 2 dilate \
                  --output=$tmpdir/galaxy-mask.fits


  
    # Find the centre and dimensions of the galaxy mask corresponding ellipse 
    astmkcatalog $tmpdir/galaxy-mask.fits -h1 --ids --area \
                 --geox --geoy --geoaxisratio --geopositionangle \
                 --geosemimajor --geosemiminor \
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



factor=$(echo $factor | awk '{print $1 + 0.2}')
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
    astmkcatalog $tmpdir/labeled-stream.fits -h1 --ids --area \
                 --output=$tmpdir/cat-labeled-stream.fits
#fi
streamlabel=$(asttable $tmpdir/cat-labeled-stream.fits --sort=AREA --column=OBJ_ID --tail=1)

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
#if ! [ -f $tmpdir/stream-footprint.fits ]; then

   astarithmetic $tmpdir/stream-final.fits isblank not \
                 --output=$tmpdir/stream-footprint.fits
#fi


 
# Make a catalog with measurements for r band
# For the whole stream with automatic masking
numrandom=10000
astmkcatalog $tmpdir/stream-footprint.fits -h1 --valuesfile=$tmpdir/clumps-masked-r.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-regions-r.fits \
	         --ids --brightness --magnitude --magnitudeerr --area \
                 --areaarcsec2 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

echo "ITERATION FACTOR" >> $output
echo $factor >> $output
asttable $tmpdir/cat-regions-r.fits >> $output
#
# check convergence
#
SB_r_new=$(asttable $tmpdir/cat-regions-r.fits  -cSURFACE_BRIGHTNESS)
SB_r_delta=$(awk 'BEGIN {print '$SB_r_new' - '$SB_r'}')
SB_r=$SB_r_new
itend_r=$(awk 'BEGIN {if ('$SB_r_delta' <= 0.1 ) print 1; else print 0 }')

#correction of artifact in image
#itend_r=1

#check that we are out of the host 
SB_r_delim=$(awk 'BEGIN {print '$SB_r_lim' - '$SB_r'}')
ilim_r=$(awk 'BEGIN {if ('$SB_r_delim' <= 0.1 ) print 1; else print 0 }')

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
                 --ids --brightness --magnitude --magnitudeerr --area \
                 --areaarcsec2 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

asttable $tmpdir/cat-regions-g.fits >> $output
#
# check convergence
#
SB_g_new=$(asttable $tmpdir/cat-regions-g.fits  -cSURFACE_BRIGHTNESS)
SB_g_delta=$(awk 'BEGIN {print '$SB_g_new' - '$SB_g'}')
SB_g=$SB_g_new
itend_g=$(awk 'BEGIN {if ('$SB_g_delta' <= 0.1 ) print 1; else print 0 }')

echo SB_g_new SB_g_delta itend_g
echo $SB_g_new $SB_g_delta $itend_g
 
 

# Make a catalog with measurements for z band
# For the whole stream with automatic masking
#astmkcatalog $tmpdir/stream-footprint.fits -h1 --valuesfile=$tmpdir/clumps-masked-z.fits --envseed \
#		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
#                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
#  	         --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
#                 --instd=$tmpdir/nc-z.fits \
#		 --zeropoint=$zeropoint -o$tmpdir/cat-regions-z.fits \
#	         --ids --brightness --magnitude --magnitudeerr --area \
#                 --areaarcsec2 --upperlimitsigma --sn --surfacebrightness \
#                 --sberror

#asttable $tmpdir/cat-regions-z.fits >> $output

#
# check convergence
#
#SB_z_new=$(asttable $tmpdir/cat-regions-z.fits  -cSURFACE_BRIGHTNESS)
#SB_z_delta=$(awk 'BEGIN {print '$SB_z_new' - '$SB_z'}')
#SB_z=$SB_z_new
#itend_z=$(awk 'BEGIN {if ('$SB_z_delta' <= 0.1 ) print 1; else print 0 }')

#echo SB_z_new SB_z_delta itend_z
#echo $SB_z_new $SB_z_delta $itend_z

 

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
	         --ids --brightness --magnitude --magnitudeerr --area \
                 --areaarcsec2 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

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
                 --ids --brightness --magnitude --magnitudeerr --area \
                 --areaarcsec2 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

asttable $tmpdir/cat-autostream-g.fits >> $output

  # Make a catalog with measurements for z band
astmkcatalog $tmpdir/stream-footprint.fits -h1 --valuesfile=$tmpdir/stream-SNR-gt-$SNRcutoff-z.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
  	         --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-z.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-autostream-z.fits \
	         --ids --brightness --magnitude --magnitudeerr --area \
                 --areaarcsec2 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

asttable $tmpdir/cat-autostream-z.fits >> $output



fi


if [ $apertures -eq 1 ]; then
############## MANUAL APERTURES #####################################


echo "PHOTOMETRY MEASURED IN CIRCULAR APERTURES" >> $output


### Measure the surface brighness, colours and limits on the stream.



# Mask the host galaxy with the ellipse mask calculated in the AUTOMATIC option 
if [ $imask -eq 1 ]; then

   astarithmetic $tmpdir/clumps-masked-r.fits -h1 set-mask \
                 $tmpdir/ellipse.fits -h1 set-ellipse \
                 mask ellipse nan where \
                 --output=$tmpdir/clumps-host-masked-r.fits
                 
   astarithmetic $tmpdir/clumps-masked-g.fits -h1 set-mask \
                 $tmpdir/ellipse.fits -h1 set-ellipse \
                 mask ellipse nan where \
                 --output=$tmpdir/clumps-host-masked-g.fits
                 
   astarithmetic $tmpdir/clumps-masked-z.fits -h1 set-mask \
                 $tmpdir/ellipse.fits -h1 set-ellipse \
                 mask ellipse nan where \
                 --output=$tmpdir/clumps-host-masked-z.fits


cp $tmpdir/clumps-host-masked-r.fits $tmpdir/clumps-masked-r.fits 
cp $tmpdir/clumps-host-masked-g.fits $tmpdir/clumps-masked-g.fits 
cp $tmpdir/clumps-host-masked-z.fits $tmpdir/clumps-masked-z.fits 

fi




# Read manual apertures and convert them to XYR.txt
if [ $apertureconv -eq 1 ]; then

grep ^circle $APDIR/$NAME-apertures-physical.reg \
     | sed -e's/circle(//' -e's/)//' -e's/,/ /g' \
     | awk '{printf "%-20s%-20s%s\n", $1, $2, $3}'\
     > $APDIR/$NAME-XYR-apertures.txt
 
cp $APDIR/$NAME-apertures-physical.reg $tmpdir/$NAME-apertures-physical.reg
cp $APDIR/$NAME-XYR-apertures.txt $tmpdir/$NAME-XYR-apertures.txt

echo "APERTURES: Coordinates X,Y (pix) Radius (pix) RA,Dec (deg) Radius (as) Distance to image centre (as) " >> $output
asttable $tmpdir/$NAME-XYR-apertures.txt -c1,2,3,'arith $1 $2 img-to-wcs' \
         --wcshdu=INPUT-NO-SKY --wcsfile=$tmpdir/nc-$filter.fits \
         --output=$tmpdir/$NAME-XYRRaDec-apertures.txt

asttable $tmpdir/$NAME-XYRRaDec-apertures.txt \
         -c1,2,3,4,5 \
         -c'arith $3 '$pixscale' x 3600 x' \
         --colmetadata=6,Ras,arcsec,"Aperture radius (arcsec)" \
         --output=$tmpdir/$NAME-XYRRaDecRas-apertures.txt 

# Distance of apertures centre to host galaxy centre

asttable $tmpdir/$NAME-XYRRaDecRas-apertures.txt \
         -c1,2,3,4,5,6 \
         -c'arith $4 '$RA' - 2 pow $5 '$Dec' - 2 pow + sqrt 3600 x' \
         --colmetadata=7,distas,arcsec,"Aperture center distance to host (arcsec)" \
         --output=$tmpdir/$NAME-apertures-coordinates.txt 

asttable $tmpdir/$NAME-apertures-coordinates.txt >> $output


radiusmean=$(aststatistics $tmpdir/$NAME-apertures-coordinates.txt  -c6 --mean) >> $output
widthmean=$(awk 'BEGIN {print '$radiusmean' * 2}')
distmax=$(aststatistics $tmpdir/$NAME-apertures-coordinates.txt  -c7 --maximum) >> $output
distmin=$(aststatistics $tmpdir/$NAME-apertures-coordinates.txt  -c7 --minimum) >> $output


fi

## Create aperture profiles from an aperture definition input file 
numrandom=10000
apercat_raw=$APDIR/$NAME-XYR-apertures.txt
aperimg=$tmpdir/apertures.fits
echo numrandom zeropoint
echo $numrandom $zeropoint
awk '{print NR, $1, $2, 5, $3, 0, 0, 1, NR, 1}' $apercat_raw \
    | astmkprof --background=$tmpdir/nc-r.fits --clearcanvas \
		    --mode=img --oversample=1 --mforflatpix \
		    --type=uint8 --replace -o$aperimg

## Make a catalog with measurements on predefined apertures
#
# For r band
# 
# Filtering the clumps (except the host galaxy) and all other objects
#astmkcatalog $aperimg -h1 --valuesfile=$tmpdir/masked-r.fits --envseed \
# Filtering all the clumps
#astmkcatalog $aperimg -h1 --valuesfile=$tmpdir/clumps-masked-r.fits --envseed \
astmkcatalog $aperimg -h1 --valuesfile=$tmpdir/clumps-masked-r.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-regions-r.fits \
	         --ids --area --areaarcsec2 --brightness --brightnesserr --magnitude --magnitudeerr \
                 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

echo "---------------------------------------------------------------------------------------------" >> $output
echo "# Column 1:APERTURE ID		      [Integer,] Circular aperture identifier." >> $output
echo "# Column 2:AREA      			      [Integer,] Area of the circular aperture in pixels." >> $output
echo "# Column 3:AREAARCSEC2		      [arcsec^2, f32,] Area of the circular aperture in arcsec^2." >> $output
echo "# Column 4:BRIGHTNESS	  	      [counts, f32,] Sum of sky-subtracted pixel values in the circular aperture ." >> $output
echo "# Column 5:BRIGHTNESS_ERROR	    [counts, f32,] Error (1-sigma) in measuring brightness." >> $output
echo "# Column 6:MAGNITUDE	  	      [mag, f32,] Magnitude measured in the circular aperture." >> $output
echo "# Column 7:MAGNITUDE_ERROR	    [mag, f32,] Error in measring magnitude." >> $output
echo "# Column 8:UPPERLIMITSIGMA	    [Integer,] Multiple of 'upper limit' sigma." >> $output
echo "# Column 9:SNR			            [Integer,] Signal to noise ratio." >> $output
echo "# Column 10:SURFACE_BRIGHTNESS	[mag/arcsec^2, f32,] Surface brightness." >> $output
echo "# Column 11:SB_ERROR		        [mag/arcsec^2, f32,] Error in measuring surface brightness." >> $output
echo "---------------------------------------------------------------------------------------------" >> $output



echo "r band" >> $output
asttable $tmpdir/cat-regions-r.fits >> $output

# Calculation of average values for r band

magmeanr=$(aststatistics $tmpdir/cat-regions-r.fits  -cMAGNITUDE --mean) >> $output
magerrorr=$(aststatistics $tmpdir/cat-regions-r.fits  -cMAGNITUDE_ERROR --mean) >> $output
sbmeanr=$(aststatistics $tmpdir/cat-regions-r.fits  -cSURFACE_BRIGHTNESS --mean) >> $output
sberrorr=$(aststatistics $tmpdir/cat-regions-r.fits  -cSB_ERROR --mean) >> $output
ulsigmeanr=$(aststatistics $tmpdir/cat-regions-r.fits  -cUPPERLIMIT_SIGMA --mean) >> $output
#uplsbr=$(aststatistics $tmpdir/cat-regions-r.fits  -cUPPERLIMIT_SB --mean)


# For g band
#
# Filtering the clumps (except the host galaxy) and all other objects
#astmkcatalog $aperimg -h1 --valuesfile=$tmpdir/masked-g.fits --envseed \
# Filtering all the clumps
#astmkcatalog $aperimg -h1 --valuesfile=$tmpdir/clumps-masked-g.fits --envseed \
astmkcatalog $aperimg -h1 --valuesfile=$tmpdir/clumps-masked-g.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
	         --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-g.fits \
	         --zeropoint=$zeropoint -o$tmpdir/cat-regions-g.fits \
                 --ids --area --areaarcsec2 --brightness --brightnesserr --magnitude --magnitudeerr  \
                 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

echo "g band" >> $output
asttable $tmpdir/cat-regions-g.fits >> $output
 
#calculation of average values for g band

magmeang=$(aststatistics $tmpdir/cat-regions-g.fits  -cMAGNITUDE --mean) >> $output
magerrorg=$(aststatistics $tmpdir/cat-regions-g.fits  -cMAGNITUDE_ERROR --mean) >> $output
sbmeang=$(aststatistics $tmpdir/cat-regions-g.fits  -cSURFACE_BRIGHTNESS --mean) >> $output
sberrorg=$(aststatistics $tmpdir/cat-regions-g.fits  -cSB_ERROR --mean) >> $output
ulsigmeang=$(aststatistics $tmpdir/cat-regions-g.fits  -cUPPERLIMIT_SIGMA --mean) >> $output
#uplsbg=$(aststatistics $tmpdir/cat-regions-g.fits  -cUPPERLIMIT_SB --mean)
 

# Ffor z band
#
# Filtering the clumps (except the host galaxy) and all other objects
#astmkcatalog $aperimg -h1 --valuesfile=$tmpdir/masked-z.fits --envseed \
# Filtering all the clumps
#astmkcatalog $aperimg -h1 --valuesfile=$tmpdir/clumps-masked-z.fits --envseed \
astmkcatalog $aperimg -h1 --valuesfile=$tmpdir/clumps-masked-z.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
  	         --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-z.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-regions-z.fits \
	         --ids --area --areaarcsec2 --brightness --brightnesserr --magnitude --magnitudeerr \
           --upperlimitsigma --sn --surfacebrightness \
                 --sberror

echo "z band" >> $output
asttable $tmpdir/cat-regions-z.fits >> $output

#calculation of average values for z band

magmeanz=$(aststatistics $tmpdir/cat-regions-z.fits  -cMAGNITUDE --mean) >> $output
magerrorz=$(aststatistics $tmpdir/cat-regions-z.fits  -cMAGNITUDE_ERROR --mean) >> $output
sbmeanz=$(aststatistics $tmpdir/cat-regions-z.fits  -cSURFACE_BRIGHTNESS --mean) >> $output
sberrorz=$(aststatistics $tmpdir/cat-regions-z.fits  -cSB_ERROR --mean) >> $output
ulsigmeanz=$(aststatistics $tmpdir/cat-regions-z.fits  -cUPPERLIMIT_SIGMA --mean) >> $output
#uplsbz=$(aststatistics $tmpdir/cat-regions-z.fits  -cUPPERLIMIT_SB --mean)


## Calculate colours in apertures and averages
# merge the tables for g, r and z
asttable $tmpdir/cat-regions-g.fits -h1 \
         --column=OBJ_ID,MAGNITUDE,MAGNITUDE_ERROR \
         --catcolumnfile=$tmpdir/cat-regions-r.fits \
         --catcolumnfile=$tmpdir/cat-regions-z.fits \
         --catcolumnhdu=1 --catcolumnhdu=1 \
         --catcolumns=MAGNITUDE \
         --colmetadata=MAGNITUDE,MAGNITUDE-g,mag,"Magnitude in g band" \
         --colmetadata=MAGNITUDE-1,MAGNITUDE-r,mag,"Magnitude in r band" \
         --colmetadata=MAGNITUDE-2,MAGNITUDE-z,mag,"Magnitude in z band" \
         --output=$tmpdir/cat-all-bands_1.fits 

echo cat-all-bands_1

asttable $tmpdir/cat-all-bands_1.fits -h1 \
         --column=OBJ_ID,MAGNITUDE-g,MAGNITUDE_ERROR,MAGNITUDE-r,MAGNITUDE-z \
         --catcolumnfile=$tmpdir/cat-regions-r.fits \
         --catcolumnfile=$tmpdir/cat-regions-z.fits \
         --catcolumnhdu=1 --catcolumnhdu=1 \
         --catcolumns=MAGNITUDE_ERROR \
         --colmetadata=MAGNITUDE_ERROR,MAGNITUDE_ERROR-g,mag,"Magnitude in g band" \
         --colmetadata=MAGNITUDE_ERROR-1,MAGNITUDE_ERROR-r,mag,"Magnitude in r band" \
         --colmetadata=MAGNITUDE_ERROR-2,MAGNITUDE_ERROR-z,mag,"Magnitude in z band" \
         --output=$tmpdir/cat-all-bands.fits 

echo cat-all-bands

asttable $tmpdir/cat-all-bands.fits


# table with magnitudes, colours and colour errors 
asttable $tmpdir/cat-all-bands.fits -h1 \
         -cOBJ_ID,MAGNITUDE-g,MAGNITUDE-r,MAGNITUDE-z \
         -cMAGNITUDE_ERROR-g,MAGNITUDE_ERROR-r,MAGNITUDE_ERROR-z \
         -c'arith MAGNITUDE-g MAGNITUDE-r -' \
         -c'arith MAGNITUDE_ERROR-g 2 pow MAGNITUDE_ERROR-r 2 pow + sqrt' \
         -c'arith MAGNITUDE-g MAGNITUDE-z -' \
         -c'arith MAGNITUDE_ERROR-g 2 pow MAGNITUDE_ERROR-z 2 pow + sqrt' \
         -c'arith MAGNITUDE-r MAGNITUDE-z -' \
         -c'arith MAGNITUDE_ERROR-r 2 pow MAGNITUDE_ERROR-z 2 pow + sqrt' \
         --colmetadata=8,g-r,mag,"g-r" \
         --colmetadata=9,g-r-error,mag,"g-r error" \
         --colmetadata=10,g-z,mag,"g-z" \
         --colmetadata=11,g-z-error,mag,"g-z error" \
         --colmetadata=12,r-z,mag,"r-z" \
         --colmetadata=13,r-z-error,mag,"r-z error" \
         --output=$tmpdir/cat-all-colours.fits

echo cat-all-colours

echo "MAGNITUDES AND COLOURS------------------------------------------------------------------------" >> $output
echo "# Column 1:APERTURE ID		     [Integer,] Circular aperture identifier." >> $output
echo "# Column 2:MAGNITUDE-g		    [mag, f32,] Magnitude in g band." >> $output
echo "# Column 3:MAGNITUDE-r		    [mag, f32,] Magnitude in r band." >> $output
echo "# Column 4:MAGNITUDE-z		    [mag, f32,] Magnitude in z band." >> $output
echo "# Column 5:MAGNITUDE_ERROR-g	[mag, f32,] Error in measuring magnitude in g band." >> $output
echo "# Column 6:MAGNITUDE_ERROR-r	[mag, f32,] Error in measuring magnitude in r band." >> $output
echo "# Column 7:MAGNITUDE_ERROR-z	[log, f32,] Error in measuring magnitude in z band." >> $output
echo "# Column 8: g-r			          [mag, f32,] g-r color." >> $output
echo "# Column 9: g-r-error		      [mag, f32,] g-r color error." >> $output
echo "# Column 10: g-z			          [mag, f32,] g-z color." >> $output
echo "# Column 11: g-z-error		    [mag, f32,] g-z color error." >> $output
echo "# Column 12: r-z		          [mag, f32,] r-z color." >> $output
echo "# Column 13: r-z-error		    [mag, f32,] r-z color error." >> $output
echo "---------------------------------------------------------------------------------------------" >> $output

asttable $tmpdir/cat-all-colours.fits >> $output


asttable $tmpdir/cat-all-colours.fits


# average colours and colour errors

grmean=$(aststatistics $tmpdir/cat-all-colours.fits  -cg-r --mean) >> $output
grerror=$(aststatistics $tmpdir/cat-all-colours.fits  -cg-r-error --mean) >> $output
gzmean=$(aststatistics $tmpdir/cat-all-colours.fits  -cg-z --mean) >> $output
gzerror=$(aststatistics $tmpdir/cat-all-colours.fits  -cg-z-error --mean) >> $output
rzmean=$(aststatistics $tmpdir/cat-all-colours.fits  -cr-z --mean) >> $output
rzerror=$(aststatistics $tmpdir/cat-all-colours.fits  -cr-z-error --mean) >> $output


echo average colours


# Add all information in one table
echo "AVERAGE VALUES FROM ALL APERTURES------------------------------------------------------------" >> $output
echo "# Column 1:MAGNITUDE-r          [log, f32,] Magnitude in r band." >> $output
echo "# Column 2:MAGNITUDE_ERROR-r    [log, f32,] Error in measuring magnitude in r band." >> $output
echo "# Column 3:SURFACE_BRIGHTNESS-r [mag/arcsec^2, f32,] Surface brightness in r band (magnitude of brightness/area)." >> $output
echo "# Column 4: SB_ERROR-r          [mag/arcsec^2, f32,] Error in measuring Surface brightness in r band." >> $output
echo "# Column 5:MAGNITUDE-g          [log, f32,] Magnitude in g band." >> $output
echo "# Column 6:MAGNITUDE_ERROR-g    [log, f32,] Error in measuring magnitude in g band." >> $output
echo "# Column 7:SURFACE_BRIGHTNESS-g [mag/arcsec^2, f32,] Surface brightness in g band (magnitude of brightness/area)." >> $output
echo "# Column 8: SB_ERROR-g          [mag/arcsec^2, f32,] Error in measuring Surface brightness in g band." >> $output
echo "# Column 9:MAGNITUDE-z          [log, f32,] Magnitude in z band." >> $output
echo "# Column 10:MAGNITUDE_ERROR-z    [log, f32,] Error in measuring magnitude in z band." >> $output
echo "# Column 11:SURFACE_BRIGHTNESS-z [mag/arcsec^2, f32,] Surface brightness in z band (magnitude of brightness/area)." >> $output
echo "# Column 12: SB_ERROR-z          [mag/arcsec^2, f32,] Error in measuring Surface brightness in z band." >> $output
echo "---------------------------------------------------------------------------------------------" >> $output

echo $magmeanr $magerrorr $sbmeanr $sberrorr $magmeang $magerrorg $sbmeang $sberrorg $magmeanz $magerrorz $sbmeanz $sberrorz >> $output

echo "---------------------------------------------------------------------------------------------" >> $output
echo "# Column 13: g-r          [log, f32,] g-r color." >> $output
echo "# Column 14: g-r-error    [log, f32,] g-r color error." >> $output
echo "# Column 15: g-z          [log, f32,] g-z color." >> $output
echo "# Column 16: g-z-error    [log, f32,] g-z color error." >> $output
echo "# Column 17: r-z          [log, f32,] r-z color." >> $output
echo "# Column 18: r-z-error    [log, f32,] r-z color error." >> $output
echo "---------------------------------------------------------------------------------------------" >> $output


echo $grmean $grerror $gzmean $gzerror $rzmean $rzerror >> $output


#MAGNITUDES AND COLOURS WITH GALACTIC EXTINCTION----------------------------

##Galactic Extinction Calculation-------------------------------------------               

CRA=$(astfits $tmpdir/masked-$filter.fits -h1 --keyvalue=CRVAL1 --quiet)
CDEC=$(astfits $tmpdir/masked-$filter.fits -h1 --keyvalue=CRVAL2 --quiet)
apcenter="$CRA $CDEC"

astquery ned --dataset=extinction --center=$CRA,$CDEC --output=ned-extinction.xml

grep '^<TR><TD>' ned-extinction.xml | sed -e's|<TR><TD>||' -e's|</TD></TR>||' -e's|</TD><TD>|@|g' | awk 'BEGIN{FS="@";
               print "# Column 1: FILTER [name,str15] Filter name"; \
               print "# Column 2: CENTRAL [um,f32] Central Wavelength"; \
               print "# Column 3: EXTINCTION [mag,f32] Galactic Ext."; \
               print "# Column 4: ADS_REF [ref,str50] ADS reference"} \
                  {printf "%-15s %g %g %s\n", $1, $2, $3, $4}'  | asttable -oned-extinction.fits
                  
eg=$(asttable ned-extinction.fits --equal=Filter,"DES g" -cEXTINCTION)
er=$(asttable ned-extinction.fits --equal=Filter,"DES r" -cEXTINCTION)
ez=$(asttable ned-extinction.fits --equal=Filter,"DES z" -cEXTINCTION)

echo "END of EXTINCTION CALCULATION"
echo "eg er ez"
echo $eg $er $ez
echo "exit 2"

echo "EXTINCTION CALCULATION RESULTS---------------------------------------------------------------" >> $output
echo "eg er ez" >> $output
echo $eg $er $ez >> $output

##End Galactic Extinction Calculation---------------------------------------

##table with magnitudes, colours and colour errors with galactic extinction
 

asttable $tmpdir/cat-all-bands.fits -h1 \
         -cOBJ_ID,MAGNITUDE-g,MAGNITUDE-r,MAGNITUDE-z \
         -cMAGNITUDE_ERROR-g,MAGNITUDE_ERROR-r,MAGNITUDE_ERROR-z \
         -c"arith MAGNITUDE-g $eg -" \
         -c"arith MAGNITUDE-r $er -" \
         -c"arith MAGNITUDE-z $ez -" \
         --colmetadata=8,go,mag,"go" \
         --colmetadata=9,ro,mag,"ro" \
         --colmetadata=10,zo,mag,"zo" \
         --output=$tmpdir/cat-all-bands-e.fits


echo cat-all-bands-e

asttable $tmpdir/cat-all-bands-e.fits

echo "eg er ez"
echo $eg $er $ez

asttable $tmpdir/cat-all-bands-e.fits -h1 \
         -cOBJ_ID,go,ro,zo \
         -cMAGNITUDE_ERROR-g,MAGNITUDE_ERROR-r,MAGNITUDE_ERROR-z \
         -c'arith go ro -' \
         -c'arith MAGNITUDE_ERROR-g 2 pow MAGNITUDE_ERROR-r 2 pow + sqrt' \
         -c'arith go zo -' \
         -c'arith MAGNITUDE_ERROR-g 2 pow MAGNITUDE_ERROR-z 2 pow + sqrt' \
         -c'arith ro zo -' \
         -c'arith MAGNITUDE_ERROR-r 2 pow MAGNITUDE_ERROR-z 2 pow + sqrt' \
         --colmetadata=8,go-ro,mag,"g-r" \
         --colmetadata=9,g-r-error,mag,"g-r error" \
         --colmetadata=10,go-zo,mag,"g-z" \
         --colmetadata=11,g-z-error,mag,"g-z error" \
         --colmetadata=12,ro-zo,mag,"r-z" \
         --colmetadata=13,r-z-error,mag,"r-z error" \
         --output=$tmpdir/cat-all-colours-e.fits

echo cat-all-colours-e

asttable $tmpdir/cat-all-colours-e.fits

echo "GALACTIC EXTINCTION CORRECTED MAGNITUDES AND COLOURS ----------------------------------------" >> $output
echo "# Column 1:APERTURE ID		     [Integer,] Circular aperture identifier." >> $output
echo "# Column 2:go		    [mag, f32,] Magnitude in g band." >> $output
echo "# Column 3:ro		    [mag, f32,] Magnitude in r band." >> $output
echo "# Column 4:zo		    [mag, f32,] Magnitude in z band." >> $output
echo "# Column 5:MAGNITUDE_ERROR-g	[mag, f32,] Error in measuring magnitude in g band." >> $output
echo "# Column 6:MAGNITUDE_ERROR-r	[mag, f32,] Error in measuring magnitude in r band." >> $output
echo "# Column 7:MAGNITUDE_ERROR-z	[log, f32,] Error in measuring magnitude in z band." >> $output
echo "# Column 8: (g-r)o			          [mag, f32,] g-r color." >> $output
echo "# Column 9: g-r-error		      [mag, f32,] g-r color error." >> $output
echo "# Column 10: (g-z)o			          [mag, f32,] g-z color." >> $output
echo "# Column 11: g-z-error		    [mag, f32,] g-z color error." >> $output
echo "# Column 12: (r-z)o		          [mag, f32,] r-z color." >> $output
echo "# Column 13: r-z-error		    [mag, f32,] r-z color error." >> $output
echo "---------------------------------------------------------------------------------------------" >> $output

asttable $tmpdir/cat-all-colours-e.fits >> $output


# average colours and colour errors

grmean=$(aststatistics $tmpdir/cat-all-colours.fits  -cg-r --mean) >> $output
grerror=$(aststatistics $tmpdir/cat-all-colours.fits  -cg-r-error --mean) >> $output
gzmean=$(aststatistics $tmpdir/cat-all-colours.fits  -cg-z --mean) >> $output
gzerror=$(aststatistics $tmpdir/cat-all-colours.fits  -cg-z-error --mean) >> $output
rzmean=$(aststatistics $tmpdir/cat-all-colours.fits  -cr-z --mean) >> $output
rzerror=$(aststatistics $tmpdir/cat-all-colours.fits  -cr-z-error --mean) >> $output


echo average colours


# Add all information in one table
echo "GALACTIC EXTINCTION CORRECTED AVERAGE VALUES FROM ALL APERTURES------------------------------" >> $output
echo "# Column 1:MAGNITUDE-r          [log, f32,] Magnitude in r band." >> $output
echo "# Column 2:MAGNITUDE_ERROR-r    [log, f32,] Error in measuring magnitude in r band." >> $output
echo "# Column 3:SURFACE_BRIGHTNESS-r [mag/arcsec^2, f32,] Surface brightness in r band (magnitude of brightness/area)." >> $output
echo "# Column 4: SB_ERROR-r          [mag/arcsec^2, f32,] Error in measuring Surface brightness in r band." >> $output
echo "# Column 5:MAGNITUDE-g          [log, f32,] Magnitude in g band." >> $output
echo "# Column 6:MAGNITUDE_ERROR-g    [log, f32,] Error in measuring magnitude in g band." >> $output
echo "# Column 7:SURFACE_BRIGHTNESS-g [mag/arcsec^2, f32,] Surface brightness in g band (magnitude of brightness/area)." >> $output
echo "# Column 8: SB_ERROR-g          [mag/arcsec^2, f32,] Error in measuring Surface brightness in g band." >> $output
echo "# Column 9:MAGNITUDE-z          [log, f32,] Magnitude in z band." >> $output
echo "# Column 10:MAGNITUDE_ERROR-z    [log, f32,] Error in measuring magnitude in z band." >> $output
echo "# Column 11:SURFACE_BRIGHTNESS-z [mag/arcsec^2, f32,] Surface brightness in z band (magnitude of brightness/area)." >> $output
echo "# Column 12: SB_ERROR-z          [mag/arcsec^2, f32,] Error in measuring Surface brightness in z band." >> $output
echo "---------------------------------------------------------------------------------------------" >> $output


magmeanro=$(awk 'BEGIN {print '$magmeanr' - '$er'}')
magmeango=$(awk 'BEGIN {print '$magmeang' - '$eg'}')
magmeanzo=$(awk 'BEGIN {print '$magmeanz' - '$ez'}')

echo $magmeanro $magerrorr $sbmeanr $sberrorr $magmeango $magerrorg $sbmeang $sberrorg $magmeanzo $magerrorz $sbmeanz $sberrorz >> $output

echo "---------------------------------------------------------------------------------------------" >> $output
echo "# Column 13: g-r          [log, f32,] g-r color." >> $output
echo "# Column 14: g-r-error    [log, f32,] g-r color error." >> $output
echo "# Column 15: g-z          [log, f32,] g-z color." >> $output
echo "# Column 16: g-z-error    [log, f32,] g-z color error." >> $output
echo "# Column 17: r-z          [log, f32,] r-z color." >> $output
echo "# Column 18: r-z-error    [log, f32,] r-z color error." >> $output
echo "---------------------------------------------------------------------------------------------" >> $output


gromean=$(awk 'BEGIN {print '$magmeango' - '$magmeanro'}')
gzomean=$(awk 'BEGIN {print '$magmeango' - '$magmeanzo'}')
rzomean=$(awk 'BEGIN {print '$magmeanro' - '$magmeanzo'}')

echo $gromean $grerror $gzomean $gzerror $rzomean $rzerror >> $output


#output for plots of aperture colours and SB-r gradients (with TopCat)

asttable $tmpdir/$NAME-apertures-coordinates.txt --output=$tmpdir/$NAME-photometry-apertures.txt \
         --catcolumnfile=$tmpdir/cat-regions-r.fits --catcolumnhdu=1 \
         --catcolumnfile=$tmpdir/cat-all-colours-e.fits --catcolumnhdu=1        

echo "Xpix  Ypix Rpix  RA  Dec  Ras  DIST-H  A-ID Apix Aas2 B-r  B-r-ERR  mag-r  mag-r-err  DI-r SNR-r SB-r  SB-r-err A-ID mag-r mag-r-err mag-g  mag-g-err  mag-z   mag-z-err  (g-r)0 (g-r)o-err (g-z)0 (g-z)o-err (r-z)0 (r-z)o-err" >> $outputaper

asttable $tmpdir/$NAME-photometry-apertures.txt >> $outputaper


#END STREAM MAGNITUDE AND COLOURS WITH EXTINCTION ----------------------------------

#PHOTOMETRY MEASUREMENT OF THE HOST GALAXY (if selected) ---------------------------

if [ $ihost -eq 1 ]; then

echo "=============================================================================================" >> $output
echo "PHOTOMETRY MEASUREMENT ON THE HOST GALAXY----------------------------------------------------" >> $output

grep ^circle $APDIR/$NAME-host-aperture-physical.reg \
     | sed -e's/circle(//' -e's/)//' -e's/,/ /g' \
     | awk '{printf "%-20s%-20s%s\n", $1, $2, $3}'\
     > $APDIR/$NAME-XYR-host-aperture.txt
 
cp $APDIR/$NAME-host-aperture-physical.reg $tmpdir/$NAME-host-aperture-physical.reg
cp $APDIR/$NAME-XYR-host-aperture.txt $tmpdir/$NAME-XYR-host-aperture.txt

echo "HOST APERTURE: X,Y (pix) Radius (pix) RA,Dec (deg) Radius (as) Distance to image centre (as) " >> $output
asttable $tmpdir/$NAME-XYR-host-aperture.txt -c1,2,3,'arith $1 $2 img-to-wcs' \
         --wcshdu=INPUT-NO-SKY --wcsfile=$tmpdir/nc-$filter.fits \
         --output=$tmpdir/$NAME-XYRRaDec-host-aperture.txt

asttable $tmpdir/$NAME-XYRRaDec-host-aperture.txt \
         -c1,2,3,4,5 \
         -c'arith $3 '$pixscale' x 3600 x' \
         --colmetadata=6,Ras,arcsec,"Aperture radius (arcsec)" \
         --output=$tmpdir/$NAME-XYRRaDecRas-host-aperture.txt 
#asttable $tmpdir/$NAME-XYRRaDecRas-host-aperture.txt >> $output

HRA=$(asttable $tmpdir/$NAME-XYRRaDecRas-host-aperture.txt -c4)
HDec=$(asttable $tmpdir/$NAME-XYRRaDecRas-host-aperture.txt -c5)

# Distance of host aperture to host galaxy centre

asttable $tmpdir/$NAME-XYRRaDecRas-host-aperture.txt \
         -c1,2,3,4,5,6 \
         -c'arith $4 '$RA' - 2 pow $5 '$Dec' - 2 pow + sqrt 3600 x' \
         --colmetadata=7,hdistas,arcsec,"Aperture center distance to host (arcsec)" \
         --output=$tmpdir/$NAME-host-aperture-coordinates.txt 

asttable $tmpdir/$NAME-host-aperture-coordinates.txt >> $output

hdistas=$(asttable $tmpdir/$NAME-host-aperture-coordinates.txt -c7)

#echo "DISTANCE OF THE APERTURE ON HOST TO THE IMAGE CENTRE (arcsec): " $hdistas >> $output

## Create aperture profile from an aperture definition input file 
numrandom=10000
hostapercat_raw=$APDIR/$NAME-XYR-host-aperture.txt
hostaperimg=$tmpdir/hostaper.fits
echo numrandom zeropoint
echo $numrandom $zeropoint
awk '{print NR, $1, $2, 5, $3, 0, 0, 1, NR, 1}' $hostapercat_raw \
    | astmkprof --background=$tmpdir/nc-r.fits --clearcanvas \
		    --mode=img --oversample=1 --mforflatpix \
		    --type=uint8 --replace -o$hostaperimg

## Measure phtometry on predefined aperture

echo "HOST PHOTOMETRY ---------------------------------------------------------------------------- " >> $output

# r band
astmkcatalog $hostaperimg -h1 --valuesfile=$tmpdir/nc-r.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-host-r.fits \
	         --ids --area --areaarcsec2 --brightness --brightnesserr --magnitude --magnitudeerr \
                 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

echo "r band" >> $output
asttable $tmpdir/cat-host-r.fits >> $output

 
# g band
astmkcatalog $hostaperimg -h1 --valuesfile=$tmpdir/nc-g.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-host-g.fits \
	         --ids --area --areaarcsec2 --brightness --brightnesserr --magnitude --magnitudeerr \
                 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

echo "g band" >> $output
asttable $tmpdir/cat-host-g.fits >> $output


# z band
astmkcatalog $hostaperimg -h1 --valuesfile=$tmpdir/nc-z.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-host-z.fits \
	         --ids --area --areaarcsec2 --brightness --brightnesserr --magnitude --magnitudeerr \
                 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

echo "z band" >> $output
asttable $tmpdir/cat-host-z.fits >> $output

hsbr=$(asttable $tmpdir/cat-host-r.fits -cSURFACE_BRIGHTNESS)
hsbrerr=$(asttable $tmpdir/cat-host-r.fits -cSB_ERROR)
hsbg=$(asttable $tmpdir/cat-host-g.fits -cSURFACE_BRIGHTNESS)
hsbgerr=$(asttable $tmpdir/cat-host-g.fits -cSB_ERROR)
hsbz=$(asttable $tmpdir/cat-host-z.fits -cSURFACE_BRIGHTNESS)
hsbzerr=$(asttable $tmpdir/cat-host-z.fits -cSB_ERROR)
hmagr=$(asttable $tmpdir/cat-host-r.fits -cMAGNITUDE)
hmagrerr=$(asttable $tmpdir/cat-host-r.fits -cMAGNITUDE_ERROR)
hmagg=$(asttable $tmpdir/cat-host-g.fits -cMAGNITUDE)
hmaggerr=$(asttable $tmpdir/cat-host-g.fits -cMAGNITUDE_ERROR)
hmagz=$(asttable $tmpdir/cat-host-z.fits -cMAGNITUDE)
hmagzerr=$(asttable $tmpdir/cat-host-z.fits -cMAGNITUDE_ERROR)

echo "HOST APERTURE MAGNITUDES AND ERRORS ---------------------------------------------------------  " >> $output
echo "h-mag-r h-mag-r-err h-mag-g h-mag-g-err h-mag-z h-mag-z-err" >> $output
echo "---------------------------------------------------------------------------------------------" >> $output
echo $hmagr $hmagrerr $hmagg $hmaggerr $hmagz $hmagzerr >> $output


hmagro=$(awk 'BEGIN {print '$hmagr' - '$er'}')
hmaggo=$(awk 'BEGIN {print '$hmagg' - '$eg'}')
hmagzo=$(awk 'BEGIN {print '$hmagz' - '$ez'}')

echo "GALACTC EXTINCTIN CORRECTED HOST APERTURE MAGNITUDES AND ERROS --------------------------------  " >> $output
echo "h-mag-ro h-mag-r-err h-mag-go h-mag-g-err h-mag-zo h-mag-z-err" >> $output
echo "---------------------------------------------------------------------------------------------" >> $output
echo $hmagro $hmagrerr $hmaggo $hmaggerr $hmagzo $hmagzerr >> $output

hgro=$(awk 'BEGIN {print '$hmaggo' - '$hmagro'}')
hgzo=$(awk 'BEGIN {print '$hmaggo' - '$hmagzo'}')
hrzo=$(awk 'BEGIN {print '$hmagro' - '$hmagzo'}')

hgroerr=$(awk 'BEGIN {print sqrt('$hmagrerr'^2 + '$hmaggerr'^2)}')
hgzoerr=$(awk 'BEGIN {print sqrt('$hmaggerr'^2 + '$hmagzerr'^2)}')
hrzoerr=$(awk 'BEGIN {print sqrt('$hmagrerr'^2 + '$hmagzerr'^2)}')


echo "GALACTC EXTINCTIN CORRECTED HOST COLOURS AND ERROS ------------------------------------------  " >> $output
echo "h-(g-r)o h-(g-r)o-err h-(g-z)o h-(g-z)o-err h-(r-z)o h-(r-z)o-err " >> $output
echo "---------------------------------------------------------------------------------------------" >> $output
echo $hgro $hgroerr $hgzo $hgzoerr $hrzo $hrzoerr >> $output


#output for plots of aperture colours and SB-r gradients (with TopCat)

H=1

echo $H $hmagro $hmagrerr $hmaggo $hmaggerr $hmagzo $hmagzerr $hgro $hgroerr $hgzo $hgzoerr $hrzo $hrzoerr > $tmpdir/cat-host-colours-e.txt

asttable $tmpdir/$NAME-host-aperture-coordinates.txt --output=$tmpdir/$NAME-photometry-host.txt \
         --catcolumnfile=$tmpdir/cat-host-r.fits --catcolumnhdu=1 \
         --catcolumnfile=$tmpdir/cat-host-colours-e.txt --catcolumnhdu=1        

asttable $tmpdir/$NAME-photometry-host.txt >> $outputaper

fi

#PHOTOMETRY MEASUREMENT OF THE PROGENITOR (if selected) -----------------------------------------

if [ $iprog -eq 1 ]; then

echo "=============================================================================================" >> $output
echo "PHOTOMETRY MEASUREMENT ON THE PROGENITOR-----------------------------------------------------" >> $output

grep ^circle $APDIR/$NAME-prog-aperture-physical.reg \
     | sed -e's/circle(//' -e's/)//' -e's/,/ /g' \
     | awk '{printf "%-20s%-20s%s\n", $1, $2, $3}'\
     > $APDIR/$NAME-XYR-prog-aperture.txt
 
cp $APDIR/$NAME-prog-aperture-physical.reg $tmpdir/$NAME-prog-aperture-physical.reg
cp $APDIR/$NAME-XYR-prog-aperture.txt $tmpdir/$NAME-XYR-prog-aperture.txt

echo "PROGENITOR APERTURE: X,Y (pix) Radius (pix) RA,Dec (deg) Radius (as) Distance to image centre (as) " >> $output
asttable $tmpdir/$NAME-XYR-prog-aperture.txt -c1,2,3,'arith $1 $2 img-to-wcs' \
         --wcshdu=INPUT-NO-SKY --wcsfile=$tmpdir/nc-$filter.fits \
         --output=$tmpdir/$NAME-XYRRaDec-prog-aperture.txt
asttable $tmpdir/$NAME-XYRRaDec-prog-aperture.txt \
         -c1,2,3,4,5 \
         -c'arith $3 '$pixscale' x 3600 x' \
         --colmetadata=6,Ras,arcsec,"Aperture radius (arcsec)" \
         --output=$tmpdir/$NAME-XYRRaDecRas-prog-aperture.txt 
#asttable $tmpdir/$NAME-XYRRaDecRas-prog-aperture.txt >> $output

PRA=$(asttable $tmpdir/$NAME-XYRRaDecRas-prog-aperture.txt -c4)
PDec=$(asttable $tmpdir/$NAME-XYRRaDecRas-prog-aperture.txt -c5)

# Distance of ptogenitor to host galaxy centre

#pdistRA=$(awk 'BEGIN {print '$PRA' - '$RA'}')
#pdistDec=$(awk 'BEGIN {print '$PDec' - '$Dec'}')
#pdistd=$(awk 'BEGIN {print sqrt('$pdistRA'^2 + '$pdistDec'^2)}')
#pdistas=$(awk 'BEGIN {print '$pdistd' * 3600}')

asttable $tmpdir/$NAME-XYRRaDecRas-prog-aperture.txt \
         -c1,2,3,4,5,6 \
         -c'arith $4 '$RA' - 2 pow $5 '$Dec' - 2 pow + sqrt 3600 x' \
         --colmetadata=7,pdistas,arcsec,"Progenitor distance to image centre (arcsec)" \
         --output=$tmpdir/$NAME-prog-aperture-coordinates.txt 

asttable $tmpdir/$NAME-prog-aperture-coordinates.txt >> $output

pdistas=$(asttable $tmpdir/$NAME-prog-aperture-coordinates.txt -c7)

#echo "DISTANCE OF THE PROGENITOR TO THE HOST CENTRE (arcsec): " $pdistas >> $output

## Create aperture profile from an aperture definition input file 
numrandom=10000
progapercat_raw=$APDIR/$NAME-XYR-prog-aperture.txt
progaperimg=$tmpdir/progaper.fits
echo numrandom zeropoint
echo $numrandom $zeropoint
awk '{print NR, $1, $2, 5, $3, 0, 0, 1, NR, 1}' $progapercat_raw \
    | astmkprof --background=$tmpdir/nc-r.fits --clearcanvas \
		    --mode=img --oversample=1 --mforflatpix \
		    --type=uint8 --replace -o$progaperimg

## Measure phtometry on predefined aperture

echo "PROGENITOR PHOTOMETRY ---------------------------------------------------------------------------- " >> $output

# r band
astmkcatalog $progaperimg -h1 --valuesfile=$tmpdir/nc-r.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-prog-r.fits \
	         --ids --area --areaarcsec2 --brightness --brightnesserr --magnitude --magnitudeerr \
                 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

echo "r band" >> $output
asttable $tmpdir/cat-prog-r.fits >> $output

 
# g band
astmkcatalog $progaperimg -h1 --valuesfile=$tmpdir/nc-g.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-prog-g.fits \
	         --ids --area --areaarcsec2 --brightness --brightnesserr --magnitude --magnitudeerr \
                 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

echo "g band" >> $output
asttable $tmpdir/cat-prog-g.fits >> $output


# z band
astmkcatalog $progaperimg -h1 --valuesfile=$tmpdir/nc-z.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
                 --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-$filter.fits --upmaskhdu=DETECTIONS \
                 --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-prog-z.fits \
	         --ids --area --areaarcsec2 --brightness --brightnesserr --magnitude --magnitudeerr \
                 --upperlimitsigma --sn --surfacebrightness \
                 --sberror

echo "z band" >> $output
asttable $tmpdir/cat-prog-z.fits >> $output

psbr=$(asttable $tmpdir/cat-prog-r.fits -cSURFACE_BRIGHTNESS)
psbrerr=$(asttable $tmpdir/cat-prog-r.fits -cSB_ERROR)
psbg=$(asttable $tmpdir/cat-prog-g.fits -cSURFACE_BRIGHTNESS)
psbgerr=$(asttable $tmpdir/cat-prog-g.fits -cSB_ERROR)
psbz=$(asttable $tmpdir/cat-prog-z.fits -cSURFACE_BRIGHTNESS)
psbzerr=$(asttable $tmpdir/cat-prog-z.fits -cSB_ERROR)
pmagr=$(asttable $tmpdir/cat-prog-r.fits -cMAGNITUDE)
pmagrerr=$(asttable $tmpdir/cat-prog-r.fits -cMAGNITUDE_ERROR)
pmagg=$(asttable $tmpdir/cat-prog-g.fits -cMAGNITUDE)
pmaggerr=$(asttable $tmpdir/cat-prog-g.fits -cMAGNITUDE_ERROR)
pmagz=$(asttable $tmpdir/cat-prog-z.fits -cMAGNITUDE)
pmagzerr=$(asttable $tmpdir/cat-prog-z.fits -cMAGNITUDE_ERROR)

echo "PROGENITOR APERTURE MAGNITUDES AND ERRORS ---------------------------------------------------  " >> $output
echo "p-mag-r p-mag-r-err p-mag-g p-mag-g-err p-mag-z p-mag-z-err" >> $output
echo "---------------------------------------------------------------------------------------------" >> $output
echo $pmagr $pmagrerr $pmagg $pmaggerr $pmagz $pmagzerr >> $output


pmagro=$(awk 'BEGIN {print '$pmagr' - '$er'}')
pmaggo=$(awk 'BEGIN {print '$pmagg' - '$eg'}')
pmagzo=$(awk 'BEGIN {print '$pmagz' - '$ez'}')

echo "GALACTC EXTINCTIN CORRECTED PROGENITOR APERTURE MAGNITUDES AND ERROS ------------------------  " >> $output
echo "p-mag-ro p-mag-r-err p-mag-go p-mag-g-err p-mag-zo p-mag-z-err" >> $output
echo "---------------------------------------------------------------------------------------------" >> $output
echo $pmagro $pmagrerr $pmaggo $pmaggerr $pmagzo $pmagzerr >> $output

pgro=$(awk 'BEGIN {print '$pmaggo' - '$pmagro'}')
pgzo=$(awk 'BEGIN {print '$pmaggo' - '$pmagzo'}')
przo=$(awk 'BEGIN {print '$pmagro' - '$pmagzo'}')

pgroerr=$(awk 'BEGIN {print sqrt('$pmagrerr'^2 + '$pmaggerr'^2)}')
pgzoerr=$(awk 'BEGIN {print sqrt('$pmaggerr'^2 + '$pmagzerr'^2)}')
przoerr=$(awk 'BEGIN {print sqrt('$pmagrerr'^2 + '$pmagzerr'^2)}')


echo "GALACTC EXTINCTIN CORRECTED PROGENITOR COLOURS AND ERROS ------------------------------------  " >> $output
echo "p-(g-r)o p-(g-r)o-err p-(g-z)o p-(g-z)o-err p-(r-z)o p-(r-z)o-err " >> $output
echo "---------------------------------------------------------------------------------------------" >> $output
echo $pgro $pgroerr $pgzo $pgzoerr $przo $przoerr >> $output


#output for plots of aperture colours and SB-r gradients (with TopCat)

P=1

echo $P  $pmagr $pmagrerr $pmagg $pmaggerr $pmagz $pmagzerr $pgro $pgroerr $pgzo $pgzoerr $przo $przoerr > $tmpdir/cat-prog-colours-e.txt

asttable $tmpdir/$NAME-prog-aperture-coordinates.txt --output=$tmpdir/$NAME-photometry-prog.txt \
         --catcolumnfile=$tmpdir/cat-prog-r.fits --catcolumnhdu=1 \
         --catcolumnfile=$tmpdir/cat-prog-colours-e.txt --catcolumnhdu=1        

asttable $tmpdir/$NAME-photometry-prog.txt >> $outputaper

fi

fi
############### END MANUAL APERTURES ######################################## 



if [ $ellipse -eq 1 ]; then
################ MANUAL ELLIPSE #############################################
## This option is not working generally (ellipse aperture is defined here) ##



# Create an ellipse profile to measure the stream magnitude
if ! [ -f $tmpdir/ellipse-aperture.fits ]; then

ellcenter='539.21311 532.02505'
ellincline='63.411726'
ellsamajor='115.73479'
ellsaminor='22.455308'
ellaxratio='0.194024'

echo stream ellipse aperture
echo ellcenter ellincline ellaxratio ellsamajor ellsaminor
echo $ellcenter $ellincline $ellaxratio $ellsamajor $ellsaminor

     echo "1 $ellcenter 5 $ellsamajor 0 $ellincline $ellaxratio 1 1" \
         | astmkprof --background=$DATADIR/$image_$filter --backhdu=$imagehdu  \
                     --clearcanvas \
                     --mode=img --oversample=1 --mforflatpix \
                     --type=uint8 --output=$tmpdir/ellipse-aperture.fits
fi



## Measure total stream magnitud on the ellipse aperture

# Create a profile with the star masks
numrandom=10000
maskcat_raw=NGC7241_XYR_masks_11a.txt
maskaper=$tmpdir/masks.fits
awk '{print NR, $1, $2, 5, $3, 0, 0, 1, NR, 1}' $maskcat_raw \
    | astmkprof --background=$tmpdir/nc-g.fits --clearcanvas \
		    --mode=img --oversample=1 --mforflatpix \
		    --type=uint8 --replace -o$maskaper



# Mask the images

      # For the r band 
      astarithmetic $tmpdir/nc-r.fits -hINPUT-NO-SKY set-input \
                 $tmpdir/masks.fits -h1 set-mask \
                 input mask nan where \
                 --output=$tmpdir/stars-masked-r.fits

      # For the g band  
      astarithmetic $tmpdir/nc-g.fits -hINPUT-NO-SKY set-input \
                 $tmpdir/masks.fits -h1 set-mask \
                 input mask nan where \
                 --output=$tmpdir/stars-masked-g.fits



# Measure total stream magnitud in the r band

astmkcatalog $tmpdir/ellipse-aperture.fits -h1 --valuesfile=$tmpdir/clumps-masked-r.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
     --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-r.fits --upmaskhdu=DETECTIONS \
     --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-stream-r.fits \
	   --ids --brightness --brightnesserr --magnitude --magnitudeerr --area \
     --areaarcsec2 --upperlimitsigma --sn --surfacebrightness --sberror

asttable $tmpdir/cat-stream-r.fits > $tmpdir/cat-stream-r.txt

# Measure total stream magnitude in the g band

astmkcatalog $tmpdir/ellipse-aperture.fits -h1 --valuesfile=$tmpdir/clumps-masked-g.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
     --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
	   --upmaskfile=$tmpdir/nc-g.fits --upmaskhdu=DETECTIONS \
     --instd=$tmpdir/nc-g.fits \
	   --zeropoint=$zeropoint -o$tmpdir/cat-stream-g.fits \
     --ids --brightness --brightnesserr --magnitude --magnitudeerr --area \
     --areaarcsec2 --upperlimitsigma --sn --surfacebrightness --sberror

asttable $tmpdir/cat-stream-g.fits > $tmpdir/cat-stream-g.txt

fi



if [ $polygon -gt 0 ]; then
################ MANUAL POLYGON #############################################



# Create a polygon profile to measure the stream magnitude
if ! [ -f $tmpdir/polygon-cutout-1.fits ]; then

astcrop --mode=img -hINPUT-NO-SKY \
        --polygon=$APDIR/$NAME-polygon-image.reg \
        $tmpdir/nc-$filter.fits --polygonout \
        --output=$tmpdir/polygon-cutout-1.fits


cp $APDIR/$NAME-polygon-image.reg $tmpdir/$NAME-polygon-image.reg


echo stream polygon cutout


astarithmetic $tmpdir/polygon-cutout-1.fits isblank --output=$tmpdir/polygon-aperture-1.fits


echo stream polygon aperture

fi


echo "=============================================================================================" >> $output
echo "PHOTOMETRY MEASURED IN POLYGON APERTURES" >> $output



## Measure total stream magnitud on the polygon aperture
# Polygon 1
echo "Polygon 1" >> $output
#  Measure total stream magnitud in the r band
numrandom=20
astmkcatalog $tmpdir/polygon-aperture-1.fits -h1 --valuesfile=$tmpdir/clumps-masked-r.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
     --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-r.fits --upmaskhdu=DETECTIONS \
     --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-stream-r.fits \
	   --ids --brightness --brightnesserr --magnitude --magnitudeerr --area \
     --areaarcsec2 --upperlimitsigma --sn --surfacebrightness --sberror

asttable $tmpdir/cat-stream-r.fits >> $output

magp1r=$(asttable $tmpdir/cat-stream-r.fits -cMAGNITUDE)
magerrp1r=$(asttable $tmpdir/cat-stream-r.fits -cMAGNITUDE_ERROR)
sbp1r=$(asttable $tmpdir/cat-stream-r.fits -cSURFACE_BRIGHTNESS)
sberrp1r=$(asttable $tmpdir/cat-stream-r.fits -cSB_ERROR)

#galactic extinction correction
magp1ro=$(awk 'BEGIN {print '$magp1r' - '$er'}')

# Measure total stream magnitude in the g band

astmkcatalog $tmpdir/polygon-aperture-1.fits -h1 --valuesfile=$tmpdir/clumps-masked-g.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
     --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
	   --upmaskfile=$tmpdir/nc-g.fits --upmaskhdu=DETECTIONS \
     --instd=$tmpdir/nc-g.fits \
	   --zeropoint=$zeropoint -o$tmpdir/cat-stream-g.fits \
     --ids --brightness --brightnesserr --magnitude --magnitudeerr --area \
     --areaarcsec2 --upperlimitsigma --sn --surfacebrightness --sberror

asttable $tmpdir/cat-stream-g.fits >> $output

magp1g=$(asttable $tmpdir/cat-stream-g.fits -cMAGNITUDE)
magerrp1g=$(asttable $tmpdir/cat-stream-g.fits -cMAGNITUDE_ERROR)
sbp1g=$(asttable $tmpdir/cat-stream-g.fits -cSURFACE_BRIGHTNESS)
sberrp1g=$(asttable $tmpdir/cat-stream-g.fits -cSB_ERROR)

#galactic extinction correction
magp1go=$(awk 'BEGIN {print '$magp1g' - '$eg'}')

# Measure total stream magnitude in the z band

astmkcatalog $tmpdir/polygon-aperture-1.fits -h1 --valuesfile=$tmpdir/clumps-masked-z.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
     --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
	   --upmaskfile=$tmpdir/nc-g.fits --upmaskhdu=DETECTIONS \
     --instd=$tmpdir/nc-g.fits \
	   --zeropoint=$zeropoint -o$tmpdir/cat-stream-z.fits \
     --ids --brightness --brightnesserr --magnitude --magnitudeerr --area \
     --areaarcsec2 --upperlimitsigma --sn --surfacebrightness --sberror

asttable $tmpdir/cat-stream-z.fits >> $output

magp1z=$(asttable $tmpdir/cat-stream-z.fits -cMAGNITUDE)
magerrp1z=$(asttable $tmpdir/cat-stream-z.fits -cMAGNITUDE_ERROR)
sbp1z=$(asttable $tmpdir/cat-stream-z.fits -cSURFACE_BRIGHTNESS)
sberrp1z=$(asttable $tmpdir/cat-stream-z.fits -cSB_ERROR)

#galactic extinction correction
magp1zo=$(awk 'BEGIN {print '$magp1z' - '$ez'}')

# colour calculation

grop1=$(awk 'BEGIN {print '$magp1go' - '$magp1ro'}') 
grerrorp1=$(awk 'BEGIN {print sqrt('$magerrp1g'^2 + '$magerrp1r'^2)}')
gzop1=$(awk 'BEGIN {print '$magp1go' - '$magp1zo'}')
gzerrorp1=$(awk 'BEGIN {print sqrt('$magerrp1g'^2 + '$magerrp1z'^2)}') 
rzop1=$(awk 'BEGIN {print '$magp1ro' - '$magp1zo'}')
rzerrorp1=$(awk 'BEGIN {print sqrt('$magerrp1r'^2 + '$magerrp1z'^2)}')

echo "--------------------------------------------------------------------------------------------------------" >> $output
echo "mag-r-0 mag-r-err mag-g-0 mag-g-err mag-z-0 mag-z-err (g-r)0 (g-r)-err (g-z)0 (g-z)-err (r-z)0 (r-z)-err" >> $output
echo $magp1r $magerrp1r $magp1g $magerrp1g $magp1z $magerrp1z $grop1 $grerrorp1 $gzop1 $gzerrorp1 $rzop1 $rzerrorp1 >> $output  

if [ $polygon -eq 2 ]; then

# Polygon 2
echo "Polygon 2" >> $output

# in case more than 1 polygon (e.g. NGC922)
astcrop --mode=img -hINPUT-NO-SKY \
        --polygon=$APDIR/$NAME-polygon-image-2.reg \
        $tmpdir/nc-$filter.fits --polygonout \
        --output=$tmpdir/polygon-cutout-2.fits

astarithmetic $tmpdir/polygon-cutout-2.fits isblank --output=$tmpdir/polygon-aperture-2.fits

cp $APDIR/$NAME-polygon-image-2.reg $tmpdir/$NAME-polygon-image-2.reg

#  Measure total stream magnitud in the r band
numrandom=20
astmkcatalog $tmpdir/polygon-aperture-2.fits -h1 --valuesfile=$tmpdir/clumps-masked-r.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
     --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$tmpdir/nc-r.fits --upmaskhdu=DETECTIONS \
     --instd=$tmpdir/nc-r.fits \
		 --zeropoint=$zeropoint -o$tmpdir/cat-stream-r.fits \
	   --ids --brightness --brightnesserr --magnitude --magnitudeerr --area \
     --areaarcsec2 --upperlimitsigma --sn --surfacebrightness --sberror

asttable $tmpdir/cat-stream-r.fits >> $output

magp2r=$(asttable $tmpdir/cat-stream-r.fits -cMAGNITUDE)
magerrp2r=$(asttable $tmpdir/cat-stream-r.fits -cMAGNITUDE_ERROR)
sbp2r=$(asttable $tmpdir/cat-stream-r.fits -cSURFACE_BRIGHTNESS)
sberrp2r=$(asttable $tmpdir/cat-stream-r.fits -cSB_ERROR)

#galactic extinction correction
magp2ro=$(awk 'BEGIN {print '$magp2r' - '$er'}')

# Measure total stream magnitude in the g band

astmkcatalog $tmpdir/polygon-aperture-2.fits -h1 --valuesfile=$tmpdir/clumps-masked-g.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
     --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
	   --upmaskfile=$tmpdir/nc-g.fits --upmaskhdu=DETECTIONS \
    --instd=$tmpdir/nc-g.fits \
	   --zeropoint=$zeropoint -o$tmpdir/cat-stream-g.fits \
     --ids --brightness --brightnesserr --magnitude --magnitudeerr --area \
    --areaarcsec2 --upperlimitsigma --sn --surfacebrightness --sberror

asttable $tmpdir/cat-stream-g.fits >> $output

magp2g=$(asttable $tmpdir/cat-stream-g.fits -cMAGNITUDE)
magerrp2g=$(asttable $tmpdir/cat-stream-g.fits -cMAGNITUDE_ERROR)
sbp2g=$(asttable $tmpdir/cat-stream-g.fits -cSURFACE_BRIGHTNESS)
sberrp2g=$(asttable $tmpdir/cat-stream-g.fits -cSB_ERROR)

#galactic extinction correction
magp2go=$(awk 'BEGIN {print '$magp2g' - '$eg'}')

# Measure total stream magnitude in the z band

astmkcatalog $tmpdir/polygon-aperture-2.fits -h1 --valuesfile=$tmpdir/clumps-masked-z.fits --envseed \
		 --valueshdu=1 --checkuplim=1 --upnum=$numrandom \
     --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
	   --upmaskfile=$tmpdir/nc-g.fits --upmaskhdu=DETECTIONS \
     --instd=$tmpdir/nc-g.fits \
	   --zeropoint=$zeropoint -o$tmpdir/cat-stream-z.fits \
     --ids --brightness --brightnesserr --magnitude --magnitudeerr --area \
     --areaarcsec2 --upperlimitsigma --sn --surfacebrightness --sberror

asttable $tmpdir/cat-stream-z.fits >> $output

magp2z=$(asttable $tmpdir/cat-stream-z.fits -cMAGNITUDE)
magerrp2z=$(asttable $tmpdir/cat-stream-z.fits -cMAGNITUDE_ERROR)
sbp2z=$(asttable $tmpdir/cat-stream-z.fits -cSURFACE_BRIGHTNESS)
sberrp2z=$(asttable $tmpdir/cat-stream-z.fits -cSB_ERROR)

#galactic extinction correction
magp2zo=$(awk 'BEGIN {print '$magp2z' - '$ez'}')


# colour calculation

grop2=$(awk 'BEGIN {print '$magp2go' - '$magp2ro'}') 
grerrorp2=$(awk 'BEGIN {print sqrt('$magerrp2g'^2 + '$magerrp2r'^2)}')
gzop2=$(awk 'BEGIN {print '$magp2go' - '$magp2zo'}')
gzerrorp2=$(awk 'BEGIN {print sqrt('$magerrp2g'^2 + '$magerrp2z'^2)}') 
rzop2=$(awk 'BEGIN {print '$magp2ro' - '$magp2zo'}')
rzerrorp2=$(awk 'BEGIN {print sqrt('$magerrp2r'^2 + '$magerrp2z'^2)}')


echo "--------------------------------------------------------------------------------------------------------" >> $output
echo "mag-r-0 mag-r-err mag-g-0 mag-g-err mag-z-0 mag-z-err (g-r)0 (g-r)-err (g-z)0 (g-z)-err (r-z)0 (r-z)-err" >> $output
echo $magp2r $magerrp2r $magp2g $magerrp2g $magp2z $magerrp2z $grop2 $grerrorp2 $gzop2 $gzerrorp2 $rzop2 $rzerrorp2 >> $output

fi

fi


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
		 --ids --brightness --brightnesserr --magnitude --magnitudeerr --area --areaarcsec2 \
		 --upperlimitsigma --sn --surfacebrightness --sberror --upperlimitsb

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
		 --ids --brightness --brightnesserr --magnitude --magnitudeerr --area --areaarcsec2 \
		 --upperlimitsigma --sn --surfacebrightness --sberror --upperlimitsb

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
		 --ids --brightness --brightnesserr --magnitude --magnitudeerr --area --areaarcsec2 \
		 --upperlimitsigma --sn --surfacebrightness --sberror --upperlimitsb

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


#===================== GLOBAL OUTPUT GENERATION =============================
if [ $iglobalresults -eq 1 ]; then


if ! [ -f $results ]; then

echo "HOSTID RA DEC H-SB-r H-SB-r-err H-SB-g H-SB-g-err H-SB-z H-SB-z-err H-(g-r)o H-(g-r)o-err H-(g-z)o H-(g-z)o-err H-(r-z)o H-(r-z)o-err SB-lim-r SB-lim-g SB-lim-z UL-SB-r UL-SB-g UL-SB-z ST-DIST-H-MAX ST-DIST-H-MIN ST-WIDTH ST-DI-r ST-DI-g ST-DI-z ST-SB-r ST-SB-r-err ST-SB-g ST-SB-g-err ST-SB-z ST-SB-z-err ST-(g-r)o ST-(g-r)o-err ST-(g-z)o ST-(g-z)o-err ST-(r-z)o ST-(r-z)o-err PRA PDEC P-DIST-H P-SB-r P-SB-r-err P-SB-g P-SB-g-err P-SB-z P-SB-z-err P-(g-r)o P-(g-r)o-err P-(g-z)o P-(g-z)o-err P-(r-z)o P-(r-z)o-err" > $results

fi

if [ $iprog -eq 1 ]; then

echo $NAME $CRA $CDEC $hsbr $hsbrerr $hsbg $hsbgerr $hsbz $hsbzerr $hgro $hgroerr $hgzo $hgzoerr $hrzo $hrzoerr \
$sblimr $sblimg $sblimz $ulsbr $ulsbg $ulsbz $distmax $distmin $widthmean $ulsigmeanr $ulsigmeang $ulsigmeanz $sbmeanr $sberrorr $sbmeang $sberrorg $sbmeanz $sberrorz $gromean $grerror $gzomean $gzerror $rzomean $rzerror \
$PRA $PDec $pdistas $psbr $psbrerr $psbg $psbgerr $psbz $psbzerr $pgro $pgroerr $pgzo $pgzoerr $przo $przoerr $irun >> $results

else

blank='        '

echo $NAME $CRA $CDEC $hsbr $hsbrerr $hsbg $hsbgerr $hsbz $hsbzerr $hgro $hgroerr $hgzo $hgzoerr $hrzo $hrzoerr \
$sblimr $sblimg $sblimz $ulsbr $ulsbg $ulsbz $distmax $distmin $widthmean $ulsigmeanr $ulsigmeang $ulsigmeanz $sbmeanr $sberrorr $sbmeang $sberrorg $sbmeanz $sberrorz $gromean $grerror $gzomean $gzerror $rzomean $rzerror \
"$blank" "$blank" "$blank" "$blank" "$blank" "$blank" $irun >> $results

fi

if [ $polygon -gt 0 ]; then

echo $NAME $CRA $CDEC $hsbr $hsbrerr $hsbg $hsbgerr $hsbz $hsbzerr $hgro $hgroerr $hgzo $hgzoerr $hrzo $hrzoerr \
$sblimr $sblimg $sblimz $ulsbr $ulsbg $ulsbz $distmax $distmin $widthmean $ulsigmeanr $ulsigmeang $ulsigmeanz $sbp1r $sberrp1r $sbp1g $sberrp1g $sbp1z $sberrp1z $grop1 $grerrorp1 $gzop1 $gzerrorp1 $rzop1 $rzerrorp1 \
"$blank" "$blank" "$blank" "$blank" "$blank" "$blank" $irun "polygon-1" >> $results

if [ $polygon -eq 2 ]; then

echo $NAME $CRA $CDEC $hsbr $hsbrerr $hsbg $hsbgerr $hsbz $hsbzerr $hgro $hgroerr $hgzo $hgzoerr $hrzo $hrzoerr \
$sblimr $sblimg $sblimz $ulsbr $ulsbg $ulsbz $distmax $distmin $widthmean $ulsigmeanr $ulsigmeang $ulsigmeanz $sbp2r $sberrp2r $sbp2g $sberrp2g $sbp2z $sberrp2z $grop2 $grerrorp2 $gzop2 $gzerrorp2 $rzop2 $rzerrorp2 \
"$blank" "$blank" "$blank" "$blank" "$blank" "$blank" $irun "polygon-2" >> $results

fi 

fi

fi
#===================== JPG IMAGE GENERATION =============================


# Generate selected JPG images
#maskjpg=$jpgdir/$NAME-masked.jpg 
   convertparams="--colormap=gray --fluxlow=-0.005 --fluxhigh=0.02 --invert"
#   astconvertt $tmpdir/masked.fits $convertparams -o$maskjpg
    astfits $tmpdir/nc-$filter.fits --copy=DETECTIONS --output=$tmpdir/nc-$filter-detections.fits
    astfits $tmpdir/nc-$filter.fits --copy=INPUT-NO-SKY --output=$tmpdir/nc-$filter-input-no-sky.fits
#   astconvertt nc-g-detections.fits > nc-g-detections.jpg
   astconvertt $tmpdir/nc-$filter-input-no-sky.fits $convertparams --output=$jpgdir/nc-$filter-input-no-sky.jpg
   astconvertt $tmpdir/nc-$filter-detections.fits --output=$jpgdir/nc-$filter-detections.jpg



# draw the contour of the galaxy and stream on the masked image
# if stream is attached to the host galaxy
astarithmetic $tmpdir/nc-lab.fits set-i i $label eq 2 dilate 2 fill-holes set-j \
j 2 erode 2 erode 2 erode set-k j k - --output=$tmpdir/contour.fits

# if stream is separated to the host galaxy
#astarithmetic $tmpdir/nc-lab.fits set-i i 'host label' eq i 'stream lable' eq + 2 dilate 2 fill-holes set-j \
#j 2 erode 2 erode 2 erode set-k j k - --output=$tmpdir/contour.fits

astarithmetic $tmpdir/nc-$filter.fits -g1 $tmpdir/contour.fits 1000 where \
              --output=$tmpdir/input-w-contour.fits

astarithmetic $tmpdir/masked-$filter.fits $tmpdir/contour.fits 1000 where -g1 \
              --output=$tmpdir/masked-w-contour.fits
              
#astconvertt $tmpdir/input-w-contour.fits --output=$tmpdir/input-w-contour.pdf \ 
#            --fluxlow=-0.005 --fluxhigh=0.02 --invert

#astconvertt $tmpdir/masked-w-contour.fits --output=$tmpdir/masked-w-contour.pdf \ 
#            --fluxlow=-0.005 --fluxhigh=0.02 --invert


# end of second step
echo end step 2
exit 1
fi


#===================== PDF FILE GENERATION ==============================


# Build the displayed PDF images
#image=$NAME-custom-image-$filter.fits
#basename=$(echo $image | sed -e's|-custom-image||' -e's|.fits.gz||')
basename=$NAME-$filter
inpdf=$figdir/$basename.pdf
inwcpdf=$figdir/$basename-wc.pdf
maskpdf=$figdir/$basename-masked.pdf
maskwcpdf=$figdir/$basename-masked-wc.pdf
warppdf=$figdir/$basename-warped.pdf
detectpdf=$figdir/$basename-detect.pdf
if ! [ -f $maskpdf ]; then
    wconvparams="--colormap=gray --fluxlow=-0.04 --fluxhigh=0.25 --invert"
    convertparams="--colormap=gray --fluxlow=-0.005 --fluxhigh=0.02 --invert"
#    astconvertt $tmpdir/conv.fits   $convertparams -o$inpdf
    astconvertt $tmpdir/nc-$filter-input-no-sky.fits   $convertparams -o$inpdf
    astconvertt $tmpdir/input-w-contour.fits   $convertparams -o$inwcpdf
#    astconvertt $tmpdir/interpolated.fits $convertparams -o$interppdf
#    astconvertt $tmpdir/nc-$filter-detections.fits $convertparams  -o$detectpdf
    astconvertt $tmpdir/nc-$filter-detections.fits --invert  -o$detectpdf 
    astconvertt $tmpdir/warped.fits $wconvparams   -o$warppdf
    astconvertt $tmpdir/masked-$filter.fits $convertparams -o$maskpdf
    astconvertt $tmpdir/masked-w-contour.fits $convertparams -o$maskwcpdf
fi


# end of second step
if [ $step -eq 3 ]; then
echo end step 3
exit 2
fi


#================== LATEX DOCUMENT GENERATION ===========================


# Write the LaTeX macros (to put into the paper):
macros=$texdir/detection-macros.tex
echo "\\newcommand{\\detectionaperradarcsec}{$rarcsec}" > $macros
echo "\\newcommand{\\detectioninterpngb}{$interpngb}" >> $macros
echo "\\newcommand{\\detectionapernumrandom}{$numrandom}" >> $macros
echo "\\newcommand{\\detectionnckernelfwhm}{$nc_kernel_fwhm}" >> $macros
echo "\\newcommand{\\detectionnckerneltrunc}{$nc_kernel_trunc}" >> $macros
echo "\\newcommand{\\detectionnckernelfwhmseg}{$seg_kernel_fwhm}" >> $macros
echo "\\newcommand{\\detectionnctilesize}{$nc_tilesize}" >> $macros
echo "\\newcommand{\\detectionncholesize}{$nc_holesize}" >> $macros

v=$(astnoisechisel --version | awk 'NR==1{print $NF}')
echo "\\newcommand{\\detectiongnuastrover}{$v}" >> $macros

aperbright=$(asttable $tmpdir/cat-region-$filter-ULSB.fits -cbrightness)
echo "\\newcommand{\\detectionaperbright}{$aperbright}" >> $macros

v=$(asttable $tmpdir/cat-region-$filter-ULSB.fits -cSURFACE_BRIGHTNESS \
	| awk '{printf "%.2f", $1}')
echo "\\newcommand{\\detectionapersb}{$v}" >> $macros

v=$(asttable $tmpdir/cat-region-$filter-ULSB.fits -cUPPERLIMIT_SIGMA \
	| awk '{printf "%.2f", $1}')
echo "\\newcommand{\\detectionaperupsigma}{$v}" >> $macros



# Delete contents of the Tikz directory in case it has anything and
# copy the PDF's LaTeX source into the TeX directory.
cp -r paper-$NAME.tex tex-$NAME/ $texdir/



# Go into the TeX directory and build the PDF there (to avoid all the
# temporary files).
cd $texdir
pdflatex -shell-escape -halt-on-error paper-$NAME.tex
biber paper-$NAME
pdflatex -shell-escape -halt-on-error paper-$NAME.tex
cp paper-$NAME.pdf $curdir/


