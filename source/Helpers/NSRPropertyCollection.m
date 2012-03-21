//
//  NSRPropertyCollection.m
//  NSRails
//
//  Created by Dan Hassin on 2/28/12.
//  Copyright (c) 2012 InContext LLC. All rights reserved.
//

#import "NSRPropertyCollection.h"
#import "NSRails.h"
#import "NSObject+Properties.h"
#import "NSString+Inflection.h"

//this is the marker for the propertyEquivalents dictionary if there's no explicit equivalence set
#define NSRNoEquivalentMarker @""

//this will be the marker for any property that has the "-b flag"
//this gonna go in the nestedModelProperties (properties can never have a comma/space in them so we're safe from any conflicts)
#define NSRBelongsToKeyForProperty(prop) [prop stringByAppendingString:@", belongs_to"]


@interface NSRailsModel (internal)

+ (NSString *) railsProperties;
+ (NSString *) NSRailsSync;

@end


@implementation NSRPropertyCollection
@synthesize sendableProperties, retrievableProperties, encodeProperties, decodeProperties;
@synthesize nestedModelProperties, propertyEquivalents;

#pragma mark -
#pragma mark Parser

- (void) addPropertyAsSendable:(NSString *)prop equivalent:(NSString *)equivalent class:(Class)_class
{
	//for sendable, we can only have ONE property which per Rails attribute which is marked as sendable
	//  (otherwise, which property's value should we stick in the json?)
	
	//so, see if there are any other properties defined so far with the same Rails equivalent that are marked as sendable
	NSArray *objs = [propertyEquivalents allKeysForObject:equivalent];
	NSMutableArray *sendables = [NSMutableArray arrayWithObject:prop];
	for (NSString *sendable in objs)
	{
		if ([sendableProperties indexOfObject:sendable] != NSNotFound)
			[sendables addObject:sendable];
	}
	//greater than 1 cause we're including this property
	if (equivalent && sendables.count > 1)
	{
		if ([equivalent isEqualToString:@"id"])
		{
#ifdef NSRLogErrors
			NSLog(@"NSR Warning: Obj-C property %@ (class %@) found to set equivalence with 'id'. This is fine for retrieving but should not be marked as sendable. Ignoring this property on send.", prop, NSStringFromClass(_class));
#endif
		}
		else
		{
#ifdef NSRLogErrors
			NSLog(@"NSR Warning: Multiple Obj-C properties marked as sendable (%@) found pointing to the same Rails attribute ('%@'). Only using data from the first Obj-C property listed. Please fix by only having one sendable property per Rails attribute (you can make the others retrieve-only with the -r flag).", sendables, equivalent);
#endif
		}
	}
	else
	{
		[sendableProperties addObject:prop];
	}
}

- (id) initWithClass:(Class)_class
{
	self = [self initWithClass:_class properties:[_class railsProperties]];
	return self;
}

