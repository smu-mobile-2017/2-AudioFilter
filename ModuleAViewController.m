//
//  ViewController.m
//  AudioLab
//
//  Seed Code - Created by Eric Larson
//  Copyright © 2016 Eric Larson. All rights reserved.
//
//  Writen by Justin Wilson, Paul Herz, and Jake Rowland
//  Sept 22 2017

#import "ModuleAViewController.h"
#import "Novocaine.h"
#import "CircularBuffer.h"
#import "SMUGraphHelper.h"
#import "FFTHelper.h"
#import "SMULab2AudioUtils.h"

// 2^13 is 8192, 2^14 is 16384, 200ms = 8820, 400ms = 17640
#define BUFFER_SIZE 16384//twice as big to cover 400ms vs 200ms (ftt)
//#define SAMPLE_BUFFER_FOR_FFT 8192

// Fs/N = dF only the size of sampling buffer passed to the ftt
#define DELTA_FREQ 44100.0/16384//8192 //BUFFER_SIZE/2 (accounting for the 200ms cut.
#define WINDOW_SIZE 50 //in Hz

@interface ModuleAViewController ()

@property (nonatomic, getter=isLocked) BOOL locked;
@property (strong, nonatomic) Novocaine *audioManager;
@property (strong, nonatomic) CircularBuffer *buffer;
@property (strong, nonatomic) SMUGraphHelper *graphHelper;
@property (strong, nonatomic) FFTHelper *fftHelper;
@property (strong, nonatomic) NSNumberFormatter *floatFormatter;
@property (weak, nonatomic) IBOutlet UILabel *peakValuesTextLabel;
@property (weak, nonatomic) IBOutlet UIButton *lockButton;
@property (weak, nonatomic) IBOutlet UISlider *thresholdSlider;
@property (weak, nonatomic) IBOutlet UILabel *thresholdLabel;

@end

@implementation ModuleAViewController

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
			_fftHelper = [[FFTHelper alloc]initWithFFTSize:BUFFER_SIZE];
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
	
    [self.graphHelper setFullScreenBounds];
    
    __block ModuleAViewController * __weak  weakSelf = self;
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

///If lockButton is pressed swap action
- (IBAction)lockButtonPressed:(UIButton *)sender {
	if([self isLocked]) {
		[sender setTitle:@"Lock" forState:UIControlStateNormal];
		self.locked = NO;
	} else {
		[sender setTitle:@"Resume" forState:UIControlStateNormal];
		self.locked = YES;
	}
}

///If slider is moved change threshold value
- (IBAction)thresholdSliderSlid:(UISlider *)sender {
	
	[self.thresholdLabel setText:[NSString stringWithFormat:@"%@ dB",
														[self.floatFormatter stringFromNumber: @(self.thresholdSlider.value)]]];
}


#pragma mark GLK Inherited Functions
///  override the GLKViewController update function, from OpenGLES - Seed code Dr. Larson
- (void)update{
    //just plot the audio stream
	
    //get audio stream data
    float* arrayData = malloc(sizeof(float) * BUFFER_SIZE); //record longer
	  float* fftMagnitude = malloc(sizeof(float) * BUFFER_SIZE/2);//half of ~200 ms samlple size
	
	  //create returnBuffer for peakValue aquisition
		float* peakValues = malloc(sizeof(float)*6);
    
    [self.buffer fetchFreshData:arrayData withNumSamples:BUFFER_SIZE];
	
		//overwrite ~200 MS from the front and padd with 0s for increased res.
		for(int pos = 0; pos < BUFFER_SIZE/2; pos++) {
			arrayData[pos] = 0;
		}
	
    //send off for graphing
    [self.graphHelper setGraphData:&arrayData[BUFFER_SIZE/2]
                    withDataLength:8000//BUFFER_SIZE/2 which is 8192, suppress error use 8k
                     forGraphIndex:1];
	
    // take forward FFT
		[self.fftHelper performForwardFFTWithData:arrayData
                   andCopydBMagnitudeToBuffer:fftMagnitude];
	
		//reduce error
		[self fftErrorReducer:arrayData withSizeOf:BUFFER_SIZE
								dataStart:BUFFER_SIZE/2 forFTT:fftMagnitude
								withSizeOf:BUFFER_SIZE/2];
    
    // graph the FFT Data
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
																withNpeaks:3];
	
	//[self.floatFormatter stringFromNumber:@(peakValues[0] * DELTA_FREQ)],
	
		if(!self.isLocked) {
			[self.peakValuesTextLabel setText:
			 [NSString stringWithFormat:@"%@ Hz %@ dB\n%@ Hz %@ dB",
				[self.floatFormatter stringFromNumber:@(peakValues[0] * DELTA_FREQ)],
				[self.floatFormatter stringFromNumber:@(peakValues[1])],
				[self.floatFormatter stringFromNumber:@(peakValues[2] * DELTA_FREQ)],
				[self.floatFormatter stringFromNumber:@(peakValues[3])]]];
			

			
			float f1, f2, f3;
			f1 =[SMULab2AudioUtils resolveFPeak:fftMagnitude withIndex:peakValues[0] withDeltaFreq:DELTA_FREQ];
			f2 =[SMULab2AudioUtils resolveFPeak:fftMagnitude withIndex:peakValues[2] withDeltaFreq:DELTA_FREQ];
			f3 =[SMULab2AudioUtils resolveFPeak:fftMagnitude withIndex:peakValues[4] withDeltaFreq:DELTA_FREQ];
		
			NSLog(@"\nF1:%f F2:%f F3:%f rawF3:%f\n", f1, f2, f3, peakValues[4] * DELTA_FREQ);
			
		}

    [self.graphHelper update]; // update the graph
    free(arrayData);
    free(fftMagnitude);
	
	
	if(peakValues[1] > self.thresholdSlider.value && !self.isLocked) {
			//if greater than 10 db, pause
			[self.lockButton setTitle:@"Resume" forState:UIControlStateNormal];
			self.locked = YES;
		}
	
	free(peakValues);
}

//Reduce the error of fftArray with sampleArray of the time domain
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

//  override the GLKView draw function, from OpenGLES
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
		if(!self.isLocked)
			[self.graphHelper draw]; // draw the graph
}


@end
