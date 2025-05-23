//
//  NSURL+OCPrivateLink.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 22.04.20.
//  Copyright © 2020 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2020, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import "NSURL+OCPrivateLink.h"
#import "OCCore.h"

@implementation NSURL (OCPrivateLink)

- (OCPrivateLinkFileID)privateLinkFileID
{
	NSArray<NSString *> *pathComponents = nil;
	NSString *privateFileID = nil;

	if ((pathComponents = self.path.pathComponents) != nil)
	{
		if (pathComponents.count > 1)
		{
			if ([[pathComponents objectAtIndex:pathComponents.count-2] isEqual:@"f"])
			{
				privateFileID = pathComponents.lastObject;
			}
		}
	}

	return (privateFileID);
}

- (OCFileIDUniquePrefix)fileIDUniquePrefixFromPrivateLinkInCore:(OCCore *)core isPrefix:(BOOL *)outIsPrefix
{
	// Put any special handling here if the private link fileID
	// is not / no longer identical to FileIDs - or needs conversion
	OCPrivateLinkFileID linkFileID;
	OCFileIDUniquePrefix uniquePrefix = nil;
	BOOL isPrefix = YES;

	if ((linkFileID = self.privateLinkFileID) != nil)
	{
		NSInteger fileIDInt = linkFileID.integerValue;

		if ([[NSString stringWithFormat:@"%lu",fileIDInt] isEqual:linkFileID]) // Fully numeric ID
		{
			uniquePrefix = [NSString stringWithFormat:@"%08lu", fileIDInt]; // Prefix of old server-style fileIDs (f.ex. 00000090ocxif4l0973a, where "00000090" is the numeric file ID and "ocxif4l0973a" is the host ID)
			isPrefix = YES;
		}
		else if (core.useDrives)
		{
			// opencloud-style, non-numeric File ID
			uniquePrefix = linkFileID;
			isPrefix = NO;
		}
	}

	if (outIsPrefix != NULL)
	{
		*outIsPrefix = isPrefix;
	}

	return (uniquePrefix);
}

@end
