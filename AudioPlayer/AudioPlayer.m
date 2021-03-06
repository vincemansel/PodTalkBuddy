/**********************************************************************************
 AudioPlayer.m
 
 Developed by Vince Mansel
 
 Inspired by Thong Nguyen's adjustable
 https://github.com/tumtumtum/audjustable
 
 Inspired by Matt Gallagher's AudioStreamer:
 https://github.com/mattgallagher/AudioStreamer
 
 Copyright (c) 2012 Thong Nguyen (tumtumtum@gmail.com). All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 3. All advertising materials mentioning features or use of this software
 must display the following acknowledgement:
 This product includes software developed by the <organization>.
 4. Neither the name of the <organization> nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY <COPYRIGHT HOLDER> ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **********************************************************************************/

#import "AudioPlayer.h"
#import "AudioToolbox/AudioToolbox.h"
#import "HttpDataSource.h"
#import "LocalFileDataSource.h"
#import "libkern/OSAtomic.h"

#define BitRateEstimationMinPackets (64)
#define AudioPlayerBuffersNeededToStart (16)
#define AudioPlayerDefaultReadBufferSize (32 * 1024)
#define AudioPlayerDefaultPacketBufferSize (1024)

#define OSSTATUS_PARAM_ERROR (-50)

#define SPIN_LOCK_LOCK(x) \
	while(OSAtomicCompareAndSwapInt(0, 1, x) == false);

#define SPIN_LOCK_UNLOCK(x) \
	*x = 0;

@interface NSMutableArray(AudioPlayerExtensions)
-(void) enqueue:(id)obj;
-(id) dequeue;
-(id) peek;
@end

@implementation NSMutableArray(AudioPlayerExtensions)

-(void) enqueue:(id)obj
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);

    [self insertObject:obj atIndex:0];
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

}

-(void) skipQueue:(id)obj
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);

    [self addObject:obj];
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

}

-(id) dequeue
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);

    if ([self count] == 0)
    {
        return nil;
    }
    
    id retval = [self lastObject];
    
    [self removeLastObject];
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

    return retval;
}

-(id) peek
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

    return [self lastObject];
}

-(id) peekRecent
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

    if (self.count == 0)
    {
        return nil;
    }
    
    return [self objectAtIndex:0];
}

@end

@interface QueueEntry : NSObject
{
@public
    BOOL parsedHeader;
    double sampleRate;
    double lastProgress;
    double packetDuration;
    UInt64 audioDataOffset;
    UInt64 audioDataByteCount;
    UInt32 packetBufferSize;
    volatile double seekTime;
    volatile int bytesPlayed;
    volatile int processedPacketsCount;
	volatile int processedPacketsSizeTotal;
    AudioStreamBasicDescription audioStreamBasicDescription;
}
@property (readwrite, retain) NSObject* queueItemId;
@property (readwrite, retain) DataSource* dataSource;
@property (readwrite) int bufferIndex;
@property (readonly) UInt64 audioDataLengthInBytes;

-(double) duration;
-(double) calculatedBitRate;
-(double) progress;

-(id) initWithDataSource:(DataSource*)dataSource andQueueItemId:(NSObject*)queueItemId;
-(id) initWithDataSource:(DataSource*)dataSource andQueueItemId:(NSObject*)queueItemId andBufferIndex:(int)bufferIndex;

@end

@implementation QueueEntry
@synthesize dataSource, queueItemId, bufferIndex;

-(id) initWithDataSource:(DataSource*)dataSourceIn andQueueItemId:(NSObject*)queueItemIdIn
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

    return [self initWithDataSource:dataSourceIn andQueueItemId:queueItemIdIn andBufferIndex:-1];
}

-(id) initWithDataSource:(DataSource*)dataSourceIn andQueueItemId:(NSObject*)queueItemIdIn andBufferIndex:(int)bufferIndexIn
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);

    if (self = [super init])
    {
        self.dataSource = dataSourceIn;
        self.queueItemId = queueItemIdIn;
        self.bufferIndex = bufferIndexIn;
    }
    
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);

    return self;
}

-(double) calculatedBitRate
{
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

    double retval;
    
    if (packetDuration && processedPacketsCount > BitRateEstimationMinPackets)
	{
		double averagePacketByteSize = processedPacketsSizeTotal / processedPacketsCount;
        
		retval = averagePacketByteSize / packetDuration * 8;
        
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

        return retval;
	}
	
    retval = (audioStreamBasicDescription.mBytesPerFrame * audioStreamBasicDescription.mSampleRate) * 8;
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

    return retval;
}

-(void) updateAudioDataSource
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);

    if ([self->dataSource conformsToProtocol:@protocol(AudioDataSource)])
    {
        double calculatedBitrate = [self calculatedBitRate];
        
        id<AudioDataSource> audioDataSource = (id<AudioDataSource>)self->dataSource;
        
        audioDataSource.averageBitRate = calculatedBitrate;
        audioDataSource.audioDataOffset = audioDataOffset;
    }
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

}

-(double) progress
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);

    double retval = lastProgress;
    double duration = [self duration];
    
    if (self->sampleRate > 0)
    {
        double calculatedBitrate = [self calculatedBitRate];
        
        retval = self->bytesPlayed / calculatedBitrate * 8;
        
        retval = seekTime + retval;
        
        [self updateAudioDataSource];
    }
    
    if (retval > duration)
    {
        retval = duration;
    }
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

	return retval;
}

-(double) duration
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);

    if (self->sampleRate <= 0)
    {
        return 0;
    }
    
    UInt64 audioDataLengthInBytes = [self audioDataLengthInBytes];
    
    double calculatedBitRate = [self calculatedBitRate];
    
    if (calculatedBitRate == 0 || self->dataSource.length == 0)
    {
        NSLog(@"OUT: %s = 0", __PRETTY_FUNCTION__);

        return 0;
    }
    
    NSLog(@"OUT: %s = %f ", __PRETTY_FUNCTION__, audioDataLengthInBytes / (calculatedBitRate / 8));

    
    return audioDataLengthInBytes / (calculatedBitRate / 8);
}

-(UInt64) audioDataLengthInBytes
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    
    if (audioDataByteCount)
    {
        return audioDataByteCount;
    }
    else
    {
        if (!dataSource.length)
        {
            NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
            return 0;
        }
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        
        return dataSource.length - audioDataOffset;
    }
}

-(NSString*) description
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    return [[self queueItemId] description];
}

@end

@interface AudioPlayer()
@property (readwrite) AudioPlayerInternalState internalState;

-(void) processQueue:(BOOL)skipCurrent;
-(void) createAudioQueue;
-(void) enqueueBuffer;
-(void) resetAudioQueue;
-(BOOL) startAudioQueue;
-(void) stopAudioQueue;
-(BOOL) processRunloop;
-(void) wakeupPlaybackThread;
-(void) audioQueueFinishedPlaying:(QueueEntry*)entry;
-(void) processSeekToTime;
-(void) didEncounterError:(AudioPlayerErrorCode)errorCode;
-(void) setInternalState:(AudioPlayerInternalState)value;
-(void) processDidFinishPlaying:(QueueEntry*)entry withNext:(QueueEntry*)next;
-(void) handlePropertyChangeForFileStream:(AudioFileStreamID)audioFileStreamIn fileStreamPropertyID:(AudioFileStreamPropertyID)propertyID ioFlags:(UInt32*)ioFlags;
-(void) handleAudioPackets:(const void*)inputData numberBytes:(UInt32)numberBytes numberPackets:(UInt32)numberPackets packetDescriptions:(AudioStreamPacketDescription*)packetDescriptions;
-(void) handleAudioQueueOutput:(AudioQueueRef)audioQueue buffer:(AudioQueueBufferRef)buffer;
-(void) handlePropertyChangeForQueue:(AudioQueueRef)audioQueue propertyID:(AudioQueuePropertyID)propertyID;
@end

