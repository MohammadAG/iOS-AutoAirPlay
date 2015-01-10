#import <libactivator/libactivator.h>
#import <substrate.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// The default "1" only does a shallow scan (Bluetooth or similar)
#define DISCOVERY_MODE_THE_ONE_THAT_SHOWS_AIRPLAY_SPEAKERS 2

// Not sure if this is actually default, but sounds like it.
#define STOCK_UTTERANCE_SPEED 0.07

@interface AirPlayActivator : NSObject<LAListener>
@end

@interface MPAVRoute : NSObject
@property(readonly, nonatomic) NSString *routeName;
@property(readonly, nonatomic) BOOL requiresPassword;
- (NSDictionary*) avRouteDescription;
@end

@interface MPAVRoutingController
- (void)fetchAvailableRoutesWithCompletionHandler:(id)block;
- (BOOL)pickRoute:(MPAVRoute*)route withPassword:(NSString*)password;
- (BOOL)pickRoute:(MPAVRoute*)route;
@property(nonatomic) int discoveryMode;
@property(readonly, copy, nonatomic) NSArray *availableRoutes;
@end

@interface SBMediaController
@end

static SBMediaController *mediaController = nil;
static int retryCount = 0;

static int maxRetryCount = 3;
static int delay = 4;
static BOOL audioOnlyFirst = YES;
static NSString *preferredSpeakerRouteName = nil;
static NSString *preferredSpeakerPassword = nil;
static NSString *textToSpeak = nil;


static const CFStringRef DOMAIN_NAME = CFSTR("com.mohammadag.airplayactivator");

static NSString * const KEY_DELAY = @"delay";
static NSString * const KEY_AUDIO_ONLY = @"audioOnlyFirst";
static NSString * const KEY_PREFERRED_SPEAKER = @"preferredSpeaker";
static NSString * const KEY_PREFERRED_SPEAKER_PASSWORD = @"preferredSpeakerPassword";
static NSString * const KEY_RETRY_COUNT = @"retryCount";
static NSString * const KEY_SPEAK_TEXT = @"speakWhenConnected";
static NSString * const KEY_TEXT_TO_SPEAK = @"textToSpeak";

static NSString * getStringPreference(NSDictionary *dictionary, NSString *key) {
    NSString *pref = [dictionary objectForKey:key];
    if (pref)
        return [pref retain];
    
    return nil;
}

static int getIntPreference(NSDictionary *dictionary, NSString *key, int defaultValue) {
    id value = [dictionary objectForKey:key];
    if (value)
        return [value intValue];
    
    return defaultValue;
}

static BOOL getBoolPreference(NSDictionary *dictionary, NSString *key, BOOL defaultValue) {
    id value = [dictionary objectForKey:key];
    if (value)
        return [value boolValue];
    
    return defaultValue;
}

static void notificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    
    CFPreferencesAppSynchronize(DOMAIN_NAME);
    
    CFArrayRef keyList = CFPreferencesCopyKeyList(DOMAIN_NAME, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!keyList) {
        NSLog(@"There's been an error getting the key list!");
        return;
    }
    NSDictionary* preferences = (NSDictionary *) CFPreferencesCopyMultiple(keyList, DOMAIN_NAME, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!preferences) {
        NSLog(@"There's been an error getting the preferences dictionary!");
    }
    
    delay = getIntPreference(preferences, KEY_DELAY, 4);
    maxRetryCount = getIntPreference(preferences, KEY_RETRY_COUNT, 3);
    audioOnlyFirst = getBoolPreference(preferences, KEY_AUDIO_ONLY, YES);
    preferredSpeakerRouteName = getStringPreference(preferences, KEY_PREFERRED_SPEAKER);
    preferredSpeakerPassword = getStringPreference(preferences, KEY_PREFERRED_SPEAKER_PASSWORD);
    BOOL speakWhenConnected = getBoolPreference(preferences, KEY_SPEAK_TEXT, NO);
    if (speakWhenConnected) {
        textToSpeak = getStringPreference(preferences, KEY_TEXT_TO_SPEAK);
    } else if (textToSpeak) {
        [textToSpeak release];
        textToSpeak = nil;
    }
    
    NSLog(@"Delay: %i, Retries: %i, AudioOnly: %d, preferName: %@, pass: %@, speakConnected: %d, What? %@",
          delay, maxRetryCount, audioOnlyFirst, preferredSpeakerRouteName, preferredSpeakerPassword, speakWhenConnected, textToSpeak);
    
    CFRelease(keyList);
    
    [preferences release];
}

@implementation AirPlayActivator

