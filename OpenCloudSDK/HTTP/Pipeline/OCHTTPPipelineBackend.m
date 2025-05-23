//
//  OCHTTPPipelineBackend.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 04.02.19.
//  Copyright © 2019 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2019, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import "OCHTTPPipelineBackend.h"
#import "OCSQLiteDB.h"
#import "OCSQLiteTableSchema.h"
#import "OCSQLiteTransaction.h"
#import "OCSQLiteQueryCondition.h"
#import "OCHTTPPipelineTask.h"
#import "OCMacros.h"
#import "OCHTTPPipelineTaskCache.h"
#import "OCLogger.h"
#import "NSError+OCError.h"

// High verbosity
// #define TaskDescription(task) task

// Medium verbosity
#define TaskDescription(task) [NSString stringWithFormat:@"taskID=%@, requestID=%@, request.ATID=%@, request.identifier=%@", task.taskID, task.requestID, task.request.actionTrackingID, task.request.identifier]

// Low verbosity
// #define TaskDescription(task) task.taskID

static NSString *OCHTTPPipelineTasksTableName = @"httpPipelineTasks";

@implementation OCHTTPPipelineBackend

#pragma mark - Init & dealloc
- (instancetype)init
{
	return ([self initWithSQLDB:nil temporaryFilesRoot:nil]);
}

- (instancetype)initWithSQLDB:(nullable OCSQLiteDB *)sqlDB temporaryFilesRoot:(nullable NSURL *)temporaryFilesRoot
{
	if ((self = [super init]) != nil)
	{
		_bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
		if (temporaryFilesRoot != nil)
		{
			_temporaryFilesRoot = temporaryFilesRoot;
		}

		_taskCache = [[OCHTTPPipelineTaskCache alloc] initWithBackend:self];

		if (sqlDB != nil)
		{
			_sqlDB = sqlDB;
			if (_sqlDB.databaseURL != nil)
			{
				_sqlDB.journalMode = OCSQLiteJournalModeWAL;
				OCLogDebug(@"PipelineBackendDB=%@", _sqlDB.databaseURL.path);
			}
		}
		else
		{
			_sqlDB = [[OCSQLiteDB alloc] initWithURL:nil];
		}

		// Share one thread across all OCHTTPPipelineBackend SQLite databases
		_sqlDB.runLoopThreadName = @"OCHTTPPipelineBackend SQL Thread";
	}

	[self addSchemas];

	return (self);
}

- (void)dealloc
{

}

#pragma mark - Open & Close
- (void)openWithCompletionHandler:(OCCompletionHandler)completionHandler
{
	if (_sqlDB != nil)
	{
		@synchronized(self)
		{
			_openCount++;

			if (_openCount == 1)
			{
				_openCompletionHandler = [completionHandler copy];

				[_sqlDB openWithFlags:OCSQLiteOpenFlagsDefault completionHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error) {
					db.maxBusyRetryTimeInterval = 10; // Avoid busy timeout if another process performs large changes
					[db executeQueryString:@"PRAGMA synchronous=FULL"]; // Force checkpoint / synchronization after every transaction

					if (error == nil)
					{
						[self->_sqlDB applyTableSchemasWithCompletionHandler:^(OCSQLiteDB *db, NSError *error) {
							@synchronized(self)
							{
								OCCompletionHandler completionHandler = self->_openCompletionHandler;
								self->_openCompletionHandler = nil;
								completionHandler(self, error);
							}
						}];
					}
					else
					{
						@synchronized(self)
						{
							OCCompletionHandler completionHandler = self->_openCompletionHandler;
							self->_openCompletionHandler = nil;
							completionHandler(self, error);
						}
					}
				}];
			}
			else
			{
				if (self->_openCompletionHandler != nil)
				{
					OCCompletionHandler oldCompletionHandler = self->_openCompletionHandler;

					self->_openCompletionHandler = ^(id sender, NSError *error) {
						oldCompletionHandler(sender, error);
						completionHandler(sender, error);
					};
				}
				else
				{
					completionHandler(self, nil);
				}
			}
		}
	}
	else
	{
		completionHandler(self, OCError(OCErrorInternal));
	}
}

