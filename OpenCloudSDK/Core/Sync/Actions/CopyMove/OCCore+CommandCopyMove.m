//
//  OCCore+CommandCopyMove.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 19.06.18.
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
#import "OCSyncActionCopyMove.h"

@implementation OCCore (CommandCopyMove)

#pragma mark - Commands
- (nullable NSProgress *)copyItem:(OCItem *)item to:(OCItem *)parentItem withName:(NSString *)name options:(nullable NSDictionary<OCCoreOption,id> *)options resultHandler:(nullable OCCoreActionResultHandler)resultHandler
{
	if ((item == nil) || (name == nil) || (parentItem == nil)) { return(nil); }

	return ([self _enqueueSyncRecordWithAction:[[OCSyncActionCopy alloc] initWithItem:item targetName:name targetParentItem:parentItem isRename:NO] cancellable:NO resultHandler:resultHandler]);
}

- (nullable NSProgress *)moveItem:(OCItem *)item to:(OCItem *)parentItem withName:(NSString *)name options:(nullable NSDictionary<OCCoreOption,id> *)options resultHandler:(nullable OCCoreActionResultHandler)resultHandler
{
	if ((item == nil) || (name == nil) || (parentItem == nil)) { return(nil); }

	return ([self _enqueueSyncRecordWithAction:[[OCSyncActionMove alloc] initWithItem:item targetName:name targetParentItem:parentItem isRename:NO] cancellable:NO resultHandler:resultHandler]);
}

- (nullable NSProgress *)renameItem:(OCItem *)item to:(NSString *)newFileName options:(nullable NSDictionary<OCCoreOption,id> *)options resultHandler:(nullable OCCoreActionResultHandler)resultHandler
{
	__block OCItem *parentItem = nil;

	OCSyncExec(cacheItemRetrieval, {
		[self.vault.database retrieveCacheItemForFileID:item.parentFileID completionHandler:^(OCDatabase *db, NSError *error, OCSyncAnchor syncAnchor, OCItem *item) {
			if (item != nil)
			{
				parentItem = item;
			}

			OCSyncExecDone(cacheItemRetrieval);
		}];
	});

	if ((item == nil) || (newFileName == nil) || (parentItem == nil)) { return(nil); }

	return ([self _enqueueSyncRecordWithAction:[[OCSyncActionMove alloc] initWithItem:item targetName:newFileName targetParentItem:parentItem isRename:YES] cancellable:NO resultHandler:resultHandler]);
}

@end
