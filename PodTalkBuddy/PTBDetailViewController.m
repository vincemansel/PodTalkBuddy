//
//  PTBDetailViewController.m
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/20/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import "PTBDetailViewController.h"

@interface PTBDetailViewController ()
@property (strong, nonatomic) UIPopoverController *masterPopoverController;
- (void)configureView;
- (void) setupTimer;
- (void) updateControls;
@end

@implementation PTBDetailViewController

@synthesize audioPlayer = _audioPlayer;

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
}

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
}

- (void)viewDidDisappear:(BOOL)animated {
    [timer invalidate];
}

- (IBAction)sliderMoved:(id)sender {
    [self sliderChanged];
}

- (IBAction)play:(id)sender {
    [self playButtonPressed];
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