- (void)closeWithCompletionHandler:(OCCompletionHandler)completionHandler
{
	if (_sqlDB != nil)
	{
		BOOL openCountZero;

		@synchronized (self)
		{
			if (_openCount > 0)
			{
				_openCount--;
			}

			openCountZero = (_openCount == 0);
		}

		if (openCountZero)
		{
			dispatch_block_t closeBlock = ^{
				[self->_sqlDB closeWithCompletionHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error) {
					completionHandler(self, error);
				}];
			};

			@synchronized (self)
			{
				if (self->_openCompletionHandler != nil)
				{
					OCCompletionHandler oldCompletionHandler = self->_openCompletionHandler;

					self->_openCompletionHandler = ^(id sender, NSError *error) {
						oldCompletionHandler(sender, error);
						closeBlock();
					};

					return; // Avoid closeBlock being called twice
				}
			}

			closeBlock();
		}
		else
		{
			completionHandler(self, nil);
		}
	}
	else
	{
		completionHandler(self, OCError(OCErrorInternal));
	}
}

#pragma mark - Schemas
- (void)addSchemas
{
	// Version 1
	[_sqlDB addTableSchema:[OCSQLiteTableSchema
		schemaWithTableName:OCHTTPPipelineTasksTableName
		version:1
		creationQueries:@[
			/*
				taskID : INTEGER		- unique ID used to uniquely identify and efficiently update a row

				pipelineID : TEXT		- ID of the pipeline
				bundleID : TEXT			- bundle identifier of the process from which the record originated

				urlSessionID : TEXT		- ID of the pipeline's URL session
				urlSessionTaskID : INTEGER	- the NSURLSessionTask.taskIdentifier of this request

				partitionID : TEXT		- ID of the partition for which this request was scheduled
				groupID : TEXT			- group ID this request belongs to

				state : INTEGER			- status of request: pending, inProcess, completed

				requestID : TEXT		- the OCHTTPRequestID of this request

				requestData : BLOB		- data of serialized OCHTTPRequest
				requestFinal : INTEGER 		- Boolean indicating whether the request is final, i.e. can be sent "as-is" (without going through the delegate)

				responseData : BLOB		- data of serialized OCHTTPResponse
			*/
			@"CREATE TABLE httpPipelineTasks (taskID INTEGER PRIMARY KEY AUTOINCREMENT, pipelineID TEXT NOT NULL, bundleID TEXT NOT NULL, urlSessionID TEXT, urlSessionTaskID INTEGER, partitionID TEXT NOT NULL, groupID TEXT, state INTEGER NOT NULL, requestID TEXT NOT NULL, requestData BLOB NOT NULL, requestFinal INTEGER NOT NULL, responseData BLOB)",
		]
		openStatements:nil
		upgradeMigrator:nil]
	];

	// Version 2
	[_sqlDB addTableSchema:[OCSQLiteTableSchema
		schemaWithTableName:OCHTTPPipelineTasksTableName
		version:2
		creationQueries:@[
			/*
				taskID : INTEGER		- unique ID used to uniquely identify and efficiently update a row

				pipelineID : TEXT		- ID of the pipeline
				bundleID : TEXT			- bundle identifier of the process from which the record originated

				urlSessionID : TEXT		- ID of the pipeline's URL session
				urlSessionTaskID : INTEGER	- the NSURLSessionTask.taskIdentifier of this request

				partitionID : TEXT		- ID of the partition for which this request was scheduled
				groupID : TEXT			- group ID this request belongs to

				state : INTEGER			- status of request: pending, inProcess, completed

				requestID : TEXT		- the OCHTTPRequestID of this request
				actionTrackingID : TEXT		- the OCActionTrackingID of this request (if any)

				requestData : BLOB		- data of serialized OCHTTPRequest
				requestFinal : INTEGER 		- Boolean indicating whether the request is final, i.e. can be sent "as-is" (without going through the delegate)

				responseData : BLOB		- data of serialized OCHTTPResponse
			*/
			@"CREATE TABLE httpPipelineTasks (taskID INTEGER PRIMARY KEY AUTOINCREMENT, pipelineID TEXT NOT NULL, bundleID TEXT NOT NULL, urlSessionID TEXT, urlSessionTaskID INTEGER, partitionID TEXT NOT NULL, groupID TEXT, state INTEGER NOT NULL, requestID TEXT NOT NULL, actionTrackingID TEXT, requestData BLOB NOT NULL, requestFinal INTEGER NOT NULL, responseData BLOB)",
		]
		openStatements:nil
		upgradeMigrator:^(OCSQLiteDB *db, OCSQLiteTableSchema *schema, void (^completionHandler)(NSError *error)) {
			// Migrate to version 2
			[db executeTransaction:[OCSQLiteTransaction transactionWithBlock:^NSError *(OCSQLiteDB *db, OCSQLiteTransaction *transaction) {
				INSTALL_TRANSACTION_ERROR_COLLECTION_RESULT_HANDLER

				// Add actionTrackingID column
				[db executeQuery:[OCSQLiteQuery query:@"ALTER TABLE httpPipelineTasks ADD COLUMN actionTrackingID TEXT" resultHandler:resultHandler]];
				if (transactionError != nil) { return(transactionError); }

				return (transactionError);

			} type:OCSQLiteTransactionTypeDeferred completionHandler:^(OCSQLiteDB *db, OCSQLiteTransaction *transaction, NSError *error) {
				completionHandler(error);
			}]];
		}]

	];
}

