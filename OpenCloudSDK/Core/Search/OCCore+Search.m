//
//  OCCore+Search.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 31.10.24.
//  Copyright © 2024 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2024, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import "OCCore+Search.h"
#import "OCConnection.h"
#import "NSError+OCError.h"
#import "NSArray+OCFiltering.h"
#import "OCMacros.h"

@implementation OCCore (Search)

- (nullable OCSearchResult *)searchFilesWithPattern:(NSString *)pattern limit:(nullable NSNumber *)limit options:(nullable NSDictionary<OCConnectionOptionKey,id> *)options
{
	OCSearchResult *searchResult = [[OCSearchResult alloc] initWithKQLQuery:pattern core:self];

	if (self.connectionStatus != OCCoreConnectionStatusOnline)
	{
		searchResult.error = OCError(OCErrorNotAvailableOffline);
	}
	else
	{
		__weak OCCore *weakSelf = self;

		OCProgress *progress = [self.connection searchFilesWithPattern:pattern limit:limit options:options resultTarget:[OCEventTarget eventTargetWithEphermalEventHandlerBlock:^(OCEvent * _Nonnull event, id  _Nonnull sender) {
			NSArray<OCItem *> *items;

			if ((items = OCTypedCast(event.result, NSArray)) != nil)
			{
				// Vault spaces are encrypted by the web vault app, so their contents are not shown
				event.result = [items filteredArrayUsingBlock:^BOOL(OCItem * _Nonnull item, BOOL * _Nonnull stop) {
					return ((item.driveID == nil) || ![weakSelf driveWithIdentifier:item.driveID attachedOnly:NO].isVault);
				}];
			}

			[searchResult _handleResultEvent:event];
		} userInfo:nil ephermalUserInfo:nil]];

		searchResult.progress = progress;
	}

	return (searchResult);
}

@end
