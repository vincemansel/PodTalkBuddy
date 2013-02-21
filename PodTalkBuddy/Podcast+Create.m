//
//  Podcast+Create.m
//  PodTalkBuddy
//
//  Created by waveOcean Software on 2/20/13.
//  Copyright (c) 2013 vincemansel. All rights reserved.
//

#import "Podcast+Create.h"

@implementation Podcast (Create)

+ (Podcast *)createPodcastInManagedObjectContext:(NSManagedObjectContext *)context
                                          withID:(NSString *)pid
                                       withTitle:(NSString *)title
                                     withSpeaker:(NSString *)speaker
                                         withURL:(NSString *)urlString
                             withPodcastCateogry:(Category *)category
{
    Podcast *podcast = nil;
    
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Podcast"];
    
    request.predicate = [NSPredicate predicateWithFormat:@"jid = %@", pid];
    //NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES];
    //request.sortDescriptors = [NSArray arrayWithObject:sortDescriptor];
    
    NSError *error = nil;
    NSArray *matches = [context executeFetchRequest:request error:&error];
    
    if (!matches || ([matches count] > 1)) {
        // handle error
        NSLog(@"[%@ %@] Error = %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), error);
    } else if ([matches count] == 0) {
        podcast = [NSEntityDescription insertNewObjectForEntityForName:@"Podcast" inManagedObjectContext:context];
        podcast.jid = pid;
        podcast.title  = title;
        podcast.speaker = speaker;
        podcast.url = urlString;
        podcast.category = category;
        
    } else {
         podcast = [matches lastObject];
    }
    
    return podcast;    
}

@end
