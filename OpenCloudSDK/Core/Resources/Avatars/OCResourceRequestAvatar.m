//
//  OCResourceRequestAvatar.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 27.02.21.
//  Copyright © 2021 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2021, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import "OCResourceRequestAvatar.h"
#import "OCResource.h"

@implementation OCResourceRequestAvatar

+ (instancetype)requestAvatarFor:(OCUser *)user maximumSize:(CGSize)requestedMaximumSizeInPoints scale:(CGFloat)scale waitForConnectivity:(BOOL)waitForConnectivity changeHandler:(OCResourceRequestChangeHandler)changeHandler
{
	OCResourceRequestAvatar *request;

	if (scale == 0)
	{
		scale = UIScreen.mainScreen.scale;
	}

	request = [[OCResourceRequestAvatar alloc] initWithType:OCResourceTypeAvatar identifier:user.userIdentifier];
	request.reference = user;

	request.maxPointSize = requestedMaximumSizeInPoints;
	request.scale = scale;

	request.waitForConnectivity = waitForConnectivity;
	request.changeHandler = changeHandler;

	return (request);
}

@end
