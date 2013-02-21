//
//  PodcastService+Create.h
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/20/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import "PodcastService.h"

@interface PodcastService (Create)

+ (PodcastService *)createPodcastServiceInManagedObjectContext:(NSManagedObjectContext *)context
                                                        withID:(NSString *)pid
                                                      withName:(NSString *)name
                                                       withURL:(NSString *)urlString;
@end
