//
//  OCCore+CommandDownload.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 02.08.18.
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
#import "OCSyncActionDownload.h"

@implementation OCCore (CommandDownload)

#pragma mark - Command
- (nullable NSProgress *)downloadItem:(OCItem *)item options:(nullable NSDictionary<OCCoreOption,id> *)options resultHandler:(nullable OCCoreDownloadResultHandler)resultHandler
{
	// Enqueue sync record
	NSProgress *progress;

	progress = [self _enqueueSyncRecordWithAction:[[OCSyncActionDownload alloc] initWithItem:item options:options] cancellable:YES resultHandler:resultHandler];

	return (progress);
}

@end
