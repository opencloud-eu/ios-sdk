//
//  OCAuthenticationMethod+UIAppExtension.m
//  OpenCloudUI
//
//  Created by Felix Schwarz on 08.06.18.
//  Copyright © 2018 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2018, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import "OCAuthenticationMethod+UIAppExtension.h"

@protocol OCUIApplicationProtocol

+ (id<OCUIApplicationProtocol>)sharedApplication;
- (UIApplicationState)applicationState;

@end

@implementation OCAuthenticationMethod (UIAppExtension)

- (BOOL)cacheSecrets
{
	// Only cache secret if the app is running in the foreground and receiving events
	Class uiApplicationClass;

	if ((uiApplicationClass = NSClassFromString(@"UIApplication")) != nil)
	{
		return ([uiApplicationClass sharedApplication].applicationState == UIApplicationStateActive);
	}

	return (NO);
}

@end
