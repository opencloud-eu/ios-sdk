//
//  NSError+OpenCloudError.m
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

#import "NSError+OpenCloudError.h"
#import "OCMacros.h"

@implementation NSError (OpenCloudError)

+ (nullable NSError *)errorFromOpenCloudErrorDictionary:(NSDictionary<NSString *, NSString *> *)openCloudErrorDict underlyingError:(nullable NSError *)underlyingError
{
	NSError *error = nil;

	if ([openCloudErrorDict isKindOfClass:NSDictionary.class])
	{
		NSString *openCloudCode;

		if ((openCloudCode = OCTypedCast(openCloudErrorDict[@"code"], NSString)) != nil)
		{
			NSMutableDictionary<NSErrorUserInfoKey, id> *errorUserInfo = [NSMutableDictionary new];
			NSString *message = nil;
			OCError errorCode = OCErrorUnknown;

			errorUserInfo[OCOpenCloudErrorCodeKey] = openCloudCode;

			if ((message = OCTypedCast(openCloudErrorDict[@"message"], NSString)) != nil)
			{
				errorUserInfo[NSLocalizedDescriptionKey] = message;
			}

			// via https://opencloud.dev/services/app-registry/apps/
			if ([openCloudCode isEqual:@"RESOURCE_NOT_FOUND"])
			{
				errorCode = OCErrorResourceNotFound;
			}

			// via https://opencloud.dev/services/app-registry/apps/
			if ([openCloudCode isEqual:@"INVALID_PARAMETER"])
			{
				errorCode = OCErrorInvalidParameter;
			}

			if ([openCloudCode isEqual:@"TOO_EARLY"])
			{
				errorCode = OCErrorItemProcessing;
			}

			if (underlyingError != nil)
			{
				errorUserInfo[NSUnderlyingErrorKey] = underlyingError;
			}

			error = [NSError errorWithDomain:OCErrorDomain code:errorCode userInfo:errorUserInfo];
		}
	}

	if (error == nil)
	{
		error = underlyingError;
	}

	return (error);
}

@end

// NOTE: There is also OCErrorDomain in another file.
NSErrorUserInfoKey OCOpenCloudErrorCodeKey = @"openCloudErrorCode";
