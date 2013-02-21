//
//  Category+Create.m
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/20/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import "Category+Create.h"

@implementation Category (Create)

+ (Category *)createPodcastCategoryInManagedObjectContext:(NSManagedObjectContext *)context
                                                   withID:(NSString *)pid
                                                 withName:(NSString *)name
                                       withPodcastService:(PodcastService *)service
{
    Category *podcastCategory = nil;
    
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Category"];
    
    request.predicate = [NSPredicate predicateWithFormat:@"jid = %@", pid];
    //NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES];
    //request.sortDescriptors = [NSArray arrayWithObject:sortDescriptor];
    
    NSError *error = nil;
    NSArray *matches = [context executeFetchRequest:request error:&error];
    
    if (!matches || ([matches count] > 1)) {
        // handle error
        NSLog(@"[%@ %@] Error = %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), error);
    } else if ([matches count] == 0) {
        podcastCategory = [NSEntityDescription insertNewObjectForEntityForName:@"Category" inManagedObjectContext:context];
        podcastCategory.jid = pid;
        podcastCategory.name = name;
        podcastCategory.service = service;
        
    } else {
        podcastCategory = [matches lastObject];
    }
    
    return podcastCategory;
}

@end
