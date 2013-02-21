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

#import "HttpDataSource.h"

@interface HttpDataSource()
-(void) open;
@end

@implementation HttpDataSource
@synthesize url;

-(id) initWithURL:(NSURL*)urlIn
{
    if (self = [super init])
    {
        seekStart = 0;
        relativePosition = 0;
        fileLength = -1;
        
        self.url = urlIn;
        
        [self open];
    }
    
    return self;
}

-(void) dataAvailable
{
    if (fileLength < 0)
    {
        CFTypeRef copyPropertyMessage = CFReadStreamCopyProperty(stream, kCFStreamPropertyHTTPResponseHeader);

        httpHeaders = (__bridge NSDictionary*)CFHTTPMessageCopyAllHeaderFields((CFHTTPMessageRef)copyPropertyMessage);

        CFRelease(copyPropertyMessage);
        
        if (seekStart == 0)
        {
            fileLength = [[httpHeaders objectForKey:@"Content-Length"] integerValue];
        }
    }
    
    [super dataAvailable];
}

-(long long) position
{
    return seekStart + relativePosition;
}

-(long long) length
{
    return fileLength >= 0 ? fileLength : 0;
}

-(void) seekToOffset:(long long)offset
{
    if (eventsRunLoop)
    {
        [self unregisterForEvents];
    }
    
    CFReadStreamClose(stream);
    
    stream = nil;
    relativePosition = 0;
    seekStart = offset;
    
    [self open];
    [self reregisterForEvents];
}

-(int) readIntoBuffer:(UInt8*)buffer withSize:(int)size
{
    if (size == 0)
    {
        return 0;
    }
    
    int read = CFReadStreamRead(stream, buffer, size);
    
    if (read < 0)
    {
        return read;
    }
    
    relativePosition += read;
    
    return read;
}

-(void) open
{
    CFHTTPMessageRef message = CFHTTPMessageCreateRequest(NULL, (CFStringRef)@"GET", (__bridge CFURLRef)self.url, kCFHTTPVersion1_1);
    
    if (seekStart > 0)
    {
        CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Range"), (__bridge CFStringRef)[NSString stringWithFormat:@"bytes=%d-", seekStart]);
        
        discontinuous = YES;
    }
    
    stream = CFReadStreamCreateForHTTPRequest(NULL, message);

	if (!CFReadStreamSetProperty(stream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue))
    {
        CFRelease(message);
        
        return;
    }

    // Proxy support

    CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
    CFReadStreamSetProperty(stream, kCFStreamPropertyHTTPProxy, proxySettings);
    CFRelease(proxySettings);

    // SSL support

    if ([url.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame)
    {
        NSDictionary* sslSettings = [NSDictionary dictionaryWithObjectsAndKeys:
         (NSString*)kCFStreamSocketSecurityLevelNegotiatedSSL, kCFStreamSSLLevel,
         [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredCertificates,
         [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredRoots,
         [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
         [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain,
         [NSNull null], kCFStreamSSLPeerName,
		 nil];
        
        CFReadStreamSetProperty(stream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)sslSettings);
    }

    // Open
    
    if (!CFReadStreamOpen(stream))
    {
        CFRelease(stream);
        CFRelease(message);
        
        return;
    }
    
    CFRelease(message);
}

@end