#pragma mark - Task access
- (NSError *)addPipelineTask:(OCHTTPPipelineTask *)task
{
	OCTLogVerbose(@[@"enter"], @"addPipelineTask: task=%@", TaskDescription(task));

	return([_sqlDB executeOperationSync:^NSError * _Nullable(OCSQLiteDB * _Nonnull db) {
		__block NSError *insertionError = nil;

		// Persist in database
		NSDictionary<NSString *,id<NSObject>> *rowValues = @{
			@"pipelineID" 		: task.pipelineID,
			@"bundleID"		: task.bundleID,

			@"urlSessionID"		: OCSQLiteNullProtect(task.urlSessionID),

			@"partitionID"		: task.partitionID,
			@"groupID"		: OCSQLiteNullProtect(task.groupID),

			@"state"		: @(task.state),

			@"actionTrackingID"	: OCSQLiteNullProtect(task.request.actionTrackingID),

			@"requestID"		: task.requestID,
			@"requestData"		: task.requestData,

			@"requestFinal"		: @(task.requestFinal)
		};

		OCTLogVerbose(@[@"values"], @"Inserting into tasks table: %@", rowValues);

		[db executeQuery:[OCSQLiteQuery queryInsertingIntoTable:OCHTTPPipelineTasksTableName rowValues:rowValues resultHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error, NSNumber * _Nullable rowID) {
			task.taskID = rowID;

			insertionError = error;
		}]];

		// Update cache
		[self->_taskCache updateWithTask:task remove:NO];

		OCTLogVerbose(@[@"leave"], @"addPipelineTask: task.taskID=%@, error=%@, task=%@", task.taskID, insertionError, TaskDescription(task));

		if (insertionError != nil)
		{
			OCLogError(@"Error inserting task=%@: %@", task, insertionError);
		}

		return (insertionError);
	}]);
}