static void AudioFileStreamPropertyListenerProc(void* clientData, AudioFileStreamID audioFileStream, AudioFileStreamPropertyID	propertyId, UInt32* flags)
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	AudioPlayer* player = (__bridge AudioPlayer*)clientData;
    
	[player handlePropertyChangeForFileStream:audioFileStream fileStreamPropertyID:propertyId ioFlags:flags];
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

static void AudioFileStreamPacketsProc(void* clientData, UInt32 numberBytes, UInt32 numberPackets, const void* inputData, AudioStreamPacketDescription* packetDescriptions)
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	AudioPlayer* player = (__bridge AudioPlayer*)clientData;
    
	[player handleAudioPackets:inputData numberBytes:numberBytes numberPackets:numberPackets packetDescriptions:packetDescriptions];
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

static void AudioQueueOutputCallbackProc(void* clientData, AudioQueueRef audioQueue, AudioQueueBufferRef buffer)
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	AudioPlayer* player = (__bridge AudioPlayer*)clientData;
    
	[player handleAudioQueueOutput:audioQueue buffer:buffer];
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

static void AudioQueueIsRunningCallbackProc(void* userData, AudioQueueRef audioQueue, AudioQueuePropertyID propertyId)
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	AudioPlayer* player = (__bridge AudioPlayer*)userData;
    
	[player handlePropertyChangeForQueue:audioQueue propertyID:propertyId];
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

@implementation AudioPlayer
@synthesize delegate, internalState, state;

-(AudioQueueRef)audioQueueRef
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    return audioQueue;
}

-(AudioPlayerInternalState) internalState
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    return internalState;
}

-(void) setInternalState:(AudioPlayerInternalState)value
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    if (value == internalState)
    {
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        return;
    }
    
    internalState = value;
    
    if ([self.delegate respondsToSelector:@selector(internalStateChanged:)])
    {
        dispatch_async(dispatch_get_main_queue(), ^
                       {
                           NSLog(@"GCD IN: %s", __PRETTY_FUNCTION__);
                           [self.delegate audioPlayer:self internalStateChanged:internalState];
                           NSLog(@"GCD OUT: %s", __PRETTY_FUNCTION__);
                       });
    }
    
    AudioPlayerState newState;
    
    switch (internalState)
    {
        case AudioPlayerInternalStateInitialised:
            newState = AudioPlayerStateReady;
            break;
        case AudioPlayerInternalStateRunning:
        case AudioPlayerInternalStateStartingThread:
        case AudioPlayerInternalStateWaitingForData:
        case AudioPlayerInternalStateWaitingForQueueToStart:
        case AudioPlayerInternalStatePlaying:
            newState = AudioPlayerStatePlaying;
            break;
        case AudioPlayerInternalStateStopping:
        case AudioPlayerInternalStateStopped:
            newState = AudioPlayerStateStopped;
            break;
        case AudioPlayerInternalStatePaused:
            newState = AudioPlayerStatePaused;
            break;
        case AudioPlayerInternalStateDisposed:
            newState = AudioPlayerStateDisposed;
            break;
        case AudioPlayerInternalStateError:
            newState = AudioPlayerStateError;
            break;
    }
    
    if (newState != self.state)
    {
        self.state = newState;
        
        dispatch_async(dispatch_get_main_queue(), ^
                       {
                           NSLog(@"GCD IN: %s", __PRETTY_FUNCTION__);
                           [self.delegate audioPlayer:self stateChanged:self.state];
                           NSLog(@"GCD OUT: %s", __PRETTY_FUNCTION__);
                       });
    }
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(AudioPlayerStopReason) stopReason
{
    return stopReason;
}

-(BOOL) audioQueueIsRunning
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    UInt32 isRunning;
    UInt32 isRunningSize = sizeof(isRunning);
    
    AudioQueueGetProperty(audioQueue, kAudioQueueProperty_IsRunning, &isRunning, &isRunningSize);
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    return isRunning ? YES : NO;
}

-(id) init
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    return [self initWithNumberOfAudioQueueBuffers:AudioPlayerDefaultNumberOfAudioQueueBuffers andReadBufferSize:AudioPlayerDefaultReadBufferSize];
}

-(id) initWithNumberOfAudioQueueBuffers:(int)numberOfAudioQueueBuffers andReadBufferSize:(int)readBufferSizeIn
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    if (self = [super init])
    {
        fastApiQueue = [[NSOperationQueue alloc] init];
        [fastApiQueue setMaxConcurrentOperationCount:1];

        readBufferSize = readBufferSizeIn;
        readBuffer = calloc(sizeof(UInt8), readBufferSize);
        
        audioQueueBufferCount = numberOfAudioQueueBuffers;
        audioQueueBuffer = calloc(sizeof(AudioQueueBufferRef), audioQueueBufferCount);
        
        audioQueueBufferRefLookupCount = audioQueueBufferCount * 2;
        audioQueueBufferLookup = calloc(sizeof(AudioQueueBufferRefLookupEntry), audioQueueBufferRefLookupCount);
        
        packetDescs = calloc(sizeof(AudioStreamPacketDescription), audioQueueBufferCount);
        bufferUsed = calloc(sizeof(bool), audioQueueBufferCount);
        
        pthread_mutexattr_t attr;
        
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
        int err;
        
        err = pthread_mutex_init(&playerMutex, &attr);
        err = pthread_mutex_init(&queueBuffersMutex, NULL);
        err = pthread_cond_init(&queueBufferReadyCondition, NULL);
        
        threadFinishedCondLock = [[NSConditionLock alloc] initWithCondition:0];
        
        self.internalState = AudioPlayerInternalStateInitialised;
        
        upcomingQueue = [[NSMutableArray alloc] init];
        bufferingQueue = [[NSMutableArray alloc] init];
    }
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    return self;
}

