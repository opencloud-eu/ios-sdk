//
//  OCDatabase.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 05.02.18.
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

#import "OCDatabase.h"
#import "OCSQLiteMigration.h"
#import "OCLogger.h"
#import "OCSQLiteTransaction.h"
#import "OCSQLiteQueryCondition.h"
#import "OCItem.h"
#import "OCItem+OCTypeAlias.h"
#import "OCItemVersionIdentifier.h"
#import "OCSyncRecord.h"
#import "NSString+OCPath.h"
#import "NSError+OCError.h"
#import "OCMacros.h"
#import "OCSyncAction.h"
#import "OCSyncLane.h"
#import "OCDrive.h"
#import "OCProcessManager.h"
#import "OCQueryCondition+SQLBuilder.h"
#import "OCAsyncSequentialQueue.h"
#import "NSString+OCSQLTools.h"
#import "OCItemPolicy.h"
#import "OCPlatform.h"
#import "NSArray+OCSegmentedProcessing.h"
#import "OCSQLiteDB+Internal.h"

#import <objc/runtime.h>

@interface OCDatabase ()
{
	NSMutableDictionary <OCSyncRecordID, NSProgress *> *_progressBySyncRecordID;
	NSMutableDictionary <OCSyncRecordID, NSDictionary<OCSyncActionParameter,id> *> *_ephermalParametersBySyncRecordID;
	NSMutableDictionary <OCSyncRecordID, OCSyncRecord *> *_syncRecordsByID;

	OCAsyncSequentialQueue *_openQueue;
	NSInteger _openCount;
	OCPlatformMemoryConfiguration _memoryConfiguration;

	NSMutableSet<OCSyncRecordID> *_knownInvalidSyncRecordIDs;
}

@end

@implementation OCDatabase

@synthesize databaseURL = _databaseURL;

@synthesize removedItemRetentionLength = _removedItemRetentionLength;

@synthesize itemFilter = _itemFilter;

@synthesize sqlDB = _sqlDB;

#pragma mark - Initialization
- (instancetype)initWithURL:(NSURL *)databaseURL
{
	if ((self = [self init]) != nil)
	{
		self.databaseURL = databaseURL;
		self.thumbnailDatabaseURL = [[self.databaseURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"tdb"];

		self.removedItemRetentionLength = 100;

		_selectItemRowsSQLQueryPrefix = @"SELECT mdID, mdTimestamp, syncAnchor, itemData";

		_memoryConfiguration = OCPlatform.current.memoryConfiguration;

		_progressBySyncRecordID = [NSMutableDictionary new];
		_ephermalParametersBySyncRecordID = [NSMutableDictionary new];
		_eventsByDatabaseID = [NSMutableDictionary new];
		_knownInvalidSyncRecordIDs = [NSMutableSet new];

		if (![OCProcessManager isProcessExtension])
		{
			// Set up sync record caching if not running in an extension
			_syncRecordsByID = [NSMutableDictionary new];
		}

		_openQueue = [OCAsyncSequentialQueue new];
		_openQueue.executor = ^(OCAsyncSequentialQueueJob  _Nonnull job, dispatch_block_t  _Nonnull completionHandler) {
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
				job(completionHandler);
			});
		};

		self.sqlDB = [[OCSQLiteDB alloc] initWithURL:databaseURL];
		self.sqlDB.journalMode = OCSQLiteJournalModeWAL;
		[self addSchemas];
	}

	return (self);
}

#pragma mark - Open / Close
- (void)openWithCompletionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	[_openQueue async:^(dispatch_block_t  _Nonnull openQueueCompletionHandler) {
		if (self->_openCount > 0)
		{
			self->_openCount++;

			if (completionHandler != nil)
			{
				completionHandler(self, nil);
			}

			openQueueCompletionHandler();
			return;
		}

		[self.sqlDB openWithFlags:OCSQLiteOpenFlagsDefault completionHandler:^(OCSQLiteDB *db, NSError *error) {
			db.maxBusyRetryTimeInterval = 10; // Avoid busy timeout if another process performs large changes
			[db executeQueryString:@"PRAGMA synchronous=FULL"]; // Force checkpoint / synchronization after every transaction

			if (error == nil)
			{
				NSString *thumbnailsDBPath = self.thumbnailDatabaseURL.path;

				self->_openCount++;

				[self.sqlDB executeQuery:[OCSQLiteQuery query:@"ATTACH DATABASE ? AS 'thumb'" withParameters:@[ thumbnailsDBPath ] resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) { // relatedTo:OCDatabaseTableNameThumbnails
					if (error == nil)
					{
						[self.sqlDB applyTableSchemasWithCompletionHandler:^(OCSQLiteDB *db, NSError *error) {
							if (error == nil)
							{
								[self.sqlDB executeQueryString:@"PRAGMA journal_mode"];

								[self.sqlDB dropTableSchemas]; //!< Table schemas no longer needed, save memory

								if (completionHandler!=nil)
								{
									completionHandler(self, error);
								}
							}
							else
							{
								[self.sqlDB closeWithCompletionHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable closeError) {
									if (completionHandler!=nil)
									{
										completionHandler(self, error);
									}
								}];
							}

							openQueueCompletionHandler();
						}];
					}
					else
					{
						OCLogError(@"Error attaching thumbnail database: %@", error);

						if (completionHandler!=nil)
						{
							completionHandler(self, error);
						}

						openQueueCompletionHandler();
					}
				}]];
			}
			else
			{
				if (completionHandler!=nil)
				{
					completionHandler(self, error);
				}

				self->_openCount--;
				openQueueCompletionHandler();
			}
		}];
	}];
}

- (void)closeWithCompletionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	[_openQueue async:^(dispatch_block_t  _Nonnull openQueueCompletionHandler) {
		self->_openCount--;

		if (self->_openCount > 0)
		{
			if (completionHandler!=nil)
			{
				completionHandler(self, nil);
			}

			openQueueCompletionHandler();
			return;
		}

		[self.sqlDB executeQuery:[OCSQLiteQuery query:@"DETACH DATABASE thumb" resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) { // relatedTo:OCDatabaseTableNameThumbnails
			if (error != nil)
			{
				OCLogError(@"Error detaching thumbnail database: %@", error);
			}
		}]];

		[self.sqlDB closeWithCompletionHandler:^(OCSQLiteDB *db, NSError *error) {
			if (completionHandler != nil)
			{
				completionHandler(self, error);
			}

			openQueueCompletionHandler();
		}];
	}];
}

- (BOOL)isOpened
{
	return (_openCount > 0);
}

#pragma mark - Transactions
- (void)performBatchUpdates:(NSError *(^)(OCDatabase *database))updates completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	[self.sqlDB executeTransaction:[OCSQLiteTransaction transactionWithBlock:^NSError *(OCSQLiteDB *db, OCSQLiteTransaction *transaction) {
		if (updates != nil)
		{
			return(updates(self));
		}

		return (nil);
	} type:OCSQLiteTransactionTypeDeferred completionHandler:^(OCSQLiteDB *db, OCSQLiteTransaction *transaction, NSError *error) {
		if (completionHandler != nil)
		{
			completionHandler(self, error);
		}
	}]];
}

#pragma mark - Meta data interface
- (OCDatabaseTimestamp)_timestampForSyncAnchor:(OCSyncAnchor)syncAnchor
{
	// Ensure a consistent timestamp for every sync anchor, so that matching for mdTimestamp will also match on the entirety of all included sync anchors, not just parts of it (worst case)
	@synchronized(self)
	{
		if (syncAnchor != nil)
		{
			if ((_lastSyncAnchor==nil) || ((_lastSyncAnchor!=nil) && ![_lastSyncAnchor isEqual:syncAnchor]))
			{
				_lastSyncAnchor = syncAnchor;
				_lastSyncAnchorTimestamp = @((NSUInteger)NSDate.timeIntervalSinceReferenceDate);
			}

			return (_lastSyncAnchorTimestamp);
		}
	}

	return @((NSUInteger)NSDate.timeIntervalSinceReferenceDate);
}

- (void)addCacheItems:(NSArray <OCItem *> *)items syncAnchor:(OCSyncAnchor)syncAnchor completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	OCDatabaseTimestamp mdTimestamp = [self _timestampForSyncAnchor:syncAnchor];

	if (_itemFilter != nil)
	{
		items = _itemFilter(items);
	}

	[items enumerateObjectsWithTransformer:^id _Nullable(OCItem * _Nonnull item, NSUInteger idx, BOOL * _Nonnull stop) {
		OCSQLiteQuery *query = nil;

		if (item.localID == nil)
		{
			OCLogWarning(@"Item added without localID: %@", item);
		}

		if ((item.parentLocalID == nil) && (![item.path isEqualToString:@"/"]))
		{
			OCLogWarning(@"Item added without parentLocalID: %@", item);
		}

		query = [OCSQLiteQuery queryInsertingIntoTable:OCDatabaseTableNameMetaData rowValues:@{
			@"type" 		: @(item.type),
			@"syncAnchor"		: syncAnchor,
			@"removed"		: @(0),
			@"mdTimestamp"		: mdTimestamp,
			@"locallyModified" 	: @(item.locallyModified),
			@"localRelativePath"	: OCSQLiteNullProtect(item.localRelativePath),
			@"downloadTrigger"	: OCSQLiteNullProtect(item.downloadTriggerIdentifier),
			@"locationString"	: item.locationString,
			@"path" 		: item.path,
			@"parentPath" 		: [item.path parentPath],
			@"name"			: [item.path lastPathComponent],
			@"mimeType" 		: OCSQLiteNullProtect(item.mimeType),
			@"typeAlias" 		: OCSQLiteNullProtect(item.typeAlias),
			@"size" 		: @(item.size),
			@"favorite" 		: @(item.isFavorite.boolValue),
			@"cloudStatus" 		: @(item.cloudStatus),
			@"hasLocalAttributes" 	: @(item.hasLocalAttributes),
			@"syncActivity"		: @(item.syncActivity),
			@"lastUsedDate" 	: OCSQLiteNullProtect(item.lastUsed),
			@"lastModifiedDate"	: OCSQLiteNullProtect(item.lastModified),
			@"driveID"		: OCSQLiteNullProtect(item.driveID),
			@"fileID"		: OCSQLiteNullProtect(item.fileID),
			@"localID"		: OCSQLiteNullProtect(item.localID),
			@"ownerUserName"	: OCSQLiteNullProtect(item.ownerUserName),
			@"itemData"		: [item serializedData]
		} resultHandler:^(OCSQLiteDB *db, NSError *error, NSNumber *rowID) {
			item.databaseID = rowID;
			item.databaseTimestamp = mdTimestamp;
		}];

		return (query);
	} process:^(NSArray<OCSQLiteQuery *> * _Nonnull queries, NSUInteger processed, NSUInteger total, BOOL * _Nonnull stop) {
		[self.sqlDB executeTransaction:[OCSQLiteTransaction transactionWithQueries:queries type:OCSQLiteTransactionTypeDeferred completionHandler:^(OCSQLiteDB *db, OCSQLiteTransaction *transaction, NSError *error) {
			if (error != nil)
			{
				*stop = YES;
			}

			[db logMemoryStatistics];
			[db flushCache];

			if ((processed == total) || (error != nil))
			{
				completionHandler(self, error);
			}
		}]];
	} segmentSize:((_memoryConfiguration == OCPlatformMemoryConfigurationMinimum) ? 10 : 200)];
}