- (NSError *)updatePipelineTask:(OCHTTPPipelineTask *)task
{
	OCTLogVerbose(@[@"enter"], @"updatePipelineTask: task=%@", TaskDescription(task));

	if (task.taskID == nil)
	{
		OCTLogError(@[@"leave"], @"updatePipelineTask: attempt to update task without taskID: task=%@", TaskDescription(task));
		return (OCError(OCErrorInsufficientParameters));
	}

	return([_sqlDB executeOperationSync:^NSError * _Nullable(OCSQLiteDB * _Nonnull db) {
		__block NSError *updateError = nil;
		NSDictionary<NSString *,id<NSObject>> *rowValues = @{
			@"bundleID" 		: task.bundleID,

			@"urlSessionID" 	: OCSQLiteNullProtect(task.urlSessionID),
			@"urlSessionTaskID"	: OCSQLiteNullProtect(task.urlSessionTaskID),

			@"state"		: @(task.state),

			@"requestID"		: task.requestID,
			@"requestData"		: task.requestData,

			@"responseData"		: OCSQLiteNullProtect(task.responseData),
		};

		OCTLogVerbose(@[@"values"], @"Updating tasks table for taskID=%@: %@", task.taskID, rowValues);

		[db executeQuery:[OCSQLiteQuery queryUpdatingRowWithID:task.taskID inTable:OCHTTPPipelineTasksTableName withRowValues:rowValues completionHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error) {
			updateError = error;
		}]];

		// Update cache
		[self->_taskCache updateWithTask:task remove:NO];

		if (updateError != nil)
		{
			OCLogError(@"Error updating task=%@: %@", task, updateError);
		}

		OCTLogVerbose(@[@"leave"], @"updatePipelineTask: task.taskID=%@, error=%@, task=%@", task.taskID, updateError, TaskDescription(task));

		return (updateError);
	}]);
}

- (NSError *)removePipelineTask:(OCHTTPPipelineTask *)task
{
	OCTLogVerbose(@[@"enter"], @"removePipelineTask: task=%@", TaskDescription(task));

	if (task.taskID == nil)
	{
		OCTLogError(@[@"leave"], @"removePipelineTask: attempt to remove task without taskID: task=%@", TaskDescription(task));
		return (OCError(OCErrorInsufficientParameters));
	}

	return([_sqlDB executeOperationSync:^NSError * _Nullable(OCSQLiteDB * _Nonnull db) {
		__block NSError *removeError = nil;

		[db executeQuery:[OCSQLiteQuery queryDeletingRowWithID:task.taskID fromTable:OCHTTPPipelineTasksTableName completionHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error) {
			removeError = error;
		}]];

		// Remove from cache
		[self->_taskCache updateWithTask:task remove:YES];

		if (removeError != nil)
		{
			OCLogError(@"Error removing task=%@: %@", task, removeError);
		}

		OCTLogVerbose(@[@"leave"], @"removePipelineTask: task.taskID=%@, error=%@, task=%@", task.taskID, removeError, TaskDescription(task));

		return (removeError);
	}]);
}

- (NSError *)removeAllTasksForPipeline:(OCHTTPPipelineID)pipelineID partition:(OCHTTPPipelinePartitionID)partitionID
{
	OCTLogVerbose(@[@"enter"], @"removeAllTasksForPipeline: pipelineID=%@, partitionID=%@", pipelineID, partitionID);

	if ((pipelineID == nil) || (partitionID == nil))
	{
		OCLogError(@"Attempt to remove all tasks for pipeline=%@, partitionID=%@", pipelineID, partitionID);
		return (OCError(OCErrorInsufficientParameters));
	}

	return([_sqlDB executeOperationSync:^NSError * _Nullable(OCSQLiteDB * _Nonnull db) {
		__block NSError *removeError = nil;

		[db executeQuery:[OCSQLiteQuery queryDeletingRowsWhere:@{
			@"pipelineID" 		: pipelineID,
			@"partitionID"		: partitionID
		} fromTable:OCHTTPPipelineTasksTableName completionHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error) {
			removeError = error;
		}]];

		// Update cache
		[self->_taskCache removeAllTasksForPipeline:pipelineID partition:partitionID];

		OCTLogVerbose(@[@"leave"], @"removeAllTasksForPipeline: pipelineID=%@, partitionID=%@, removeError=%@", pipelineID, partitionID, removeError);

		return (removeError);
	}]);
}

