//
//  Podcast.h
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/20/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class Category;

@interface Podcast : NSManagedObject

@property (nonatomic, retain) NSString * speaker;
@property (nonatomic, retain) NSString * title;
@property (nonatomic, retain) NSString * url;
@property (nonatomic, retain) NSString * jid;
@property (nonatomic, retain) Category *category;

@end