- (void)updateCacheItems:(NSArray <OCItem *> *)items syncAnchor:(OCSyncAnchor)syncAnchor completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	OCDatabaseTimestamp mdTimestamp = [self _timestampForSyncAnchor:syncAnchor];
	__block NSMutableSet<OCLocationString> *removedLocations = nil;

	if (_itemFilter != nil)
	{
		items = _itemFilter(items);
	}

	[items enumerateObjectsWithTransformer:^id _Nullable(OCItem * _Nonnull item, NSUInteger idx, BOOL * _Nonnull stop) {
		OCSQLiteQuery *query = nil;

		if ((item.localID == nil) && (!item.removed))
		{
			OCLogDebug(@"Item updated without localID: %@", item);
		}

		if ((item.parentLocalID == nil) && (![item.path isEqualToString:@"/"]))
		{
			OCLogDebug(@"Item updated without parentLocalID: %@", item);
		}

		if (item.databaseID != nil)
		{
			query = [OCSQLiteQuery queryUpdatingRowWithID:item.databaseID inTable:OCDatabaseTableNameMetaData withRowValues:@{
				@"type" 		: @(item.type),
				@"syncAnchor"		: syncAnchor,
				@"removed"		: @(item.removed),
				@"mdTimestamp"		: mdTimestamp,
				@"locallyModified" 	: @(item.locallyModified),
				@"localRelativePath"	: OCSQLiteNullProtect(item.localRelativePath),
				@"downloadTrigger"	: OCSQLiteNullProtect(item.downloadTriggerIdentifier),
				@"locationString"	: item.locationString,
				@"path" 		: item.path,
				@"parentPath" 		: [item.path parentPath],
				@"name"			: [item.path lastPathComponent],
				@"mimeType" 		: OCSQLiteNullProtect(item.mimeType),
				@"typeAlias" 		: OCSQLiteNullProtect(item.typeAlias),
				@"size" 		: @(item.size),
				@"favorite" 		: @(item.isFavorite.boolValue),
				@"cloudStatus" 		: @(item.cloudStatus),
				@"hasLocalAttributes" 	: @(item.hasLocalAttributes),
				@"syncActivity"		: @(item.syncActivity),
				@"lastUsedDate" 	: OCSQLiteNullProtect(item.lastUsed),
				@"lastModifiedDate" 	: OCSQLiteNullProtect(item.lastModified),
				@"driveID"		: OCSQLiteNullProtect(item.driveID),
				@"fileID"		: OCSQLiteNullProtect(item.fileID),
				@"localID"		: OCSQLiteNullProtect(item.localID),
				@"ownerUserName"	: OCSQLiteNullProtect(item.ownerUserName),
				@"itemData"		: [item serializedData]
			} completionHandler:nil];

			item.databaseTimestamp = mdTimestamp;
		}
		else
		{
			OCLogError(@"Item without databaseID can't be used for updating: %@", item);
		}

		if ((item.type == OCItemTypeCollection) && item.removed)
		{
			// Removed folders -> also trigger removal of ALL items inside
			OCLocationString itemLocationString;

			if ((itemLocationString = item.locationString) != nil)
			{
				if (removedLocations == nil) {
					removedLocations = [NSMutableSet new];
				}

				[removedLocations addObject:itemLocationString];
			}
		}

		return (query);
	} process:^(NSArray<OCSQLiteQuery *> *queries, NSUInteger processed, NSUInteger total, BOOL * _Nonnull stop) {
		// If removedLocations has entries, add SQL entries for them
		NSMutableArray<OCSQLiteQuery *> *combinedQueries = (removedLocations != nil) ? [[NSMutableArray alloc] initWithArray:queries] : (NSMutableArray *)queries;

		if (removedLocations != nil)
		{
			for (OCLocationString locationString in removedLocations)
			{
				// Update removed and syncAnchor for all items inside removed folders
				OCSQLiteQuery *removalQuery = [OCSQLiteQuery queryUpdatingRowsWhere:@{
					@"locationString" : [OCSQLiteQueryCondition queryConditionWithOperator:@" LIKE " value:[locationString stringByAppendingString:@"%"] apply:YES]
				} inTable:OCDatabaseTableNameMetaData withRowValues:@{
					@"removed"	: @(YES),
					@"syncAnchor"	: syncAnchor,
					@"mdTimestamp"	: mdTimestamp
				} completionHandler:nil];

				[combinedQueries addObject:removalQuery];
			}

			removedLocations = nil;
		}

		[self.sqlDB executeTransaction:[OCSQLiteTransaction transactionWithQueries:combinedQueries type:OCSQLiteTransactionTypeDeferred completionHandler:^(OCSQLiteDB *db, OCSQLiteTransaction *transaction, NSError *error) {
			if (error != nil)
			{
				*stop = YES;
			}

			[db logMemoryStatistics];
			[db flushCache];

			if ((processed == total) || (error != nil))
			{
				completionHandler(self, error);
			}
		}]];
	} segmentSize:((_memoryConfiguration == OCPlatformMemoryConfigurationMinimum) ? 10 : 200)];
}

- (void)removeCacheItems:(NSArray <OCItem *> *)items syncAnchor:(OCSyncAnchor)syncAnchor completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	// TODO: Update parent directories with new sync anchor value (not sure if necessary, as a change in eTag should also trigger an update of the parent directory sync anchor)
	if (_itemFilter != nil)
	{
		items = _itemFilter(items);
	}

	// Set .removed on all items
	for (OCItem *item in items)
	{
		item.removed = YES;

		if (item.databaseID == nil)
		{
			OCLogError(@"Item without databaseID can't be used for deletion: %@", item);
		}
	}

	// Update cache items
	[self updateCacheItems:items syncAnchor:syncAnchor completionHandler:completionHandler];
}

- (void)purgeCacheItemsWithDatabaseIDs:(NSArray <OCDatabaseID> *)databaseIDs completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	if (databaseIDs.count == 0)
	{
		if (completionHandler != nil)
		{
			completionHandler(self, nil);
		}
	}
	else
	{
		NSMutableArray <OCSQLiteQuery *> *queries = [[NSMutableArray alloc] initWithCapacity:databaseIDs.count];

		for (OCDatabaseID databaseID in databaseIDs)
		{
			[queries addObject:[OCSQLiteQuery queryDeletingRowWithID:databaseID fromTable:OCDatabaseTableNameMetaData completionHandler:nil]];
		}

		[self.sqlDB executeTransaction:[OCSQLiteTransaction transactionWithQueries:queries type:OCSQLiteTransactionTypeDeferred completionHandler:^(OCSQLiteDB *db, OCSQLiteTransaction *transaction, NSError *error) {
			if (completionHandler != nil)
			{
				completionHandler(self, error);
			}
		}]];
	}
}

- (void)removeCacheItemsWithDriveID:(OCDriveID)driveID syncAnchor:(OCSyncAnchor)syncAnchor completionHandler:(OCDatabaseCompletionHandler)completionHandler;
{
	if ((driveID == nil) || (OCTypedCast(driveID, NSString).length == 0))
	{
		if (completionHandler != nil)
		{
			completionHandler(self, nil);
		}
	}
	else
	{
		OCDatabaseTimestamp mdTimestamp = [self _timestampForSyncAnchor:syncAnchor];

		OCSQLiteQuery *query = [OCSQLiteQuery queryUpdatingRowsWhere:@{
			@"driveID" 	: driveID,
		} inTable:OCDatabaseTableNameMetaData withRowValues:@{
			@"removed" 	: @(YES),
			@"syncAnchor" 	: syncAnchor,
			@"mdTimestamp"	: mdTimestamp
		} completionHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error) {
			if (completionHandler != nil)
			{
				completionHandler(self, error);
			}
		}];

		[self.sqlDB executeQuery:query];
	}
}

- (void)purgeCacheItemsWithDriveID:(OCDriveID)driveID completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	if ((driveID == nil) || (OCTypedCast(driveID, NSString).length == 0))
	{
		if (completionHandler != nil)
		{
			completionHandler(self, nil);
		}
	}
	else
	{
		OCSQLiteQuery *query = [OCSQLiteQuery queryDeletingRowsWhere:@{ @"driveID" : driveID } fromTable:OCDatabaseTableNameMetaData completionHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error) {
			if (completionHandler != nil)
			{
				completionHandler(self, error);
			}
		}];

		[self.sqlDB executeQuery:query];
	}
}

- (OCItem *)_itemFromResultDict:(NSDictionary<NSString *,id<NSObject>> *)resultDict
{
	NSData *itemData;
	OCItem *item = nil;

	if ((itemData = (NSData *)resultDict[@"itemData"]) != nil)
	{
		if ((item = [OCItem itemFromSerializedData:itemData]) != nil)
		{
			NSNumber *removed, *mdTimestamp;
			NSString *downloadTrigger;

			if ((removed = (NSNumber *)resultDict[@"removed"]) != nil)
			{
				item.removed = removed.boolValue;
			}

			if ((mdTimestamp = (NSNumber *)resultDict[@"mdTimestamp"]) != nil)
			{
				item.databaseTimestamp = mdTimestamp;
			}

			if ((downloadTrigger = (NSString *)resultDict[@"downloadTrigger"]) != nil)
			{
				item.downloadTriggerIdentifier = downloadTrigger;
			}

			item.databaseID = resultDict[@"mdID"];
		}
	}

	return (item);
}

