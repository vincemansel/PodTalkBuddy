//
//  PTBDetailViewController.m
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/20/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import "PTBDetailViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import "AQLevelMeter.h"

@interface PTBDetailViewController ()
@property (strong, nonatomic) UIPopoverController *masterPopoverController;
- (void)configureView;
- (void) setupTimer;
- (void) updateControls;
@end

@implementation PTBDetailViewController

@synthesize audioPlayer = _audioPlayer;
@synthesize lvlMeter_in = _lvlMeter_in;

#pragma mark - Managing the detail item

- (void)setDetailItem:(id)newDetailItem
{
    if (_detailItem != newDetailItem) {
        _detailItem = newDetailItem;
        
        // Update the view.
        [self.audioPlayer stop];
        [self configureView];
    }

    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }        
}

- (void)configureView
{
    // Update the user interface for the detail item.

    if (self.detailItem) {
        self.detailDescriptionLabel.text = [[self.detailItem valueForKey:@"title"] description];
    }
    UIColor *bgColor = [[UIColor alloc] initWithRed:.39 green:.44 blue:.57 alpha:.5];
	[_lvlMeter_in setBackgroundColor:bgColor];
	[_lvlMeter_in setBorderColor:bgColor];
}

#pragma mark - Lifecyle Management

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    self.title = NSLocalizedString(@"Podcast", @"Podcast");
    
    [self configureView];
    
    [self.audioPlayer stop];
    //self.slider.value = 0;
    //[self.playButton setTitle:@"Play" forState:UIControlStateNormal];
    
    [self setupTimer];
    [self updateControls];
    
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackQueueStopped:) name:@"playbackQueueStopped" object:nil];
//	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackQueueResumed:) name:@"playbackQueueResumed" object:nil];
}


- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // Turn on remote control event delivery
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    
    [self becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated
{
    // Turn off remote control event delivery
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    
    // Resign as first responder
    [self resignFirstResponder];
    
    [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [timer invalidate];
    [self.audioPlayer stop];
    // Clean up delegate since some callbacks occur after state changes
//    [[NSNotificationCenter defaultCenter] postNotificationName: @"playbackQueueStopped" object: nil];
    _audioPlayer.delegate = nil;
    
//    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"playbackQueueResumed" object:nil];
}

# pragma mark Notification routines
- (void)playbackQueueStopped:(NSNotification *)note
{
	//btn_play.title = @"Play";
//	[_lvlMeter_in setAq: nil];
//    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)playbackQueueResumed:(NSNotification *)note
{
	//btn_play.title = @"Stop";
//	[_lvlMeter_in setAq: _audioPlayer.audioQueueRef];
}


#pragma mark - UIResponder method overrides for Remote Control

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)receivedEvent
{
    if (receivedEvent.type == UIEventTypeRemoteControl) {
        NSLog(@"sub type: %d", receivedEvent.subtype);
        switch (receivedEvent.subtype) {
            case UIEventSubtypeRemoteControlTogglePlayPause:
                [self playButtonPressed];
                break;
                
            case UIEventSubtypeRemoteControlPreviousTrack:
                [self back:self];
                break;
                
            case UIEventSubtypeRemoteControlNextTrack:
                [self forward:self];
                break;
                
            default:
                break;
        }
    }
}

#pragma mark - Target Action Methods

- (IBAction)sliderMoved:(id)sender
{
    [self sliderChanged];
}

- (IBAction)play:(id)sender
{
    [self playButtonPressed];
}

- (IBAction)back:(id)sender
{
    NSLog(@"Slider now: %f", self.slider.value);
    [self.slider setValue:self.slider.value - 10];
    NSLog(@"Slider back: %f", self.slider.value);

    [self.audioPlayer seekToTime:self.slider.value];
}

- (IBAction)forward:(id)sender
{
    NSLog(@"Slider now: %f", self.slider.value);
    [self.slider setValue:self.slider.value + 10];
    NSLog(@"Slider forward: %f", self.slider.value);

    [self.audioPlayer seekToTime:self.slider.value];
}

-(void) sliderChanged
{
	if (!self.audioPlayer)
	{
		return;
	}
	
	NSLog(@"Slider Changed: %f", self.slider.value);
	
	[self.audioPlayer seekToTime:self.slider.value];
}

#

-(void) setupTimer
{
	timer = [NSTimer timerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
	
	[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

-(void) tick
{
	if (!self.audioPlayer || self.audioPlayer.duration == 0)
	{
		self.slider.value = 0;
		
		return;
	}
	
	self.slider.minimumValue = 0;
	self.slider.maximumValue = self.audioPlayer.duration;
	
	self.slider.value = self.audioPlayer.progress;
}

-(void) playFromHTTPButtonTouched
{
	[self.delegate audioPlayerViewControllerPlayFromHTTPSelected:self withURLString:[self.detailItem valueForKey:@"url"]];
}

-(void) playFromLocalFileButtonTouched
{
	[self.delegate audioPlayerViewControllerPlayFromLocalFileSelected:self];
}

-(void) playButtonPressed
{
	if (!self.audioPlayer || !self.detailItem)
	{
		return;
	}
    
    if ([self.playButton.titleLabel.text isEqualToString:@"Play"]) {
        [self playFromHTTPButtonTouched];
        
        NSMutableDictionary *newNowPlayingInfo = [[NSMutableDictionary alloc] init];
        
        [newNowPlayingInfo setObject:[self.detailItem valueForKey:@"title"] forKey:MPMediaItemPropertyTitle];
        [newNowPlayingInfo setObject:[self.detailItem valueForKey:@"speaker"] forKey:MPMediaItemPropertyArtist];
        [newNowPlayingInfo setObject:[[self.detailItem valueForKey:@"category"] name] forKey:MPMediaItemPropertyAlbumTitle];

        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:newNowPlayingInfo];
        
    }
	
	if (self.audioPlayer.state == AudioPlayerStatePaused)
	{
		[self.audioPlayer resume];
	}
	else
	{
		[self.audioPlayer pause];
	}
}

-(void) updateControls
{
	if (self.audioPlayer == nil)
	{
		[self.playButton setTitle:@"Play" forState:UIControlStateNormal];
	}
	else if (self.audioPlayer.state == AudioPlayerStatePaused)
	{
		[self.playButton setTitle:@"Resume" forState:UIControlStateNormal];
	}
	else if (self.audioPlayer.state == AudioPlayerStatePlaying)
	{
		[self.playButton setTitle:@"Pause" forState:UIControlStateNormal];
	}
	else
	{
		[self.playButton setTitle:@"Play" forState:UIControlStateNormal];
	}
    
}

-(void) setAudioPlayer:(AudioPlayer*)value
{
	if (_audioPlayer)
	{
		_audioPlayer.delegate = nil;
	}
    
	_audioPlayer = value;
	_audioPlayer.delegate = self;
	
	[self updateControls];
}

-(AudioPlayer*) audioPlayer
{
	return _audioPlayer;
}

#pragma mark - AudioPlayerDelegate Methods

-(void) audioPlayer:(AudioPlayer*)audioPlayer stateChanged:(AudioPlayerState)state
{
	[self updateControls];
}

-(void) audioPlayer:(AudioPlayer*)audioPlayer didEncounterError:(AudioPlayerErrorCode)errorCode
{
	[self updateControls];
}

-(void) audioPlayer:(AudioPlayer*)audioPlayer didStartPlayingQueueItemId:(NSObject*)queueItemId
{
	[self updateControls];
}

-(void) audioPlayer:(AudioPlayer*)audioPlayer didFinishBufferingSourceWithQueueItemId:(NSObject*)queueItemId
{
	[self updateControls];
}

-(void) audioPlayer:(AudioPlayer*)audioPlayer didFinishPlayingQueueItemId:(NSObject*)queueItemId withReason:(AudioPlayerStopReason)stopReason andProgress:(double)progress andDuration:(double)duration
{
	[self updateControls];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Split view

- (void)splitViewController:(UISplitViewController *)splitController willHideViewController:(UIViewController *)viewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)popoverController
{
    barButtonItem.title = NSLocalizedString(@"PodTalkBuddy", @"PodTalkBuddy");
    [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    self.masterPopoverController = popoverController;
}

- (void)splitViewController:(UISplitViewController *)splitController willShowViewController:(UIViewController *)viewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    // Called when the view is shown again in the split view, invalidating the button and popover controller.
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    self.masterPopoverController = nil;
}


@end
