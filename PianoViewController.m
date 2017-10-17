//
//  ViewController.m
//  AudioLab
//
//  Seed Code - Created by Eric Larson
//  Copyright © 2016 Eric Larson. All rights reserved.
//
//  Writen by Justin Wilson, Paul Herz, and Jake Rowland
//  Sept 22 2017
//

#import "PianoViewController.h"
#import "Novocaine.h"
#import "CircularBuffer.h"
#import "SMUGraphHelper.h"
#import "FFTHelper.h"
#import "SMULab2AudioUtils.h"

// 2^13 is 8192, 2^14 is 16384, 200ms = 8820, 400ms = 17640
#define BUFFER_SIZE 16384//twice as big to cover 400ms vs 200ms (ftt)

// Fs/N = dF only the size of sampling buffer passed to the ftt
#define DELTA_FREQ 44100.0/16384//8192 //BUFFER_SIZE/2 accounting for the 200ms cut.
#define WINDOW_SIZE 10 //in Hz

@interface PianoViewController ()

@property (nonatomic, getter=isLocked) BOOL locked;
@property (nonatomic) int debounceP; //decaying flag for piano key harmonic label
@property (strong, nonatomic) Novocaine *audioManager;
@property (strong, nonatomic) CircularBuffer *buffer;
@property (strong, nonatomic) SMUGraphHelper *graphHelper;
@property (strong, nonatomic) FFTHelper *fftHelper;
@property (strong, nonatomic) NSNumberFormatter *floatFormatter;
@property (weak, nonatomic) IBOutlet UILabel *peakValuesTextLabel;
@property (weak, nonatomic) IBOutlet UIButton *lockButton;
@property (weak, nonatomic) IBOutlet UISlider *thresholdSlider;
@property (weak, nonatomic) IBOutlet UILabel *thresholdLabel;
@property (weak, nonatomic) IBOutlet UILabel *keyLabel;

@end

@implementation PianoViewController

#pragma mark Lazy Instantiation
- (Novocaine*)audioManager{
    if(!_audioManager){
        _audioManager = [Novocaine audioManager];
    }
    return _audioManager;
}

- (CircularBuffer*)buffer{
    if(!_buffer){
        _buffer = [[CircularBuffer alloc]initWithNumChannels:1 andBufferSize:BUFFER_SIZE];
    }
    return _buffer;
}

- (SMUGraphHelper*)graphHelper{
    if(!_graphHelper){
        _graphHelper = [[SMUGraphHelper alloc]initWithController:self
                                        preferredFramesPerSecond:15
                                                       numGraphs:2
                                                       plotStyle:PlotStyleSeparated
                                               maxPointsPerGraph:BUFFER_SIZE];
    }
    return _graphHelper;
}

- (FFTHelper*)fftHelper{
    if(!_fftHelper){
			_fftHelper = [[FFTHelper alloc]initWithFFTSize:BUFFER_SIZE];//sampler buffer of ~200 will be passed
    }
    
    return _fftHelper;
}

- (NSFormatter*) floatFormatter {
	if(!_floatFormatter){
		_floatFormatter = [[NSNumberFormatter alloc] init];
		[_floatFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
		[_floatFormatter setMaximumFractionDigits:2];
	}
	
	return _floatFormatter;
}

#pragma mark VC Life Cycle
- (void)viewDidLoad {
	
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
		self.debounceP = 0;
    [self.graphHelper setFullScreenBounds];
    
    __block PianoViewController * __weak  weakSelf = self;
    [self.audioManager setInputBlock:^(float *data, UInt32 numFrames, UInt32 numChannels){
        [weakSelf.buffer addNewFloatData:data withNumSamples:numFrames];
    }];
	
		//rotate slider
		[self.thresholdLabel setText:[NSString stringWithFormat:@"%@ dB", [self.floatFormatter stringFromNumber: @(self.thresholdSlider.value)]]];
		self.thresholdSlider.transform = CGAffineTransformMakeRotation((CGFloat) -M_PI_2);
	
		[self.audioManager play];
}

#pragma mark VC Life Cycle
- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	[self.audioManager pause];
}

///Handles lockButton
- (IBAction)lockButtonPressed:(UIButton *)sender {
	if([self isLocked]) {
		[sender setTitle:@"Lock" forState:UIControlStateNormal];
		self.locked = NO;
		//[self.audioManager play];
	} else {
		[sender setTitle:@"Resume" forState:UIControlStateNormal];
		self.locked = YES;
		//[self.audioManager pause];
	}
}

/// Sets label for thresholdSlider
- (IBAction)thresholdSliderSlid:(UISlider *)sender {
	[self.thresholdLabel setText:[NSString stringWithFormat:@"%@ dB",
														[self.floatFormatter stringFromNumber: @(self.thresholdSlider.value)]]];
}