- (OCHTTPPipelineTask *)_retrieveTaskWhere:(nullable NSDictionary<NSString *,id<NSObject>> *)whereConditions error:(NSError * _Nullable *)outDBError
{
	NSError *dbError = nil;
	__block OCHTTPPipelineTask *task = nil;

	dbError = [_sqlDB executeOperationSync:^NSError * _Nullable(OCSQLiteDB * _Nonnull db) {
		__block NSError *retrieveError = nil;

		[db executeQuery:[OCSQLiteQuery querySelectingColumns:nil fromTable:OCHTTPPipelineTasksTableName where:whereConditions resultHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error, OCSQLiteTransaction * _Nullable transaction, OCSQLiteResultSet * _Nullable resultSet) {
			retrieveError = error;

			if (error == nil)
			{
				OCSQLiteRowDictionary rowDictionary;

				if ((rowDictionary = [resultSet nextRowDictionaryWithError:&retrieveError]) != nil)
				{
					// Retrieve from cache (if possible)
					if ((task = [self->_taskCache cachedTaskForPipelineTaskID:(NSNumber *)rowDictionary[@"taskID"]]) == nil)
					{
					 	// If not, assemble new OCHTTPPipelineTask ..
						if ((task = [[OCHTTPPipelineTask alloc] initWithRowDictionary:rowDictionary]) != nil)
						{
							// .. and store it in the cache
							[self->_taskCache updateWithTask:task remove:NO];
						}
					}
				}
			}
		}]];

		return (retrieveError);
	}];

	if (outDBError != NULL)
	{
		*outDBError = dbError;
	}

	OCLogVerbose(@"Retrieve task where %@ - return task=%@, dbError=%@", whereConditions, task, dbError);

	return (task);
}

- (OCHTTPPipelineTask *)retrieveTaskForRequestID:(OCHTTPRequestID)requestID error:(NSError **)outDBError
{
	if (requestID == nil)
	{
		OCLogError(@"Attempt to retrieve task without requestID.");
		return (nil);
	}

	return ([self _retrieveTaskWhere:@{
			@"requestID" : requestID
		} error:outDBError]);
}

- (OCHTTPPipelineTask *)retrieveTaskForPipeline:(OCHTTPPipeline *)pipeline URLSession:(NSURLSession *)urlSession task:(NSURLSessionTask *)urlSessionTask error:(NSError **)outDBError
{
	NSString *urlSessionIdentifier = urlSession.configuration.identifier;

	OCHTTPPipelineTask *task;

	NSString *XRequestID = [urlSessionTask.currentRequest valueForHTTPHeaderField:OCHTTPHeaderFieldNameXRequestID];

	/*
		WARNING: urlSessionTask.taskIdentifier is not unique!

		Identifiers can be reused - even on background queues - after a queue
		has been shut down and recreated.

		Therefore, the XRequestID is used as preferred search criteria to retrieve
		the correct OCHTTPPipelineTask for a NSURLSessionTask.
	*/

	// Repurpose X-Request-ID to retrieve by requestID ..
	if (XRequestID != nil)
	{
		// .. narrowing further by sessionID and sessionTaskID
		task = [self _retrieveTaskWhere:@{
				@"pipelineID"	    : pipeline.identifier,
				@"requestID"	    : XRequestID,
				@"urlSessionID"	    : OCSQLiteNullProtect(urlSessionIdentifier),
				@"urlSessionTaskID" : @(urlSessionTask.taskIdentifier)
		} error:outDBError];

		if (task == nil)
		{
			// .. using just the request ID
			task = [self _retrieveTaskWhere:@{
					@"pipelineID"	: pipeline.identifier,
					@"requestID"	: XRequestID
			} error:outDBError];
		}
	}

	// Use combination of urlSessionID and urlSessionTaskID to retrieve task
	if (task == nil)
	{
		task = [self _retrieveTaskWhere:@{
			@"pipelineID"	  	: pipeline.identifier,
			@"bundleID"	  	: [OCSQLiteQueryCondition queryConditionWithOperator:@"=" value:pipeline.bundleIdentifier apply:(urlSessionIdentifier==nil)],
			@"urlSessionID"	  	: OCSQLiteNullProtect(urlSessionIdentifier),
			@"urlSessionTaskID" 	: @(urlSessionTask.taskIdentifier)
		} error:outDBError];
	}

	return (task);
}

