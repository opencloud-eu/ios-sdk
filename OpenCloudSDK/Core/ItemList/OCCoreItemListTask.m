//
//  OCCoreItemListTask.m
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

#import "OCCoreItemListTask.h"
#import "OCCore.h"
#import "OCCore+Internal.h"
#import "OCCore+SyncEngine.h"
#import "NSString+OCPath.h"
#import "OCLogger.h"
#import "NSError+OCDAVError.h"
#import "OCCore+ConnectionStatus.h"
#import "OCCore+ItemList.h"
#import "OCMacros.h"
#import "NSProgress+OCExtensions.h"
#import "OCCoreDirectoryUpdateJob.h"

@interface OCCoreItemListTask ()
{
	OCActivityIdentifier _activityIdentifier;
}

@end

@implementation OCCoreItemListTask

#pragma mark - Init & Dealloc
- (instancetype)init
{
	if ((self = [super init]) != nil)
	{
		_cachedSet = [OCCoreItemList new];
		_retrievedSet = [OCCoreItemList new];
	}

	return(self);
}

- (instancetype)initWithCore:(OCCore *)core location:(OCLocation *)location updateJob:(OCCoreDirectoryUpdateJob *)updateJob
{
	if ((self = [self init]) != nil)
	{
		self.core = core;
		self.location = location;
		self.updateJob = updateJob;
	}

	return (self);
}

- (void)update
{
	[_core queueBlock:^{ // Update inside the core's serial queue to make sure we never change the data while the core is also working on it
		[self _update];
	}];
}

- (void)forceUpdateCacheSet
{
	[_core queueBlock:^{
		[self _updateCacheSet];
	}];
}

- (void)_updateCacheSet
{
	// Retrieve items from cache
	if (_core != nil)
	{
		[_core beginActivity:@"update cache set"];

		_cachedSet.state = OCCoreItemListStateStarted;

		[self _cacheUpdateInline:NO notifyChange:YES completionHandler:^{
			[self->_core endActivity:@"update cache set"];
		}];
	}
}

- (void)_cacheUpdateInline:(BOOL)doInline notifyChange:(BOOL)notifyChange completionHandler:(dispatch_block_t)completionHandler
{
	OCMeasureEventBegin(self, @"db.cache", cacheRetrieveRef, @"Retrieve from cache");

	[_core.vault.database retrieveCacheItemsAtLocation:self.location itemOnly:NO completionHandler:^(OCDatabase *db, NSError *error, OCSyncAnchor syncAnchor, NSArray<OCItem *> *items) {
		OCSyncAnchor latestAnchorAtRetrieval = [self->_core retrieveLatestSyncAnchorWithError:NULL];
		OCMeasurementEventReference queueRef = 0;

		OCMeasureEventEnd(self, @"db.cache", cacheRetrieveRef, @"Retrieve from cache");

		if (!doInline)
		{
			OCMeasureEventBegin(self, @"core.queue", inQueueRef, @"Schedule cache update in core queue");
			queueRef = inQueueRef;
		}

		dispatch_block_t workBlock = ^{ // Update inside the core's serial queue to make sure we never change the data while the core is also working on it
			if (!doInline)
			{
				OCMeasureEventEnd(self, @"core.queue", queueRef, @"Start cache update in core queue");
			}

			self->_syncAnchorAtStart = latestAnchorAtRetrieval;

			[self->_cachedSet updateWithError:error items:items];

			if (notifyChange && ((self->_cachedSet.state == OCCoreItemListStateSuccess) || (self->_cachedSet.state == OCCoreItemListStateFailed)))
			{
				if (self.changeHandler != nil)
				{
					self.changeHandler(self->_core, self);
				}
				else
				{
					OCLogWarning(@"OCCoreItemListTask: no changeHandler specified");
				}
			}

			completionHandler();
		};

		if (doInline)
		{
			workBlock();
		}
		else
		{
			[self->_core queueBlock:workBlock];
		}
	}];
}

- (void)forceUpdateRetrievedSet
{
	[_core queueBlock:^{
		[self _updateRetrievedSet];
	}];
}