- (void)_completeRetrievalWithResultSet:(OCSQLiteResultSet *)resultSet completionHandler:(OCDatabaseRetrieveCompletionHandler)completionHandler
{
	NSMutableArray <OCItem *> *items = [NSMutableArray new];
	NSMutableArray <OCUser *> *cachedUsers = [NSMutableArray new];
	NSError *returnError = nil;
	__block OCSyncAnchor syncAnchor = nil;

	[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *resultDict, BOOL *stop) {
		OCSyncAnchor itemSyncAnchor;
		OCItem *item;

		if ((item = [self _itemFromResultDict:resultDict]) != nil)
		{
			[items addObject:item];

			if (item.owner != nil)
			{
				NSUInteger cachedUserIndex;

				if ((cachedUserIndex = [cachedUsers indexOfObject:item.owner]) != NSNotFound)
				{
					item.owner = [cachedUsers objectAtIndex:cachedUserIndex];
				}
				else
				{
					[cachedUsers addObject:item.owner];
				}
			}
		}

		if ((itemSyncAnchor = (NSNumber *)resultDict[@"syncAnchor"]) != nil)
		{
			if (syncAnchor != nil)
			{
				if (syncAnchor.integerValue < itemSyncAnchor.integerValue)
				{
					syncAnchor = itemSyncAnchor;
				}
			}
			else
			{
				syncAnchor = itemSyncAnchor;
			}
		}
	} error:&returnError];

	if (returnError != nil)
	{
		completionHandler(self, returnError, nil, nil);
	}
	else
	{
		completionHandler(self, nil, syncAnchor, items);
	}
}

- (void)_retrieveCacheItemForSQLQuery:(NSString *)sqlQuery parameters:(nullable NSArray<id> *)parameters completionHandler:(OCDatabaseRetrieveItemCompletionHandler)completionHandler
{
	[self.sqlDB executeQuery:[OCSQLiteQuery query:sqlQuery withParameters:parameters resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		if (error != nil)
		{
			completionHandler(self, error, nil, nil);
		}
		else
		{
			[self _completeRetrievalWithResultSet:resultSet completionHandler:^(OCDatabase *db, NSError *error, OCSyncAnchor syncAnchor, NSArray<OCItem *> *items) {
				completionHandler(db, error, syncAnchor, items.firstObject);
			}];
		}
	}]];

}

- (void)_retrieveCacheItemsForSQLQuery:(NSString *)sqlQuery parameters:(nullable NSArray<id> *)parameters cancelAction:(OCCancelAction *)cancelAction completionHandler:(OCDatabaseRetrieveCompletionHandler)completionHandler
{
	OCSQLiteQuery *query = [OCSQLiteQuery query:sqlQuery withParameters:parameters resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		if (error != nil)
		{
			completionHandler(self, error, nil, nil);
		}
		else
		{
			[self _completeRetrievalWithResultSet:resultSet completionHandler:completionHandler];
		}
	}];

	if (cancelAction != nil)
	{
		__weak OCSQLiteQuery *weakQuery = query;

		if (cancelAction.cancelled)
		{
			completionHandler(self, OCSQLiteDBError(OCSQLiteDBErrorQueryCancelled), nil, @[]);
			return;
		}
		else
		{
			cancelAction.handler = ^BOOL{
				return ([weakQuery cancel]);
			};
		}
	}

	[self.sqlDB executeQuery:query];

	cancelAction.handler = nil;
}

- (void)retrieveCacheItemForLocalID:(OCLocalID)localID completionHandler:(OCDatabaseRetrieveItemCompletionHandler)completionHandler
{
	if (localID == nil)
	{
		OCLogError(@"Retrieval of localID==nil failed");

		completionHandler(self, OCError(OCErrorItemNotFound), nil, nil);
		return;
	}

	[self _retrieveCacheItemForSQLQuery:[_selectItemRowsSQLQueryPrefix stringByAppendingString:@" FROM metaData WHERE localID=? AND removed=0"]
				 parameters:@[localID]
			  completionHandler:completionHandler];
}

- (void)retrieveCacheItemForFileID:(OCFileID)fileID completionHandler:(OCDatabaseRetrieveItemCompletionHandler)completionHandler
{
	[self retrieveCacheItemForFileID:fileID includingRemoved:NO completionHandler:completionHandler];
}

- (void)retrieveCacheItemForFileID:(OCFileID)fileID includingRemoved:(BOOL)includingRemoved completionHandler:(OCDatabaseRetrieveItemCompletionHandler)completionHandler
{
	if (fileID == nil)
	{
		OCLogError(@"Retrieval of fileID==nil failed");

		completionHandler(self, OCError(OCErrorItemNotFound), nil, nil);
		return;
	}

	[self _retrieveCacheItemForSQLQuery:(includingRemoved ? [_selectItemRowsSQLQueryPrefix stringByAppendingString:@", removed FROM metaData WHERE fileID=?"] : [_selectItemRowsSQLQueryPrefix stringByAppendingString:@", removed FROM metaData WHERE fileID=? AND removed=0"])
				 parameters:@[fileID]
			  completionHandler:completionHandler];
}

- (void)retrieveCacheItemForFileIDUniquePrefix:(OCFileIDUniquePrefix)fileIDUniquePrefix includingRemoved:(BOOL)includingRemoved completionHandler:(OCDatabaseRetrieveItemCompletionHandler)completionHandler
{
	if (fileIDUniquePrefix == nil)
	{
		OCLogError(@"Retrieval of fileIDUniquePrefix==nil failed");

		completionHandler(self, OCError(OCErrorItemNotFound), nil, nil);
		return;
	}

	[self _retrieveCacheItemForSQLQuery:(includingRemoved ? [_selectItemRowsSQLQueryPrefix stringByAppendingString:@", removed FROM metaData WHERE fileID LIKE ?"] : [_selectItemRowsSQLQueryPrefix stringByAppendingString:@", removed FROM metaData WHERE fileID LIKE ? AND removed=0"])
				 parameters:@[ [[fileIDUniquePrefix stringBySQLLikeEscaping] stringByAppendingString:@"%"] ]
			  completionHandler:completionHandler];
}


- (void)retrieveCacheItemsRecursivelyBelowLocation:(OCLocation *)location includingPathItself:(BOOL)includingPathItself includingRemoved:(BOOL)includingRemoved completionHandler:(OCDatabaseRetrieveCompletionHandler)completionHandler
{
	NSMutableArray *parameters = [NSMutableArray new];

	if (location.path.length == 0)
	{
		OCLogError(@"Retrieval below zero-length/nil path failed");

		completionHandler(self, OCError(OCErrorInsufficientParameters), nil, nil);
		return;
	}

	[parameters addObject:[[location.path stringBySQLLikeEscaping] stringByAppendingString:@"%"]];

	NSString *sqlStatement = [_selectItemRowsSQLQueryPrefix stringByAppendingString:@", removed FROM metaData WHERE path LIKE ?"];

	sqlStatement = [sqlStatement stringByAppendingString:@" AND driveID=?"];
	[parameters addObject:OCSQLiteNullProtect(location.driveID)];

	if (includingRemoved)
	{
		sqlStatement = [sqlStatement stringByAppendingString:@" AND removed=0"];
	}

	if (!includingPathItself)
	{
		sqlStatement = [sqlStatement stringByAppendingString:@" AND path!=?"];
		[parameters addObject:location.path];
	}

	[self _retrieveCacheItemsForSQLQuery:sqlStatement parameters:parameters cancelAction:nil completionHandler:completionHandler];
}

- (void)retrieveCacheItemsAtLocation:(OCLocation *)location itemOnly:(BOOL)itemOnly completionHandler:(OCDatabaseRetrieveCompletionHandler)completionHandler
{
	NSString *sqlQueryString = nil;
	NSArray *parameters = nil;

	if (location.path == nil)
	{
		completionHandler(self, OCError(OCErrorInsufficientParameters), nil, nil);
		return;
	}

	if (itemOnly)
	{
		sqlQueryString = [_selectItemRowsSQLQueryPrefix stringByAppendingString:@" FROM metaData WHERE path=? AND removed=0"];
		parameters = @[location.path];
	}
	else
	{
		sqlQueryString = [_selectItemRowsSQLQueryPrefix stringByAppendingString:@" FROM metaData WHERE (parentPath=? OR path=?) AND removed=0"];
		parameters = @[location.path, location.path];
	}

	if (location.driveID == nil)
	{
		sqlQueryString = [sqlQueryString stringByAppendingString:@" AND driveID IS NULL"];
	}
	else
	{
		sqlQueryString = [sqlQueryString stringByAppendingString:@" AND driveID=?"];
		parameters = [parameters arrayByAddingObject:location.driveID];
	}

	[self _retrieveCacheItemsForSQLQuery:sqlQueryString parameters:parameters cancelAction:nil completionHandler:completionHandler];
}

- (NSArray <OCItem *> *)retrieveCacheItemsSyncAtLocation:(OCLocation *)location itemOnly:(BOOL)itemOnly error:(NSError * __autoreleasing *)outError syncAnchor:(OCSyncAnchor __autoreleasing *)outSyncAnchor
{
	__block NSArray <OCItem *> *items = nil;

	OCSyncExec(cacheItemsRetrieval, {
		[self retrieveCacheItemsAtLocation:location itemOnly:itemOnly completionHandler:^(OCDatabase *db, NSError *error, OCSyncAnchor syncAnchor, NSArray<OCItem *> *dbItems) {
			items = dbItems;

			if (outError != NULL) { *outError = error; }
			if (outSyncAnchor != NULL) { *outSyncAnchor = syncAnchor; }

			OCSyncExecDone(cacheItemsRetrieval);
		}];
	});

	return (items);
}

- (void)retrieveCacheItemsUpdatedSinceSyncAnchor:(OCSyncAnchor)synchAnchor foldersOnly:(BOOL)foldersOnly completionHandler:(OCDatabaseRetrieveCompletionHandler)completionHandler
{
	NSString *sqlQueryString = [_selectItemRowsSQLQueryPrefix stringByAppendingString:@", removed FROM metaData WHERE syncAnchor > ?"];

	if (foldersOnly)
	{
		sqlQueryString = [sqlQueryString stringByAppendingFormat:@" AND type == %ld", (long)OCItemTypeCollection];
	}

	[self _retrieveCacheItemsForSQLQuery:sqlQueryString parameters:@[synchAnchor] cancelAction:nil completionHandler:completionHandler];
}