- (NSError *)enumerateTasksForPipeline:(OCHTTPPipeline *)pipeline enumerator:(void (^)(OCHTTPPipelineTask * _Nonnull, BOOL * _Nonnull))taskEnumerator
{
	return ([self enumerateTasksWhere:@{
			@"pipelineID" : pipeline.identifier,
		} orderBy:@"taskID" limit:nil enumerator:taskEnumerator]);
}

- (NSError *)enumerateTasksForPipeline:(OCHTTPPipeline *)pipeline partition:(OCHTTPPipelinePartitionID)partitionID enumerator:(void (^)(OCHTTPPipelineTask * _Nonnull, BOOL * _Nonnull))taskEnumerator
{
	return ([self enumerateTasksWhere:@{
			@"pipelineID" : pipeline.identifier,
			@"partitionID"  : partitionID
		} orderBy:@"taskID" limit:nil enumerator:taskEnumerator]);
}

- (NSError *)enumerateCompletedTasksForPipeline:(OCHTTPPipeline *)pipeline partition:(OCHTTPPipelinePartitionID)partitionID enumerator:(void (^)(OCHTTPPipelineTask * _Nonnull, BOOL * _Nonnull))taskEnumerator
{
	return ([self enumerateTasksWhere:@{
			@"pipelineID"   : pipeline.identifier,
			@"partitionID"  : partitionID,
			@"state"	: @(OCHTTPPipelineTaskStateCompleted)
		} orderBy:@"taskID" limit:nil enumerator:taskEnumerator]);
}

- (NSError *)enumerateTasksWhere:(nullable NSDictionary<NSString *,id<NSObject>> *)whereConditions orderBy:(nullable NSString *)orderBy limit:(nullable NSString *)limit enumerator:(void (^)(OCHTTPPipelineTask * _Nonnull, BOOL * _Nonnull))taskEnumerator
{
	NSError *dbError = nil;

	dbError = [_sqlDB executeOperationSync:^NSError * _Nullable(OCSQLiteDB * _Nonnull db) {
		__block NSError *retrieveError = nil;

		[db executeQuery:[OCSQLiteQuery querySelectingColumns:nil
						fromTable:OCHTTPPipelineTasksTableName
						where:whereConditions
						orderBy:orderBy
						limit:limit
						resultHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error, OCSQLiteTransaction * _Nullable transaction, OCSQLiteResultSet * _Nullable resultSet)
		{
			retrieveError = error;

			if (error == nil)
			{
				[resultSet iterateUsing:^(OCSQLiteResultSet * _Nonnull resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> * _Nonnull rowDictionary, BOOL * _Nonnull stop) {
					OCHTTPPipelineTask *task;

					// Retrieve from cache (if possible)
					if ((task = [self->_taskCache cachedTaskForPipelineTaskID:(NSNumber *)rowDictionary[@"taskID"]]) == nil)
					{
					 	// If not, assemble new OCHTTPPipelineTask ..
						if ((task = [[OCHTTPPipelineTask alloc] initWithRowDictionary:rowDictionary]) != nil)
						{
							// .. and store it in the cache
							[self->_taskCache updateWithTask:task remove:NO];
						}
					}

					if (task != nil)
					{
						taskEnumerator(task, stop);
					}
				} error:&retrieveError];
			}
		}]];

		return (retrieveError);
	}];

	return (dbError);
}

