//
//  Podcast+Create.h
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/20/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import "Podcast.h"

@interface Podcast (Create)

+ (Podcast *)createPodcastInManagedObjectContext:(NSManagedObjectContext *)context
                                          withID:(NSString *)pid
                                        withTitle:(NSString *)title
                                       withSpeaker:(NSString *)speaker
                                         withURL:(NSString *)urlString
                             withPodcastCateogry:(Category *)category;

@end