+ (NSDictionary<OCItemPropertyName, NSString *> *)columnNameByPropertyName
{
	static dispatch_once_t onceToken;
	static NSDictionary<OCItemPropertyName, NSString *> *columnNameByPropertyName;

	dispatch_once(&onceToken, ^{
		columnNameByPropertyName = @{
			OCItemPropertyNameType : @"type",

			OCItemPropertyNameLocalID : @"localID",
			OCItemPropertyNameFileID : @"fileID",

			OCItemPropertyNameName : @"name",
			OCItemPropertyNameDriveID : @"driveID",
			OCItemPropertyNamePath : @"path",
			OCItemPropertyNameParentPath : @"parentPath",
			OCItemPropertyNameLocationString : @"locationString",

			OCItemPropertyNameLocalRelativePath 	: @"localRelativePath",
			OCItemPropertyNameLocallyModified 	: @"locallyModified",

			OCItemPropertyNameMIMEType 		: @"mimeType",
			OCItemPropertyNameTypeAlias		: @"typeAlias",
			OCItemPropertyNameSize 			: @"size",
			OCItemPropertyNameIsFavorite 		: @"favorite",
			OCItemPropertyNameCloudStatus 		: @"cloudStatus",
			OCItemPropertyNameHasLocalAttributes 	: @"hasLocalAttributes",
			OCItemPropertyNameSyncActivity		: @"syncActivity",
			OCItemPropertyNameLastUsed 		: @"lastUsedDate",
			OCItemPropertyNameLastModified		: @"lastModifiedDate",
			OCItemPropertyNameOwnerUserName		: @"ownerUserName",

			OCItemPropertyNameDownloadTrigger	: @"downloadTrigger",

			OCItemPropertyNameRemoved		: @"removed",
			OCItemPropertyNameDatabaseTimestamp	: @"mdTimestamp"
		};
	});

	return (columnNameByPropertyName);
}

- (void)retrieveCacheItemsForQueryCondition:(OCQueryCondition *)queryCondition cancelAction:(OCCancelAction *)cancelAction completionHandler:(OCDatabaseRetrieveCompletionHandler)completionHandler
{
	NSString *sqlQueryString = [_selectItemRowsSQLQueryPrefix stringByAppendingString:@", removed FROM metaData WHERE removed=0 AND "];
	NSString *sqlWhereString = nil;
	NSArray *parameters = nil;
	NSError *error = nil;

	if ((sqlWhereString = [queryCondition buildSQLQueryWithPropertyColumnNameMap:[[self class] columnNameByPropertyName] parameters:&parameters error:&error]) != nil)
	{
		sqlQueryString = [sqlQueryString stringByAppendingString:sqlWhereString];

		[self _retrieveCacheItemsForSQLQuery:sqlQueryString parameters:parameters cancelAction:cancelAction completionHandler:completionHandler];
	}
	else
	{
		completionHandler(self, error, nil, nil);
	}
}

- (void)iterateCacheItemsWithIterator:(void(^)(NSError *error, OCSyncAnchor syncAnchor, OCItem *item, BOOL *stop))iterator
{
	NSString *sqlQueryString = [_selectItemRowsSQLQueryPrefix stringByAppendingString:@", removed FROM metaData ORDER BY mdID ASC"];

	[self.sqlDB executeQuery:[OCSQLiteQuery query:sqlQueryString withParameters:nil resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		NSError *returnError = nil;

		[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *resultDict, BOOL *stop) {
			OCItem *item;

			if ((item = [self _itemFromResultDict:resultDict]) != nil)
			{
				iterator(nil, (NSNumber *)resultDict[@"syncAnchor"], item, stop);
			}
		} error:&returnError];

		iterator(returnError, nil, nil, NULL);
	}]];
}

- (void)iterateCacheItemsForQueryCondition:(nullable OCQueryCondition *)queryCondition excludeRemoved:(BOOL)excludeRemoved withIterator:(OCDatabaseItemIterator)iterator
{
	NSString *sqlQueryString = nil;
	NSString *sqlWhereString = nil;
	NSArray *parameters = nil;
	NSError *error = nil;

	if (queryCondition != nil)
	{
		if ((sqlWhereString = [queryCondition buildSQLQueryWithPropertyColumnNameMap:[[self class] columnNameByPropertyName] parameters:&parameters error:&error]) != nil)
		{
			sqlQueryString = [_selectItemRowsSQLQueryPrefix stringByAppendingFormat:@", removed FROM metaData WHERE %@%@", (excludeRemoved ? @"removed=0 AND " : @""), sqlWhereString];
		}
	}
	else
	{
		sqlQueryString = [_selectItemRowsSQLQueryPrefix stringByAppendingString:@", removed FROM metaData ORDER BY mdID ASC"];
	}

	if (sqlQueryString == nil)
	{
		iterator(OCError(OCErrorInsufficientParameters), nil, nil, NULL);
		return;
	}

	// OCLogDebug(@"Iterating result for %@ with parameters %@", sqlQueryString, parameters);

	[self.sqlDB executeQuery:[OCSQLiteQuery query:sqlQueryString withParameters:parameters resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		NSError *returnError = nil;

		[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *resultDict, BOOL *stop) {
			OCItem *item;

			if ((item = [self _itemFromResultDict:resultDict]) != nil)
			{
				iterator(nil, (NSNumber *)resultDict[@"syncAnchor"], item, stop);
			}
		} error:&returnError];

		iterator(returnError, nil, nil, NULL);
	}]];
}

#pragma mark - Directory Update Job interface
- (void)addDirectoryUpdateJob:(OCCoreDirectoryUpdateJob *)updateJob completionHandler:(OCDatabaseDirectoryUpdateJobCompletionHandler)completionHandler
{
	if ((updateJob != nil) && (updateJob.location.path != nil))
	{
		[self.sqlDB executeQuery:[OCSQLiteQuery queryInsertingIntoTable:OCDatabaseTableNameUpdateJobs rowValues:@{
			@"driveID"		: OCSQLiteNullProtect(updateJob.location.driveID),
			@"path" 		: updateJob.location.path
		} resultHandler:^(OCSQLiteDB *db, NSError *error, NSNumber *rowID) {
			updateJob.identifier = rowID;

			if (completionHandler != nil)
			{
				completionHandler(self, error, updateJob);
			}
		}]];
	}
	else
	{
		OCLogError(@"updateJob=%@, updateJob.location=%@ => could not be stored in database", updateJob, updateJob.location);
		completionHandler(self, OCError(OCErrorInsufficientParameters), nil);
	}
}

- (void)retrieveDirectoryUpdateJobsAfter:(OCCoreDirectoryUpdateJobID)jobID forLocation:(OCLocation *)location maximumJobs:(NSUInteger)maximumJobs completionHandler:(OCDatabaseRetrieveDirectoryUpdateJobsCompletionHandler)completionHandler
{
	[self.sqlDB executeQuery:[OCSQLiteQuery querySelectingColumns:nil fromTable:OCDatabaseTableNameUpdateJobs where:@{
		@"jobID" 	: [OCSQLiteQueryCondition queryConditionWithOperator:@">=" value:jobID apply:(jobID!=nil)],
		@"driveID" 	: [OCSQLiteQueryCondition queryConditionWithOperator:@"="  value:location.driveID apply:(location.driveID!=nil)],
		@"path" 	: [OCSQLiteQueryCondition queryConditionWithOperator:@"="  value:location.path apply:(location.path!=nil)]
	} orderBy:@"jobID ASC" limit:((maximumJobs == 0) ? nil : [NSString stringWithFormat:@"0,%ld",maximumJobs]) resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		__block NSMutableArray <OCCoreDirectoryUpdateJob *> *updateJobs = nil;
		NSError *iterationError = error;

		if (error == nil)
		{
			[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *rowDictionary, BOOL *stop) {
				if ((rowDictionary[@"jobID"] != nil) && (rowDictionary[@"path"] != nil))
				{
					OCCoreDirectoryUpdateJob *updateJob;

					if ((updateJob = [OCCoreDirectoryUpdateJob new]) != nil)
					{
						updateJob.identifier = (OCCoreDirectoryUpdateJobID)rowDictionary[@"jobID"];
						updateJob.location = [[OCLocation alloc] initWithDriveID:(OCDriveID)rowDictionary[@"driveID"] path:(OCPath)rowDictionary[@"path"]];

						if (updateJobs == nil) { updateJobs = [NSMutableArray new]; }

						[updateJobs addObject:updateJob];
					}

				}
			} error:&iterationError];
		}

		if (completionHandler != nil)
		{
			completionHandler(self, iterationError, updateJobs);
		}
	}]];
}

- (void)removeDirectoryUpdateJobWithID:(OCCoreDirectoryUpdateJobID)jobID completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	if (jobID != nil)
	{
		[self.sqlDB executeQuery:[OCSQLiteQuery queryDeletingRowWithID:jobID fromTable:OCDatabaseTableNameUpdateJobs completionHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error) {
			completionHandler(self, error);
		}]];
	}
	else
	{
		OCLogError(@"Could not remove updateJob: jobID is nil");
		completionHandler(self, OCError(OCErrorInsufficientParameters));
	}
}

#pragma mark - Sync Lane interface
- (void)addSyncLane:(OCSyncLane *)lane completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	NSData *laneData = [NSKeyedArchiver archivedDataWithRootObject:lane];

	if (laneData != nil)
	{
		[self.sqlDB executeQuery:[OCSQLiteQuery queryInsertingIntoTable:OCDatabaseTableNameSyncLanes rowValues:@{
			@"laneData" 		: laneData
		} resultHandler:^(OCSQLiteDB *db, NSError *error, NSNumber *rowID) {
			lane.identifier = rowID;

			completionHandler(self, error);
		}]];
	}
	else
	{
		OCLogError(@"Could not serialize lane=%@ to laneData=%@", lane, laneData);
		completionHandler(self, OCError(OCErrorInsufficientParameters));
	}
}

