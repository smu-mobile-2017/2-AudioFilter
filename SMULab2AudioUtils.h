//
//  SMULab2AudioUtils.h
//  AudioLab
//
//  Created by Justin Wilson on 9/20/17.
//
//  Writen by Justin Wilson, Paul Herz, and Jake Rowland
//  Sept 22 2017


#import <Foundation/Foundation.h>

@interface SMULab2AudioUtils : NSObject
/// Resovles the peak freq with quad. estimation from 3 quantas
+ (float) resolveFPeak: (float) f2
							 withMag1: (float) m1
							 withMag2: (float) m2
							 withMag3: (float) m3
				 withDeltaFreq: (float) dF;

/// Resovles the peak freq with quad. estimation
+ (float) resolveFPeak: (float*) fftMagArray withIndex: (int) idx withDeltaFreq: (float) dF;

/// Find the index of the max value in an c-style array, no error checking
+ (int) findMaxIndex: (float*) array withSizeOf: (int) arraySize;

/// Fills resultBuffer of size nPeaks*2, [Hz 0, dB value 0,...];
//  fftMagArray must be > floor(WINDOW_SIZE), even length only, no error checking,
//  Starts at an index of 1
+ (void) detectHightestTones: (float*) fftMagArray
									withSizeOf: (int) magArraySize
							withWindowSize: (float) winSize
								andDeltaFreq: (float) deltaFreq
				 placeInResultBuffer: (float*) resultBuffer
									withNpeaks: (int) nPeaks;

/// Shifts array left by dist, padds end with zeros and no error checking
+ (void) shiftArrayLeft: (float*) array withSizeOf: (int) arraySize
																 withStartPosition: (int) start
															 withShiftDistanceOf: (int) dist;
@end
