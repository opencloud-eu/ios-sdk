//
//  OCCore+ItemUpdates.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 24.10.18.
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

#import "OCMacros.h"
#import "OCLogger.h"

#import "OCCore+SyncEngine.h"
#import "OCCore+ItemUpdates.h"
#import "OCCore+Internal.h"
#import "OCCore+ItemList.h"
#import "OCQuery+Internal.h"
#import "OCCore+FileProvider.h"
#import "OCCore+ItemPolicies.h"
#import "NSString+OCPath.h"

@implementation OCCore (ItemUpdates)

- (void)performUpdatesForAddedItems:(nullable NSArray<OCItem *> *)addedItems
		       removedItems:(nullable NSArray<OCItem *> *)removedItems
		       updatedItems:(nullable NSArray<OCItem *> *)updatedItems
		   refreshLocations:(nullable NSArray<OCLocation *> *)refreshLocations
		      newSyncAnchor:(nullable OCSyncAnchor)newSyncAnchor
		 beforeQueryUpdates:(nullable OCCoreItemUpdateAction)beforeQueryUpdatesAction
		  afterQueryUpdates:(nullable OCCoreItemUpdateAction)afterQueryUpdatesAction
		 queryPostProcessor:(nullable OCCoreItemUpdateQueryPostProcessor)queryPostProcessor
		       skipDatabase:(BOOL)skipDatabase
{
	// Discard empty updates
	if ((addedItems.count==0) && (removedItems.count == 0) && (updatedItems.count == 0) && (refreshLocations.count == 0) &&
	     (beforeQueryUpdatesAction == nil) && (afterQueryUpdatesAction == nil) && (queryPostProcessor == nil))
	{
		return;
	}

	// Begin
	[self beginActivity:@"Perform item and query updates"];

	// Ensure protection
	if (newSyncAnchor == nil)
	{
		// Make sure updates are wrapped into -incrementSyncAnchorWithProtectedBlock
		[self incrementSyncAnchorWithProtectedBlock:^NSError *(OCSyncAnchor previousSyncAnchor, OCSyncAnchor newSyncAnchor) {
			[self performUpdatesForAddedItems:addedItems removedItems:removedItems updatedItems:updatedItems refreshLocations:refreshLocations newSyncAnchor:newSyncAnchor beforeQueryUpdates:beforeQueryUpdatesAction afterQueryUpdates:afterQueryUpdatesAction queryPostProcessor:queryPostProcessor skipDatabase:skipDatabase];

			return ((NSError *)nil);
		} completionHandler:^(NSError *error, OCSyncAnchor previousSyncAnchor, OCSyncAnchor newSyncAnchor) {
			[self endActivity:@"Perform item and query updates"];
		}];

		return;
	}

	// Update version seeds for updated and removed items
	[updatedItems makeObjectsPerformSelector:@selector(updateSeed)];
	[removedItems makeObjectsPerformSelector:@selector(updateSeed)];

	// Update metaData table and queries
	if ((addedItems.count > 0) || (removedItems.count > 0) || (updatedItems.count > 0) || (beforeQueryUpdatesAction!=nil))
	{
		__block NSError *databaseError = nil;

		OCWaitInit(cacheUpdatesGroup);

		// Update metaData table with changes from the parameter set
		if (!skipDatabase)
		{
			OCWaitWillStartTask(cacheUpdatesGroup);

			[self.database performBatchUpdates:^(OCDatabase *database){
				if (removedItems.count > 0)
				{
					[self.database removeCacheItems:removedItems syncAnchor:newSyncAnchor completionHandler:^(OCDatabase *db, NSError *error) {
						if (error != nil) { databaseError = error; }
					}];
				}

				if (addedItems.count > 0)
				{
					[self.database addCacheItems:addedItems syncAnchor:newSyncAnchor completionHandler:^(OCDatabase *db, NSError *error) {
						if (error != nil) { databaseError = error; }
					}];
				}

				if (updatedItems.count > 0)
				{
					[self.database updateCacheItems:updatedItems syncAnchor:newSyncAnchor completionHandler:^(OCDatabase *db, NSError *error) {
						if (error != nil) { databaseError = error; }
					}];
				}

				// Run preflight action
				if (beforeQueryUpdatesAction != nil)
				{
					OCWaitWillStartTask(cacheUpdatesGroup);

					beforeQueryUpdatesAction(^{
						OCWaitDidFinishTask(cacheUpdatesGroup);
					});
				}

				return ((NSError *)nil);
			} completionHandler:^(OCDatabase *db, NSError *error) {
				if (error != nil)
				{
					OCLogError(@"IU: error updating metaData database after sync engine result handler pass: %@", error);
				}

				OCWaitDidFinishTask(cacheUpdatesGroup);
			}];
		}

		// Wait for updates to complete
		OCWaitForCompletion(cacheUpdatesGroup);
	}

	if ((beforeQueryUpdatesAction!=nil) && skipDatabase)
	{
		// Run preflight action when database should be skipped and beforeQueryUpdatesAction did not yet run
		OCSyncExec(waitForUpdates, {
			beforeQueryUpdatesAction(^{
				OCSyncExecDone(waitForUpdates);
			});
		});
	}

	// Update queries
	if ((addedItems.count > 0) || (removedItems.count > 0) || (updatedItems.count > 0) || (afterQueryUpdatesAction!=nil) || (queryPostProcessor!=nil))
	{
		NSArray <OCItem *> *theRemovedItems = removedItems;

		[self beginActivity:@"Item Updates - update queries"];

		[self queueBlock:^{
			OCCoreItemList *addedItemList   = nil;
			OCCoreItemList *removedItemList = nil;
			OCCoreItemList *updatedItemList = nil;
			NSArray <OCItem *> *removedItems = theRemovedItems;
			__block NSMutableArray <OCItem *> *addedUpdatedRemovedItems = nil;
			NSMutableArray <OCItem *> *relocatedItems = nil;
			NSMutableArray <OCItem *> *movedFolderItems = nil;

			// Support for relocated items
			for (OCItem *updatedItem in updatedItems)
			{
				// Item has previous path
				if (updatedItem.previousPath != nil)
				{
					// Has the parent folder changed?
					if (![updatedItem.path.stringByDeletingLastPathComponent isEqual:updatedItem.previousPath.stringByDeletingLastPathComponent])
					{
						OCItem *reMovedItem;

						// Make a decoupled copy of the item, replace its path and add it to relocatedItems
						if ((reMovedItem = [OCItem itemFromSerializedData:updatedItem.serializedData]) != nil)
						{
							reMovedItem.path = updatedItem.previousPath;
							reMovedItem.removed = YES;

							if (relocatedItems == nil) { relocatedItems = [NSMutableArray new]; }
							[relocatedItems addObject:reMovedItem];
						}
					}

					// Is this a moved folder?
					if (updatedItem.type == OCItemTypeCollection)
					{
						if (movedFolderItems == nil) { movedFolderItems = [NSMutableArray new]; }
						[movedFolderItems addObject:updatedItem];
					}
				}
			}

			if (relocatedItems != nil)
			{
				// Add any specially prepared relocatedItems to the list of removedItems
				if (removedItems != nil)
				{
					[relocatedItems addObjectsFromArray:removedItems];
				}

				removedItems = relocatedItems;
			}

			// Populate item lists
			addedItemList   = ((addedItems.count>0)   ? [OCCoreItemList itemListWithItems:addedItems]   : nil);
			removedItemList = ((removedItems.count>0) ? [OCCoreItemList itemListWithItems:removedItems] : nil);
			updatedItemList = ((updatedItems.count>0) ? [OCCoreItemList itemListWithItems:updatedItems] : nil);

			void (^BuildAddedUpdatedRemovedItemList)(void) = ^{
				if (addedUpdatedRemovedItems==nil)
				{
					addedUpdatedRemovedItems = [NSMutableArray arrayWithCapacity:(addedItemList.items.count + updatedItemList.items.count + removedItemList.items.count)];

					if (removedItemList!=nil)
					{
						[addedUpdatedRemovedItems addObjectsFromArray:removedItemList.items];
					}

					if (addedItemList!=nil)
					{
						[addedUpdatedRemovedItems addObjectsFromArray:addedItemList.items];
					}

					if (updatedItemList!=nil)
					{
						[addedUpdatedRemovedItems addObjectsFromArray:updatedItemList.items];
					}
				}
			};

			NSArray *queries;
			@synchronized(self->_queries)
			{
				queries = [self->_queries copy];
			}

			for (OCQuery *query in queries)
			{
				// Protect full query results against modification (-setFullQueryResults: is protected using @synchronized(query), too)
				@synchronized(query)
				{
					// Queries targeting directories
					OCLocation *queryLocation = query.queryLocation;
					OCPath queryPath;

					if ((queryPath = queryLocation.path) != nil)
					{
						// Find moved observed folders
						for (OCItem *movedFolderItem in movedFolderItems)
						{
							OCPath previousPath = movedFolderItem.previousPath;

							if ((previousPath != nil) &&
							    [queryPath isEqual:movedFolderItem.previousPath] &&
							    OCDriveIDIsIdentical(queryLocation.driveID, movedFolderItem.driveID))
							{
								query.queryLocation = movedFolderItem.location;
								queryLocation = query.queryLocation;
							}
						}
					}

					if ((queryPath = queryLocation.path) != nil)
					{
						// Create drive-specific item lists
						OCDriveID queryDriveID = OCDriveIDWrap(queryLocation.driveID);
						OCCoreItemList *driveAddedItemList   = addedItemList.itemListsByDriveID[queryDriveID];
						OCCoreItemList *driveRemovedItemList = removedItemList.itemListsByDriveID[queryDriveID];
						OCCoreItemList *driveUpdatedItemList = updatedItemList.itemListsByDriveID[queryDriveID];

						// Only update queries that ..
						if ((query.state == OCQueryStateIdle) || // .. have already gone through their complete, initial content update.
						    ((query.state == OCQueryStateWaitingForServerReply) && (self.connectionStatus != OCCoreConnectionStatusOnline)) || // .. have not yet been able to factor in server replies because the connection isn't online.
						    ((query.state == OCQueryStateContentsFromCache) && (self.connectionStatus != OCCoreConnectionStatusOnline))) // .. have not yet been able to go through their complete, initial content update because the connection isn't online.
						{
							__block NSMutableArray <OCItem *> *updatedFullQueryResults = nil;
							__block OCCoreItemList *updatedFullQueryResultsItemList = nil;

							void (^GetUpdatedFullResultsReady)(void) = ^{
								if (updatedFullQueryResults == nil)
								{
									NSMutableArray <OCItem *> *fullQueryResults;

									if ((fullQueryResults = query.fullQueryResults) != nil)
									{
										updatedFullQueryResults = [fullQueryResults mutableCopy];
									}
									else
									{
										updatedFullQueryResults = [NSMutableArray new];
									}
								}

								if (updatedFullQueryResultsItemList == nil)
								{
									updatedFullQueryResultsItemList = [OCCoreItemList itemListWithItems:updatedFullQueryResults];
								}
							};

							if ((driveAddedItemList != nil) && (driveAddedItemList.itemsByParentPaths[queryPath].count > 0))
							{
								// Items were added in the target path of this query
								GetUpdatedFullResultsReady();

								for (OCItem *item in driveAddedItemList.itemsByParentPaths[queryPath])
								{
									if (!query.includeRootItem && [item.path isEqual:queryPath])
									{
										// Respect query.includeRootItem for special case "/" and don't include root items if not wanted
										continue;
									}

									[updatedFullQueryResults addObject:item];
								}
							}

							if (driveRemovedItemList != nil)
							{
								if (driveRemovedItemList.itemsByParentPaths[queryPath].count > 0)
								{
									// Items were removed in the target path of this query
									GetUpdatedFullResultsReady();

									for (OCItem *item in driveRemovedItemList.itemsByParentPaths[queryPath])
									{
										if (item.path != nil)
										{
											OCItem *removeItem;

											if ((removeItem = updatedFullQueryResultsItemList.itemsByLocalID[item.localID]) != nil)
											{
												[updatedFullQueryResults removeObjectIdenticalTo:removeItem];
											}
											else if ((removeItem = updatedFullQueryResultsItemList.itemsByFileID[item.fileID]) != nil)
											{
												[updatedFullQueryResults removeObjectIdenticalTo:removeItem];
											}
										}
									}
								}

								if (driveRemovedItemList.itemsByPath[queryPath] != nil)
								{
									if (driveAddedItemList.itemsByPath[queryPath] != nil)
									{
										// Handle replacement scenario
										query.rootItem = driveAddedItemList.itemsByPath[queryPath];
									}
									else
									{
										// The target of this query was removed
										updatedFullQueryResults = [NSMutableArray new];
										query.state = OCQueryStateTargetRemoved;
									}
								}

								// Check if a parent folder of the queryPath has been removed
								if (query.state != OCQueryStateTargetRemoved)
								{
									for (OCItem *removedItem in driveRemovedItemList.items)
									{
										OCPath removedItemPath = removedItem.path;

										if (removedItemPath.isNormalizedDirectoryPath && [queryPath hasPrefix:removedItemPath])
										{
											// A parent folder of this query has been removed
											updatedFullQueryResults = [NSMutableArray new];
											query.state = OCQueryStateTargetRemoved;

											break;
										}
									}
								}
							}

							if ((driveUpdatedItemList != nil) && (query.state != OCQueryStateTargetRemoved))
							{
								OCItem *updatedRootItem = nil;

								GetUpdatedFullResultsReady();

								if ((driveUpdatedItemList.itemsByParentPaths[queryPath].count > 0) || // path match
								    ([driveUpdatedItemList.itemLocalIDsSet intersectsSet:updatedFullQueryResultsItemList.itemLocalIDsSet])) // Contained localID match
								{
									// Items were updated
									for (OCItem *item in driveUpdatedItemList.itemsByParentPaths[queryPath])
									{
										if (!query.includeRootItem && [item.path isEqual:queryPath])
										{
											// Respect query.includeRootItem for special case "/" and don't include root items if not wanted
											continue;
										}

										if (item.path != nil)
										{
											OCItem *reMoveItem = nil;

											if ((reMoveItem = updatedFullQueryResultsItemList.itemsByFileID[item.fileID]) == nil)
											{
												reMoveItem = updatedFullQueryResultsItemList.itemsByLocalID[item.localID];
											}

											if (reMoveItem != nil)
											{
												NSUInteger replaceAtIndex;

												// Replace if found
												if ((replaceAtIndex = [updatedFullQueryResults indexOfObjectIdenticalTo:reMoveItem]) != NSNotFound)
												{
													[updatedFullQueryResults removeObjectAtIndex:replaceAtIndex];
													if (!item.removed)
													{
														[updatedFullQueryResults insertObject:item atIndex:replaceAtIndex];
													}
												}
												else
												{
													if (!item.removed)
													{
														[updatedFullQueryResults addObject:item];
													}
												}
											}
											else
											{
												if (!item.removed)
												{
													[updatedFullQueryResults addObject:item];
												}
											}
										}
									}
								}

								if ((updatedRootItem = driveUpdatedItemList.itemsByPath[queryPath]) != nil)
								{
									// Root item of query was updated
									query.rootItem = updatedRootItem;

									if (query.includeRootItem)
									{
										OCItem *removeItem;

										if ((removeItem = updatedFullQueryResultsItemList.itemsByPath[queryPath]) != nil)
										{
											[updatedFullQueryResults removeObject:removeItem];
										}

										if ([updatedFullQueryResults indexOfObjectIdenticalTo:updatedRootItem] == NSNotFound)
										{
											[updatedFullQueryResults addObject:updatedRootItem];
										}
									}
								}
							}

							if (updatedFullQueryResults != nil)
							{
								query.fullQueryResults = updatedFullQueryResults;
							}
						}
					}

					// Queries targeting items
					if (query.queryItem != nil)
					{
						// Only update queries that have already gone through their complete, initial content update
						if ((query.state == OCQueryStateIdle) ||
						    (query.state == OCQueryStateTargetRemoved)) // An item could appear removed temporarily when it was moved on the server and the item has not yet been seen by the core in its new location
						{
							OCPath queryItemPath = query.queryItem.path;
							OCLocalID queryItemLocalID = query.queryItem.localID;
							OCDriveID queryItemDriveID = OCDriveIDWrap(query.queryItem.driveID);
							OCItem *resultItem = nil;
							OCItem *setNewItem = nil;

							OCCoreItemList *itemQueryAddedItemList   = addedItemList.itemListsByDriveID[queryItemDriveID];
							OCCoreItemList *itemQueryRemovedItemList = removedItemList.itemListsByDriveID[queryItemDriveID];
							OCCoreItemList *itemQueryUpdatedItemList = updatedItemList.itemListsByDriveID[queryItemDriveID];

							if (itemQueryAddedItemList!=nil)
							{
								if ((resultItem = itemQueryAddedItemList.itemsByPath[queryItemPath]) != nil)
								{
									setNewItem = resultItem;
								}
								else if ((resultItem = itemQueryAddedItemList.itemsByLocalID[queryItemLocalID]) != nil)
								{
									setNewItem = resultItem;
								}
							}

							if (itemQueryUpdatedItemList!=nil)
							{
								if ((resultItem = itemQueryUpdatedItemList.itemsByPath[queryItemPath]) != nil)
								{
									setNewItem = resultItem;
								}
								else if ((resultItem = itemQueryUpdatedItemList.itemsByLocalID[queryItemLocalID]) != nil)
								{
									setNewItem = resultItem;
								}
							}

							if (setNewItem != nil)
							{
								query.state = OCQueryStateIdle;
								query.queryItem = setNewItem;
								query.fullQueryResults = [NSMutableArray arrayWithObject:setNewItem];
							}
							else
							{
								if (itemQueryRemovedItemList!=nil)
								{
									if ((itemQueryRemovedItemList.itemsByPath[queryItemPath] != nil) || (itemQueryRemovedItemList.itemsByLocalID[queryItemLocalID] != nil))
									{
										query.state = OCQueryStateTargetRemoved;
										query.fullQueryResults = [NSMutableArray new];
									}
								}
							}
						}
					}

					// Queries targeting sync anchors
					if ((query.querySinceSyncAnchor != nil) && (newSyncAnchor!=nil))
					{
						BuildAddedUpdatedRemovedItemList();

						if (addedUpdatedRemovedItems.count > 0)
						{
							[query performUpdates:^{
								query.state = OCQueryStateWaitingForServerReply;

								[query mergeItemsToFullQueryResults:addedUpdatedRemovedItems syncAnchor:newSyncAnchor];

								query.state = OCQueryStateIdle;

								[query setNeedsRecomputation];
							}];
						}
					}

					// Custom queries
					if (query.isCustom && ((addedItemList!=nil) || (updatedItemList!=nil) || (removedItemList!=nil)))
					{
						[query updateWithAddedItems:addedItemList updatedItems:updatedItemList removedItems:removedItemList];
					}

					// Apply postprocessing on queries
					if (queryPostProcessor != nil)
					{
						queryPostProcessor(self, query, addedItemList, removedItemList, updatedItemList);
					}
				}
			}

			// Run postflight action
			if (afterQueryUpdatesAction != nil)
			{
				afterQueryUpdatesAction(^{
					[self endActivity:@"Item Updates - update queries"];
				});
			}
			else
			{
				[self endActivity:@"Item Updates - update queries"];
			}

			// Signal file provider
			if (self.postFileProviderNotifications && !skipDatabase)
			{
				BuildAddedUpdatedRemovedItemList();

				if (addedUpdatedRemovedItems.count > 0)
				{
					[self signalChangesToFileProviderForItems:addedUpdatedRemovedItems];
				}
			}
		}];
	}

	// - Fetch updated directory contents as needed
	if (refreshLocations.count > 0)
	{
		for (OCLocation *location in refreshLocations)
		{
			// Ensure the sync anchor was updated following these updates before triggering a refresh
			[self scheduleUpdateScanForLocation:location.normalizedDirectoryPathLocation waitForNextQueueCycle:YES];
		}
	}

	// Trigger item policies
	NSArray <OCItem *> *newChangedAndDeletedItems = nil;

	#define AddArrayToNewAndChanged(itemArray) \
		if (itemArray.count > 0) \
		{ \
			if (newChangedAndDeletedItems == nil) \
			{ \
				newChangedAndDeletedItems = itemArray; \
			} \
			else \
			{ \
				newChangedAndDeletedItems = [newChangedAndDeletedItems arrayByAddingObjectsFromArray:itemArray]; \
			} \
		} \

	AddArrayToNewAndChanged(addedItems);
	AddArrayToNewAndChanged(updatedItems);
//	AddArrayToNewAndChanged(removedItems);

	if (newChangedAndDeletedItems.count > 0)
	{
		[self runPolicyProcessorsOnNewUpdatedAndDeletedItems:newChangedAndDeletedItems forTrigger:OCItemPolicyProcessorTriggerItemsChanged];
	}

	// Initiate an IPC change notification
	if (!skipDatabase)
	{
		[self postIPCChangeNotification];
	}

	[self endActivity:@"Perform item and query updates"];
}

@end
