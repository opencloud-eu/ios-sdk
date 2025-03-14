//
//  OCExtensionLocation.m
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

#import "OCExtensionLocation.h"

@implementation OCExtensionLocation

+ (instancetype)locationOfType:(nullable OCExtensionType)type identifier:(nullable OCExtensionLocationIdentifier)identifier
{
	OCExtensionLocation *location = [self new];

	location.type = type;
	location.identifier = identifier;

	return (location);
}

@end