- (id) initWithClass:(Class)_class properties:(NSString *)props
{
	if ((self = [super init]))
	{		
		//log on param string for testing
		//NSLog(@"found props %@",props);
		
		//initialize property categories
		sendableProperties = [[NSMutableArray alloc] init];
		retrievableProperties = [[NSMutableArray alloc] init];
		nestedModelProperties = [[NSMutableDictionary alloc] init];
		propertyEquivalents = [[NSMutableDictionary alloc] init];
		encodeProperties = [[NSMutableArray alloc] init];
		decodeProperties = [[NSMutableArray alloc] init];
				
		//here begins the code used for parsing the NSRailsSync param string
		
		NSCharacterSet *wn = [NSCharacterSet whitespaceAndNewlineCharacterSet];
		
		//exclusion array for any properties declared as -x (will later remove properties from * definition)
		NSMutableArray *exclude = [NSMutableArray array];
		
		//check to see if we should even consider *
		BOOL markedAll = ([props rangeOfString:@"*"].location != NSNotFound);
		
		//marked as NO for the first time in the loop
		//if a * appeared (markedAll is true), this will enable by the end of the loop and the whole thing will loop again, for the *
		BOOL onStarIteration = NO;
		
		do
		{
			NSMutableArray *elements;
			
			if (onStarIteration)
			{
				//make sure we don't loop again
				onStarIteration = NO;
				markedAll = NO;
				
				NSMutableArray *relevantIvars = [NSMutableArray array];
				
				//go up the class hierarchy
				Class c = _class;				
				while (c != [NSRailsModel class])
				{
					NSString *properties = [c NSRailsSync];
					
					//if there's a *, add all ivars from that class
					if ([properties rangeOfString:@"*"].location != NSNotFound)
						[relevantIvars addObjectsFromArray:[c classPropertyNames]];
					
					//if there's a NoCarryFromSuper, stop the loop right there since we don't want stuff from any more superclasses
					if ([properties rangeOfString:_NSRNoCarryFromSuper_STR].location != NSNotFound)
						break;
					
					c = [c superclass];
				}
				
				
				elements = [NSMutableArray array];
				//go through all the ivars we found
				for (NSString *ivar in relevantIvars)
				{
					//if it hasn't been previously declared (from the first run), add it to the list we have to process
					if (![propertyEquivalents objectForKey:ivar])
					{
						[elements addObject:ivar];
					}
				}
			}
			else
			{
				//if on the first run, split properties by commas ("username=user_name, password"=>["username=user_name","password"]
				elements = [NSMutableArray arrayWithArray:[props componentsSeparatedByString:@","]];
			}
			for (int i = 0; i < elements.count; i++)
			{
				NSString *element = [[elements objectAtIndex:i] stringByTrimmingCharactersInSet:wn];
				
				//skip if there's no NSRailsSync definition (ie, it just inherited NSRailsModel's, so it's not the first time through but it's the same thing as NSRailsModel's)
				if ([element isEqualToString:NSRAILS_BASE_PROPS] && i != 0)
				{
					continue;
				}
				
				//remove any NSRNoCarryFromSuper's to not screw anything up
				NSString *prop = [element stringByReplacingOccurrencesOfString:_NSRNoCarryFromSuper_STR withString:@""];
				
				if (prop.length > 0)
				{
					if ([prop rangeOfString:@"*"].location != NSNotFound)
					{
						//if there's a * in this piece, skip it (we already accounted for stars above)
						continue;
					}
					
					if ([exclude containsObject:prop])
					{
						//if it's been marked with '-x' flag previously, ignore it
						continue;
					}
					
					//prop can be something like "username=user_name:Class -etc"
					//find string sets between =, :, and -
					NSArray *opSplit = [prop componentsSeparatedByString:@"-"];
					NSArray *modSplit = [[opSplit objectAtIndex:0] componentsSeparatedByString:@":"];
					NSArray *eqSplit = [[modSplit objectAtIndex:0] componentsSeparatedByString:@"="];
					
					prop = [[eqSplit objectAtIndex:0] stringByTrimmingCharactersInSet:wn];
					
					//check to see if a class is redefining remoteID (remoteID from NSRailsModel is the first property checked - if it's not the first, give a warning)
					if ([prop isEqualToString:@"remoteID"] && i != 0)
					{
#ifdef NSRLogErrors
						NSLog(@"NSR Warning: Found attempt to define 'remoteID' in NSRailsSync for class %@. This property is reserved by the NSRailsModel superclass and should not be modified. Please fix this; element ignored.", NSStringFromClass(_class));
#endif
						continue;
					}
					
					NSString *options = [opSplit lastObject];
					//if it was marked exclude, add to exclude list in case * was declared, and skip over anything else
					if (opSplit.count > 1 && [options rangeOfString:@"x"].location != NSNotFound)
					{
						[exclude addObject:prop];
						continue;
					}
					
					//if it's sendable & encodable but not part of the class
					BOOL remoteOnly = NO;
					
					//check to see if the listed property even exists
					NSString *ivarType = [_class getPropertyType:prop];
					if (!ivarType)
					{
						//could be that it's encodable (rails-only attr)
						NSString *maybeEncodable = [@"encode" stringByAppendingString:[prop toClassName]];
						if ([_class instancesRespondToSelector:NSSelectorFromString(maybeEncodable)])
						{
							//TODO inform the user that this is going on, there also should be no "retrievable" declared etc
							
							//if it has encode, make sure it's added as encodable & sendable
							[encodeProperties addObject:prop];
							[sendableProperties addObject:prop];
							
							//later on we'll skip those two
							remoteOnly = YES;
						}
						else
						{
#ifdef NSRLogErrors
							NSLog(@"NSR Warning: Property '%@' declared in NSRailsSync for class %@ was not found in this class or in superclasses. Maybe you forgot to @synthesize it? Element ignored.", prop, NSStringFromClass(_class));
#endif
							continue;
						}
					}
					
					//make sure that the property type is not a primitive
					NSString *primitive = [_class propertyIsPrimitive:prop];
					if (primitive)
					{
#ifdef NSRLogErrors
						NSLog(@"NSR Warning: Property '%@' declared in NSRailsSync for class %@ was found to be of primitive type '%@' - please use NSNumber*. Element ignored.", prop, NSStringFromClass(_class), primitive);
#endif
						continue;
					}
					
					//see if there are any = declared
					NSString *equivalent = nil;
					if (eqSplit.count > 1)
					{
						//set the equivalence to the last element after the =
						equivalent = [[eqSplit lastObject] stringByTrimmingCharactersInSet:wn];
						
						[propertyEquivalents setObject:equivalent forKey:prop];
					}
					else
					{
						//if no property explicitly set, make it NSRNoEquivalentMarker
						//later on we'll see if automaticallyCamelize is on for the config and get the equivalence accordingly
						[propertyEquivalents setObject:NSRNoEquivalentMarker forKey:prop];
					}
					
					if (opSplit.count > 1)
					{
						if ([options rangeOfString:@"r"].location != NSNotFound && !remoteOnly)
							[retrievableProperties addObject:prop];
						
						if ([options rangeOfString:@"s"].location != NSNotFound && !remoteOnly)
							[self addPropertyAsSendable:prop equivalent:equivalent class:_class];
						
						if ([options rangeOfString:@"e"].location != NSNotFound && !remoteOnly)
							[encodeProperties addObject:prop];
						
						if ([options rangeOfString:@"d"].location != NSNotFound)
							[decodeProperties addObject:prop];
						
						//add a special marker in nestedModelProperties dict
						if ([options rangeOfString:@"b"].location != NSNotFound)
							[nestedModelProperties setObject:[NSNumber numberWithBool:YES] forKey:NSRBelongsToKeyForProperty(prop)];
					}
					
					//if no options are defined or some are but neither -s nor -r are defined, by default add sendable+retrievable
					if (opSplit.count == 1 ||
						([options rangeOfString:@"s"].location == NSNotFound && [options rangeOfString:@"r"].location == NSNotFound))
					{
						//if remoteOnly, means we already added as sendable and we do NOT want to retrieve it
						if (!remoteOnly)
						{
							[self addPropertyAsSendable:prop equivalent:equivalent class:_class];
							[retrievableProperties addObject:prop];
						}
					}
					
					//see if there was a : declared
					if (modSplit.count > 1)
					{
						NSString *otherModel = [[modSplit lastObject] stringByTrimmingCharactersInSet:wn];
						if (otherModel.length > 0)
						{
							//class entered is not a real class
							if (!NSClassFromString(otherModel))
							{
#ifdef NSRLogErrors
								NSLog(@"NSR Warning: Failed to find class '%@', declared as class for nested property '%@' of class '%@'. Nesting relation not set - will still send any NSRailsModel subclasses correctly but will always retrieve as NSDictionaries. ",otherModel,prop,NSStringFromClass(_class));
#endif
							}
							//class entered is not a subclass of NSRailsModel
							else if (![NSClassFromString(otherModel) isSubclassOfClass:[NSRailsModel class]])
							{
#ifdef NSRLogErrors
								NSLog(@"NSR Warning: '%@' was declared as the class for the nested property '%@' of class '%@', but '%@' is not a subclass of NSRailsModel. Nesting relation not set - won't be able to send or retrieve this property.",otherModel,prop, NSStringFromClass(_class),otherModel);
#endif
							}
							else
							{
								[nestedModelProperties setObject:otherModel forKey:prop];
							}
						}
					}
					else
					{
						//if no : was declared for this property, check to see if we should link it anyway
						
						if ([ivarType isEqualToString:@"NSArray"] ||
							[ivarType isEqualToString:@"NSMutableArray"])
						{
#ifdef NSRLogErrors
							NSLog(@"NSR Warning: Property '%@' in class %@ was found to be an array, but no nesting model was set. Note that without knowing with which models NSR should populate the array, NSDictionaries with the retrieved Rails attributes will be set. If NSDictionaries are desired, to suppress this warning, simply add a colon with nothing following to the property in NSRailsSync... '%@:'",prop,NSStringFromClass(_class),element);
#endif
						}
						else if (!([ivarType isEqualToString:@"NSString"] ||
								   [ivarType isEqualToString:@"NSMutableString"] ||
								   [ivarType isEqualToString:@"NSDictionary"] ||
								   [ivarType isEqualToString:@"NSMutableDictionary"] ||
								   [ivarType isEqualToString:@"NSNumber"] ||
								   [ivarType isEqualToString:@"NSDate"]))
						{
							//must be custom obj, see if its a railsmodel, if it is, link it automatically
							Class c = NSClassFromString(ivarType);
							if (c && [c isSubclassOfClass:[NSRailsModel class]])
							{
								//automatically link that ivar type (ie, Pet) for that property (ie, pets)
								[nestedModelProperties setObject:ivarType forKey:prop];
							}
						}
					}
				}
			}
			
			//if markedAll (a * was encountered somewhere), loop again one more time to add all properties not already listed (*)
			if (markedAll)
				onStarIteration = YES;
		} 
		while (onStarIteration);
		
		// for testing's sake
		//		NSLog(@"-------- %@ ----------",[_class getModelName]);
		//		NSLog(@"list: %@",props);
		//		NSLog(@"sendable: %@",sendableProperties);
		//		NSLog(@"retrievable: %@",retrievableProperties);
		//		NSLog(@"NMP: %@",nestedModelProperties);
		//		NSLog(@"eqiuvalents: %@",propertyEquivalents);
		//		NSLog(@"\n");
	}
	
	return self;
}