-(void) dealloc
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    if (currentlyReadingEntry)
    {
        currentlyReadingEntry.dataSource.delegate = nil;
    }
    
    if (currentlyPlayingEntry)
    {
        currentlyPlayingEntry.dataSource.delegate = nil;
    }
    
    pthread_mutex_destroy(&playerMutex);
    pthread_mutex_destroy(&queueBuffersMutex);
    pthread_cond_destroy(&queueBufferReadyCondition);
    
    if (audioFileStream)
    {
        AudioFileStreamClose(audioFileStream);
    }
    
    if (audioQueue)
    {
        AudioQueueDispose(audioQueue, true);
    }
    
    free(bufferUsed);
    free(readBuffer);
    free(packetDescs);
    free(audioQueueBuffer);
    free(audioQueueBufferLookup);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) startSystemBackgroundTask
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	pthread_mutex_lock(&playerMutex);
	{
		if (backgroundTaskId != UIBackgroundTaskInvalid)
		{
            pthread_mutex_unlock(&playerMutex);
            
			return;
		}
		
		backgroundTaskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^
                            {
                                [self stopSystemBackgroundTask];
                            }];
	}
    pthread_mutex_unlock(&playerMutex);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) stopSystemBackgroundTask
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	pthread_mutex_lock(&playerMutex);
	{
		if (backgroundTaskId != UIBackgroundTaskInvalid)
		{
			[[UIApplication sharedApplication] endBackgroundTask:backgroundTaskId];
			
			backgroundTaskId = UIBackgroundTaskInvalid;
		}
	}
    pthread_mutex_unlock(&playerMutex);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(DataSource*) dataSourceFromURL:(NSURL*)url
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    DataSource* retval;
    
    if ([url.scheme isEqualToString:@"file"])
    {
        retval = [[LocalFileDataSource alloc] initWithFilePath:url.path];
    }
    else
    {
        retval = [[HttpDataSource alloc] initWithURL:url];
    }
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    
    return retval;
}

-(void) clearQueue
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    pthread_mutex_lock(&playerMutex);
    {
        NSMutableArray* array = [[NSMutableArray alloc] initWithCapacity:bufferingQueue.count + upcomingQueue.count];
        
        QueueEntry* entry = [bufferingQueue dequeue];
        
        if (entry && entry != currentlyPlayingEntry)
        {
            [array addObject:[entry queueItemId]];
        }
        
        while (bufferingQueue.count > 0)
        {
            [array addObject:[[bufferingQueue dequeue] queueItemId]];
        }
        
        for (QueueEntry* entry in upcomingQueue)
        {
            [array addObject:entry.queueItemId];
        }
        
        [upcomingQueue removeAllObjects];
        
        dispatch_async(dispatch_get_main_queue(), ^
        {
            NSLog(@"GCD IN: %s", __PRETTY_FUNCTION__);
            if ([self.delegate respondsToSelector:@selector(audioPlayer:didCancelQueuedItems:)])
            {
                [self.delegate audioPlayer:self didCancelQueuedItems:array];
            }
            NSLog(@"GCD OUT: %s", __PRETTY_FUNCTION__);
        });
    }
    pthread_mutex_unlock(&playerMutex);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) play:(NSURL*)url
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	[self setDataSource:[self dataSourceFromURL:url] withQueueItemId:url];
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) setDataSource:(DataSource*)dataSourceIn withQueueItemId:(NSObject*)queueItemId
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    [fastApiQueue cancelAllOperations];
    
	[fastApiQueue addOperationWithBlock:^
    {
        pthread_mutex_lock(&playerMutex);
        {
            [self startSystemBackgroundTask];

            [self clearQueue];

            [upcomingQueue enqueue:[[QueueEntry alloc] initWithDataSource:dataSourceIn andQueueItemId:queueItemId]];

            self.internalState = AudioPlayerInternalStateRunning;
            [self processQueue:YES];
        }
        pthread_mutex_unlock(&playerMutex);
    }];
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) queueDataSource:(DataSource*)dataSourceIn withQueueItemId:(NSObject*)queueItemId
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	[fastApiQueue addOperationWithBlock:^
    {
        pthread_mutex_lock(&playerMutex);
        {
            [upcomingQueue enqueue:[[QueueEntry alloc] initWithDataSource:dataSourceIn andQueueItemId:queueItemId]];

            [self processQueue:NO];
        }
        pthread_mutex_unlock(&playerMutex);
    }];
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) handlePropertyChangeForFileStream:(AudioFileStreamID)inAudioFileStream fileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID ioFlags:(UInt32*)ioFlags
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	OSStatus error;
    
    switch (inPropertyID)
    {
        case kAudioFileStreamProperty_DataOffset:
        {
            SInt64 offset;
            UInt32 offsetSize = sizeof(offset);
            
            AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_DataOffset, &offsetSize, &offset);
            
            currentlyReadingEntry->parsedHeader = YES;
            currentlyReadingEntry->audioDataOffset = offset;
            
            [currentlyReadingEntry updateAudioDataSource];
        }
            break;
        case kAudioFileStreamProperty_DataFormat:
        {
            AudioStreamBasicDescription newBasicDescription;
            UInt32 size = sizeof(newBasicDescription);
            
            AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &size, &newBasicDescription);
            
            currentlyReadingEntry->audioStreamBasicDescription = newBasicDescription;
            
            currentlyReadingEntry->sampleRate = currentlyReadingEntry->audioStreamBasicDescription.mSampleRate;
            currentlyReadingEntry->packetDuration = currentlyReadingEntry->audioStreamBasicDescription.mFramesPerPacket / currentlyReadingEntry->sampleRate;
            
            UInt32 packetBufferSize = 0;
            UInt32 sizeOfPacketBufferSize = sizeof(packetBufferSize);
            
            error = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfPacketBufferSize, &packetBufferSize);
            
            if (error || packetBufferSize == 0)
            {
                error = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfPacketBufferSize, &packetBufferSize);
                
                if (error || packetBufferSize == 0)
                {
                    currentlyReadingEntry->packetBufferSize = AudioPlayerDefaultPacketBufferSize;
                }
            }
            
            [currentlyReadingEntry updateAudioDataSource];
            
            AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1);
        }
            break;
        case kAudioFileStreamProperty_AudioDataByteCount:
        {
            UInt64 audioDataByteCount;
            UInt32 byteCountSize = sizeof(audioDataByteCount);
            
            AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_AudioDataByteCount, &byteCountSize, &audioDataByteCount);
            
            currentlyReadingEntry->audioDataByteCount = audioDataByteCount;
            
            [currentlyReadingEntry updateAudioDataSource];
        }
            break;
		case kAudioFileStreamProperty_ReadyToProducePackets:
        {
            discontinuous = YES;
        }
            break;
    }
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) handleAudioPackets:(const void*)inputData numberBytes:(UInt32)numberBytes numberPackets:(UInt32)numberPackets packetDescriptions:(AudioStreamPacketDescription*)packetDescriptionsIn
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    
    if (currentlyReadingEntry == nil)
    {
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

        return;
    }
    
    if (seekToTimeWasRequested)
    {
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

        return;
    }
    
	if (audioQueue == nil || memcmp(&currentAudioStreamBasicDescription, &currentlyReadingEntry->audioStreamBasicDescription, sizeof(currentAudioStreamBasicDescription)) != 0)
    {
        [self createAudioQueue];
    }
    
    if (discontinuous)
    {
        discontinuous = NO;
    }
    
    if (packetDescriptionsIn)
    {
        // VBR
        
        for (int i = 0; i < numberPackets; i++)
        {
            SInt64 packetOffset = packetDescriptionsIn[i].mStartOffset;
            SInt64 packetSize = packetDescriptionsIn[i].mDataByteSize;
            int bufSpaceRemaining;
            
            if (currentlyReadingEntry->processedPacketsSizeTotal < 0xfffff)
            {
                OSAtomicAdd32(packetSize, &currentlyReadingEntry->processedPacketsSizeTotal);
                OSAtomicIncrement32(&currentlyReadingEntry->processedPacketsCount);
            }
            
            if (packetSize > currentlyReadingEntry->packetBufferSize)
            {
                NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

                return;
            }
            
            bufSpaceRemaining = currentlyReadingEntry->packetBufferSize - bytesFilled;
            
            if (bufSpaceRemaining < packetSize)
            {
                [self enqueueBuffer];
                
                if (seekToTimeWasRequested || self.internalState == AudioPlayerInternalStateStopped || self.internalState == AudioPlayerInternalStateStopping || self.internalState == AudioPlayerInternalStateDisposed)
                {
                    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

                    return;
                }
            }
            
            if (bytesFilled + packetSize > currentlyReadingEntry->packetBufferSize)
            {
                NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

                return;
            }
            
            AudioQueueBufferRef bufferToFill = audioQueueBuffer[fillBufferIndex];
            memcpy((char*)bufferToFill->mAudioData + bytesFilled, (const char*)inputData + packetOffset, packetSize);
            
            packetDescs[packetsFilled] = packetDescriptionsIn[i];
            packetDescs[packetsFilled].mStartOffset = bytesFilled;
            
            bytesFilled += packetSize;
            packetsFilled++;
            
            int packetsDescRemaining = audioQueueBufferCount - packetsFilled;
            
            if (packetsDescRemaining <= 0)
            {
                [self enqueueBuffer];
                
                if (seekToTimeWasRequested || self.internalState == AudioPlayerInternalStateStopped || self.internalState == AudioPlayerInternalStateStopping || self.internalState == AudioPlayerInternalStateDisposed)
                {
                    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

                    return;
                }
            }
        }
    }
    else
    {
        // CBR
        
    	int offset = 0;
        
		while (numberBytes)
		{
			int bytesLeft = AudioPlayerDefaultPacketBufferSize - bytesFilled;
            
			if (bytesLeft < numberBytes)
			{
				[self enqueueBuffer];
                
                if (seekToTimeWasRequested || self.internalState == AudioPlayerInternalStateStopped || self.internalState == AudioPlayerInternalStateStopping || self.internalState == AudioPlayerInternalStateDisposed)
                {
                    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

                    return;
                }
			}
			
			pthread_mutex_lock(&playerMutex);
			{
				int copySize;
				bytesLeft = AudioPlayerDefaultPacketBufferSize - bytesFilled;
                
				if (bytesLeft < numberBytes)
				{
					copySize = bytesLeft;
				}
				else
				{
					copySize = numberBytes;
				}
                
				if (bytesFilled > currentlyPlayingEntry->packetBufferSize)
				{
                    pthread_mutex_unlock(&playerMutex);
                    
                    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

					return;
				}
				
				AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
				memcpy((char*)fillBuf->mAudioData + bytesFilled, (const char*)(inputData + offset), copySize);
                
				bytesFilled += copySize;
				packetsFilled = 0;
				numberBytes -= copySize;
				offset += copySize;
			}
            pthread_mutex_unlock(&playerMutex);
		}
    }
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

}

