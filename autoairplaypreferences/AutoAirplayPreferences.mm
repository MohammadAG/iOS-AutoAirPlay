#import <Preferences/Preferences.h>

@interface AutoAirplayPreferencesListController: PSListController {
}
@end

@implementation AutoAirplayPreferencesListController
- (id)specifiers {
	if(_specifiers == nil) {
		_specifiers = [[self loadSpecifiersFromPlistName:@"AutoAirplayPreferences" target:self] retain];
	}
	return _specifiers;
}

- (void)sourceOnGithub {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/MohammadAG/iOS-AutoAirPlay"]];
}
@end

// vim:ft=objc