- (NSNumber *)numberOfRequestsWithState:(OCHTTPPipelineTaskState)state inPipeline:(OCHTTPPipeline *)pipeline partition:(OCHTTPPipelinePartitionID)partitionID error:(NSError **)outDBError
{
	NSError *dbError = nil;
	__block NSNumber *numberOfRequestsWithState = nil;

	dbError = [_sqlDB executeOperationSync:^NSError * _Nullable(OCSQLiteDB * _Nonnull db) {
		__block NSError *retrieveError = nil;

		NSString *queryString = (partitionID != nil) ?
						@"SELECT COUNT(*) AS cnt FROM httpPipelineTasks WHERE pipelineID=:pipelineID AND state=:state AND partitionID=:partitionID" :
						@"SELECT COUNT(*) AS cnt FROM httpPipelineTasks WHERE pipelineID=:pipelineID AND state=:state";

		[db executeQuery:[OCSQLiteQuery query:queryString withNamedParameters:[NSDictionary dictionaryWithObjectsAndKeys:
			pipeline.identifier, 	@"pipelineID",
			@(state), 		@"state",
			partitionID,		@"partitionID",
		nil] resultHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error, OCSQLiteTransaction * _Nullable transaction, OCSQLiteResultSet * _Nullable resultSet) {
			numberOfRequestsWithState = (NSNumber *)[resultSet nextRowDictionaryWithError:&retrieveError][@"cnt"];
		}]];

		return (retrieveError);
	}];

	if (outDBError != NULL)
	{
		*outDBError = dbError;
	}

	return (numberOfRequestsWithState);
}

- (NSNumber *)numberOfRequestsInPipeline:(OCHTTPPipeline *)pipeline partition:(OCHTTPPipelinePartitionID)partitionID error:(NSError * _Nullable *)outDBError
{
	NSError *dbError = nil;
	__block NSNumber *numberOfRequests = nil;

	dbError = [_sqlDB executeOperationSync:^NSError * _Nullable(OCSQLiteDB * _Nonnull db) {
		__block NSError *retrieveError = nil;

		[db executeQuery:[OCSQLiteQuery query:@"SELECT COUNT(*) AS cnt FROM httpPipelineTasks WHERE pipelineID=:pipelineID AND partitionID=:partitionID" withNamedParameters:@{
			@"pipelineID" : pipeline.identifier,
			@"partitionID" : partitionID
		} resultHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error, OCSQLiteTransaction * _Nullable transaction, OCSQLiteResultSet * _Nullable resultSet) {
			numberOfRequests = (NSNumber *)[resultSet nextRowDictionaryWithError:&retrieveError][@"cnt"];
		}]];

		return (retrieveError);
	}];

	if (outDBError != NULL)
	{
		*outDBError = dbError;
	}

	return (numberOfRequests);
}

