/**********************************************************************************
 AudioPlayer.m
 
 Created by Thong Nguyen on 14/05/2012.
 https://github.com/tumtumtum/audjustable
 
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

#import "CoreFoundationDataSource.h"

static void ReadStreamCallbackProc(CFReadStreamRef stream, CFStreamEventType eventType, void* inClientInfo)
{
	CoreFoundationDataSource* datasource = (__bridge CoreFoundationDataSource*)inClientInfo;
    
    switch (eventType)
    {
        case kCFStreamEventErrorOccurred:
            [datasource errorOccured];
            break;
        case kCFStreamEventEndEncountered:
            [datasource eof];
            break;
        case kCFStreamEventHasBytesAvailable:
            [datasource dataAvailable];
            break;
        default:
            break;
    }
}

@implementation CoreFoundationDataSourceClientInfo
@synthesize readStreamRef, datasource;
@end

@implementation CoreFoundationDataSource

-(void) dataAvailable
{
    [self.delegate dataSourceDataAvailable:self];
}

-(void) eof
{
    [self.delegate dataSourceEof:self];
}

-(void) errorOccured
{
    [self.delegate dataSourceErrorOccured:self];
}

-(void) dealloc
{
    if (stream)
    {
        [self unregisterForEvents];
        
        CFReadStreamClose(stream);
        
        stream = 0;
    }
}

-(void) seekToOffset:(long long)offset
{
}

-(int) readIntoBuffer:(UInt8*)buffer withSize:(int)size
{
    return CFReadStreamRead(stream, buffer, size);
}

-(void) unregisterForEvents
{
    if (stream)
    {
        CFReadStreamSetClient(stream, kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, NULL, NULL);
        CFReadStreamUnscheduleFromRunLoop(stream, [eventsRunLoop getCFRunLoop], kCFRunLoopCommonModes);
    }
}

-(BOOL) reregisterForEvents
{
    if (eventsRunLoop && stream)
    {
        CFStreamClientContext context = {0, (__bridge void*)self, NULL, NULL, NULL};
        CFReadStreamSetClient(stream, kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, ReadStreamCallbackProc, &context);
        CFReadStreamScheduleWithRunLoop(stream, [eventsRunLoop getCFRunLoop], kCFRunLoopCommonModes);
        
        return YES;
    }
    
    return NO;
}

-(BOOL) registerForEvents:(NSRunLoop*)runLoop
{
    eventsRunLoop = runLoop;
 
    if (stream)
    {
        CFStreamClientContext context = {0, (__bridge void*)self, NULL, NULL, NULL};
        
        CFReadStreamSetClient(stream, kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, ReadStreamCallbackProc, &context);
        
        CFReadStreamScheduleWithRunLoop(stream, [eventsRunLoop getCFRunLoop], kCFRunLoopCommonModes);
    
        return YES;
    }
    
    return NO;
}

-(BOOL) hasBytesAvailable
{
    if (!stream)
    {
        return NO;
    }
    
    return CFReadStreamHasBytesAvailable(stream);
}

@end