-(void) handleAudioQueueOutput:(AudioQueueRef)audioQueueIn buffer:(AudioQueueBufferRef)bufferIn
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    
    int bufferIndex = -1;
    
    if (audioQueueIn != audioQueue)
    {
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

        return;
    }
    
    if (currentlyPlayingEntry)
    {
        if (!audioQueueFlushing)
        {
            currentlyPlayingEntry->bytesPlayed += bufferIn->mAudioDataByteSize;
        }
    }
    
    int index = (int)bufferIn % audioQueueBufferRefLookupCount;
    
    for (int i = 0; i < audioQueueBufferCount; i++)
    {
        if (audioQueueBufferLookup[index].ref == bufferIn)
        {
            bufferIndex = audioQueueBufferLookup[index].bufferIndex;
            
            break;
        }
        
        index = (index + 1) % audioQueueBufferRefLookupCount;
    }
    
    audioPacketsPlayedCount++;
	
	if (bufferIndex == -1)
	{
		[self didEncounterError:AudioPlayerErrorUnknownBuffer];
        
		pthread_mutex_lock(&queueBuffersMutex);
		pthread_cond_signal(&queueBufferReadyCondition);
		pthread_mutex_unlock(&queueBuffersMutex);
        
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

		return;
	}
	
    pthread_mutex_lock(&queueBuffersMutex);
    
    BOOL signal = NO;
    
    if (bufferUsed[bufferIndex])
    {
        bufferUsed[bufferIndex] = false;
        numberOfBuffersUsed--;
    }
    else
    {
        // This should never happen
        
        signal = YES;
    }
    
    if (!audioQueueFlushing)
    {
        QueueEntry* entry = currentlyPlayingEntry;
        
        if (entry != nil)
        {
            if (entry.bufferIndex <= audioPacketsPlayedCount && entry.bufferIndex != -1)
            {
                entry.bufferIndex = -1;
                
                if (playbackThread)
                {
                    CFRunLoopPerformBlock([playbackThreadRunLoop getCFRunLoop], NSDefaultRunLoopMode, ^
                    {
                        [self audioQueueFinishedPlaying:entry];
                    });
                    
                    CFRunLoopWakeUp([playbackThreadRunLoop getCFRunLoop]);
                    
                    signal = YES;
                }
            }
        }
    }

    if (self.internalState == AudioPlayerInternalStateStopped
        || self.internalState == AudioPlayerInternalStateStopping
        || self.internalState == AudioPlayerInternalStateDisposed
        || self.internalState == AudioPlayerInternalStateError
        || self.internalState == AudioPlayerInternalStateWaitingForQueueToStart)
    {
        signal = waiting || numberOfBuffersUsed < 8;
    }
    else if (audioQueueFlushing)
    {
        signal = signal || (audioQueueFlushing && numberOfBuffersUsed < 8);
    }
    else
    {
        if (seekToTimeWasRequested)
        {
            signal = YES;
        }
        else
        {
            if ((waiting && numberOfBuffersUsed < audioQueueBufferCount / 2) || (numberOfBuffersUsed < 8))
            {
                signal = YES;
            }
        }
    }
    
    if (signal)
    {
        pthread_cond_signal(&queueBufferReadyCondition);
    }
    
    pthread_mutex_unlock(&queueBuffersMutex);
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

}

