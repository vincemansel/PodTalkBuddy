//
//  PodcastService+Create.m
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/20/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import "PodcastService+Create.h"

@implementation PodcastService (Create)

+ (PodcastService *)createPodcastServiceInManagedObjectContext:(NSManagedObjectContext *)context
                                                        withID:(NSString *)pid
                                                      withName:(NSString *)name
                                                       withURL:(NSString *)urlString;
{
    PodcastService *podcastService = nil;
    
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"PodcastService"];
    
    request.predicate = [NSPredicate predicateWithFormat:@"jid = %@", pid];
    //NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES];
    //request.sortDescriptors = [NSArray arrayWithObject:sortDescriptor];
    
    NSError *error = nil;
    NSArray *matches = [context executeFetchRequest:request error:&error];
    
    if (!matches || ([matches count] > 1)) {
        // handle error
        NSLog(@"[%@ %@] Error = %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), error);
    } else if ([matches count] == 0) {
        podcastService = [NSEntityDescription insertNewObjectForEntityForName:@"PodcastService" inManagedObjectContext:context];
        podcastService.jid = pid;
        podcastService.name = name;
        podcastService.url = urlString;
        
    } else {
        podcastService = [matches lastObject];
    }
    
    return podcastService;
}

@end
