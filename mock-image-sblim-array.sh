#!/bin/bash
set -e
#
# High-level script to generate mock-images with background noise: 
# first adding noise to a sb map from cosmo-sims for a given sb limit,
# then measuring the sb limit of the generated image to verify the result.
#
# the sblimit will be calculated for sblimit1, sblimit1+1,.., sblimit2
#
# ioption = 0: subhalo array input, only images with noise will be produced
# ioption = 1: single subhalo input, only image with noise will be produced
# ioption = 2: single subhalo input, in addition, the SB-limit and Upper Level SB 
#              of the resulting image will be measured for verification purposes

#=========================== I / O ======================================

# in this version an array of subhalos is pocessed as an option


# see above
ioption=$1

if [ $ioption -eq 0 ]; then

array=$2

 
# 30 AURIGA halos (each with 3 los: 001, 010, 100) MW-like galaxies with stellar mass range ..... 
#subhaloArray=(1  2  3  4  5  6  7  8  9  10  11  12  13  14  15  16  17  18  19  20  21  22  23  24  25  26  27  28  29  30)
#subhaloArray=(1  2)
subhaloArray=(3  4  5  6  7  8  9  10  11  12  13  14  15)
#subhaloArray=(16  17  18  19  20  21  22  23  24  25  26  27  28  29  30)
 

echo "write subhalo array"

for i in ${!subhaloArray[@]}; do
  echo "element $i is ${subhaloArray[$i]}"
done

# echo "exit 0"
# exit 0


else
# The image file to be processed (sb map).
image=$2

fi

# sb limit from sblimit1 and up to sblimit2
sblimit1=$3
sblimit2=$4

#input directory
inpdir=$5

#output directory
outdir=$6



#zeropint for DES images is 22.5
zeropoint=22.5


export GSL_RNG_SEED=1599251212
 

if [ $ioption -eq 2 ]; then

# The output data file
output=$outdir/$image-$zeropoint-$sblimit-output.txt

echo "name of input image file" $image > $output
echo "zeropoint: " $zeropoint >> $output
echo "sblimit: " $sblimit1 >> $output
echo "sblimit: " $sblimit2 >> $output

fi   


#===================GENERATE IMAGE WITH BACKGROUND NOISE====================

#pixel width for DES is 0.262 arcsec/pixel
pixel_width_arcsec=0.262
#pixel width for ARRAKIHS is 1.375 arcsec/pixel
#pixel_width_arcsec=1.375

pixarea=$(awk 'BEGIN {print '$pixel_width_arcsec'^2}')

# 3 sigma for calculation of sb limit
sblimitsigman=3

# sb limit calculated in a 100 arcsec^2 aperture
sblimitareaarcsec2=100



if [ $ioption -eq 0 ]; then

# do loop over all subhalos in the array

echo "start processing subhalo array"

for i in ${!subhaloArray[@]}; do
  echo "element $i is subhalo: ${subhaloArray[$i]}"

subhalo=${subhaloArray[$i]}

# DECam instrument at 70 Mpc distance
image=AURIGA_halo_${subhalo}_DES_DECam_SDSSr_70Mpc_rspmode-none_rspfac-1_los010.fits.gz


if ! [ -d $outdir/$image ]; then mkdir $outdir/$image; fi

jpgdir=$outdir/JPEG
if ! [ -d $jpgdir  ]; then mkdir $jpgdir ; fi


sblimit=$sblimit1

# start of loop to generate images for sblimit1, sblimit1+1,..., sbmlimit2
#
while [ $sblimit -le $sblimit2 ]; do

#for nfkoating point sblimit
#while (( $(echo "$sblimit2 > $sblimit" |bc -l) )); do

sigma_counts=$(astarithmetic $sblimit $zeropoint $sblimitareaarcsec2 $pixarea x sqrt sb-to-counts $sblimitsigman / --quiet)


echo $sigma_counts

if [ $ioption -eq 2 ]; then

echo "sigma_counts: " $sigma_counts >> $output   

fi

# the output image (counts with noise corresponding to sblimit and zeropint)
output_image=$outdir/$image/$image-$zeropoint-$sblimit.fits


astarithmetic $inpdir/$image --hdu=0 $zeropoint $pixarea sb-to-counts $sigma_counts mknoise-sigma --envseed --output=$output_image



# Generate JPG images

   convertparams="--colormap=gray --fluxlow=-0.005 --fluxhigh=0.02 --invert --quality=100"
   
   astconvertt $output_image $convertparams --output=$jpgdir/$image-$zeropoint-$sblimit.jpg



# increment sblimit by 1
sblimit=$(awk 'BEGIN {print '$sblimit' + 1}')

# end of the loop over the sblimit  
done



# end of the lopp over the halos
done




else

# single sbmap to be processed

jpgdir=$outdir/jpg
if ! [ -d $outdir  ]; then mkdir $outdir ; fi
if ! [ -d $jpgdir  ]; then mkdir $jpgdir ; fi
#mkdir $outdir
#mkdir $jpgdir

