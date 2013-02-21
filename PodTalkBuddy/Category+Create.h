//
//  Category+Create.h
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/20/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import "Category.h"

@interface Category (Create)

+ (Category *)createPodcastCategoryInManagedObjectContext:(NSManagedObjectContext *)context
                                                   withID:(NSString *)pid
                                                 withName:(NSString *)name
                                       withPodcastService:(PodcastService *)service;

@end
