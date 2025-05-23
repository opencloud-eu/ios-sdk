//
//  NSDictionary+OCFormEncoding.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 19.09.22.
//  Copyright © 2022 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2022, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import "NSDictionary+OCFormEncoding.h"

@implementation NSDictionary (OCFormEncoding)

- (nullable NSData *)urlFormEncodedData
{
	// Encode dictionary as parameters for POST / PUT HTTP request body data
	NSMutableArray <NSURLQueryItem *> *queryItems = [NSMutableArray array];
	NSURLComponents *urlComponents = [[NSURLComponents alloc] init];

	[self enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL * _Nonnull stop) {
		[queryItems addObject:[NSURLQueryItem queryItemWithName:name value:value]];
	}];

	urlComponents.queryItems = queryItems;

	NSString *encodedString = urlComponents.percentEncodedQuery;
	// NSURLComponents.percentEncodedQuery will NOT
	// - escape "+" as "%2B" because Apple argues that's not what's in the standard and causes issues with normalization (source: http://www.openradar.me/24076063)
	encodedString = [encodedString stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
	// - escape ";" as "%3B" (seen under iOS 17.0.1)
	encodedString = [encodedString stringByReplacingOccurrencesOfString:@";" withString:@"%3B"];

	return ([encodedString dataUsingEncoding:NSUTF8StringEncoding]);
}

@end