-(void) handlePropertyChangeForQueue:(AudioQueueRef)audioQueueIn propertyID:(AudioQueuePropertyID)propertyId
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    
    if (audioQueueIn != audioQueue)
    {
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        return;
    }
    
    if (propertyId == kAudioQueueProperty_IsRunning)
    {
        if (![self audioQueueIsRunning] && self.internalState == AudioPlayerInternalStateStopping)
        {
            self.internalState = AudioPlayerInternalStateStopped;
        }
        else if (self.internalState == AudioPlayerInternalStateWaitingForQueueToStart)
        {
            [NSRunLoop currentRunLoop];
            
            self.internalState = AudioPlayerInternalStatePlaying;
            [[NSNotificationCenter defaultCenter] postNotificationName: @"playbackQueueResumed" object: nil];

        }
        else if (self.internalState == AudioPlayerInternalStateStopped)
        {
            
        }
    }
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) enqueueBuffer
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    pthread_mutex_lock(&playerMutex);
    {
		OSStatus error;
        
        if (audioFileStream == 0)
        {
            pthread_mutex_unlock(&playerMutex);
            
            NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

            return;
        }
        
        if (self.internalState == AudioPlayerInternalStateStopped)
        {
            pthread_mutex_unlock(&playerMutex);
            
            NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

            return;
        }
        
        if (audioQueueFlushing || newFileToPlay)
        {
            pthread_mutex_unlock(&playerMutex);
            
            NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

            return;
        }
        
        pthread_mutex_lock(&queueBuffersMutex);
        
        bufferUsed[fillBufferIndex] = true;
        numberOfBuffersUsed++;
        
        pthread_mutex_unlock(&queueBuffersMutex);
        
        AudioQueueBufferRef buffer = audioQueueBuffer[fillBufferIndex];
        
        buffer->mAudioDataByteSize = bytesFilled;
        
        if (packetsFilled)
        {
            error = AudioQueueEnqueueBuffer(audioQueue, buffer, packetsFilled, packetDescs);
        }
        else
        {
            error = AudioQueueEnqueueBuffer(audioQueue, buffer, 0, NULL);
        }
        
        audioPacketsReadCount++;
        
        if (error)
        {
            pthread_mutex_unlock(&playerMutex);
            
            NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

            return;
        }
        
        if (self.internalState == AudioPlayerInternalStateWaitingForData && numberOfBuffersUsed >= AudioPlayerBuffersNeededToStart)
        {
            if (![self startAudioQueue])
            {
                pthread_mutex_unlock(&playerMutex);
                
                NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

                return;
            }
        }
        
        if (++fillBufferIndex >= audioQueueBufferCount)
        {
            fillBufferIndex = 0;
        }
        
        bytesFilled = 0;
        packetsFilled = 0;
    }
    pthread_mutex_unlock(&playerMutex);
    
    pthread_mutex_lock(&queueBuffersMutex);

    waiting = YES;
    
    while (bufferUsed[fillBufferIndex] && !(seekToTimeWasRequested || self.internalState == AudioPlayerInternalStateStopped || self.internalState == AudioPlayerInternalStateStopping || self.internalState == AudioPlayerInternalStateDisposed))
    {
        if (numberOfBuffersUsed == 0)
        {
            memset(&bufferUsed[0], 0, sizeof(bool) * audioQueueBufferCount);
            
            break;
        }
        
        pthread_cond_wait(&queueBufferReadyCondition, &queueBuffersMutex);
    }
    
    waiting = NO;
    
    pthread_mutex_unlock(&queueBuffersMutex);
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

}

-(void) didEncounterError:(AudioPlayerErrorCode)errorCodeIn
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    errorCode = errorCodeIn;
    self.internalState = AudioPlayerInternalStateError;
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

}

-(void) createAudioQueue
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	OSStatus error;
	
	[self startSystemBackgroundTask];
	
    if (audioQueue)
    {
        error = AudioQueueStop(audioQueue, YES);
        error = AudioQueueDispose(audioQueue, YES);
        
        audioQueue = nil;
    }
    
    currentAudioStreamBasicDescription = currentlyPlayingEntry->audioStreamBasicDescription;
    
    error = AudioQueueNewOutput(&currentlyPlayingEntry->audioStreamBasicDescription, AudioQueueOutputCallbackProc, (__bridge void*)self, NULL, NULL, 0, &audioQueue);
    
    if (error)
    {
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

        return;
    }
    
    error = AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, AudioQueueIsRunningCallbackProc, (__bridge void*)self);
    
    if (error)
    {
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        return;
    }
    
#if TARGET_OS_IPHONE
    UInt32 val = kAudioQueueHardwareCodecPolicy_PreferHardware;
    
    error = AudioQueueSetProperty(audioQueue, kAudioQueueProperty_HardwareCodecPolicy, &val, sizeof(UInt32));
    
    AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1);
    
    if (error)
    {
    }
#endif
    
    memset(audioQueueBufferLookup, 0, sizeof(AudioQueueBufferRefLookupEntry) * audioQueueBufferRefLookupCount);
    
    // Allocate AudioQueue buffers
    
    for (int i = 0; i < audioQueueBufferCount; i++)
    {
        error = AudioQueueAllocateBuffer(audioQueue, currentlyPlayingEntry->packetBufferSize, &audioQueueBuffer[i]);
        
        unsigned int hash = (unsigned int)audioQueueBuffer[i] % audioQueueBufferRefLookupCount;
        
        while (true)
        {
            if (audioQueueBufferLookup[hash].ref == 0)
            {
                audioQueueBufferLookup[hash].ref = audioQueueBuffer[i];
                audioQueueBufferLookup[hash].bufferIndex = i;
                
                break;
            }
            else
            {
                hash++;
                hash %= audioQueueBufferRefLookupCount;
            }
        }
        
        bufferUsed[i] = false;
        
        if (error)
        {
            NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

            return;
        }
    }
    
    audioPacketsReadCount = 0;
    audioPacketsPlayedCount = 0;
    
    // Get file cookie/magic bytes information
    
	UInt32 cookieSize;
	Boolean writable;
    
	error = AudioFileStreamGetPropertyInfo(audioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    
	if (error)
	{
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

		return;
	}
    
	void* cookieData = calloc(1, cookieSize);
    
	error = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    
	if (error)
	{
        free(cookieData);
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

		return;
	}
    
	error = AudioQueueSetProperty(audioQueue, kAudioQueueProperty_MagicCookie, cookieData, cookieSize);
    
	if (error)
	{
        free(cookieData);
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

		return;
	}
    
    free(cookieData);
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(double) duration
{
    //NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    if (newFileToPlay)
    {
        //NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

        return 0;
    }
    
    QueueEntry* entry = currentlyPlayingEntry;
    
    if (entry == nil)
    {
        //NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

        return 0;
    }
    
    //NSLog(@"OUT: %s", __PRETTY_FUNCTION__);

    return [entry duration];
}

-(double) progress
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    if (seekToTimeWasRequested)
    {
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        return requestedSeekTime;
    }
    
    if (newFileToPlay)
    {
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        return 0;
    }
    
    QueueEntry* entry = currentlyPlayingEntry;
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    return [entry progress];
}

-(void) wakeupPlaybackThread
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	NSRunLoop* runLoop = playbackThreadRunLoop;
	
    if (runLoop)
    {
        CFRunLoopPerformBlock([runLoop getCFRunLoop], NSDefaultRunLoopMode, ^
                              {
                                  NSLog(@"runloop block IN: %s", __PRETTY_FUNCTION__);
                                  [self processRunloop];
                                  NSLog(@"runloop block OUT: %s", __PRETTY_FUNCTION__);
                              });
        
        CFRunLoopWakeUp([runLoop getCFRunLoop]);
    }
    
    pthread_mutex_lock(&queueBuffersMutex);
    
    if (waiting)
    {
        pthread_cond_signal(&queueBufferReadyCondition);
    }
    
    pthread_mutex_unlock(&queueBuffersMutex);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    
}

