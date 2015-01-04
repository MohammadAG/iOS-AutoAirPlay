#import <libactivator/libactivator.h>
#import <substrate.h>

@interface IPActviator : NSObject<LAListener>
@end

@interface MPAVRoutingController
- (void)fetchAvailableRoutesWithCompletionHandler:(id)arg1;
- (BOOL)pickRoute:(id)arg1;
@property(nonatomic) int discoveryMode;
@property(readonly, copy, nonatomic) NSArray *availableRoutes;
@end

@interface MPAVRoute : NSObject
@property(readonly, nonatomic) NSString *routeName;
@end

@interface SBMediaController
@end

static SBMediaController *mediaController = nil;

@implementation IPActviator

-(void)performAction {
    if (!mediaController)
        return;
    
    MPAVRoutingController *routingController = MSHookIvar<MPAVRoutingController *>(mediaController, "_routingController");
    
    if (!routingController)
        return;
    
    int oldDiscoveryMode = routingController.discoveryMode;
    routingController.discoveryMode = 2;
    
    [routingController fetchAvailableRoutesWithCompletionHandler:^{
        NSArray *routes = routingController.availableRoutes;
        BOOL switched = NO;
        for (MPAVRoute *route in routes) {
            NSDictionary* routeDescription = [route performSelector:@selector(avRouteDescription)];
            if ([routeDescription[@"AVAudioRouteName"] isEqualToString:@"AirTunes"] &&
                ![routeDescription objectForKey:@"RouteSupportsAirPlayVideo"]) {
                if ([routingController pickRoute:route]) {
                    NSLog(@"Succesfully switched to audio-only speaker");
                    switched = YES;
                    break;
                } else {
                    NSLog(@"Failed, trying next speaker if available");
                }
            }
        }
        
        if (!switched) {
            for (MPAVRoute *route in routes) {
                NSDictionary* routeDescription = [route performSelector:@selector(avRouteDescription)];
                BOOL switched = NO;
                if ([routeDescription[@"AVAudioRouteName"] isEqualToString:@"AirTunes"]) {
                    if ([routingController pickRoute:route]) {
                        NSLog(@"Succesfully switched to speaker");
                        switched = YES;
                        break;
                    } else {
                        NSLog(@"Failed, trying next AirPlay device");
                    }
                }
            }
        }
        
        routingController.discoveryMode = oldDiscoveryMode;
    }];
}

-(void)activator:(LAActivator *)activator receiveEvent:(LAEvent *)event {
    if ([event.name rangeOfString:@"libactivator.network.joined-wifi" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        [self performSelector:@selector(performAction) withObject:nil afterDelay:4.0];
    } else {
        [self performSelector:@selector(performAction)];
    }
}

+(void)load {
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
    [[LAActivator sharedInstance] registerListener:[self new] forName:@"com.mohammadag.airplayactivator"];
    [p release];
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedTitleForListenerName:(NSString *)listenerName {
    return @"AirPlay Activator";
}
- (NSString *)activator:(LAActivator *)activator requiresLocalizedDescriptionForListenerName:(NSString *)listenerName {
    return @"Enables the first possible AirPlay receiver";
}
- (NSArray *)activator:(LAActivator *)activator requiresCompatibleEventModesForListenerWithName:(NSString *)listenerName {
    return [NSArray arrayWithObjects:@"springboard", @"lockscreen", @"application", nil];
}

@end

%hook SBMediaController

-(void)init {
    %orig;
    mediaController = self;
}

%end