sblimit=$sblimit1

# start of loop to generate images for sblimit1, sblimit1+1,..., sbmlimit2
#
while [ $sblimit -le $sblimit2 ]; do

sigma_counts=$(astarithmetic $sblimit $zeropoint $sblimitareaarcsec2 $pixarea x sqrt sb-to-counts $sblimitsigman / --quiet)


echo $sigma_counts

if [ $ioption -eq 2 ]; then

echo "sigma_counts: " $sigma_counts >> $output   

fi

# the output image (counts with noise corresponding to sblimit and zeropint)
output_image=$outdir/$image-$zeropoint-$sblimit.fits


astarithmetic $inpdir/$image --hdu=0 $zeropoint $pixarea sb-to-counts $sigma_counts mknoise-sigma --envseed --output=$output_image



# Generate JPG images
   convertparams="--colormap=gray --fluxlow=-0.005 --fluxhigh=0.02 --invert --quality=100"
   astconvertt $output_image $convertparams --output=$jpgdir/$image-$zeropoint-$sblimit.jpg



# increment sblimit by 1
sblimit=$(awk 'BEGIN {print '$sblimit' + 1}')

# end of the loop  
done

fi

if [ $ioption -le 1 ]; then

echo exit1

exit 1

fi
#=================== DEFINE MISSING DATA IN IMAGE HEADER =================

# Adding WCS data to the mock-image (has only pixel dimensions in the header)
# This is done in 3 steps:
# 1) by creating an empty FITs file with the WCS data,
# 2) updating the WCS data of the empty file to the right ones
# 3) superimpose the empty image on the input image for it to take the data  


# Position on the sky (dummy values to fill in the WCS structure)
center_dec=0
center_ra=180

cdelt=$(echo $pixel_width_arcsec | awk '{print $1/3600}')
naxis1=$(astfits $output_image -h1 --keyvalue=NAXIS1 -q)
naxis2=$(astfits $output_image -h1 --keyvalue=NAXIS2 -q)
crpix1=$(echo $naxis1 | awk '{print int($1/2)+1}')
crpix2=$(echo $naxis2 | awk '{print int($1/2)+1}')

echo $center_ra $center_dec $cdelt $naxis1 $naxis2 $crpix1 $crpix2

echo "center_ra center_dec cdelt naxis1 naxis2 crpix1 crpix2:"  >> $output
echo $center_ra $center_dec $cdelt $naxis1 $naxis2 $crpix1 $crpix2    >> $output

echo "1 1 1 4 0 0 0 0 1 1" \
    | astmkprof --mergedsize=3,3 --output=wcs-structure.fits
astfits wcs-structure.fits  \
	--update=CDELT1,$cdelt \
	--update=CDELT2,$cdelt \
	--update=CRPIX1,$crpix1 \
	--update=CRPIX2,$crpix2 \
	--update=CRVAL1,$center_ra \
	--update=CRVAL2,$center_dec
astarithmetic $output_image -h1 --wcsfile=wcs-structure.fits --output=$output_image-w-wcs.fits


#======================== GNUASTRO CONFIGURATION ==========================

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


# Detection parameters and default values:
blocksize=8
interpngb=10
nc_tilesize=40
nc_kernel_fwhm=3
#nc_kernel_fwhm=3 default
nc_holesize=10000
#nc_holesize=10000 default
nc_kernel_trunc=4
qthreshold=0.3
#qthreshold=0.4 default, but 0.3 for all DES streams
#detgrowquant=0.9 default set in code
#detgrowquant=0.8 to grow detections
segbordersn=1
#segbordersn=1 default value


echo "IMAGE CHARACTERISTICS ----------------------------------------------------------------------" >> $output
echo "PIXEL SCALE (pixel/arcsec): " $pixel_width_arcsec >> $output
echo "PIXEL SCALE (pixel/deg): " $cdelt >> $output  
echo "ZERO POINT = " $zeropoint >> $output
echo "NOISECHISEL DETECTION CONFIGURATION PARAMETERS-----------------------------------------------" >> $output
echo "qthresh = " $qthreshold >> $output
echo "blocksize = " $blocksize >> $output
echo "interpngb = " $interpngb >> $output
echo "nc_tilesize = " $nc_tilesize >> $output
echo "nc_kernel_fwhm = " $nc_kernel_fwhm >> $output
echo "nc_holesize = " $nc_holesize >> $output
echo "nc_kernel_trunc = " $nc_kernel_trunc >> $output
echo "objbordersn  = " $segbordersn >> $output


#================= DETECTION ==========================================

# The kernel's center is built with Monte-carlo integration (using
# random numbers), so to avoid reproducibility problems, we'll fix the
# random number generator (RNG) seed.
export GSL_RNG_SEED=1599251212

    astmkprof --kernel=gaussian,$nc_kernel_fwhm,$nc_kernel_trunc \
	      --oversample=1 --envseed --output=kernel.fits


# Detection with noise-chissel