- (void)retrieveActionTrackingIDsForPartition:(OCHTTPPipelinePartitionID)partitionID resultHandler:(void (^)(NSError * _Nullable error, NSSet<OCActionTrackingID> * _Nullable trackingsIDs, NSNumber * _Nullable totalNumberOfRequestsInBackend))resultHandler
{
	__block NSMutableSet<OCActionTrackingID> *actionTrackingIDs = nil;
	__block NSNumber *numberOfRequests = nil;
	__block NSError *retrieveError = nil;

	[_sqlDB executeTransaction:[OCSQLiteTransaction
		transactionWithQueries:@[
			// Retrieve http tasks who have actionTrackingIDs
			[OCSQLiteQuery query:@"SELECT actionTrackingID, pipelineID FROM httpPipelineTasks WHERE partitionID=:partitionID AND actionTrackingID IS NOT NULL" withNamedParameters:@{
				@"partitionID" : partitionID
			} resultHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error, OCSQLiteTransaction * _Nullable transaction, OCSQLiteResultSet * _Nullable resultSet) {
				if (error == nil)
				{
					actionTrackingIDs = [NSMutableSet new];

					[resultSet iterateUsing:^(OCSQLiteResultSet * _Nonnull resultSet, NSUInteger line, NSDictionary<NSString *,id<NSObject>> * _Nonnull rowDictionary, BOOL * _Nonnull stop) {
						OCActionTrackingID actionTrackingID;

						if ((actionTrackingID = (OCActionTrackingID)rowDictionary[@"actionTrackingID"]) != nil) {
							[actionTrackingIDs addObject:actionTrackingID];
							OCLogDebug(@"Found request with actionTrackingID %@ in partition %@ pipeline %@", actionTrackingID, partitionID, rowDictionary[@"pipelineID"]);
						}
					} error:&retrieveError];
				}
			}],

			// Retrieve number of pipeline tasks
			[OCSQLiteQuery query:@"SELECT COUNT(*) AS cnt FROM httpPipelineTasks WHERE partitionID=:partitionID" withNamedParameters:@{
				@"partitionID" : partitionID
			} resultHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error, OCSQLiteTransaction * _Nullable transaction, OCSQLiteResultSet * _Nullable resultSet) {
				numberOfRequests = (NSNumber *)[resultSet nextRowDictionaryWithError:&retrieveError][@"cnt"];
			}]
		]
		type:OCSQLiteTransactionTypeExclusive
		completionHandler:^(OCSQLiteDB * _Nonnull db, OCSQLiteTransaction * _Nonnull transaction, NSError * _Nullable error) {
			if (resultHandler != nil)
			{
				resultHandler(error, actionTrackingIDs, numberOfRequests);
			}
		}]
	];
}

- (BOOL)isOnQueueThread
{
	return _sqlDB.isOnSQLiteThread;
}

- (void)queueBlock:(dispatch_block_t)block
{
	[_sqlDB executeOperation:^NSError * _Nullable(OCSQLiteDB * _Nonnull db) {
		block();
		return(nil);
	} completionHandler:nil];
}

#pragma mark - Storage
- (NSURL *)temporaryFilesRoot
{
	if (_temporaryFilesRoot == nil)
	{
		_temporaryFilesRoot = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"OCHTTPPipeline"];
		[[NSFileManager defaultManager] createDirectoryAtURL:_temporaryFilesRoot withIntermediateDirectories:YES attributes:@{ NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication } error:NULL];
	}

	return (_temporaryFilesRoot);
}

#pragma mark - Debugging
- (void)dumpDBTable
{
	OCSyncExec(dumpTable, {
		[_sqlDB executeQuery:[OCSQLiteQuery query:@"SELECT * FROM httpPipelineTasks" resultHandler:^(OCSQLiteDB * _Nonnull db, NSError * _Nullable error, OCSQLiteTransaction * _Nullable transaction, OCSQLiteResultSet * _Nullable resultSet) {

			OCLogDebug(@"== Dumping Pipeline tasks:");
			[resultSet iterateUsing:^(OCSQLiteResultSet * _Nonnull resultSet, NSUInteger line, OCSQLiteRowDictionary  _Nonnull rowDictionary, BOOL * _Nonnull stop) {
				if (rowDictionary != nil)
				{
					OCLogDebug(@"%@", rowDictionary);
				}
			} error:nil];

			OCSyncExecDone(dumpTable);
		}]];
	});
}

#pragma mark - Log tagging
+ (NSArray<OCLogTagName> *)logTags
{
	return (@[@"HTTPPipelineBackend"]);
}

- (NSArray<OCLogTagName> *)logTags
{
	return (@[@"HTTPPipelineBackend"]);
}

@end
