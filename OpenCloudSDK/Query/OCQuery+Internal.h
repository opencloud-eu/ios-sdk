//
//  OCQuery+Internal.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 02.04.18.
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

#import "OCQuery.h"
#import "OCDataTypes.h"

@interface OCQuery (Internal)

#pragma mark - Update full results
- (void)setFullQueryResults:(NSMutableArray <OCItem *> *)fullQueryResults;
- (NSMutableArray <OCItem *> *)fullQueryResults;

- (void)mergeItemsToFullQueryResults:(NSArray <OCItem *> *)mergeItems syncAnchor:(OCSyncAnchor)syncAnchor;

- (OCCoreItemList *)fullQueryResultsItemList;

#pragma mark - Data source
- (void)updateDataSourceSpecialItemsForItems:(NSArray<OCItem *> *)items;

#pragma mark - Update processed results
- (void)updateProcessedResultsIfNeeded:(BOOL)ifNeeded;
- (OCDataSourceState)_dataSourceState;

#pragma mark - Needs recomputation
- (void)performUpdates:(dispatch_block_t)updates;
- (void)beginUpdates;
- (void)endUpdates;

- (void)setNeedsRecomputation;

#pragma mark - Queue
- (void)queueBlock:(dispatch_block_t)block;

@end