#pragma mark -
#pragma mark Special definitions

- (BOOL) propertyIsMarkedBelongsTo:(NSString *)prop
{
	return !![nestedModelProperties objectForKey:NSRBelongsToKeyForProperty(prop)];
}

- (NSString *) equivalenceForProperty:(NSString *)objcProperty
{
	NSString *railsEquivalent = [propertyEquivalents objectForKey:objcProperty];
	if ([railsEquivalent isEqualToString:NSRNoEquivalentMarker])
	{
		return nil;
	}
	return railsEquivalent;
}


#pragma mark -
#pragma mark NSCoding

- (id) initWithCoder:(NSCoder *)aDecoder
{
	if (self = [super init])
	{
		sendableProperties = [aDecoder decodeObjectForKey:@"sendableProperties"];
		retrievableProperties = [aDecoder decodeObjectForKey:@"retrievableProperties"];
		encodeProperties = [aDecoder decodeObjectForKey:@"encodeProperties"];
		decodeProperties = [aDecoder decodeObjectForKey:@"decodeProperties"];
		nestedModelProperties = [aDecoder decodeObjectForKey:@"nestedModelProperties"];
		propertyEquivalents = [aDecoder decodeObjectForKey:@"propertyEquivalents"];
	}
	return self;
}

- (void) encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:sendableProperties forKey:@"sendableProperties"];
	[aCoder encodeObject:retrievableProperties forKey:@"retrievableProperties"];
	[aCoder encodeObject:encodeProperties forKey:@"encodeProperties"];
	[aCoder encodeObject:decodeProperties forKey:@"decodeProperties"];
	[aCoder encodeObject:nestedModelProperties forKey:@"nestedModelProperties"];
	[aCoder encodeObject:propertyEquivalents forKey:@"propertyEquivalents"];
}

#pragma mark -
#pragma mark Dealloc for non-ARC
#ifndef ARC_ENABLED

- (void) dealloc
{	
	[sendableProperties release];
	[retrievableProperties release];
	[encodeProperties release];
	[decodeProperties release];
	[nestedModelProperties release];
	[propertyEquivalents release];
	
	[super dealloc];
}

#endif

@end