- (void)updateSyncLane:(OCSyncLane *)lane completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	NSData *laneData = [NSKeyedArchiver archivedDataWithRootObject:lane];

	if ((lane.identifier != nil) && (laneData != nil))
	{
		[self.sqlDB executeQuery:[OCSQLiteQuery queryUpdatingRowWithID:lane.identifier inTable:OCDatabaseTableNameSyncLanes withRowValues:@{
			@"laneData"	: laneData
		} completionHandler:^(OCSQLiteDB *db, NSError *error) {
			completionHandler(self, error);
		}]];
	}
	else
	{
		OCLogError(@"Could not update lane: serialize lane=%@ to laneData=%@ failed - or lane.identifier=%@ is nil", lane, laneData, lane.identifier);
		completionHandler(self, OCError(OCErrorInsufficientParameters));
	}
}

- (void)removeSyncLane:(OCSyncLane *)lane completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	if (lane.identifier != nil)
	{
		[self.sqlDB executeQuery:[OCSQLiteQuery queryDeletingRowWithID:lane.identifier fromTable:OCDatabaseTableNameSyncLanes completionHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error) {
			completionHandler(self, error);
		}]];
	}
	else
	{
		OCLogError(@"Could not remove lane: lane.identifier is nil");
		completionHandler(self, OCError(OCErrorInsufficientParameters));
	}
}

- (void)retrieveSyncLaneForID:(OCSyncLaneID)laneID completionHandler:(OCDatabaseRetrieveSyncLaneCompletionHandler)completionHandler
{
	if (laneID != nil)
	{
		[self.sqlDB executeQuery:[OCSQLiteQuery querySelectingColumns:@[ @"laneData" ] fromTable:OCDatabaseTableNameSyncLanes where:@{
			@"laneID" : laneID,
		} orderBy:nil resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
			__block OCSyncLane *syncLane = nil;
			NSError *iterationError = error;

			if (error == nil)
			{
				[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *rowDictionary, BOOL *stop) {
					if (rowDictionary[@"laneData"] != nil)
					{
						syncLane = [NSKeyedUnarchiver unarchiveObjectWithData:((NSData *)rowDictionary[@"laneData"])];
						syncLane.identifier = laneID;
						*stop = YES;
					}
				} error:&iterationError];
			}

			if (completionHandler != nil)
			{
				completionHandler(self, iterationError, syncLane);
			}
		}]];
	}
}

- (void)retrieveSyncLanesWithCompletionHandler:(OCDatabaseRetrieveSyncLanesCompletionHandler)completionHandler;
{
	[self.sqlDB executeQuery:[OCSQLiteQuery querySelectingColumns:@[ @"laneID", @"laneData" ] fromTable:OCDatabaseTableNameSyncLanes where:@{} orderBy:@"laneID" resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		__block NSMutableArray <OCSyncLane *> *syncLanes = nil;
		NSError *iterationError = error;

		if (error == nil)
		{
			[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *rowDictionary, BOOL *stop) {
				if (rowDictionary[@"laneData"] != nil)
				{
					if (syncLanes == nil) { syncLanes = [NSMutableArray new]; }

					OCSyncLane *syncLane;

					if ((syncLane = [NSKeyedUnarchiver unarchiveObjectWithData:((NSData *)rowDictionary[@"laneData"])]) != nil)
					{
						syncLane.identifier = (NSNumber *)rowDictionary[@"laneID"];

						[syncLanes addObject:syncLane];
					}
				}
			} error:&iterationError];
		}

		if (completionHandler != nil)
		{
			completionHandler(self, iterationError, syncLanes);
		}
	}]];
}

- (OCSyncLane *)laneForTags:(NSSet <OCSyncLaneTag> *)tags updatedLanes:(BOOL *)outUpdatedLanes readOnly:(BOOL)readOnly
{
	__block OCSyncLane *returnLane = nil;
	__block BOOL updatedLanes = NO;

	if (tags.count == 0)
	{
		return (nil);
	}

	OCSyncExec(waitForDatabase, {
		[self _laneForTags:tags updatedLanes:&updatedLanes readOnly:readOnly completionHandler:^(OCSyncLane *lane, BOOL updatedTheLanes) {
			returnLane = lane;
			updatedLanes = updatedTheLanes;

			OCSyncExecDone(waitForDatabase);
		}];
	});

	if (outUpdatedLanes != NULL)
	{
		*outUpdatedLanes = updatedLanes;
	}

	return (returnLane);
}

- (void)_laneForTags:(NSSet <OCSyncLaneTag> *)tags updatedLanes:(BOOL *)outUpdatedLanes readOnly:(BOOL)readOnly completionHandler:(void(^)(OCSyncLane *lane, BOOL updatedLanes))completionHandler
{
	if (tags.count == 0)
	{
		completionHandler(nil, NO);
	}

	[self retrieveSyncLanesWithCompletionHandler:^(OCDatabase *db, NSError *error, NSArray<OCSyncLane *> *syncLanes) {
		NSMutableSet <OCSyncLaneID> *afterLaneIDs = nil;
		__block OCSyncLane *returnLane = nil;
		__block BOOL updatedLanes = NO;

		for (OCSyncLane *lane in syncLanes)
		{
			NSUInteger prefixMatches=0, identicalTags=0;

			if ([lane coversTags:tags prefixMatches:&prefixMatches identicalTags:&identicalTags])
			{
				if (identicalTags == tags.count)
				{
					// Tags are identical => use existing lane
					returnLane = lane;
				}
				else
				{
					// Tags overlap with lane => create new, dependant lane => add afterLaneIDs
					if (!readOnly)
					{
						if (afterLaneIDs == nil) { afterLaneIDs = [NSMutableSet new]; }

						[afterLaneIDs addObject:lane.identifier];
					}
				}
			}
		}

		// Create new lane if no matching one was found
		if ((returnLane == nil) && (!readOnly))
		{
			OCSyncLane *lane;

			if ((lane = [OCSyncLane new]) != nil)
			{
				[lane extendWithTags:tags];
				lane.afterLanes = afterLaneIDs;

				[db addSyncLane:lane completionHandler:^(OCDatabase *db, NSError *error) {
					if (error != nil)
					{
						OCLogError(@"Error adding lane=%@: %@", lane, error);
					}
					else
					{
						returnLane = lane;
						updatedLanes = YES;
					}
				}];
			}
		}

		completionHandler(returnLane, updatedLanes);
	}];
}

#pragma mark - Sync Journal interface
- (void)addSyncRecords:(NSArray <OCSyncRecord *> *)syncRecords completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	NSMutableArray <OCSQLiteQuery *> *queries = [[NSMutableArray alloc] initWithCapacity:syncRecords.count];

	for (OCSyncRecord *syncRecord in syncRecords)
	{
		NSString *path = syncRecord.action.localItem.path;

		if (path == nil) { path = @""; }

		if (path != nil)
		{
			if (syncRecord.revision == nil)
			{
				syncRecord.revision = @(0);
			}

			[queries addObject:[OCSQLiteQuery queryInsertingIntoTable:OCDatabaseTableNameSyncJournal rowValues:@{
				@"laneID"		: OCSQLiteNullProtect(syncRecord.laneID),
				@"revision"		: syncRecord.revision,
				@"timestampDate" 	: syncRecord.timestamp,
				@"inProgressSinceDate"	: OCSQLiteNullProtect(syncRecord.inProgressSince),
				@"action"		: syncRecord.actionIdentifier,
				@"path"			: path,
				@"localID"		: syncRecord.localID,
				@"syncReason"		: OCSQLiteNullProtect(syncRecord.syncReason),
				@"recordData"		: [syncRecord serializedData]
			} resultHandler:^(OCSQLiteDB *db, NSError *error, NSNumber *rowID) {
				syncRecord.recordID = rowID;

				@synchronized(db)
				{
					OCSyncRecordID recordID = syncRecord.recordID;

					if (recordID != nil)
					{
						if (self->_syncRecordsByID != nil)
						{
 							// Add to cache
 							self->_syncRecordsByID[recordID] = syncRecord;
						}

						if (syncRecord.progress != nil)
						{
							self->_progressBySyncRecordID[recordID] = syncRecord.progress.progress;
						}

						if (syncRecord.action.ephermalParameters != nil)
						{
							self->_ephermalParametersBySyncRecordID[recordID] = syncRecord.action.ephermalParameters;
						}
					}
				}
			}]];
		}
	}

	[self.sqlDB executeTransaction:[OCSQLiteTransaction transactionWithQueries:queries type:OCSQLiteTransactionTypeDeferred completionHandler:^(OCSQLiteDB *db, OCSQLiteTransaction *transaction, NSError *error) {
		if (completionHandler != nil)
		{
			completionHandler(self, error);
		}
	}]];
}

- (void)updateSyncRecords:(NSArray <OCSyncRecord *> *)syncRecords completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	NSMutableArray <OCSQLiteQuery *> *queries = [[NSMutableArray alloc] initWithCapacity:syncRecords.count];

	for (OCSyncRecord *syncRecord in syncRecords)
	{
		if ((syncRecord.recordID != nil) && !syncRecord.removed)
		{
			// Increment revision of record
			syncRecord.revision = @(syncRecord.revision.longLongValue + 1);

			[queries addObject:[OCSQLiteQuery queryUpdatingRowWithID:syncRecord.recordID inTable:OCDatabaseTableNameSyncJournal withRowValues:@{
				@"laneID"		: OCSQLiteNullProtect(syncRecord.laneID),
				@"inProgressSinceDate"	: OCSQLiteNullProtect(syncRecord.inProgressSince),
				@"recordData"		: [syncRecord serializedData],
				@"localID"		: syncRecord.localID,
				@"syncReason"		: OCSQLiteNullProtect(syncRecord.syncReason),
				@"revision"		: syncRecord.revision
			} completionHandler:^(OCSQLiteDB *db, NSError *error) {
				@synchronized(db)
				{
					if (syncRecord.progress.progress != nil)
					{
						self->_progressBySyncRecordID[syncRecord.recordID] = syncRecord.progress.progress;
					}
					else
					{
						[self->_progressBySyncRecordID removeObjectForKey:syncRecord.recordID];
					}

					if (syncRecord.action.ephermalParameters != nil)
					{
						self->_ephermalParametersBySyncRecordID[syncRecord.recordID] = syncRecord.action.ephermalParameters;
					}
					else
					{
						[self->_ephermalParametersBySyncRecordID removeObjectForKey:syncRecord.recordID];
					}
				}
			}]];
		}
		else
		{
			if (syncRecord.removed)
			{
				OCLogError(@"Removed sync record can't be used for updating: %@", syncRecord);
			}
			else
			{
				OCLogError(@"Sync record without recordID can't be used for updating: %@", syncRecord);
			}
		}
	}

	[self.sqlDB executeTransaction:[OCSQLiteTransaction transactionWithQueries:queries type:OCSQLiteTransactionTypeDeferred completionHandler:^(OCSQLiteDB *db, OCSQLiteTransaction *transaction, NSError *error) {
		if (completionHandler != nil)
		{
			completionHandler(self, error);
		}
	}]];
}

