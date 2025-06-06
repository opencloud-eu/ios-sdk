//
//  OCIssue+SyncIssue.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 20.12.18.
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
#import "OCIssue.h"
#import "OCSyncIssue.h"
#import "OCCore.h"
#import "OCMessageQueue.h"

NS_ASSUME_NONNULL_BEGIN

@interface OCIssue (SyncIssue)

+ (instancetype)issueFromSyncIssue:(OCSyncIssue *)syncIssue resolutionResultHandler:(OCCoreSyncIssueResolutionResultHandler)resolutionResultHandler;

+ (instancetype)issueFromSyncIssue:(OCSyncIssue *)syncIssue forCore:(OCCore *)core;

@end

NS_ASSUME_NONNULL_END
