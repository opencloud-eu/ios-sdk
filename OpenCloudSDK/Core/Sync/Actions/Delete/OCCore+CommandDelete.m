//
//  OCCore+CommandDelete.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 16.06.18.
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

#import "OCCore.h"
#import "OCSyncActionDelete.h"
#import "OCSyncActionLocalCopyDelete.h"

@implementation OCCore (CommandDelete)

#pragma mark - Command
- (nullable NSProgress *)deleteItem:(OCItem *)item requireMatch:(BOOL)requireMatch resultHandler:(nullable OCCoreActionResultHandler)resultHandler
{
	return ([self _enqueueSyncRecordWithAction:[[OCSyncActionDelete alloc] initWithItem:item requireMatch:requireMatch] cancellable:NO resultHandler:resultHandler]);
}

- (nullable NSProgress *)deleteLocalCopyOfItem:(OCItem *)item resultHandler:(nullable OCCoreActionResultHandler)resultHandler
{
	return ([self _enqueueSyncRecordWithAction:[[OCSyncActionLocalCopyDelete alloc] initWithItem:item] cancellable:NO resultHandler:resultHandler]);
}

@end
