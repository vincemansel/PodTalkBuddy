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

#import "LocalFileDataSource.h"

@interface LocalFileDataSource()
@property (readwrite, copy) NSString* filePath;

-(void) open;
@end

@implementation LocalFileDataSource
@synthesize filePath;

-(id) initWithFilePath:(NSString*)filePathIn
{
    if (self = [super init])
    {
        self.filePath = filePathIn;
        
        [self open];
    }
    
    return self;
}

-(void) dealloc
{
    [self close];
}

-(void) close
{
    if (stream)
    {
        CFReadStreamClose(stream);
        
        stream = 0;
    }
}

-(void) open
{
    NSURL* url = [[NSURL alloc] initFileURLWithPath:self.filePath];
    
    if (stream)
    {
        CFReadStreamClose(stream);
        
        stream = 0;
    }
    
    stream = CFReadStreamCreateWithFile(NULL, (__bridge CFURLRef)url);
    
    SInt32 errorCode;
    
    NSNumber* number = (__bridge_transfer NSNumber*)CFURLCreatePropertyFromResource(NULL, (__bridge CFURLRef)url, kCFURLFileLength, &errorCode);
    
    if (number)
    {
        length = number.longLongValue;
    }
    
    CFReadStreamOpen(stream);
}

-(long long) position
{
    return position;
}

-(long long) length
{
    return length;
}

-(int) readIntoBuffer:(UInt8*)buffer withSize:(int)size
{
    int retval = CFReadStreamRead(stream, buffer, size);

    if (retval > 0)
    {
        position += retval;
    }
    else
    {
        NSNumber* property = (__bridge_transfer NSNumber*)CFReadStreamCopyProperty(stream, kCFStreamPropertyFileCurrentOffset);
        
        position = property.longLongValue;
    }
    
    return retval;
}

-(void) seekToOffset:(long long)offset
{
    CFStreamStatus status = kCFStreamStatusClosed;
    
    if (stream != 0)
    {
		status = CFReadStreamGetStatus(stream);
    }
    
    BOOL reopened = NO;
    
    if (status == kCFStreamStatusAtEnd || status == kCFStreamStatusClosed || status == kCFStreamStatusError)
    {
        reopened = YES;
        
        [self close];        
        [self open];
        [self reregisterForEvents];
    }
    
    if (CFReadStreamSetProperty(stream, kCFStreamPropertyFileCurrentOffset, (__bridge CFTypeRef)[NSNumber numberWithLongLong:offset]) != TRUE)
    {
        position = 0;
    }
    else
    {
        position = offset;
    }
    
    if (!reopened)
    {
        CFRunLoopPerformBlock(eventsRunLoop.getCFRunLoop, NSRunLoopCommonModes, ^
        {
            if ([self hasBytesAvailable])
            {
                [self dataAvailable];
            }
        });
        
        CFRunLoopWakeUp(eventsRunLoop.getCFRunLoop);
    }
}

-(NSString*) description
{
    return self->filePath;
}

@end