- (void)removeSyncRecords:(NSArray <OCSyncRecord *> *)syncRecords completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	NSMutableArray <OCSQLiteQuery *> *queries = [[NSMutableArray alloc] initWithCapacity:syncRecords.count];

	for (OCSyncRecord *syncRecord in syncRecords)
	{
		if (syncRecord.removed)
		{
			OCLogError(@"Sync record with recordID=%@ already deleted: %@", syncRecord.recordID, syncRecord);
			continue;
		}

		if (syncRecord.recordID != nil)
		{
			[queries addObject:[OCSQLiteQuery queryDeletingRowWithID:syncRecord.recordID fromTable:OCDatabaseTableNameSyncJournal completionHandler:^(OCSQLiteDB *db, NSError *error) {
				OCSyncRecordID syncRecordID;

				if (((syncRecordID = syncRecord.recordID) != nil) && !syncRecord.removed)
				{
					@synchronized(db)
					{
						syncRecord.removed = YES;

						[self->_progressBySyncRecordID removeObjectForKey:syncRecordID];
						[self->_ephermalParametersBySyncRecordID removeObjectForKey:syncRecordID];

						if (self->_syncRecordsByID != nil)
						{
							[self->_syncRecordsByID removeObjectForKey:syncRecordID];
						}
					}
				}
			}]];
		}
		else
		{
			OCLogError(@"Sync record without recordID can't be used for deletion: %@", syncRecord);
		}
	}

	[self.sqlDB executeTransaction:[OCSQLiteTransaction transactionWithQueries:queries type:OCSQLiteTransactionTypeDeferred completionHandler:^(OCSQLiteDB *db, OCSQLiteTransaction *transaction, NSError *error) {
		if (completionHandler != nil)
		{
			completionHandler(self, error);
		}
	}]];
}

- (BOOL)isValidSyncRecordID:(OCSyncRecordID)syncRecordID considerCacheValid:(BOOL)considerCacheValid
{
	// Non-existent IDs are never valid
	if (syncRecordID == nil)
	{
		return (NO);
	}

	// Check if the sync record ID is _known_ to be invalid
	@synchronized(_knownInvalidSyncRecordIDs)
	{
		if ([_knownInvalidSyncRecordIDs containsObject:syncRecordID])
		{
			return (NO);
		}
	}

	// Check cached sync records
	if (considerCacheValid && (_syncRecordsByID != nil))
	{
		OCSyncRecord *cachedSyncRecord;

		@synchronized(self.sqlDB)
		{
			if ((cachedSyncRecord = _syncRecordsByID[syncRecordID]) != nil)
			{
				// Sync record found in cache..
				if (cachedSyncRecord.removed)
				{
					// .. and it is not marked as removed.
					return (NO);
				}

				return (YES);
			}
		}
	}

	// Check database
	__block OCSyncRecord *dbSyncRecord = nil;

	OCSyncExec(retrieveSyncRecordFromDB, {
		// By retrieving the sync record, it is also added to the cache (if it exists) and speeds up further invocations
		[self retrieveSyncRecordForID:syncRecordID completionHandler:^(OCDatabase *db, NSError *error, OCSyncRecord *syncRecord) {
			dbSyncRecord = syncRecord;
			OCSyncExecDone(retrieveSyncRecordFromDB);
		}];
	});

	if ((dbSyncRecord != nil) && !dbSyncRecord.removed)
	{
		// Sync record found. It has also not been marked as removed.
		return (YES);
	}
	else
	{
		// The sync record ID is known to be definitely invalid as it does
		// not exist in the database and all sync record IDs are generated
		// by the database. We therefore save it in a set as to not have to
		// consult the cache or database again
		@synchronized(_knownInvalidSyncRecordIDs)
		{
			[_knownInvalidSyncRecordIDs addObject:syncRecordID];
		}
	}

	// No sync record found for record ID
	return (NO);
}

- (void)numberOfSyncRecordsOnSyncLaneID:(OCSyncLaneID)laneID completionHandler:(OCDatabaseRetrieveSyncRecordCountCompletionHandler)completionHandler
{
	[self.sqlDB executeQuery:[OCSQLiteQuery query:@"SELECT COUNT(*) AS cnt FROM syncJournal WHERE laneID=:laneID" withNamedParameters:@{ @"laneID" : laneID } resultHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error, OCSQLiteTransaction * _Nullable transaction, OCSQLiteResultSet * _Nullable resultSet) {
		NSError *retrieveError = error;
		NSNumber *numberOfSyncRecordsOnLane = nil;

		if (retrieveError == nil)
		{
			numberOfSyncRecordsOnLane = (NSNumber *)[resultSet nextRowDictionaryWithError:&retrieveError][@"cnt"];
		}

		completionHandler(self, retrieveError, numberOfSyncRecordsOnLane);
	}]];
}

- (OCSyncRecord *)_syncRecordFromRowDictionary:(NSDictionary<NSString *,id<NSObject>> *)rowDictionary cache:(BOOL)cache
{
	OCSyncRecord *syncRecord = nil;
	OCSyncRecordID recordID;
	OCSyncRecordRevision revision;

	if ((recordID = (OCSyncRecordID)rowDictionary[@"recordID"]) != nil)
	{
		if ((revision = (OCSyncRecordRevision)rowDictionary[@"revision"]) != nil)
		{
			if (_syncRecordsByID != nil)
			{
				@synchronized(self.sqlDB)
				{
					if ([_syncRecordsByID[recordID].revision isEqual:revision])
					{
						if (syncRecord.removed)
						{
							// Ensure instance hasn't been deleted
							OCLogWarning(@"Removed syncRecord found in cache: %@", syncRecord);
						}
						else
						{
							// Use cached sync record if its revision hasn't changed
							if (syncRecord.recordID != nil) // ensure this instance has a recordID
							{
								syncRecord = _syncRecordsByID[recordID];
							}
						}
					}
				}
			}
		}

		if (syncRecord == nil)
		{
			if ((syncRecord = [OCSyncRecord syncRecordFromSerializedData:(NSData *)rowDictionary[@"recordData"]]) != nil)
			{
				syncRecord.recordID = recordID;
				syncRecord.revision = revision;

				if (cache)
				{
					// Add to cache
					if (_syncRecordsByID != nil)
					{
						@synchronized(self.sqlDB)
						{
							_syncRecordsByID[recordID] = syncRecord;
						}
					}
				}
			}
		}

		if (syncRecord != nil)
		{
			@synchronized(self.sqlDB)
			{
				syncRecord.progress.progress = _progressBySyncRecordID[recordID];
				syncRecord.action.ephermalParameters = _ephermalParametersBySyncRecordID[recordID];
			}
		}
	}

	return(syncRecord);
}

- (void)retrieveSyncRecordIDsWithCompletionHandler:(OCDatabaseRetrieveSyncRecordIDsCompletionHandler)completionHandler
{
	[self.sqlDB executeQuery:[OCSQLiteQuery querySelectingColumns:@[ @"recordID" ] fromTable:OCDatabaseTableNameSyncJournal where:nil orderBy:nil resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		NSError *iterationError = error;
		NSMutableSet<OCSyncRecordID> *syncRecordIDs = [NSMutableSet new];

		if (error == nil)
		{
			[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *rowDictionary, BOOL *stop) {
				OCSyncRecordID syncRecordID;

				if ((syncRecordID = OCTypedCast(rowDictionary[@"recordID"], NSNumber)) != nil)
				{
					[syncRecordIDs addObject:syncRecordID];
				}
			} error:&iterationError];
		}

		if (completionHandler != nil)
		{
			completionHandler(self, iterationError, syncRecordIDs);
		}
	}]];
}

- (void)retrieveSyncRecordIDsWithPendingEventsWithCompletionHandler:(OCDatabaseRetrieveSyncRecordIDsCompletionHandler)completionHandler
{
	[self.sqlDB executeQuery:[OCSQLiteQuery querySelectingColumns:@[ @"recordID" ] fromTable:OCDatabaseTableNameEvents where:nil orderBy:nil resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		NSError *iterationError = error;
		NSMutableSet<OCSyncRecordID> *syncRecordIDs = [NSMutableSet new];

		if (error == nil)
		{
			[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *rowDictionary, BOOL *stop) {
				OCSyncRecordID syncRecordID;

				if ((syncRecordID = OCTypedCast(rowDictionary[@"recordID"], NSNumber)) != nil)
				{
					[syncRecordIDs addObject:syncRecordID];
				}
			} error:&iterationError];
		}

		if (completionHandler != nil)
		{
			completionHandler(self, iterationError, syncRecordIDs);
		}
	}]];
}

- (void)retrieveSyncRecordForID:(OCSyncRecordID)recordID completionHandler:(OCDatabaseRetrieveSyncRecordCompletionHandler)completionHandler
{
	if (recordID == nil)
	{
		if (completionHandler != nil)
		{
			completionHandler(self, nil, nil);
		}

		return;
	}

	[self.sqlDB executeQuery:[OCSQLiteQuery querySelectingColumns:@[ @"recordID", @"recordData" ] fromTable:OCDatabaseTableNameSyncJournal where:@{
		@"recordID" : recordID,
	} orderBy:nil resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		__block OCSyncRecord *syncRecord = nil;
		NSError *iterationError = error;

		if (error == nil)
		{
			[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *rowDictionary, BOOL *stop) {
				syncRecord = [self _syncRecordFromRowDictionary:rowDictionary cache:NO];
				*stop = YES;
			} error:&iterationError];
		}

		if (completionHandler != nil)
		{
			completionHandler(self, iterationError, syncRecord);
		}
	}]];
}

