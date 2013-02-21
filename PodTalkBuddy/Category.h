//
//  Category.h
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/21/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class Podcast, PodcastService;

@interface Category : NSManagedObject

@property (nonatomic, retain) NSString * name;
@property (nonatomic, retain) NSString * jid;
@property (nonatomic, retain) NSSet *podcasts;
@property (nonatomic, retain) PodcastService *service;
@end

@interface Category (CoreDataGeneratedAccessors)

- (void)addPodcastsObject:(Podcast *)value;
- (void)removePodcastsObject:(Podcast *)value;
- (void)addPodcasts:(NSSet *)values;
- (void)removePodcasts:(NSSet *)values;

@end