-(void) seekToTime:(double)value
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    pthread_mutex_lock(&playerMutex);
    {
		BOOL seekAlreadyRequested = seekToTimeWasRequested;
		
        seekToTimeWasRequested = YES;
        requestedSeekTime = value;
        
        if (!seekAlreadyRequested)
        {
            [self wakeupPlaybackThread];
        }
    }
    pthread_mutex_unlock(&playerMutex);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) processQueue:(BOOL)skipCurrent
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	if (playbackThread == nil)
	{
		newFileToPlay = YES;
		
		playbackThread = [[NSThread alloc] initWithTarget:self selector:@selector(startInternal) object:nil];
		
		[playbackThread start];
		
		[self wakeupPlaybackThread];
	}
	else
	{
		if (skipCurrent)
		{
			newFileToPlay = YES;
			
			[self resetAudioQueue];
		}
		
		[self wakeupPlaybackThread];
	}
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) setCurrentlyReadingEntry:(QueueEntry*)entry andStartPlaying:(BOOL)startPlaying
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	OSStatus error;
    
    pthread_mutex_lock(&queueBuffersMutex);
    
    if (startPlaying)
    {
        if (audioQueue)
        {
            pthread_mutex_unlock(&queueBuffersMutex);
            
            [self resetAudioQueue];
            
            pthread_mutex_lock(&queueBuffersMutex);
        }
    }
    
    if (audioFileStream)
    {
        AudioFileStreamClose(audioFileStream);
        
        audioFileStream = 0;
    }
    
    error = AudioFileStreamOpen((__bridge void*)self, AudioFileStreamPropertyListenerProc, AudioFileStreamPacketsProc, kAudioFileM4AType, &audioFileStream);
    
    if (error)
    {
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        return;
    }
    
    if (currentlyReadingEntry)
    {
        currentlyReadingEntry.dataSource.delegate = nil;
        [currentlyReadingEntry.dataSource unregisterForEvents];
        [currentlyReadingEntry.dataSource close];
    }
    
    currentlyReadingEntry = entry;
    currentlyReadingEntry.dataSource.delegate = self;
    [currentlyReadingEntry.dataSource registerForEvents:[NSRunLoop currentRunLoop]];
    
    if (startPlaying)
    {
        [bufferingQueue removeAllObjects];
        
        [self processDidFinishPlaying:currentlyPlayingEntry withNext:entry];
    }
    else
    {
        [bufferingQueue enqueue:entry];
    }
    
    pthread_mutex_unlock(&queueBuffersMutex);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) audioQueueFinishedPlaying:(QueueEntry*)entry
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    pthread_mutex_lock(&playerMutex);
    pthread_mutex_lock(&queueBuffersMutex);
    
    QueueEntry* next = [bufferingQueue dequeue];
    
    [self processDidFinishPlaying:entry withNext:next];
    
    pthread_mutex_unlock(&queueBuffersMutex);
    pthread_mutex_unlock(&playerMutex);
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) processDidFinishPlaying:(QueueEntry*)entry withNext:(QueueEntry*)next
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    if (entry != currentlyPlayingEntry)
    {
        return;
    }
    
    NSObject* queueItemId = entry.queueItemId;
    double progress = [entry progress];
    double duration = [entry duration];
    
    BOOL nextIsDifferent = currentlyPlayingEntry != next;
    
    if (next)
    {
        if (nextIsDifferent)
        {
            next->seekTime = 0;
            
            seekToTimeWasRequested = NO;
        }
        
        currentlyPlayingEntry = next;
        currentlyPlayingEntry->bytesPlayed = 0;
        
        NSObject* playingQueueItemId = currentlyPlayingEntry.queueItemId;
        
        if (nextIsDifferent && entry)
        {
            dispatch_async(dispatch_get_main_queue(), ^
                           {
                               NSLog(@"GCD IN: %s", __PRETTY_FUNCTION__);
                               [self.delegate audioPlayer:self didFinishPlayingQueueItemId:queueItemId withReason:stopReason andProgress:progress andDuration:duration];
                               NSLog(@"GCD OUT: %s", __PRETTY_FUNCTION__);
                           });
        }
        
        if (nextIsDifferent)
        {
            dispatch_async(dispatch_get_main_queue(), ^
                           {
                               NSLog(@"GCD IN: %s", __PRETTY_FUNCTION__);
                               [self.delegate audioPlayer:self didStartPlayingQueueItemId:playingQueueItemId];
                               NSLog(@"GCD OUT: %s", __PRETTY_FUNCTION__);
                           });
        }
    }
    else
    {
        currentlyPlayingEntry = nil;
        
        if (currentlyReadingEntry == nil)
        {
            self.internalState = AudioPlayerInternalStateStopping;
        }
        
        if (nextIsDifferent && entry)
        {
            dispatch_async(dispatch_get_main_queue(), ^
                           {
                               NSLog(@"GCD IN: %s", __PRETTY_FUNCTION__);
                               [self.delegate audioPlayer:self didFinishPlayingQueueItemId:queueItemId withReason:stopReason andProgress:progress andDuration:duration];
                               NSLog(@"GCD OUT: %s", __PRETTY_FUNCTION__);
                           });
        }
    }
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(BOOL) processRunloop
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    pthread_mutex_lock(&playerMutex);
    {
        if (self.internalState == AudioPlayerInternalStatePaused)
        {
            pthread_mutex_unlock(&playerMutex);
            
            return YES;
        }
        else if (newFileToPlay)
        {
            QueueEntry* entry = [upcomingQueue dequeue];
            
            self.internalState = AudioPlayerInternalStateWaitingForData;
            
            [self setCurrentlyReadingEntry:entry andStartPlaying:YES];
            
            newFileToPlay = NO;
            nextIsIncompatible = NO;
        }
        else if (seekToTimeWasRequested && currentlyPlayingEntry && currentlyPlayingEntry != currentlyReadingEntry)
        {
            currentlyPlayingEntry.bufferIndex = -1;
            [self setCurrentlyReadingEntry:currentlyPlayingEntry andStartPlaying:YES];
            
            currentlyReadingEntry->parsedHeader = NO;
            [currentlyReadingEntry.dataSource seekToOffset:0];
            
            nextIsIncompatible = NO;
        }
        else if (self.internalState == AudioPlayerInternalStateStopped && stopReason == AudioPlayerStopReasonUserAction)
        {
            [self stopAudioQueue];
            
            currentlyReadingEntry.dataSource.delegate = nil;
            [currentlyReadingEntry.dataSource unregisterForEvents];
            
            if (currentlyPlayingEntry)
            {
                [self processDidFinishPlaying:currentlyPlayingEntry withNext:nil];
            }
            
            pthread_mutex_lock(&queueBuffersMutex);
            
            if ([bufferingQueue peek] == currentlyPlayingEntry)
            {
                [bufferingQueue dequeue];
            }
            
            currentlyPlayingEntry = nil;
            currentlyReadingEntry = nil;
            seekToTimeWasRequested = NO;
            
            pthread_mutex_unlock(&queueBuffersMutex);
        }
        else if (self.internalState == AudioPlayerInternalStateStopped && stopReason == AudioPlayerStopReasonUserActionFlushStop)
        {
            currentlyReadingEntry.dataSource.delegate = nil;
            [currentlyReadingEntry.dataSource unregisterForEvents];
            
            if (currentlyPlayingEntry)
            {
                [self processDidFinishPlaying:currentlyPlayingEntry withNext:nil];
            }
            
            pthread_mutex_lock(&queueBuffersMutex);
            
            if ([bufferingQueue peek] == currentlyPlayingEntry)
            {
                [bufferingQueue dequeue];
            }
            
            currentlyPlayingEntry = nil;
            currentlyReadingEntry = nil;
            pthread_mutex_unlock(&queueBuffersMutex);
            
            [self resetAudioQueue];
        }
        else if (currentlyReadingEntry == nil)
        {
            if (nextIsIncompatible && currentlyPlayingEntry != nil)
            {
                // Holding off cause next is incompatible
            }
            else
            {
                if (upcomingQueue.count > 0)
                {
                    QueueEntry* entry = [upcomingQueue dequeue];
                    
                    BOOL startPlaying = currentlyPlayingEntry == nil;
                    
                    [self setCurrentlyReadingEntry:entry andStartPlaying:startPlaying];
                }
                else if (currentlyPlayingEntry == nil)
                {
                    if (self.internalState != AudioPlayerInternalStateStopped)
                    {
                        [self stopAudioQueue];
                    }
                }
            }
        }
        
        if (disposeWasRequested)
        {
            pthread_mutex_unlock(&playerMutex);
            
            NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
            return NO;
        }
    }
    pthread_mutex_unlock(&playerMutex);
    
    if (currentlyReadingEntry && currentlyReadingEntry->parsedHeader && currentlyReadingEntry != currentlyPlayingEntry)
    {
        if (currentAudioStreamBasicDescription.mSampleRate != 0)
        {
            if (memcmp(&currentAudioStreamBasicDescription, &currentlyReadingEntry->audioStreamBasicDescription, sizeof(currentAudioStreamBasicDescription)) != 0)
            {
                [upcomingQueue skipQueue:[[QueueEntry alloc] initWithDataSource:currentlyReadingEntry.dataSource andQueueItemId:currentlyReadingEntry.queueItemId]];
                
                currentlyReadingEntry = nil;
                nextIsIncompatible = YES;
            }
        }
    }
    
    if (currentlyPlayingEntry && currentlyPlayingEntry->parsedHeader)
    {
        if (seekToTimeWasRequested && currentlyReadingEntry == currentlyPlayingEntry)
        {
            [self processSeekToTime];
			
            seekToTimeWasRequested = NO;
        }
    }
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    
    return YES;
}