-(void)onConnectedToAirPlaySpeaker {
    if (!textToSpeak)
        return;
    
    @autoreleasepool {
        AVSpeechUtterance *utterance = [AVSpeechUtterance
                                        speechUtteranceWithString:textToSpeak];
        AVSpeechSynthesizer *synth = [[AVSpeechSynthesizer alloc] init];
        utterance.rate = STOCK_UTTERANCE_SPEED;
        [synth speakUtterance:utterance];
    }
}

-(MPAVRoute*)getPreferredRoute:(NSArray*)routes {
    for (MPAVRoute *route in routes) {
        if ([preferredSpeakerRouteName isEqualToString:route.routeName])
            return route;
    }
    
    return nil;
}

-(BOOL)isAirPlayOutput:(MPAVRoute*)route {
    NSDictionary* routeDescription = [route avRouteDescription];
    return [routeDescription[@"AVAudioRouteName"] isEqualToString:@"AirTunes"];
}

-(BOOL)isRouteAudioOnly:(MPAVRoute*)route {
    NSDictionary* routeDescription = [route avRouteDescription];
    return [self isAirPlayOutput:route] && ![routeDescription objectForKey:@"RouteSupportsAirPlayVideo"];
}

-(void)performAction {
    if (!mediaController)
        return;
    
    MPAVRoutingController *routingController = MSHookIvar<MPAVRoutingController *>(mediaController, "_routingController");
    
    if (!routingController)
        return;
    
    int oldDiscoveryMode = routingController.discoveryMode;
    routingController.discoveryMode = DISCOVERY_MODE_THE_ONE_THAT_SHOWS_AIRPLAY_SPEAKERS;
    
    [routingController fetchAvailableRoutesWithCompletionHandler:^{
        NSArray *routes = routingController.availableRoutes;
        BOOL switched = NO;
        
        if (preferredSpeakerRouteName) {
            MPAVRoute *preferredSpeaker = [self getPreferredRoute:routes];
            if (preferredSpeaker) {
                if (preferredSpeaker.requiresPassword && preferredSpeakerPassword) {
                    if ([routingController pickRoute:preferredSpeaker withPassword:preferredSpeakerPassword])
                        return;
                } else {
                    if ([routingController pickRoute:preferredSpeaker]) {
                        [self onConnectedToAirPlaySpeaker];
                        return;
                    }
                }
            }
        }
        
        for (MPAVRoute *route in routes) {
            if (route.requiresPassword)
                continue;
            
            BOOL isAudioOnly = [self isRouteAudioOnly:route];
            if ((isAudioOnly && audioOnlyFirst) || !audioOnlyFirst) {
                if ([routingController pickRoute:route]) {
                    if (isAudioOnly)
                        NSLog(@"Succesfully switched to audio-only speaker");
                    else
                        NSLog(@"Succesfully switched to speaker");
                    [self onConnectedToAirPlaySpeaker];
                    switched = YES;
                    break;
                } else {
                    NSLog(@"Failed, trying next speaker if available");
                }
            }
        }
        
        if (!switched && audioOnlyFirst) {
            for (MPAVRoute *route in routes) {
                if (route.requiresPassword)
                    continue;
                
                BOOL isAirPlay = [self isAirPlayOutput:route];
                if (isAirPlay) {
                    if ([routingController pickRoute:route]) {
                        NSLog(@"Succesfully switched to speaker");
                        [self onConnectedToAirPlaySpeaker];
                        switched = YES;
                        break;
                    } else {
                        NSLog(@"Failed, trying next AirPlay device");
                    }
                }
            }
        }
        
        routingController.discoveryMode = oldDiscoveryMode;
        
        if (!switched) {
            if (retryCount >= maxRetryCount) {
                retryCount = 0;
                return;
            } else {
                [self performSelector:@selector(performAction) withObject:nil afterDelay:1.0];
                retryCount++;
            }
        }
    }];
}

-(void)activator:(LAActivator *)activator receiveEvent:(LAEvent *)event {
    if (delay != 0 && [event.name rangeOfString:@"libactivator.network.joined-wifi" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        [self performSelector:@selector(performAction) withObject:nil afterDelay:delay];
    } else {
        [self performSelector:@selector(performAction)];
    }
}

+(void)load {
    notificationCallback(NULL, NULL, NULL, NULL, NULL);
    @autoreleasepool {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, notificationCallback, (CFStringRef) @"com.mohammadag.airplayactivator/preferences_changed", NULL, CFNotificationSuspensionBehaviorCoalesce);
        [[LAActivator sharedInstance] registerListener:[self new] forName:@"com.mohammadag.airplayactivator"];
    }
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