#pragma mark GLK Inherited Functions
/// override the GLKViewController update function, from OpenGLES - Seed code Dr. Larson
- (void)update{
    //just plot the audio stream
	
    //get audio stream data
    float* arrayData = malloc(sizeof(float) * BUFFER_SIZE); //record longer
	  float* fftMagnitude = malloc(sizeof(float) * BUFFER_SIZE/2);//half of ~200 ms samlple size
	
	  //create returnBuffer for peakValue aquisition
		int nPeaks = 15;
		float* peakValues = malloc(sizeof(float)*2*nPeaks); //2 values for each
    
    [self.buffer fetchFreshData:arrayData withNumSamples:BUFFER_SIZE];
	
		//overwrite ~200 MS from the front and padd with 0s for increased res.
		for(int pos = 0; pos < BUFFER_SIZE/2; pos++) {
			arrayData[pos] = 0;
		}
	
    //send off for graphing
    [self.graphHelper setGraphData:&arrayData[BUFFER_SIZE/2]
                    withDataLength:8000//BUFFER_SIZE/2 which is 8192, suppress error use 8k
                     forGraphIndex:1];
	
    //take forward FFT
		[self.fftHelper performForwardFFTWithData:arrayData
                   andCopydBMagnitudeToBuffer:fftMagnitude];
	
		//reduce error
		[self fftErrorReducer:arrayData withSizeOf:BUFFER_SIZE
								dataStart:BUFFER_SIZE/2 forFTT:fftMagnitude
								withSizeOf:BUFFER_SIZE/2];
    
	  [self.graphHelper setGraphData:fftMagnitude
									withDataLength:8000//BUFFER_SIZE/2 which is 8192, suppress error use 8k
									 forGraphIndex:0
							 withNormalization:64.0
									 withZeroValue:-60];
	

	  [SMULab2AudioUtils detectHightestTones: fftMagnitude
																withSizeOf:BUFFER_SIZE/2 //half the ~200ms buffer
														withWindowSize:WINDOW_SIZE
															andDeltaFreq:DELTA_FREQ
											 placeInResultBuffer:peakValues
																withNpeaks:nPeaks];
	
		if(!self.isLocked) {
				[self.peakValuesTextLabel setText:
						[NSString stringWithFormat:@"%@ Hz %@ dB\n%@ Hz %@ dB",
						[self.floatFormatter stringFromNumber:
						 @([SMULab2AudioUtils resolveFPeak:fftMagnitude withIndex:peakValues[0] withDeltaFreq:DELTA_FREQ])],
						[self.floatFormatter stringFromNumber:@(peakValues[1])],
						[self.floatFormatter stringFromNumber:
						 @([SMULab2AudioUtils resolveFPeak:fftMagnitude withIndex:peakValues[2] withDeltaFreq:DELTA_FREQ])],
					  [self.floatFormatter stringFromNumber:@(peakValues[3])]]];
			
			//Sharpen and build log
			float freqs[nPeaks];
			NSString *logString = @"\n";
			for(int i = 0; i < nPeaks; i++) {
				float fp = [SMULab2AudioUtils resolveFPeak:fftMagnitude withIndex:peakValues[i*2] withDeltaFreq:DELTA_FREQ];
				freqs[i] = fp;
				logString =  [logString stringByAppendingString:[NSString stringWithFormat:@"%f ", fp]]; //log string
			}
			[logString stringByAppendingString:@"\n"];
			
			//Find 2 different harmonics
			float threshold = 20;
			float remainder;
			float harmonic[2] = { -1, -1 };
			BOOL hFound = NO;
			
			//check first two peaks for harmonics
			for(int i = 1; i < nPeaks; i++) {
				remainder = fmodf(freqs[0], freqs[i]);
				if (remainder <= threshold || remainder >= (freqs[i] - threshold)) {
					hFound = YES;
					harmonic[0] = freqs[i]; //lowest
					self.debounceP = 2;
				}
			}
			
			for(int i = 2; i < nPeaks; i++) {
				remainder = fmodf(freqs[1], freqs[i]);
				if (remainder <= threshold || remainder >= (freqs[i] - threshold)) {
					hFound = YES;
					harmonic[1] = freqs[i]; //lowest
					self.debounceP = 2;
				}
			}
		
			NSLog(@"%@", logString);
			
		  //translate keys from lowest harmonics found
			NSString *keyName1 = [self getKey:harmonic[0] withTolerance:threshold];
			NSString *keyName2 = [self getKey:harmonic[1] withTolerance:threshold];
			
			//ensure keys found are not nil, and check two highest peaks werwe above 0dB, and set label
			if(hFound) {
				if (keyName1 != nil && keyName2 != nil && peakValues[1] > 0 && peakValues[3] > 0) {
					self.keyLabel.text = [[keyName1 stringByAppendingString:@" "] stringByAppendingString: keyName2];
				} else if(keyName1 != nil && peakValues[1] > 0) {
					self.keyLabel.text = keyName1;
				} else if(keyName2 != nil && peakValues[3] > 0) {
					self.keyLabel.text = keyName2;
				} else {
					if(self.debounceP <= 0)
						self.keyLabel.text = @" ";
				}
			}
			
		}

    [self.graphHelper update]; // update the graph
		//free
    free(arrayData);
    free(fftMagnitude);
	
	
	if(peakValues[1] > self.thresholdSlider.value && !self.isLocked) {
			//if greater than 10 db, pause
			[self.lockButton setTitle:@"Resume" forState:UIControlStateNormal];
			self.locked = YES;
		}
	
	free(peakValues);
	self.debounceP--;
}

