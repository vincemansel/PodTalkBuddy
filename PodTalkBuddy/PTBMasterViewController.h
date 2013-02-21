//
//  PTBMasterViewController.h
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/20/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AudioPlayer.h"
#import "PTBDetailViewController.h"

@class PTBDetailViewController;

#import <CoreData/CoreData.h>

@interface PTBMasterViewController : UITableViewController <NSFetchedResultsControllerDelegate, AudioPlayerViewControllerDelegate>
{
@private
    AudioPlayer* audioPlayer;
}

@property (strong, nonatomic) PTBDetailViewController *detailViewController;

@property (strong, nonatomic) NSFetchedResultsController *fetchedResultsController;
@property (strong, nonatomic) NSManagedObjectContext *managedObjectContext;

@end