-(void) startInternal
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	@autoreleasepool
	{		
		playbackThreadRunLoop = [NSRunLoop currentRunLoop];
		
		NSThread.currentThread.threadPriority = 1;
		
		bytesFilled = 0;
		packetsFilled = 0;
		
		[playbackThreadRunLoop addPort:[NSPort port] forMode:NSDefaultRunLoopMode];

		while (true)
		{
			if (![self processRunloop])
			{
				break;
			}

			[playbackThreadRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:10]];
		}
		
		disposeWasRequested = NO;
		seekToTimeWasRequested = NO;
		
		currentlyReadingEntry.dataSource.delegate = nil;
		currentlyPlayingEntry.dataSource.delegate = nil;
		
		currentlyReadingEntry = nil;
		currentlyPlayingEntry = nil;
		
		self.internalState = AudioPlayerInternalStateDisposed;
		
		[threadFinishedCondLock lock];
		[threadFinishedCondLock unlockWithCondition:1];
	}
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) processSeekToTime
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	OSStatus error;
    NSAssert(currentlyReadingEntry == currentlyPlayingEntry, @"playing and reading must be the same");
    
    if ([currentlyPlayingEntry calculatedBitRate] == 0.0 || currentlyPlayingEntry.dataSource.length <= 0)
    {
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        return;
    }
    
    long long seekByteOffset = currentlyPlayingEntry->audioDataOffset + (requestedSeekTime / self.duration) * (currentlyReadingEntry.audioDataLengthInBytes);
    
    if (seekByteOffset > currentlyPlayingEntry.dataSource.length - (2 * currentlyPlayingEntry->packetBufferSize))
    {
        seekByteOffset = currentlyPlayingEntry.dataSource.length - 2 * currentlyPlayingEntry->packetBufferSize;
    }
    
    currentlyPlayingEntry->seekTime = requestedSeekTime;
    currentlyPlayingEntry->lastProgress = requestedSeekTime;
    
    double calculatedBitRate = [currentlyPlayingEntry calculatedBitRate];
    
    if (currentlyPlayingEntry->packetDuration > 0 && calculatedBitRate > 0)
    {
        UInt32 ioFlags = 0;
        SInt64 packetAlignedByteOffset;
        SInt64 seekPacket = floor(requestedSeekTime / currentlyPlayingEntry->packetDuration);
        
        error = AudioFileStreamSeek(audioFileStream, seekPacket, &packetAlignedByteOffset, &ioFlags);
        
        if (!error && !(ioFlags & kAudioFileStreamSeekFlag_OffsetIsEstimated))
        {
            double delta = ((seekByteOffset - (SInt64)currentlyPlayingEntry->audioDataOffset) - packetAlignedByteOffset) / calculatedBitRate * 8;
            
            currentlyPlayingEntry->seekTime -= delta;
            
            seekByteOffset = packetAlignedByteOffset + currentlyPlayingEntry->audioDataOffset;
        }
    }
    
    [currentlyReadingEntry updateAudioDataSource];
    [currentlyReadingEntry.dataSource seekToOffset:seekByteOffset];
    
    if (seekByteOffset > 0)
    {
        discontinuous = YES;
    }
    
    if (audioQueue)
    {
        [self resetAudioQueue];
    }
    
    currentlyPlayingEntry->bytesPlayed = 0;
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(BOOL) startAudioQueue
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	OSStatus error;
    
    self.internalState = AudioPlayerInternalStateWaitingForQueueToStart;
    
    AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1);
    
    error = AudioQueueStart(audioQueue, NULL);
    
    if (error)
    {
		if (backgroundTaskId == UIBackgroundTaskInvalid)
		{
			[self startSystemBackgroundTask];
		}
		
        [self stopAudioQueue];
        [self createAudioQueue];
        
        self.internalState = AudioPlayerInternalStateWaitingForQueueToStart;
        
        error = AudioQueueStart(audioQueue, NULL);
    }
	
	[self stopSystemBackgroundTask];
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    return YES;
}