- (void)_updateRetrievedSet
{
	// Request item list from server
	if (_core != nil)
	{
		_retrievedSet.state = OCCoreItemListStateStarted;

		void (^RetrieveItems)(OCItem *parentDirectoryItem) = ^(OCItem *parentDirectoryItem){

			OCMeasureEventBegin(self, @"core.queue", propFindEvenRef, @"Queuing PROPFIND");

			[self->_core queueConnectivityBlock:^{
				[self->_core queueRequestJob:^(dispatch_block_t completionHandler) {
					NSProgress *retrievalProgress;

					OCMeasureEventEnd(self, @"core.queue", propFindEvenRef, @"Beginning PROPFIND");

					OCMeasureEventBegin(self, @"network.propfind", propFindEvenRef, ([NSString stringWithFormat:@"Starting PROPFIND for %@", self.location]));

					retrievalProgress = [self->_core.connection retrieveItemListAtLocation:self.location depth:1 options:[NSDictionary dictionaryWithObjectsAndKeys:
						// For background scan jobs, wait with scheduling until there is connectivity
						((self.updateJob.isForQuery) ? self.core.connection.propFindSignals : self.core.connection.actionSignals), 	OCConnectionOptionRequiredSignalsKey,

						// Schedule in a particular group
						((self.groupID != nil) ? self.groupID : nil), 									OCConnectionOptionGroupIDKey,
					nil] completionHandler:^(NSError *error, NSArray<OCItem *> *items) {
						OCMeasureEventEnd(self, @"network.propfind", propFindEvenRef, ([NSString stringWithFormat:@"Completed PROPFIND for %@", self.location]));

						if (self.core.state != OCCoreStateRunning)
						{
							// Skip processing the response if the core is not starting or running
							self.retrievedSet.state = OCCoreItemListStateNew;
							completionHandler(); // we're done for now, make sure the queue doesn't get stuck
							return;
						}

						[self->_core beginActivity:@"update retrieved set"];

						OCMeasureEventBegin(self, @"core.queue", queueRef, ([NSString stringWithFormat:@"Queue update of retrieved set for %@", self.location]));

						[self->_core queueBlock:^{
							if (self.core.state != OCCoreStateRunning)
							{
								// Skip processing the response if the core is not starting or running
								self.retrievedSet.state = OCCoreItemListStateNew;
								completionHandler(); // we're done for now, make sure the queue doesn't get stuck

								[self->_core endActivity:@"update retrieved set"];
								return;
							}

							// Update inside the core's serial queue to make sure we never change the data while the core is also working on it
							OCMeasureEventEnd(self, @"core.queue", queueRef, ([NSString stringWithFormat:@"Processing update of retrieved set for %@", self.location]));

							OCMeasureEventBegin(self, @"itemlist.update-from-propfind", propFindRef, ([NSString stringWithFormat:@"Update retrieved set for %@", self.location]));

							OCSyncAnchor latestSyncAnchor = [self.core retrieveLatestSyncAnchorWithError:NULL];

							if ((latestSyncAnchor != nil) && (![latestSyncAnchor isEqualToNumber:self.syncAnchorAtStart]))
							{
								OCTLogDebug(@[@"ItemListTask"], @"Sync anchor changed before task finished: latestSyncAnchor=%@ != task.syncAnchorAtStart=%@, path=%@ -> updating inline", latestSyncAnchor, self.syncAnchorAtStart, self.location);

								// Cache set is outdated - update now to avoid unnecessary requests
								OCSyncExec(inlineUpdate, {
									OCMeasureEventBegin(self, @"itemlist.cache-reload", cacheUpdateRef, ([NSString stringWithFormat:@"Start inline cache update for %@", self.location]));
									[self _cacheUpdateInline:YES notifyChange:NO completionHandler:^{
										OCMeasureEventEnd(self, @"itemlist.cache-reload", cacheUpdateRef, ([NSString stringWithFormat:@"Done inline cache update for %@", self.location]));
										OCSyncExecDone(inlineUpdate);
									}];
								});
							}

							// Check for maintenance mode errors
							if ((error==nil) || (error.isDAVException))
							{
								if (error.davError == OCDAVErrorServiceUnavailable)
								{
									[self->_core reportResponseIndicatingMaintenanceMode];
								}
							}

							// Update
							[self->_retrievedSet updateWithError:error items:items];

							if (self->_retrievedSet.state == OCCoreItemListStateSuccess)
							{
								// Update all items with root item
								if (self.location != nil)
								{
									OCItem *rootItem;
									OCItem *cachedRootItem;

									if ((rootItem = self->_retrievedSet.itemsByPath[self.location.path]) != nil)
									{
										if ((cachedRootItem = self->_cachedSet.itemsByFileID[rootItem.fileID]) == nil)
										{
											cachedRootItem = self->_cachedSet.itemsByPath[self.location.path];
										}

										if (cachedRootItem != nil)
										{
											rootItem.localID = cachedRootItem.localID;
										}

										if ((rootItem.type == OCItemTypeCollection) && (items.count > 1))
										{
											for (OCItem *item in items)
											{
												if (item != rootItem)
												{
													item.parentFileID = rootItem.fileID;
													item.parentLocalID = rootItem.localID;
												}
											}
										}

										if (rootItem.parentFileID == nil)
										{
											rootItem.parentFileID = parentDirectoryItem.fileID;
										}

										if (rootItem.parentLocalID == nil)
										{
											rootItem.parentLocalID = parentDirectoryItem.localID;
										}
									}
									else
									{
										OCLogWarning(@"Missing root item for %@", self.location);
									}
								}
								else
								{
									OCLogWarning(@"No path!!");
								}

								self.changeHandler(self->_core, self);
							}

							if (self->_retrievedSet.state == OCCoreItemListStateFailed)
							{
								self.changeHandler(self->_core, self);
							}

							[self->_core endActivity:@"update retrieved set"];

							OCMeasureEventEnd(self, @"itemlist.update-from-propfind", propFindRef, ([NSString stringWithFormat:@"Done updating retrieved set for %@", self.location]));

							completionHandler();
						}];
					}];

					if (retrievalProgress != nil)
					{
						[self.core.activityManager update:[[OCActivityUpdate updatingActivityFor:self] withProgress:retrievalProgress]];
					}
				}];
			}];
		};

		if ([self.location.path isEqual:@"/"])
		{
			RetrieveItems(nil);
		}
		else
		{
			[_core queueBlock:^{ // Update inside the core's serial queue to make sure we never change the data while the core is also working on it
				__block OCItem *parentItem = nil;
				__block NSError *dbError = nil;
				NSArray <OCItem *> *items = nil;

				// Retrieve parent item from cache.
				items = [self->_core.vault.database retrieveCacheItemsSyncAtLocation:self.location.parentLocation itemOnly:YES error:&dbError syncAnchor:NULL];

				if (dbError != nil)
				{
					[self->_retrievedSet updateWithError:dbError items:nil];
				}
				else
				{
					parentItem = items.firstObject;

					if (parentItem == nil)
					{
						// No parent item found - and not the root folder. If the SDK is used to discover directories and request their
						// contents after discovery, this should never happen. However, for direct requests to directories, this may happen.
						// In that case, the parent directory(s) need to be requested first, so that their parent item(s) are known and in
						// the database.
						OCQuery *parentDirectoryQuery = [OCQuery queryForLocation:self.location.parentLocation];

						[parentDirectoryQuery attachMeasurement:self.extractedMeasurement];

						parentDirectoryQuery.changesAvailableNotificationHandler = ^(OCQuery *query) {
							// Remove query once the response from the server arrived
							if (query.state == OCQueryStateIdle)
							{
								// Use root item as parent item
								RetrieveItems(query.rootItem);

								// Remove query from core
								[self->_core stopQuery:query];
							}
						};

						[self->_core startQuery:parentDirectoryQuery];
					}
					else
					{
						// Parent item found in the database
						RetrieveItems(parentItem);
					}
				}
			}];
		}
	}
}

