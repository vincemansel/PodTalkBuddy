//
//  PodcastService.h
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/21/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class Category;

@interface PodcastService : NSManagedObject

@property (nonatomic, retain) NSString * name;
@property (nonatomic, retain) NSString * url;
@property (nonatomic, retain) NSString * jid;
@property (nonatomic, retain) NSSet *categories;
@end

@interface PodcastService (CoreDataGeneratedAccessors)

- (void)addCategoriesObject:(Category *)value;
- (void)removeCategoriesObject:(Category *)value;
- (void)addCategories:(NSSet *)values;
- (void)removeCategories:(NSSet *)values;

@end