-(void) stopAudioQueue
{
    
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	OSStatus error;
	
	if (!audioQueue)
    {
        self.internalState = AudioPlayerInternalStateStopped;
        
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        return;
    }
    else
    {
        audioQueueFlushing = YES;
        
        error = AudioQueueStop(audioQueue, true);
        error = AudioQueueDispose(audioQueue, true);
        
        audioQueue = nil;
    }
    
    if (error)
    {
        [self didEncounterError:AudioPlayerErrorQueueStopFailed];
    }
    
    pthread_mutex_lock(&queueBuffersMutex);
    
    if (numberOfBuffersUsed != 0)
    {
        numberOfBuffersUsed = 0;
        
        memset(&bufferUsed[0], 0, sizeof(bool) * audioQueueBufferCount);
    }
    
    pthread_cond_signal(&queueBufferReadyCondition);
    pthread_mutex_unlock(&queueBuffersMutex);
    
    bytesFilled = 0;
    fillBufferIndex = 0;
    packetsFilled = 0;
    
    audioPacketsReadCount = 0;
    audioPacketsPlayedCount = 0;
    audioQueueFlushing = NO;
    
    self.internalState = AudioPlayerInternalStateStopped;
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) resetAudioQueue
{
    
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	OSStatus error;
    
    pthread_mutex_lock(&playerMutex);
	
    audioQueueFlushing = YES;
    
    if (audioQueue)
    {
        error = AudioQueueReset(audioQueue);
        
        if (error)
        {
            dispatch_async(dispatch_get_main_queue(), ^
            {
                [self didEncounterError:AudioPlayerErrorQueueStopFailed];;
            });
        }
    }
    
    pthread_mutex_unlock(&playerMutex);
        
    pthread_mutex_lock(&queueBuffersMutex);
    
    if (numberOfBuffersUsed != 0)
    {
        numberOfBuffersUsed = 0;
        
        memset(&bufferUsed[0], 0, sizeof(bool) * audioQueueBufferCount);
    }
    
    pthread_cond_signal(&queueBufferReadyCondition);
    pthread_mutex_unlock(&queueBuffersMutex);
    
    bytesFilled = 0;
    fillBufferIndex = 0;
    packetsFilled = 0;
    
    if (currentlyPlayingEntry)
    {
        currentlyPlayingEntry->lastProgress = 0;
    }
    
    audioPacketsReadCount = 0;
    audioPacketsPlayedCount = 0;
    audioQueueFlushing = NO;
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) dataSourceDataAvailable:(DataSource*)dataSourceIn
{
    
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
	OSStatus error;
    
    if (currentlyReadingEntry.dataSource != dataSourceIn)
    {
        return;
    }
    
    if (!currentlyReadingEntry.dataSource.hasBytesAvailable)
    {
        return;
    }
    
    int read = [currentlyReadingEntry.dataSource readIntoBuffer:readBuffer withSize:readBufferSize];
    
    if (read == 0)
    {
        return;
    }
    
    if (read < 0)
    {
        // iOS will shutdown network connections if the app is backgrounded (i.e. device is locked when player is paused)
        // We try to reopen -- should probably add a back-off protocol in the future
        
        long long position = currentlyReadingEntry.dataSource.position;
        
        [currentlyReadingEntry.dataSource seekToOffset:position];
        
        
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        return;
    }
    
    int flags = 0;
    
    if (discontinuous)
    {
        flags = kAudioFileStreamParseFlag_Discontinuity;
    }
    
    error = AudioFileStreamParseBytes(audioFileStream, read, readBuffer, flags);
    
    if (error)
    {
        if (dataSourceIn == currentlyPlayingEntry.dataSource)
        {
            [self didEncounterError:AudioPlayerErrorStreamParseBytesFailed];
        }
        
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        
        return;
    }
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) dataSourceErrorOccured:(DataSource*)dataSourceIn
{
    
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    if (currentlyReadingEntry.dataSource != dataSourceIn)
    {
        
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        return;
    }
    
    [self didEncounterError:AudioPlayerErrorDataNotFound];
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) dataSourceEof:(DataSource*)dataSourceIn
{
    
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    if (currentlyReadingEntry.dataSource != dataSourceIn)
    {
        
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        return;
    }
    
    if (bytesFilled)
    {
        [self enqueueBuffer];
    }
    
    NSObject* queueItemId = currentlyReadingEntry.queueItemId;
    
    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       NSLog(@"GCD IN: %s", __PRETTY_FUNCTION__);
                       [self.delegate audioPlayer:self didFinishBufferingSourceWithQueueItemId:queueItemId];
                       NSLog(@"GCD OUT: %s", __PRETTY_FUNCTION__);
                   });
    
    pthread_mutex_lock(&playerMutex);
    {
        if (audioQueue)
        {
            currentlyReadingEntry.bufferIndex = audioPacketsReadCount;
            currentlyReadingEntry = nil;
        }
        else
        {
            stopReason = AudioPlayerStopReasonEof;
            self.internalState = AudioPlayerInternalStateStopped;
        }
    }
    pthread_mutex_unlock(&playerMutex);
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) pause
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    pthread_mutex_lock(&playerMutex);
    {
		OSStatus error;
        
        if (self.internalState != AudioPlayerInternalStatePaused)
        {
            self.internalState = AudioPlayerInternalStatePaused;
            
            if (audioQueue)
            {
                error = AudioQueuePause(audioQueue);
                
                if (error)
                {
                    [self didEncounterError:AudioPlayerErrorQueuePauseFailed];
                    
                    pthread_mutex_unlock(&playerMutex);
                    
                    
                    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
                    return;
                }
            }
            
            [self wakeupPlaybackThread];
        }
    }
    pthread_mutex_unlock(&playerMutex);
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) resume
{
    
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    pthread_mutex_lock(&playerMutex);
    {
		OSStatus error;
		
        if (self.internalState == AudioPlayerInternalStatePaused)
        {
            self.internalState = AudioPlayerInternalStatePlaying;
            
            if (seekToTimeWasRequested)
            {
                [self resetAudioQueue];
            }
            
            error = AudioQueueStart(audioQueue, 0);
            
            if (error)
            {
                [self didEncounterError:AudioPlayerErrorQueueStartFailed];
                
                pthread_mutex_unlock(&playerMutex);
                
                NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
                
                return;
            }
            
            [self wakeupPlaybackThread];
        }
    }
    pthread_mutex_unlock(&playerMutex);
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) stop
{
    
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    pthread_mutex_lock(&playerMutex);
    {
        if (self.internalState == AudioPlayerInternalStateStopped)
        {
            pthread_mutex_unlock(&playerMutex);
            
            NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
            return;
        }
        
        stopReason = AudioPlayerStopReasonUserAction;
        self.internalState = AudioPlayerInternalStateStopped;
		
		[self wakeupPlaybackThread];
    }
    pthread_mutex_unlock(&playerMutex);
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) flushStop
{
    
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    pthread_mutex_lock(&playerMutex);
    {
        if (self.internalState == AudioPlayerInternalStateStopped)
        {
            pthread_mutex_unlock(&playerMutex);
            
            NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
            return;
        }
        
        stopReason = AudioPlayerStopReasonUserActionFlushStop;
        self.internalState = AudioPlayerInternalStateStopped;
		
		[self wakeupPlaybackThread];
    }
    pthread_mutex_unlock(&playerMutex);
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) stopThread
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    BOOL wait = NO;
    
    pthread_mutex_lock(&playerMutex);
    {
        disposeWasRequested = YES;
        
        if (playbackThread && playbackThreadRunLoop)
        {
            wait = YES;
            
            CFRunLoopStop([playbackThreadRunLoop getCFRunLoop]);
        }
    }
    pthread_mutex_unlock(&playerMutex);
    
    if (wait)
    {
        [threadFinishedCondLock lockWhenCondition:1];
        [threadFinishedCondLock unlockWithCondition:0];
    }
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(void) dispose
{
    
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    [self stop];
    [self stopThread];
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
}

-(NSObject*) currentlyPlayingQueueItemId
{
    NSLog(@"IN: %s", __PRETTY_FUNCTION__);
    QueueEntry* entry = currentlyPlayingEntry;
    
    if (entry == nil)
    {
        NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
        return nil;
    }
    
    NSLog(@"OUT: %s", __PRETTY_FUNCTION__);
    return entry.queueItemId;
}

@end