- (void)_update
{
	[_core beginActivity:@"update unstarted sets"];

	if (_cachedSet.state != OCCoreItemListStateStarted)
	{
		// Retrieve items from cache
		[self _updateCacheSet];
	}

	if (_retrievedSet.state != OCCoreItemListStateStarted)
	{
		// Request item list from server
		[self _updateRetrievedSet];
	}

	[_core endActivity:@"update unstarted sets"];
}

- (void)updateIfNew
{
	if (_cachedSet.state == OCCoreItemListStateNew)
	{
		// Retrieve items from cache
		_cachedSet.state = OCCoreItemListStateStarted;
		[self _updateCacheSet];
	}

	if (_retrievedSet.state == OCCoreItemListStateNew)
	{
		// Request item list from server
		_retrievedSet.state = OCCoreItemListStateStarted;
		[self _updateRetrievedSet];
	}
}

#pragma mark - Activity source
- (OCActivityIdentifier)activityIdentifier
{
	if (_activityIdentifier == nil)
	{
		_activityIdentifier = [@"ItemListTask:" stringByAppendingString:NSUUID.UUID.UUIDString];
	}

	return (_activityIdentifier);
}

- (OCActivity *)provideActivity
{
	OCActivity *activity = [OCActivity withIdentifier:self.activityIdentifier description:[NSString stringWithFormat:OCLocalizedString(@"Retrieving items for %@",nil), self.location.path] statusMessage:nil ranking:0];

	activity.progress = NSProgress.indeterminateProgress;

	return (activity);
}

@end
