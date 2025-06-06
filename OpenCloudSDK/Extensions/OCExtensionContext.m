//
//  OCExtensionContext.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 15.08.18.
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

#import "OCExtensionContext.h"

@implementation OCExtensionContext

+ (instancetype)contextWithLocation:(OCExtensionLocation *)location requirements:(OCExtensionRequirements)requirements preferences:(OCExtensionRequirements)preferences
{
	OCExtensionContext *context = [self new];

	context.location = location;
	context.requirements = requirements;
	context.preferences = preferences;

	return (context);
}

@end
