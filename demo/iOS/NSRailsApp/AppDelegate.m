//
//  AppDelegate.m
//  NSRailsApp
//
//  Created by Dan Hassin on 2/20/12.
//  Copyright (c) 2012 InContext LLC. All rights reserved.
//

#import "AppDelegate.h"

#import "PostsViewController.h"

#import "NSRConfig.h"

@implementation AppDelegate

@synthesize window = _window;
@synthesize navigationController = _navigationController;

- (BOOL) application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	//set app URL for defaultConfig -> will apply globally to all NSRails methods
	
	//live app! check it out
	[[NSRConfig defaultConfig] setAppURL:@"http://nsrails.com/"];
	
	//for local server:
	//[[NSRConfig defaultConfig] setAppURL:@"http://localhost:3000/"];
	
	//authentication
	[[NSRConfig defaultConfig] setAppUsername:@"NSRails"];
	[[NSRConfig defaultConfig] setAppPassword:@"iphone"];
	
	
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	
	PostsViewController *masterViewController = [[PostsViewController alloc] initWithNibName:@"PostsViewController" bundle:nil];
	self.navigationController = [[UINavigationController alloc] initWithRootViewController:masterViewController];
	self.window.rootViewController = self.navigationController;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void) alertForError:(NSError *)e
{
	//common method to display an alert given an NSRails error
	
	NSMutableString *errorString = [NSMutableString string];
	
	//get the dictionary of validation errors, if any
	NSDictionary *validationErrors = [[e userInfo] objectForKey:NSRValidationErrorsKey];
	
	if (validationErrors)
	{
		//iterate through each property in dict (keys)
		for (NSString *failedProperty in validationErrors)
		{
			//for each key, it contains an array of reasons that property failed
			for (NSString *reason in [validationErrors objectForKey:failedProperty])
			{
				if ([reason isEqualToString:@"profanity"])
				{
					//if it's profanity, it's profanity. shame!
					[errorString appendString:@"No profanity please! "];
				}
				else
				{
					//otherwise, proper-case the property (it's currently something like "name")
					NSString *properCase = [[[failedProperty substringToIndex:1] uppercaseString] stringByAppendingString:[failedProperty substringFromIndex:1]];
					
					//and add it to the string. message is something like "can't be blank"
					[errorString appendFormat:@"%@ %@. ",properCase,reason];
				}
			}
		}
	}
	else
	{
		//if it's not a validation error, just display the error
		errorString = (NSMutableString *)[e localizedDescription];
	}
	
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
													message:errorString 
												   delegate:nil 
										  cancelButtonTitle:@"OK" 
										  otherButtonTitles:nil];
	[alert show];
}


@end
