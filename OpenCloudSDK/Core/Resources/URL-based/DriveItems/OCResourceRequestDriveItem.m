//
//  OCResourceRequestDriveItem.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 12.04.22.
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

#import "OCResourceRequestDriveItem.h"
#import "OCResource.h"
#import "GAOpenGraphFile.h"

@implementation OCResourceRequestDriveItem

+ (instancetype)requestDriveItem:(GADriveItem *)driveItem waitForConnectivity:(BOOL)waitForConnectivity changeHandler:(nullable OCResourceRequestChangeHandler)changeHandler
{
	OCResourceRequestDriveItem *request = [[self alloc] initWithType:OCResourceTypeDriveItem identifier:driveItem.identifier];

	request.version = driveItem.eTag;
	request.structureDescription = driveItem.file.mimeType;

	request.reference = driveItem;

	request.waitForConnectivity = waitForConnectivity;

	request.changeHandler = changeHandler;

	return (request);
}

- (GADriveItem *)driveItem
{
	return (self.reference);
}

@end