imagehdu=1

    astnoisechisel $output_image-w-wcs.fits -h$imagehdu \
		   --kernel=kernel.fits \
		   --tilesize=$nc_tilesize,$nc_tilesize \
		   --detgrowmaxholesize=$nc_holesize \
       --qthresh=$qthreshold \
		   --output=$output_image-nc.fits


echo "=============================================================================================" >> $output
echo "SURFACE BRIGHTNESS LIMIT and UPPER LIMIT SURFACE BRIGHTNESS" >> $output


# Build aperture of 100 arcsec2 to measure UL-SB 
rarcsec=5.64
#pixscale=3.792188 DES DECam
#pixscale=0.727273 ARRAKIHS VIS
pixscale=3.792188
numrandom=10000
#CX=$(astfits nc.fits -h1 --keyvalue=CRPIX1 --quiet)
#CY=$(astfits nc.fits -h1 --keyvalue=CRPIX2 --quiet)
CX=1024
CY=1024
apcenter="$CX $CY"
rpix=$(awk 'BEGIN {print '$rarcsec' * '$pixscale'}')

echo $rarcsec $pixscale $CX $CY $apcenter $rpix

echo " rarcsec pixscale CX CY apcenter rpix" >> $output
echo $rarcsec $pixscale $CX $CY $apcenter $rpix >> $output

    aper=aperture-ULSB.fits
#    rpix=$(astfits nc.fits --pixelscale -q \
#	       | awk '{print '$rarcsec'/($1*3600)}')
    echo "1 $apcenter 5 $rpix 0 0 1 1 1" \
	| astmkprof --background=$output_image-nc.fits --clearcanvas \
		    --mode=img --envseed --oversample=1 --mforflatpix \
		    --type=uint8 -o$aper

# Make a catalog with upper-limit measurements for the r band.

    astmkcatalog $aper -h1 --valuesfile=$output_image-nc.fits --envseed \
		 --valueshdu=INPUT-NO-SKY --checkuplim=1 --upnum=$numrandom \
     --sfmagnsigma=3 --sfmagarea=100 --upnsigma=3 \
		 --upmaskfile=$output_image-nc.fits --upmaskhdu=DETECTIONS \
		 --zeropoint=$zeropoint -ocat-region-ULSB.fits \
		 --ids --sum --sum-error --magnitude --magnitude-error --area --area-arcsec2 \
		 --upperlimit-sigma --sn --sb --sb-error --upperlimit-sb

# Write results to the output file
   
echo "---------------------------------------------------------------------------------------------" >> $output
echo "# Column 1:APERTURE ID		      [Integer,] Circular aperture identifier." >> $output
echo "# Column 2:BRIGHTNESS (SUM)     [counts, f32,] Sum of sky-subtracted pixel values in the circular aperture ." >> $output
echo "# Column 3:BRIGHTNESS_ERROR	    [counts, f32,] Error (1-sigma) in measuring brightness." >> $output
echo "# Column 4:MAGNITUDE	  	      [mag, f32,] Magnitude measured in the circular aperture." >> $output
echo "# Column 5:MAGNITUDE_ERROR	    [mag, f32,] Error in measring magnitude." >> $output
echo "# Column 6:AREA      			      [Integer,] Area of the circular aperture in pixels." >> $output
echo "# Column 7:AREAARCSEC2		      [arcsec^2, f32,] Area of the circular aperture in arcsec^2." >> $output
echo "# Column 8:UPPERLIMITSIGMA	    [Integer,] Multiple of 'upper limit' sigma." >> $output
echo "# Column 9:SNR			            [Integer,] Signal to noise ratio." >> $output
echo "# Column 10:SURFACE_BRIGHTNESS	[mag/arcsec^2, f32,] Surface brightness." >> $output
echo "# Column 11:SB_ERROR		        [mag/arcsec^2, f32,] Error in measuring surface brightness." >> $output
echo "# Column 12:UPPERLIMIT_SB-r     [mag/arcsec^2, float32] Upper limit surface brightness. " >> $output
echo "---------------------------------------------------------------------------------------------" >> $output

asttable cat-region-ULSB.fits >> $output

echo "---------------------------------------------------------------------------------------------" >> $output
echo "name of image file with WCS data                                                             " >> $output   
echo $output_image-w-wcs.fits >> $output 
echo "---------------------------------------------------------------------------------------------" >> $output
 
echo "UPPERLIMIT_SB-r [mag/arcsec^2, float32] Upper limit surface brightness for r band, 3-sigma, 100 arcsec^2." >> $output
    ulsbr=$(asttable cat-region-ULSB.fits -h1 -cUPPERLIMIT_SB) >> $output
echo $ulsbr >> $output    
echo "---------------------------------------------------------------------------------------------" >> $output
echo "SURFACE BRIGHTNESS LIMIT---------------------------------------------------------------------" >> $output    
    astfits cat-region-ULSB.fits -h1 | grep ^SBL >> $output
    sblimr=$(astfits cat-region-ULSB.fits -h1 --keyvalue=SBLMAG --quiet)
#   astfits cat-region-ULSB.fits -h1 | grep ^UP >> $output