- (void)retrieveSyncRecordsForPath:(OCPath)path action:(OCSyncActionIdentifier)action inProgressSince:(NSDate *)inProgressSince completionHandler:(OCDatabaseRetrieveSyncRecordsCompletionHandler)completionHandler
{
	[self.sqlDB executeQuery:[OCSQLiteQuery querySelectingColumns:@[ @"recordID", @"recordData" ] fromTable:OCDatabaseTableNameSyncJournal where:@{
		@"path" 		: [OCSQLiteQueryCondition queryConditionWithOperator:@"="  value:path 		 apply:(path!=nil)],
		@"action" 		: [OCSQLiteQueryCondition queryConditionWithOperator:@"="  value:action 	 apply:(action!=nil)],
		@"inProgressSinceDate" 	: [OCSQLiteQueryCondition queryConditionWithOperator:@">=" value:inProgressSince apply:(inProgressSince!=nil)]
	} orderBy:@"timestampDate ASC" resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		NSMutableArray <OCSyncRecord *> *syncRecords = [NSMutableArray new];
		NSError *iterationError = error;

		[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *rowDictionary, BOOL *stop) {
			OCSyncRecord *syncRecord;

			if ((syncRecord = [self _syncRecordFromRowDictionary:rowDictionary cache:NO]) != nil)
			{
				[syncRecords addObject:syncRecord];
			}
		} error:&iterationError];

		if (completionHandler != nil)
		{
			completionHandler(self, iterationError, syncRecords);
		}
	}]];
}

- (void)retrieveSyncRecordAfterID:(OCSyncRecordID)recordID onLaneID:(OCSyncLaneID)laneID completionHandler:(OCDatabaseRetrieveSyncRecordCompletionHandler)completionHandler
{
	[self.sqlDB executeQuery:[OCSQLiteQuery querySelectingColumns:@[ @"recordID", @"recordData" ] fromTable:OCDatabaseTableNameSyncJournal where:@{
		@"recordID" 	: [OCSQLiteQueryCondition queryConditionWithOperator:@">" value:recordID apply:(recordID!=nil)],
		@"laneID"	: [OCSQLiteQueryCondition queryConditionWithOperator:@"=" value:laneID apply:(laneID!=nil)]
	} orderBy:@"recordID ASC" limit:@"0,1" resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		__block OCSyncRecord *syncRecord = nil;
		NSError *iterationError = error;

		[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *rowDictionary, BOOL *stop) {
			syncRecord = [self _syncRecordFromRowDictionary:rowDictionary cache:YES];
			*stop = YES;
		} error:&iterationError];

		if (completionHandler != nil)
		{
			completionHandler(self, iterationError, syncRecord);
		}
	}]];
}

- (void)retrieveSyncReasonCountsWithCompletionHandler:(OCDatabaseRetrieveSyncReasonCountsCompletionHandler)completionHandler
{
	[self.sqlDB executeQuery:[OCSQLiteQuery query:@"SELECT syncReason, COUNT(*) AS cnt FROM syncJournal GROUP BY syncReason" resultHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error, OCSQLiteTransaction * _Nullable transaction, OCSQLiteResultSet * _Nullable resultSet) {
		__block NSMutableDictionary<OCSyncReason, NSNumber *> *syncReasonCounts = [NSMutableDictionary new];

		[resultSet iterateUsing:^(OCSQLiteResultSet * _Nonnull resultSet, NSUInteger line, OCSQLiteRowDictionary  _Nonnull rowDictionary, BOOL * _Nonnull stop) {
			NSNumber *countForReason = (NSNumber *)rowDictionary[@"cnt"];
			OCSyncReason reason = (NSString *)rowDictionary[@"syncReason"];

			if ((countForReason != nil) && (reason != nil))
			{
				syncReasonCounts[reason] = countForReason;
			}
		} error:nil];

		completionHandler(self, error, syncReasonCounts);
	}]];
}

#pragma mark - Event interface
- (void)queueEvent:(OCEvent *)event forSyncRecordID:(OCSyncRecordID)syncRecordID processSession:(OCProcessSession *)processSession completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	NSData *eventData = [event serializedData];

	if ((eventData != nil) && (syncRecordID!=nil))
	{
		if (processSession == nil) { processSession = OCProcessManager.sharedProcessManager.processSession; }
		NSData *processSessionData = processSession.serializedData;

		[self.sqlDB executeQuery:[OCSQLiteQuery queryInsertingIntoTable:OCDatabaseTableNameEvents rowValues:@{
			@"recordID" 		: syncRecordID,
			@"processSession"	: (processSessionData!=nil) ? processSessionData : [NSData new],
			@"uuid"			: OCSQLiteNullProtect(event.uuid),
			@"eventData"		: eventData
		} resultHandler:^(OCSQLiteDB *db, NSError *error, NSNumber *rowID) {
			event.databaseID = rowID;

			if (rowID != nil)
			{
				self->_eventsByDatabaseID[rowID] = event;
			}
			else
			{
				OCLogError(@"Unexpected return from SQL insert into events table, rowID == nil, error: %@, event: %@", error, event);
			}

			completionHandler(self, error);
		}]];
	}
	else
	{
		OCLogError(@"Could not serialize event=%@ due to eventData=%@ or missing recordID=%@", event, eventData, syncRecordID);
		completionHandler(self, OCError(OCErrorInsufficientParameters));
	}
}

- (BOOL)queueContainsEvent:(OCEvent *)event
{
	if (!self.sqlDB.isOnSQLiteThread)
	{
		OCLogError(@"%@ may only be called on the SQLite thread. Returning NO.", @(__PRETTY_FUNCTION__));
		return (NO);
	}

	if (event.uuid == nil)
	{
		return (NO);
	}

	__block BOOL eventExistsInDatabase = NO;

	[self.sqlDB executeQuery:[OCSQLiteQuery querySelectingColumns:@[ @"eventID" ] fromTable:OCDatabaseTableNameEvents where:@{
		@"uuid"	: event.uuid
	} orderBy:@"eventID ASC" limit:@"0,1" resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		NSError *iterationError = error;

		[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *rowDictionary, BOOL *stop) {
			eventExistsInDatabase = YES;
			*stop = YES;
		} error:&iterationError];
	}]];

	return (eventExistsInDatabase);
}

- (OCEvent *)_eventFromRowDictionary:(NSDictionary<NSString *,id<NSObject>> *)rowDictionary processSession:(OCProcessSession **)outProcessSession doProcess:(BOOL *)outDoProcess
{
	OCEvent *event = nil;
	NSNumber *databaseID = nil;
	OCProcessSession *processSession = nil;

	if (outProcessSession != nil)
	{
		NSData *processSessionData = OCTypedCast(rowDictionary[@"processSession"], NSData);

		if ((processSessionData != nil) && (processSessionData.length > 0))
		{
			processSession = [OCProcessSession processSessionFromSerializedData:processSessionData];
		}

		*outProcessSession = processSession;
	}

	if ((databaseID = OCTypedCast(rowDictionary[@"eventID"], NSNumber) ) != nil)
	{
		if ((event = [self->_eventsByDatabaseID objectForKey:databaseID]) == nil)
		{
			event = [OCEvent eventFromSerializedData:(NSData *)rowDictionary[@"eventData"]];
		}

		event.databaseID = rowDictionary[@"eventID"];
	}

	BOOL doProcess = YES;

	if ((processSession != nil) && (event != nil))
	{
		// Only perform processSession validity check if bundleIDs differ
		if (![OCProcessManager.sharedProcessManager isSessionWithCurrentProcessBundleIdentifier:processSession])
		{
			// Don't process events originating from other processes that are running
			doProcess = ![OCProcessManager.sharedProcessManager isAnyInstanceOfSessionProcessRunning:processSession];
		}
	}

	if (outDoProcess != NULL)
	{
		*outDoProcess = doProcess;
	}

	return (event);
}

- (OCEvent *)nextEventForSyncRecordID:(OCSyncRecordID)recordID afterEventID:(OCDatabaseID)afterEventID
{
	__block OCEvent *event = nil;
	__block OCProcessSession *processSession = nil;
	__block BOOL doProcess = YES;

	if (!self.sqlDB.isOnSQLiteThread)
	{
		OCLogError(@"%@ may only be called on the SQLite thread. Returning nil.", @(__PRETTY_FUNCTION__));
		return (nil);
	}

	// Requests the oldest available event for the OCSyncRecordID.
	[self.sqlDB executeQuery:[OCSQLiteQuery querySelectingColumns:@[ @"eventID", /* @"processSession", */ @"eventData" ] fromTable:OCDatabaseTableNameEvents where:@{
		@"recordID" 	: recordID,
		@"eventID"	: [OCSQLiteQueryCondition queryConditionWithOperator:@">" value:afterEventID apply:(afterEventID!=nil)]
	} orderBy:@"eventID ASC" limit:@"0,1" resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		NSError *iterationError = error;

		[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *rowDictionary, BOOL *stop) {
			event = [self _eventFromRowDictionary:rowDictionary processSession:&processSession doProcess:&doProcess];

			*stop = YES;
		} error:&iterationError];
	}]];

	if (!doProcess)
	{
		// Do not skip and look for the next event… because this is about the events for a single sync record - and out of order execution should not happen
		return (nil);
	}

	return (event);
}

- (NSArray<OCEvent *> *)eventsForSyncRecordID:(OCSyncRecordID)recordID
{
	__block NSMutableArray<OCEvent *> *events = nil;

	[self.sqlDB executeQuery:[OCSQLiteQuery querySelectingColumns:@[ @"eventID", @"processSession", @"eventData" ] fromTable:OCDatabaseTableNameEvents where:@{
		@"recordID" 	: recordID,
	} orderBy:@"eventID ASC" limit:nil resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		NSError *iterationError = error;

		[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *rowDictionary, BOOL *stop) {
			OCEvent *event = nil;
			OCProcessSession *processSession = nil;
			BOOL doProcess = YES;

			if ((event = [self _eventFromRowDictionary:rowDictionary processSession:&processSession doProcess:&doProcess]) != nil)
			{
				NSMutableDictionary *ephermalUserInfo = [NSMutableDictionary new];

				if (event.ephermalUserInfo != nil)
				{
					[ephermalUserInfo addEntriesFromDictionary:event.ephermalUserInfo];
				}

				ephermalUserInfo[@"_processSession"] = processSession;
				ephermalUserInfo[@"_doProcess"] = @(doProcess);

				[event setValue:ephermalUserInfo forKey:@"ephermalUserInfo"]; // Change private variable

				if (events == nil)
				{
					events = [NSMutableArray new];
				}

				[events addObject:event];
			}

		} error:&iterationError];
	}]];

	return (events);
}