///Reduce the noise in the FFT
- (void) fftErrorReducer: (float *) sampleArray withSizeOf: (int) sampleSize
							 dataStart: (int) dataStart
									forFTT: (float *) fftArray
							withSizeOf: (int) fftSize {
	
	//allocate arrays
	float* samplingShift1 = malloc(sizeof(float) * sampleSize);
	float* samplingShift2 = malloc(sizeof(float) * sampleSize);
	float* fftMag1 = malloc(sizeof(float) * fftSize);
	float* fftMag2 = malloc(sizeof(float) * fftSize);
	
	//copy
	memcpy(samplingShift1, sampleArray, sizeof(float) * sampleSize);
	memcpy(samplingShift2, sampleArray, sizeof(float) * sampleSize);
	
	//shift twice
	[SMULab2AudioUtils shiftArrayLeft:samplingShift1 withSizeOf: sampleSize withStartPosition:dataStart withShiftDistanceOf:1];
	[SMULab2AudioUtils shiftArrayLeft:samplingShift2 withSizeOf: sampleSize withStartPosition:dataStart withShiftDistanceOf:1];
	
	//do two more FTTs
	[self.fftHelper performForwardFFTWithData:samplingShift1
								 andCopydBMagnitudeToBuffer:fftMag1];
	
	[self.fftHelper performForwardFFTWithData:samplingShift2
								 andCopydBMagnitudeToBuffer:fftMag2];
	
	//average
	for(int i = 0; i < fftSize; i++) {
		fftArray[i] += fftMag1[i] + fftMag2[i];
		fftArray[i] /= 3;
	}
	
	//free
	free(samplingShift1);
	free(samplingShift2);
	free(fftMag1);
	free(fftMag2);
	
}

///override the GLKView draw function, from OpenGLES
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
		if(!self.isLocked)
			[self.graphHelper draw]; // draw the graph
}

///Translate frequency to piano key, within a tolerance, keys are in scientific notation not helmholtz
- (NSString*) getKey: (float) freq withTolerance: (float) tolerance {
	
	//size 68 one to one with keyStrings
	float freqArray[] = {5274.04, 4978.03, 4698.64, 4434.92, 4186.01, 3951.07, 3729.31, 3520, 3322.44, 3135.96, 2959.96, 2793.83, 2637.02, 2489.02, 2349.32, 2217.46, 2093, 1975.53, 1864.66, 1760, 1661.22, 1567.98, 1479.98, 1396.91, 1318.51, 1244.51, 1174.66, 1108.73, 1046.5, 987.767, 932.328, 880, 830.609, 783.991, 739.989, 698.456, 659.255, 622.254, 587.33, 554.365, 523.251, 493.883, 466.164, 440, 415.305, 391.995, 369.994, 349.228, 329.628, 311.127, 293.665, 277.183, 261.626, 246.942, 233.082, 220, 207.652, 195.998, 184.997, 174.614, 164.814, 155.563, 146.832, 138.591, 130.813, 123.471, 116.541, 110};
	
	//size 68 one to one with freqArray
	NSArray *keyStrings = @[@"E8", @"D♯8", @"D8", @"C♯8", @"C8", @"B7", @"A♯7", @"A7", @"G♯7", @"G7", @"F♯7", @"F7", @"E7", @"D♯7", @"D7", @"C♯7", @"7C", @"B6", @"A♯6", @"A6", @"G♯6", @"G6", @"F♯6", @"F6", @"E6", @"D♯6", @"D6", @"C♯6", @"C6", @"B5", @"A♯5", @"A5", @"G♯5", @"G5", @"F♯5", @"F5", @"E5", @"D♯5", @"D5", @"C♯5", @"C5", @"B4", @"A♯4", @"A4", @"G♯4", @"G4", @"F♯4", @"F4", @"E4", @"D♯4", @"D4", @"C♯4", @"C4", @"B3", @"A♯3", @"A3", @"G♯3", @"G3", @"F♯", @"F3", @"E3", @"D♯3", @"D3", @"C♯3", @"C3", @"B2", @"A♯2", @"A2"];
	
	//loop through matching keys for tolerance.
	for(int i = 0; i < 68; i++) {
		if(freq >= freqArray[i] - tolerance && freq <= freqArray[i] + tolerance)
			return keyStrings[i];
	}
	
	return nil;
}


@end
