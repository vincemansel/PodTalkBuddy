//
//  PTBDetailViewController.h
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/20/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import <UIKit/UIKit.h>
//#import "AQLevelMeter.h"
#import "AudioPlayer.h"

@class AQLevelMeter;

@class PTBDetailViewController;

@protocol AudioPlayerViewControllerDelegate <NSObject>

-(void) audioPlayerViewControllerPlayFromHTTPSelected:(PTBDetailViewController *)audioPlayerControllerView
                                        withURLString:(NSString *)urlString;

-(void) audioPlayerViewControllerPlayFromLocalFileSelected:(PTBDetailViewController *)audioPlayerControllerView;
@end

@interface PTBDetailViewController : UIViewController <UISplitViewControllerDelegate, AudioPlayerDelegate>
{
@private
	NSTimer* timer;
}

@property (strong, nonatomic) id detailItem;

@property (weak, nonatomic) IBOutlet UILabel *detailDescriptionLabel;

@property (weak, nonatomic) IBOutlet AQLevelMeter *lvlMeter_in;
@property (weak, nonatomic) IBOutlet UISlider *slider;
@property (weak, nonatomic) IBOutlet UIButton *playButton;

@property (strong, readwrite) AudioPlayer* audioPlayer;

@property (weak, nonatomic) id<AudioPlayerViewControllerDelegate> delegate;

- (IBAction)sliderMoved:(id)sender;
- (IBAction)play:(id)sender;

@end