- (NSError *)removeEvent:(OCEvent *)event
{
	__block NSError *error = nil;

	if (!self.sqlDB.isOnSQLiteThread)
	{
		OCLogError(@"%@ may only be called on the SQLite thread.", @(__PRETTY_FUNCTION__));
		return (OCError(OCErrorInternal));
	}

	// Deletes the row for the OCEvent from the database.
	if (event.databaseID != nil)
	{
		[self.sqlDB executeQuery:[OCSQLiteQuery queryDeletingRowWithID:event.databaseID fromTable:OCDatabaseTableNameEvents completionHandler:^(OCSQLiteDB *db, NSError *dbError) {
			NSNumber *databaseID;

			if ((databaseID = event.databaseID) != nil)
			{
				[self->_eventsByDatabaseID removeObjectForKey:databaseID];

				event.databaseID = nil;
			}

			error = dbError;
		}]];
	}
	else
	{
		OCLogError(@"Event %@ passed to %@ without databaseID. Attempt of multi-removal?", event, @(__PRETTY_FUNCTION__));
		error = OCError(OCErrorInsufficientParameters);
	}

	return (error);
}

#pragma mark - Item policy interface
- (void)addItemPolicy:(OCItemPolicy *)itemPolicy completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	NSData *itemPolicyData = [NSKeyedArchiver archivedDataWithRootObject:itemPolicy];

	if (itemPolicyData != nil)
	{
		[self.sqlDB executeQuery:[OCSQLiteQuery queryInsertingIntoTable:OCDatabaseTableNameItemPolicies rowValues:@{
			@"identifier"	: OCSQLiteNullProtect(itemPolicy.identifier),
			@"path"		: OCSQLiteNullProtect(itemPolicy.location.path),
			@"localID"	: OCSQLiteNullProtect(itemPolicy.localID),
			@"kind"		: itemPolicy.kind,
			@"policyData"	: itemPolicyData,
		} resultHandler:^(OCSQLiteDB *db, NSError *error, NSNumber *rowID) {
			itemPolicy.databaseID = rowID;

			completionHandler(self, error);
		}]];
	}
	else
	{
		OCLogError(@"Could not serialize itemPolicy=%@ to itemPolicyData=%@", itemPolicy, itemPolicyData);
		completionHandler(self, OCError(OCErrorInsufficientParameters));
	}
}

- (void)updateItemPolicy:(OCItemPolicy *)itemPolicy completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	NSData *itemPolicyData = [NSKeyedArchiver archivedDataWithRootObject:itemPolicy];

	if ((itemPolicy.databaseID != nil) && (itemPolicyData != nil))
	{
		[self.sqlDB executeQuery:[OCSQLiteQuery queryUpdatingRowWithID:itemPolicy.databaseID inTable:OCDatabaseTableNameItemPolicies withRowValues:@{
			@"identifier"	: OCSQLiteNullProtect(itemPolicy.identifier),
			@"path"		: OCSQLiteNullProtect(itemPolicy.location.path),
			@"localID"	: OCSQLiteNullProtect(itemPolicy.localID),
			@"kind"		: itemPolicy.kind,
			@"policyData"	: itemPolicyData,
		} completionHandler:^(OCSQLiteDB *db, NSError *error) {
			completionHandler(self, error);
		}]];
	}
	else
	{
		OCLogError(@"Could not update item policy: serialize itemPolicy=%@ to itemPolicyData=%@ failed - or itemPolicy.databaseID=%@ is nil", itemPolicy, itemPolicyData, itemPolicy.databaseID);
		completionHandler(self, OCError(OCErrorInsufficientParameters));
	}
}

- (void)removeItemPolicy:(OCItemPolicy *)itemPolicy completionHandler:(OCDatabaseCompletionHandler)completionHandler
{
	if (itemPolicy.databaseID != nil)
	{
		[self.sqlDB executeQuery:[OCSQLiteQuery queryDeletingRowWithID:itemPolicy.databaseID fromTable:OCDatabaseTableNameItemPolicies completionHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error) {
			completionHandler(self, error);
		}]];
	}
	else
	{
		OCLogError(@"Could not remove item policy: itemPolicy.databaseID is nil");
		completionHandler(self, OCError(OCErrorInsufficientParameters));
	}
}

- (void)retrieveItemPoliciesForKind:(OCItemPolicyKind)kind path:(OCPath)path localID:(OCLocalID)localID identifier:(OCItemPolicyIdentifier)identifier completionHandler:(OCDatabaseRetrieveItemPoliciesCompletionHandler)completionHandler
{
	[self.sqlDB executeQuery:[OCSQLiteQuery querySelectingColumns:@[ @"policyID", @"policyData" ] fromTable:OCDatabaseTableNameItemPolicies where:@{
		@"identifier"	: [OCSQLiteQueryCondition queryConditionWithOperator:@"=" value:identifier 	apply:(identifier!=nil)],
		@"path"		: [OCSQLiteQueryCondition queryConditionWithOperator:@"=" value:path		apply:(path!=nil)],
		@"localID"	: [OCSQLiteQueryCondition queryConditionWithOperator:@"=" value:localID 	apply:(localID!=nil)],
		@"kind"		: [OCSQLiteQueryCondition queryConditionWithOperator:@"=" value:kind		apply:(kind!=nil)]
	} resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		NSMutableArray<OCItemPolicy *> *itemPolicies = [NSMutableArray new];
		NSError *iterationError = error;

		[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> *rowDictionary, BOOL *stop) {
			NSData *policyData;

			if ((policyData = (id)rowDictionary[@"policyData"]) != nil)
			{
				OCItemPolicy *itemPolicy = nil;

				if ((itemPolicy = [NSKeyedUnarchiver unarchiveObjectWithData:policyData]) != nil)
				{
					itemPolicy.databaseID = rowDictionary[@"policyID"];
					[itemPolicies addObject:itemPolicy];
				}
			}
		} error:&iterationError];

		if (completionHandler != nil)
		{
			completionHandler(self, iterationError, itemPolicies);
		}
	}]];
}

#pragma mark - Integrity / Synchronization primitives
- (void)retrieveValueForCounter:(OCDatabaseCounterIdentifier)counterIdentifier completionHandler:(void(^)(NSError *error, NSNumber *counterValue))completionHandler
{
	[self.sqlDB executeQuery:[OCSQLiteQuery query:@"SELECT value FROM counters WHERE identifier = ?" withParameters:@[ counterIdentifier ] resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
		__block NSNumber *counterValue = nil;
		NSError *returnError = error;

		if (error == nil)
		{
			[resultSet iterateUsing:^(OCSQLiteResultSet *resultSet, NSUInteger line, NSDictionary<NSString *,id> *rowDictionary, BOOL *stop) {
				counterValue = rowDictionary[@"value"];
			} error:&returnError];

			if (counterValue == nil)
			{
				counterValue = @(0);
			}
		}

		completionHandler(returnError, counterValue);
	}]];
}

- (void)increaseValueForCounter:(OCDatabaseCounterIdentifier)counterIdentifier withProtectedBlock:(NSError *(^)(NSNumber *previousCounterValue, NSNumber *newCounterValue))protectedBlock completionHandler:(OCDatabaseProtectedBlockCompletionHandler)completionHandler
{
	[self.sqlDB executeTransaction:[OCSQLiteTransaction transactionWithBlock:^NSError *(OCSQLiteDB *db, OCSQLiteTransaction *transaction) {
		__block NSNumber *previousValue=nil, *newValue=nil;
		__block NSError *transactionError = nil;

		// Retrieve current value
		[self retrieveValueForCounter:counterIdentifier completionHandler:^(NSError *error, NSNumber *counterValue) {
			previousValue = counterValue;
			if (error != nil) { transactionError = error; }
		}];

		// Update value
		if (transactionError == nil)
		{
			if ((previousValue==nil) || (previousValue.integerValue==0))
			{
				// Create row
				[db executeQuery:[OCSQLiteQuery query:@"INSERT INTO counters (identifier, value, lastUpdated) VALUES (?, ?, ?)" withParameters:@[ counterIdentifier, @(1), @(NSDate.timeIntervalSinceReferenceDate) ] resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
					if (error != nil) { transactionError = error; }
				}]];
			}
			else
			{
				// Update row
				[db executeQuery:[OCSQLiteQuery query:@"UPDATE counters SET value = value + 1, lastUpdated = ? WHERE identifier = ?" withParameters:@[ @(NSDate.timeIntervalSinceReferenceDate), counterIdentifier ] resultHandler:^(OCSQLiteDB *db, NSError *error, OCSQLiteTransaction *transaction, OCSQLiteResultSet *resultSet) {
					if (error != nil) { transactionError = error; }
				}]];
			}
		}

		// Retrieve new value
		if (transactionError == nil)
		{
			[self retrieveValueForCounter:counterIdentifier completionHandler:^(NSError *error, NSNumber *counterValue) {
				newValue = counterValue;
				if (error != nil) { transactionError = error; }
			}];

			if (transactionError == nil)
			{
				NSMutableDictionary *userInfo = [NSMutableDictionary new];

				if (previousValue != nil) { userInfo[@"old"] = previousValue; }
				if (newValue != nil)	  { userInfo[@"new"] = newValue; }

				transaction.userInfo = userInfo;
			}
		}

		// Perform protected block
		if ((transactionError == nil) && (protectedBlock != nil))
		{
			transactionError = protectedBlock(previousValue, newValue);
		}

		return (transactionError);
	} type:OCSQLiteTransactionTypeExclusive completionHandler:^(OCSQLiteDB *db, OCSQLiteTransaction *transaction, NSError *error) {
		if (completionHandler != nil)
		{
			completionHandler(error, ((NSDictionary *)transaction.userInfo)[@"old"], ((NSDictionary *)transaction.userInfo)[@"new"]);
		}
	}]];
}

#pragma mark - Log tags
+ (NSArray<OCLogTagName> *)logTags
{
	return (@[@"DB"]);
}

- (NSArray<OCLogTagName> *)logTags
{
	return (@[@"DB"]);
}

@end
