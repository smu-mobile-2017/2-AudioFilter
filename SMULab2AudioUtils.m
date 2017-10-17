//
//  SMULab2AudioUtils.m
//  AudioLab
//
//  Created by Justin Wilson on 9/20/17.
//  Copyright © 2017 Eric Larson. All rights reserved.
//
//  Writen by Justin Wilson, Paul Herz, and Jake Rowland
//  Sept 22 2017
//

#import "SMULab2AudioUtils.h"

@implementation SMULab2AudioUtils

/// Resovles the peak freq with quad. estimation from 3 quantas
+ (float) resolveFPeak: (float) f2 withMag1: (float) m1
																	 withMag2: (float) m2
																	 withMag3: (float) m3
														 withDeltaFreq: (float) dF {
	return f2 + (((m3 - m2) / (2 * m2 - m1 - m2)) * dF/2);
}


/// Resovles the peak freq with quad. estimation
+ (float) resolveFPeak: (float*) fftMagArray withIndex: (int) idx withDeltaFreq: (float) dF{
	float f2, m1, m2, m3;
	f2 = dF * idx;
	m1 = fftMagArray[idx - 1];
	m2 = fftMagArray[idx];
	m3 = fftMagArray[idx + 1];
	
	return [SMULab2AudioUtils resolveFPeak:f2 withMag1:m1 withMag2:m2 withMag3:m3 withDeltaFreq:dF];
}


/// Find the index of the max value in an c-style array, no error checking
+ (int) findMaxIndex: (float*) array withSizeOf: (int) arraySize {
	int maxIndex = 0;
	float maxValue = array[maxIndex];
	
	for(int i = 1; i < arraySize; i++){
		if(array[i] > maxValue) {
			maxValue = array[i];
			maxIndex = i;
		}
	}
	
	return maxIndex;
}

/// Fills resultBuffer of size nPeaks*2, [Hz 0, dB value 0,...];
//  fftMagArray must be > floor(WINDOW_SIZE), even length only, no error checking,
//  Starts at an index of 1
+ (void) detectHightestTones: (float*) fftMagArray
															withSizeOf: (int) magArraySize
													withWindowSize: (float) winSize
														andDeltaFreq: (float) deltaFreq
													placeInResultBuffer: (float*) resultBuffer
									withNpeaks: (int) nPeaks {
	
	//compute index window
	int windowCenterIdx = 0;
	
	int idxWindowLength = (int) winSize/deltaFreq; //cut decimal off
	
	if(idxWindowLength % 2 == 0) {
		//increase the window size by 1 to make window odd
		idxWindowLength++;
	}
	
	//calc center of window
	windowCenterIdx = (int) idxWindowLength / 2; // floor(odd/2) for 0... < Window Size
	
	//scratch vars
	float peakValues[nPeaks];  //= {-60, -60, -60}; //maintain decending order
	float peakIndicies[nPeaks]; // = {0, 1, 2};
	
	for(int i = 0; i < nPeaks; i++) {
		//fill scratch vars
		peakValues[i] = -60;
		peakIndicies[i] = i; //prevents update function from crashing when a blank buffer is passed.
		
	}
	
	int peakIdx = 0; //index of peak value in window sub-array
	float peakFound; //peak value in window sub-array
	
	//find the two largest tones, '<=' becasue window is inclusive of the index passed
	for(int index = 1; index <= magArraySize - idxWindowLength; index++){
		
		//get peak value's index for given subarry
		peakIdx = [self findMaxIndex:&fftMagArray[index] withSizeOf: idxWindowLength];
		
		//if our index is center of the window, check for the two largest tones
		if(peakIdx == windowCenterIdx) {
			peakFound = fftMagArray[index + peakIdx];  //resolve with true index, index + peakIdx

			//find index to replace in the arrays
			int replacmentIndex = -1; //if -1 then do not replace
			for(int pos = nPeaks - 1; pos >= 0; pos--) {
				if(peakFound > peakValues[pos])
					replacmentIndex = pos; //save index
			}
			
			if(replacmentIndex > -1) {
				//shift array's
				for(int pos = 2; pos > replacmentIndex; pos--) {
					peakValues[pos] = peakValues[pos-1];
					peakIndicies[pos] = peakIndicies[pos-1];
				}
			
				//update
				peakValues[replacmentIndex] = peakFound;
				peakIndicies[replacmentIndex] = peakIdx + index;
			}
		}
	}
	
	//fill the return buffer [index, value, ...]
	int peakArrayIndex = 0;
	for(int pos = 0; pos < nPeaks * 2; pos += 2) {
		resultBuffer[pos] = peakIndicies[peakArrayIndex];
		resultBuffer[pos+1] = peakValues[peakArrayIndex];
		peakArrayIndex++;
	}
}

/// Shifts array left by dist, padds end with zeros and no error checking
+ (void) shiftArrayLeft: (float*) array withSizeOf: (int) arraySize
																 withStartPosition: (int) start
															 withShiftDistanceOf: (int) dist {
	//shift
	for(int i = start; i < arraySize; i++)
		array[i-dist] = array[i];
	
	//pad last values with zero
	for(int i = arraySize-dist; i < arraySize; i++)
		array[i] = 0;
}


@end
