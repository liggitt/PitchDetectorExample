/*
 Copyright (c) Kevin P Murphy June 2012
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */


#import "PitchDetector.h"
#import <Accelerate/Accelerate.h>


@implementation PitchDetector
@synthesize lowBoundFrequency, hiBoundFrequency, sampleRate, delegate, running;

#pragma mark Initialize Methods


-(id) initWithSampleRate: (float) rate lowBoundFreq: (int) low hiBoundFreq: (int) hi andDelegate: (id<PitchDetectorDelegate>) initDelegate {
    self.lowBoundFrequency = self.targetFrequency = low;
    self.hiBoundFrequency = hi;
    self.sampleRate = rate;
    self.delegate = initDelegate;
    
    // Possible offsets we would need to try to detect the lowest (longest) frequency
    windowLength = self.sampleRate/self.lowBoundFrequency;
    
    // Number of samples needed to accomodate comparing the window and the maximum offset
    bufferLength = 2 * windowLength;
    
    hann = (float*) malloc(sizeof(float)*windowLength);
    vDSP_hann_window(hann, bufferLength, vDSP_HANN_NORM);
    
    sampleBuffer = (SInt16*) malloc(sizeof(SInt16)*bufferLength);
    samplesInSampleBuffer = 0;
    
    result = (float*) malloc(sizeof(float)*windowLength);
    
    return self;
}

#pragma  mark Insert Samples

- (void) addSamples:(SInt16 *)samples inNumberFrames:(int)frames {
    // Skip if we're waiting on a full buffer to be processed
    if (self.running)
        return;

    // Add the new samples to the end of the buffer, up to a full buffer
    int samplesToAdd = MIN(frames, bufferLength - samplesInSampleBuffer);
    memcpy(&sampleBuffer[samplesInSampleBuffer], samples, samplesToAdd*sizeof(SInt16));
    samplesInSampleBuffer += samplesToAdd;
    
    if(samplesInSampleBuffer == bufferLength) {
        self.running = YES;
        [self performSelectorInBackground:@selector(detect:) withObject:[NSNull null]];
        samplesInSampleBuffer = 0;
    } else {
        //printf("NOT ENOUGH SAMPLES: %d\n", samplesInSampleBuffer);
    }
}


#pragma mark Perform Auto Correlation

-(void) detect: (id)arg;
{
    float freq = 0;

    SInt16 *samples = sampleBuffer;
        
    int returnIndex = 0;
    float sum;
    bool goingUp = false;
    float normalize = 0;
    
    for(int i = 0; i < windowLength; i++) {
        sum = 0;
        for(int j = 0; j < windowLength; j++) {
            sum += (samples[j]*samples[j+i])*hann[j];
        }
        if(i ==0 ) normalize = sum;
        result[i] = sum/normalize;
    }
    
    for(int i = 1; i < windowLength - 1; i++) {
        if(result[i]<0) {
            i+=2; // no peaks below 0, skip forward at a faster rate
        } else {
            if(result[i]>result[i-1] && goingUp == false && i >1) {
        
                //local min at i-1
            
                goingUp = true;
            
            } else if(goingUp == true && result[i]<result[i-1]) {
                
                //local max at i-1
            
                if(returnIndex==0 && result[i-1]>result[0]*0.95) {
                    returnIndex = i-1;
                    break; 
                    //############### NOTE ##################################
                    // My implemenation breaks out of this loop when it finds the first peak.
                    // This is (probably) the greatest source of error, so if you would like to
                    // improve this algorithm, start here. the next else if() will trigger on 
                    // future local maxima (if you first take out the break; above this paragraph)
                    //#######################################################
                } else if(result[i-1]>result[0]*0.85) {
                }
                goingUp = false;
            }       
        }
    }

    freq = 0;
    if (returnIndex > 0) {
        freq =self.sampleRate/interp(result[returnIndex-1], result[returnIndex], result[returnIndex+1], returnIndex);
        if(freq < self.lowBoundFrequency || freq > self.hiBoundFrequency) {
            freq = 0;
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate updatedPitch:freq];
    });

    self.running = NO;
}


float interp(float y1, float y2, float y3, int k);
float interp(float y1, float y2, float y3, int k) {
    
    float d, kp;
    d = (y3 - y1) / (2 * (2 * y2 - y1 - y3));
    //printf("%f = %d + %f\n", k+d, k, d);
    kp  =  k + d;
    return kp;
}
@end

