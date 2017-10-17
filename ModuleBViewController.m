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

#import "ModuleBViewController.h"
#import "Novocaine.h"
#import "CircularBuffer.h"
#import "SMUGraphHelper.h"
#import "FFTHelper.h"
#import "SMULab2AudioUtils.h"


#define BUFFER_SIZE 8192
#define WINDOW_SIZE 50.0 //in Hz

@interface ModuleBViewController ()

@property (nonatomic) float frequency;
@property (nonatomic) int debounceAway; //decaying flag for away label
@property (nonatomic) int debounceToward; //decaying flag for toward label
@property (weak, nonatomic) IBOutlet UILabel *freqLabel;
@property (strong, nonatomic) Novocaine* audioManager;
@property (nonatomic) float phaseIncrement;
@property (strong, nonatomic) CircularBuffer *buffer;
@property (strong, nonatomic) SMUGraphHelper *graphHelper;
@property (strong, nonatomic) FFTHelper *fftHelper;
@property (weak, nonatomic) IBOutlet UILabel *movementLabel;

@end


@implementation ModuleBViewController

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

- (void)viewDidLoad { //Seed code by Dr. Larson
    [super viewDidLoad];
	
		self.debounceAway = 0;
		self.debounceToward = 0;
	  [self updateFrequencyInKhz:17]; //start at 17 Khz
    self.phaseIncrement = 2*M_PI*self.frequency/self.audioManager.samplingRate;
	
    __block float phase = 0.0;
    [self.audioManager setOutputBlock:^(float* data, UInt32 numFrames, UInt32 numChannels){
        for(int i=0;i<numFrames;i++){
            for(int j=0;j<numChannels;j++){
                data[i*numChannels+j] = sin(phase);
            }
            phase += self.phaseIncrement;
	
            if(phase>2*M_PI){
                phase -= 2*M_PI;
            }
        }
    }];
	
		[self.graphHelper setFullScreenBounds];
	
		__block ModuleBViewController * __weak  weakSelf = self;
		[self.audioManager setInputBlock:^(float *data, UInt32 numFrames, UInt32 numChannels){
			[weakSelf.buffer addNewFloatData:data withNumSamples:numFrames];
		}];
	
    [self.audioManager play];
}

- (void) viewDidDisappear: (BOOL)animated {
	[super viewDidDisappear:animated];
	[self.audioManager pause];
	[self.audioManager setOutputBlock: nil]; //stop outpout when in another module using audioManager
}

//Slider has changed action
- (IBAction)frequencyChanged:(UISlider *)sender {
    [self updateFrequencyInKhz:sender.value];
    
}

///Updates the Frequency and phaseIncrement
-(void)updateFrequencyInKhz:(float) freqInKHz {
    self.frequency = freqInKHz*1000.0;
    self.freqLabel.text = [NSString stringWithFormat:@"%.4f kHz",freqInKHz];
    self.phaseIncrement = 2*M_PI*self.frequency/self.audioManager.samplingRate;
}

#pragma mark GLK Inherited Functions
///  override the GLKViewController update function, from OpenGLES - Seed code Dr. Larson
- (void)update{
	
	// get audio stream data
	float* arrayData = malloc(sizeof(float) * BUFFER_SIZE);
	float* fftMagnitude = malloc(sizeof(float) * BUFFER_SIZE/2);
	
	//create returnBuffer for peakValue aquisition
	float* peakValues = malloc(sizeof(float)*6);
	
	[self.buffer fetchFreshData:arrayData withNumSamples:BUFFER_SIZE];
	
	//precision is cut off
	float deltaFreq = 44100.0/BUFFER_SIZE; // Fs/N = dF
	int zoomHalfLength = 400/deltaFreq;
	int zoomStart = self.frequency/deltaFreq - zoomHalfLength;
	
	// take forward FFT
	[self.fftHelper performForwardFFTWithData:arrayData
								 andCopydBMagnitudeToBuffer:fftMagnitude];
	
	[SMULab2AudioUtils detectHightestTones: &fftMagnitude[zoomStart]
																 withSizeOf:zoomHalfLength * 2
														 withWindowSize:50
															 andDeltaFreq:deltaFreq
												placeInResultBuffer:peakValues
															   withNpeaks:3];


	NSLog(@"%fHz %fdB; %fHz %fdB; %fHz %fdB", (peakValues[0] + zoomStart) * deltaFreq, peakValues[1],
				(peakValues[2] + zoomStart) * deltaFreq, peakValues[3],
				(peakValues[4] + zoomStart) * deltaFreq, peakValues[5]);
	
	float dbThresholdToward = -30.0;
	float dbThresholdAway = -35.0;

	if(peakValues[3] > dbThresholdToward && peakValues[2] > peakValues[0]) {
		self.debounceToward = 5;
	}
	
	if(peakValues[5] > dbThresholdToward && peakValues[4] > peakValues[0]) {
		self.debounceToward = 5;
	}
	
	if(peakValues[3] > dbThresholdAway && peakValues[2] < peakValues[0]) {
		self.debounceAway = 5;
	}
	
	if(peakValues[5] > dbThresholdAway && peakValues[4] < peakValues[0]) {
		self.debounceAway = 5;
	}
	
	// Smoothing, check to see if any flags have decayed and update label
	if(self.debounceToward > 0 && self.debounceAway > 0) {
		[self.movementLabel setText:@"Toward and Away"];
	} else if(self.debounceAway > 0) {
		[self.movementLabel setText:@"Away"];
	} else if(self.debounceToward > 0) {
		[self.movementLabel setText:@"Toward"];
	} else {
		[self.movementLabel setText:@"No Movement"];
	}
	
	// graph the FFT Data
	[self.graphHelper setGraphData:fftMagnitude
									withDataLength:BUFFER_SIZE/2
									 forGraphIndex:0
							 withNormalization:64.0
									 withZeroValue:-60];
	
	// graph the FFT Data
	[self.graphHelper setGraphData:&fftMagnitude[zoomStart]
									withDataLength:zoomHalfLength * 2
									 forGraphIndex:1
							 withNormalization:64.0
									 withZeroValue:-60];
	
	[self.graphHelper update]; // update the graph
	free(arrayData);
	free(fftMagnitude);
	free(peakValues);
	
	//decrement debounce vars
	self.debounceToward--;
	self.debounceAway--;
}


//  override the GLKView draw function, from OpenGLES
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
		[self.graphHelper draw]; // draw the graph
}



@end
