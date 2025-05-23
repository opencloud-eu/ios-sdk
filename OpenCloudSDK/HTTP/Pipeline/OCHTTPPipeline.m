//
//  OCHTTPPipeline.m
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

#import "OCHTTPPipeline.h"
#import "OCHTTPPipelineTask.h"
#import "OCHTTPResponse.h"
#import "OCHTTPPipelineBackend.h"
#import "OCHTTPPipelineManager.h"
#import "OCProcessManager.h"
#import "OCLogger.h"
#import "NSError+OCError.h"
#import "OCMacros.h"
#import "NSProgress+OCExtensions.h"
#import "OCProxyProgress.h"
#import "NSURLSessionTaskMetrics+OCCompactSummary.h"
#import "OCBackgroundTask.h"
#import "OCAppIdentity.h"
#import "UIDevice+ModelID.h"
#import "OCCellularManager.h"
#import "OCNetworkMonitor.h"
#import "OCHTTPPolicyManager.h"
#import "OCHTTPRequest+Stream.h"
#import "NSURLSessionTask+Debug.h"
#import "NSURLSessionTaskMetrics+OCCompactSummary.h"

@interface OCHTTPPipeline ()
{
	dispatch_block_t _invalidationCompletionHandler;

	NSURLSessionConfiguration *_sessionConfiguration;

	NSMutableDictionary<NSString*, NSURLSession*> *_attachedURLSessionsByIdentifier;
	NSMutableDictionary<NSString*, dispatch_block_t> *_sessionCompletionHandlersByIdentifiers;

	NSMutableSet<OCHTTPPipelinePartitionID> *_partitionsInDestruction;
	NSMutableDictionary<OCHTTPPipelinePartitionID, NSMutableArray<dispatch_block_t> *> *_partitionEmptyHandlers;

	NSMutableArray<OCHTTPPipelineTaskMetrics *> *_metricsHistory;
	NSTimeInterval _metricsHistoryMaxAge;
	NSTimeInterval _metricsMinimumTotalTransferDurationRelevancyThreshold;

	dispatch_group_t _busyGroup;

	BOOL _observingCellularSwitchChanges;
}

- (void)queueBlock:(dispatch_block_t)block;
@end

@implementation OCHTTPPipeline

#pragma mark - User agent
+ (nullable NSString *)stringForTemplate:(NSString *)userAgentTemplate variables:(nullable NSDictionary<NSString *, NSString *> *)variables
{
	NSString *bundleName = @"App";
	__block NSString *userAgent = nil;

	if (OCProcessManager.isProcessExtension)
	{
		if ((bundleName = [NSBundle.mainBundle objectForInfoDictionaryKey:(__bridge id)kCFBundleNameKey]) == nil)
		{
			bundleName = NSBundle.mainBundle.bundlePath.lastPathComponent.stringByDeletingPathExtension;
		}
	}

	if (bundleName == nil)
	{
		bundleName = @"App";
	}

	userAgent = [[[[[[[userAgentTemplate 	stringByReplacingOccurrencesOfString:@"{{app.build}}"   	withString:OCAppIdentity.sharedAppIdentity.appBuildNumber]
						stringByReplacingOccurrencesOfString:@"{{app.version}}" 	withString:OCAppIdentity.sharedAppIdentity.appVersion]
						stringByReplacingOccurrencesOfString:@"{{app.part}}"    	withString:bundleName]
						stringByReplacingOccurrencesOfString:@"{{device.model}}" 	withString:UIDevice.currentDevice.model]
						stringByReplacingOccurrencesOfString:@"{{device.model-id}}" 	withString:UIDevice.currentDevice.ocModelIdentifier]
						stringByReplacingOccurrencesOfString:@"{{os.name}}"  		withString:UIDevice.currentDevice.systemName]
						stringByReplacingOccurrencesOfString:@"{{os.version}}"  	withString:UIDevice.currentDevice.systemVersion];

	if (variables != nil)
	{
		[variables enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull varName, NSString * _Nonnull value, BOOL * _Nonnull stop) {
			userAgent = [userAgent stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"{{%@}}", varName] withString:value];
		}];
	}

	return (userAgent);
}

+ (nullable NSString *)userAgent
{
	static NSString *userAgent = nil;
	static NSString *userAgentTemplate = nil;

	NSString *template = [self classSettingForOCClassSettingsKey:OCHTTPPipelineSettingUserAgent];

	if (((userAgent == nil) && (template != nil)) || (![template isEqual:userAgentTemplate] && (template != userAgentTemplate)))
	{
		userAgent = [self stringForTemplate:template variables:nil];
		userAgentTemplate = template;
	}

	return (userAgent);
}

#pragma mark - Lifecycle
- (instancetype)initWithIdentifier:(OCHTTPPipelineID)identifier backend:(nullable OCHTTPPipelineBackend *)backend configuration:(NSURLSessionConfiguration *)sessionConfiguration
{
	if ((self = [super init]) != nil)
	{
		// Set up internals
		_partitionHandlersByID = [NSMapTable strongToWeakObjectsMapTable];
		_recentlyScheduledGroupIDs = [NSMutableArray new];
		_cachedCertificatesByHostnameAndPort = [NSMutableDictionary new];
		_taskIDsInDelivery = [NSMutableSet new];
		_partitionEmptyHandlers = [NSMutableDictionary new];

		_attachedURLSessionsByIdentifier = [NSMutableDictionary new];
		_sessionCompletionHandlersByIdentifiers = [NSMutableDictionary new];
		_partitionsInDestruction = [NSMutableSet new];

		_metricsHistory = [NSMutableArray new];
		_metricsHistoryMaxAge = 10 * 60; //!< Metrics records are used for computation for a maximum of 10 minutes
		_metricsMinimumTotalTransferDurationRelevancyThreshold = 0.01; // Only metrics with a minimum total transfer duration of X secs should be considered relevant

		_busyGroup = dispatch_group_create();

		// Set backend
		if (backend == nil)
		{
			backend = [OCHTTPPipelineBackend new];
		}

		_backend = backend;

		// Set identifiers
		_identifier = identifier;
		_bundleIdentifier = _backend.bundleIdentifier;

		// Change sessionConfiguration to not store any session-related data on disk
		sessionConfiguration.URLCredentialStorage = nil; // Do not use credential store at all
		sessionConfiguration.URLCache = nil; // Do not cache responses
		sessionConfiguration.HTTPCookieStorage = nil; // Do not store cookies

		// Grab the session identifier for those sessions that have it
		_urlSessionIdentifier = sessionConfiguration.identifier;

		// Prepare URL session creation
		_sessionConfiguration = sessionConfiguration;
	}

	return (self);
}

- (void)startWithCompletionHandler:(OCCompletionHandler)completionHandler
{
	@synchronized(self)
	{
		switch (_state)
		{
			case OCHTTPPipelineStateStarted:
				completionHandler(self, nil);
			break;

			case OCHTTPPipelineStateStopped: {
				_state = OCHTTPPipelineStateStarting;

				[self.backend openWithCompletionHandler:^(id sender, NSError *error) {
					if (error == nil)
					{
						@synchronized(self)
						{
							self->_state = OCHTTPPipelineStateStarted;
						}

						// Start URLSession
						self->_urlSession = [NSURLSession sessionWithConfiguration:self->_sessionConfiguration delegate:self delegateQueue:nil];

						// Start observation cellular switches and network status
						if (!self->_observingCellularSwitchChanges)
						{
							self->_observingCellularSwitchChanges = YES;

							[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_cellularSwitchChanged:) name:OCCellularSwitchUpdatedNotification object:nil];

							[OCNetworkMonitor.sharedNetworkMonitor addNetworkObserver:self selector:@selector(_networkStatusChanged:)];
						}

						// Recover from/with URLSession
						[self _recoverQueueForURLSession:self->_urlSession completionHandler:^{
							completionHandler(self, error);
						}];
					}
					else
					{
						OCLogError(@"Error opening backend: %@", error);
					}
				}];
			}
			break;

			default:
				completionHandler(self, OCError(OCErrorRunningOperation));
			break;
		}
	}
}

- (void)stopWithCompletionHandler:(OCCompletionHandler)completionHandler graceful:(BOOL)graceful
{
	@synchronized(self)
	{
		switch (_state)
		{
			case OCHTTPPipelineStateStopped:
				completionHandler(self, nil);
			break;

			case OCHTTPPipelineStateStarted: {
				dispatch_block_t invalidationCompletionHandler = ^{
					// Queue this block so that any operations to be queued from the current run have a chance to before closing down
					[self queueBlock:^{
						// Wait for outstanding operations to finish
						OCLogVerbose(@"Waiting for outstanding operations to finish");

						dispatch_group_notify(self->_busyGroup, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
							@autoreleasepool
							{
								[self.backend closeWithCompletionHandler:^(id sender, NSError *error) {
									@synchronized(self)
									{
										self->_state = OCHTTPPipelineStateStopped;
									}

									OCLogVerbose(@"Calling stopCompletionHandler %p", completionHandler);
									completionHandler(self, error);
								}];
							}
						});
					} withBusy:NO];
				};

				// Stop observing cellular switches and network status
				if (_observingCellularSwitchChanges)
				{
					_observingCellularSwitchChanges = NO;
					[NSNotificationCenter.defaultCenter removeObserver:self name:OCCellularSwitchUpdatedNotification object:nil];

					[OCNetworkMonitor.sharedNetworkMonitor removeNetworkObserver:self];
				}

				_state = OCHTTPPipelineStateStopping;

				if (graceful)
				{
					[self finishTasksAndInvalidateWithCompletionHandler:invalidationCompletionHandler];
				}
				else
				{
					[self invalidateAndCancelWithCompletionHandler:invalidationCompletionHandler];
				}
			}
			break;

			default:
				completionHandler(self, OCError(OCErrorRunningOperation));
			break;
		}
	}
}

#pragma mark - Queue recovery
- (void)_recoverQueueForURLSession:(NSURLSession *)urlSession completionHandler:(dispatch_block_t)completionHandler
{
	__block NSArray <NSURLSessionTask *> *urlSessionTasks = nil;
	__block NSMutableArray <OCHTTPPipelineTask *> *droppedTasks = [NSMutableArray new];
	__block NSMutableArray <OCHTTPPipelineTask *> *corruptedTasks = [NSMutableArray new];
	NSString *urlSessionIdentifier = urlSession.configuration.identifier;

	OCLogDebug(@"Recovering queue for urlSession=%@", urlSession);

	[urlSession getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> * _Nonnull tasks) {
		urlSessionTasks = tasks;

		OCLogDebug(@"Recovered urlSession=%@ tasks=%@", urlSession, tasks);

		[self queueBlock:^{
			// Re-attach URL session tasks to pipeline tasks
			for (NSURLSessionTask *urlSessionTask in urlSessionTasks)
			{
				NSError *backendError = nil;
				OCHTTPPipelineTask *task;

				if ((task = [self.backend retrieveTaskForPipeline:self URLSession:urlSession task:urlSessionTask error:&backendError]) != nil)
				{
					if (task.urlSessionTask == nil)
					{
						task.urlSessionTask = urlSessionTask;

						// Reconnect/Recreate progress
						if (task.request.progress.progress == nil)
						{
							task.request.progress.progress = [NSProgress indeterminateProgress];
						}

						if (task.request.progress.progress != nil)
						{
							__weak OCHTTPPipeline *weakSelf = self;
							__weak OCHTTPRequest *weakRequest = task.request;

							task.request.progress.progress.cancellationHandler = ^{
								if (weakRequest != nil)
								{
									[weakSelf cancelRequest:weakRequest];
								}
							};

							task.request.progress.progress.totalUnitCount += 200;
							[task.request.progress.progress addChild:[OCProxyProgress cloneProgress:urlSessionTask.progress] withPendingUnitCount:200];
						}

						OCLogDebug(@"Recovered urlSession=%@: task=%@", urlSession, task);
					}
				}
				else
				{
					OCLogError(@"Could not recover task from urlSessionTask=%@ with backendError=%@", urlSessionTask, backendError);
				}
			}

			// Identify tasks that are running, but have no URL session task (=> dropped by NSURLSession)
			NSError *enumerationError = [self.backend enumerateTasksForPipeline:self enumerator:^(OCHTTPPipelineTask *pipelineTask, BOOL *stop) {
				if (([pipelineTask.urlSessionID isEqual:urlSessionIdentifier] || ((pipelineTask.urlSessionID == nil) && (urlSessionIdentifier == nil))) && // URL Session ID identical, or both not having any
				    (pipelineTask.urlSessionTask == nil) // No URL Session task known for this pipeline task
				)
				{
					if ([pipelineTask.bundleID isEqual:self.backend.bundleIdentifier] && // Task belongs to this process (avoid dropping requests running in other processes)
					    (pipelineTask.state == OCHTTPPipelineTaskStateRunning)) // pipeline task is running (so there should be one)
					{
						OCLogDebug(@"Stored task dropped: %@", pipelineTask);
						[droppedTasks addObject:pipelineTask];
					}
					else if ([pipelineTask.bundleID isEqual:OCHTTPPipelineTaskAnyBundleID] && // Task response can be delivered on any process (so this request should have a response)
						 (pipelineTask.responseData == nil) && // Task has no response data
						 (pipelineTask.state != OCHTTPPipelineTaskStateCompleted)) // Task is NOT marked as completed, although that is the ONLY case where OCHTTPPipelineTaskAnyBundleID should occur
					{
						OCLogWarning(@"Corrupted task found (bundle ID is any(*) but state isn't completed and there is no result): %@ %@", pipelineTask, pipelineTask.request);
						[corruptedTasks addObject:pipelineTask];
					}
//					else if ((pipelineTask.state == OCHTTPPipelineTaskStateRunning) &&  // pipeline task is running
//
//					 	 (![pipelineTask.bundleID isEqual:self.backend.bundleIdentifier] &&  // not on this process ..
//						  ![pipelineTask.bundleID isEqual:OCHTTPPipelineTaskAnyBundleID]) &&  // .. and tied to a specific process
//
//						 [self.identifier isEqual:OCHTTPPipelineIDLocal]) // task runs on "local" pipeline (for "ephermal" is memory-only and background can run even if the process is not)
//					{
//						// Get process session of process
//						OCProcessSession *processSession;
//
//						processSession = [[OCProcessManager sharedProcessManager] findLatestSessionForProcessWithBundleIdentifier:pipelineTask.bundleID];
//
//						if (processSession != nil)
//						{
//							if (![[OCProcessManager sharedProcessManager] isAnyInstanceOfSessionProcessRunning:processSession]) // Process is no longer around
//							{
//								OCLogDebug(@"Stored task from other process dropped(1): %@", pipelineTask);
//								[droppedTasks addObject:pipelineTask];
//							}
//						}
//						else
//						{
//							OCLogDebug(@"Stored task from other process dropped(2): %@", pipelineTask);
//							[droppedTasks addObject:pipelineTask];
//						}
//					}
					else
					{
						OCLogDebug(@"Stored task recovered: %@", pipelineTask);
					}
				}
			}];

			OCLogDebug(@"Recovered urlSession=%@: droppedTasks=%@, corruptedTasks=%@, enumerationError=%@", urlSession, droppedTasks, corruptedTasks, enumerationError);

			// Drop identified tasks
			for (OCHTTPPipelineTask *task in droppedTasks)
			{
				[self _finishedTask:task withResponse:[OCHTTPResponse responseWithRequest:task.request HTTPError:OCError(OCErrorRequestDroppedByURLSession)]];
			}

			for (OCHTTPPipelineTask *task in corruptedTasks)
			{
				[self _finishedTask:task withResponse:[OCHTTPResponse responseWithRequest:task.request HTTPError:OCError(OCErrorRequestResponseCorruptedOrDropped)]];
			}

			// Call completionHandler
			if (completionHandler != nil)
			{
				completionHandler();
			}
		}];
	}];
}

#pragma mark - Request handling
- (void)enqueueRequest:(OCHTTPRequest *)request forPartitionID:(OCHTTPPipelinePartitionID)partitionID
{
	[self enqueueRequest:request forPartitionID:partitionID isFinal:NO];
}

- (void)enqueueRequest:(OCHTTPRequest *)request forPartitionID:(OCHTTPPipelinePartitionID)partitionID isFinal:(BOOL)isFinal
{
	OCHTTPPipelineTask *pipelineTask;

	// Check pipeline state
	@synchronized(self)
	{
		if (_state != OCHTTPPipelineStateStarted)
		{
			OCLogError(@"Attempt to enqueue request before pipeline is started: %@", request);
			return;
		}

		// Check if partition is being destroyed
		if ([self->_partitionsInDestruction containsObject:partitionID])
		{
			OCLogError(@"Attempt to enqueue request for partitionID=%@ that's being destroyed: %@", partitionID, request);
			return;
		}
	}

	if (request == nil)
	{
		OCLogError(@"Attempt to insert nil request in partition %@", partitionID);
		return;
	}

	// Update progress object
	if (request.progress.progress == nil)
	{
		request.progress.progress = [NSProgress indeterminateProgress];
	}

	if (request.progress.progress != nil)
	{
		__weak OCHTTPPipeline *weakSelf = self;
		__weak OCHTTPRequest *weakRequest = request;

		request.progress.progress.cancellationHandler = ^{
			if (weakRequest != nil)
			{
				[weakSelf cancelRequest:weakRequest];
			}
		};
	}

	if (_alwaysUseDownloadTasks)
	{
		request.downloadRequest = YES;
	}

	if ((pipelineTask = [[OCHTTPPipelineTask alloc] initWithRequest:request pipeline:self partition:partitionID]) != nil)
	{
		pipelineTask.requestFinal = isFinal;

		NSError *error;

		if ((error = [_backend addPipelineTask:pipelineTask]) != nil)
		{
			OCLogError(@"Error adding pipelineTask=%@ for request=%@: %@", pipelineTask.taskID, request, error);
		}

		[self setPipelineNeedsScheduling];
	}
}

- (void)cancelRequest:(OCHTTPRequest *)request
{
	if (request == nil) { return; }

	// Check pipeline state
	@synchronized(self)
	{
		if (_state != OCHTTPPipelineStateStarted)
		{
			OCLogError(@"Attempt to cancel request before pipeline is started");
			return;
		}
	}

	[self queueBlock:^{
		[self _cancelRequest:request];
	}];
}

- (void)_cancelRequest:(OCHTTPRequest *)request
{
	NSError *backendError = nil;
	OCHTTPPipelineTask *task = nil;

	if ((task = [self.backend retrieveTaskForRequestID:request.identifier error:&backendError]) != nil)
	{
		[self _cancelTask:task];
	}
	else
	{
		OCLogError(@"Could not retrieve task for requestID=%@ with error=%@", request.identifier, backendError);
	}
}

- (void)_cancelTask:(OCHTTPPipelineTask *)task
{
	if (task == nil) { return; }

	switch (task.state)
	{
		case OCHTTPPipelineTaskStateRunning:
			// Cancel the URLSessionTask if one is known
			if (!task.request.cancelled)
			{
				task.request.cancelled = YES;
				task.request.progress.cancelled = YES;

				if (task.urlSessionTask != nil)
				{
					[task.urlSessionTask cancel];

					[self.backend updatePipelineTask:task];
					break;
				}
			}

			// Insta-cancel otherwise

		case OCHTTPPipelineTaskStatePending:
			// Not scheduled yet => insta-cancel
			[self finishedTask:task withResponse:[OCHTTPResponse responseWithRequest:task.request HTTPError:OCError(OCErrorRequestCancelled)]];
		break;

		case OCHTTPPipelineTaskStateCompleted:
			// Can't cancel what's already complete
		break;
	}
}

- (void)cancelRequestsForPartitionID:(OCHTTPPipelinePartitionID)partitionID queuedOnly:(BOOL)queuedOnly
{
	// Check pipeline state
	@synchronized(self)
	{
		if (_state != OCHTTPPipelineStateStarted)
		{
			OCLogError(@"Attempt to cancel requests before pipeline is started");
			return;
		}
	}

	[self queueInline:^{
		NSMutableArray <OCHTTPPipelineTask *> *tasksToCancel = [NSMutableArray new];

		[self.backend enumerateTasksForPipeline:self partition:partitionID enumerator:^(OCHTTPPipelineTask *task, BOOL *stop) {
			if (queuedOnly && (task.state!=OCHTTPPipelineTaskStatePending))
			{
				return;
			}

			[tasksToCancel addObject:task];
		}];

		for (OCHTTPPipelineTask *task in tasksToCancel)
		{
			[self _cancelTask:task];
		}
	}];
}

#pragma mark - Scheduling
- (void)setPipelineNeedsScheduling
{
	@synchronized(self)
	{
		if (!_needsScheduling)
		{
			_needsScheduling = YES;

			[self queueBlock:^{
				[self _schedule];
			}];
		}
	}
}

- (void)_schedule
{
	__block NSUInteger remainingSlots = NSUIntegerMax;

	/*
		Scheduling goals:
		- the number of running requests doesn't exceed the limit imposed by .maximumConcurrentRequests at any time
		- requests are scheduled fairly: the scheduler guarantees that for N groups, every group will get one request scheduled after N slots have become available (doesn't need to be in the same scheduling run)
		- only one request can be running per group
		- request not belonging to a group are assigned to the default group:
			- any number of requests can be running for the default group at the same time
			- any spots remaining after fair scheduling are filled with requests from the default group
			- requests with a higher priority are scheduled sooner
		- requests are only considered for scheduling if a partitionHandler is attached for them - or they have the .requestFinal flag set
	*/

	@synchronized(self)
	{
		// Only schedule if pipeline is started
		if (_state != OCHTTPPipelineStateStarted)
		{
			OCLogWarning(@"Attempt to schedule while pipeline is not started (state = %ld).", _state);
			return;
		}

		// Reset needsScheduling
		_needsScheduling = NO;
	}

	// Enforce .maximumConcurrentRequests
	if (self.maximumConcurrentRequests != 0)
	{
		NSNumber *runningRequestsCount;
		NSError *error = nil;

		if ((runningRequestsCount = [_backend numberOfRequestsWithState:OCHTTPPipelineTaskStateRunning inPipeline:self partition:nil error:&error]) != nil)
		{
			if (runningRequestsCount.unsignedIntegerValue >= self.maximumConcurrentRequests)
			{
				// Maximum number of concurrent requests reached => exit early
				return;
			}
			else
			{
				// Adjust number of remaining slots
				remainingSlots = self.maximumConcurrentRequests - runningRequestsCount.unsignedIntegerValue;
			}
		}
		else if (error != nil)
		{
			OCLogError(@"Error retrieving number of requests in running state: %@", error);
		}
	}

	// Enumerate tasks in pipeline and pick ones for scheduling
	__block NSMutableDictionary <OCHTTPRequestGroupID, NSMutableArray<OCHTTPPipelineTask *> *> *schedulableTasksByGroupID = [NSMutableDictionary new];
	__block NSMutableSet <OCHTTPRequestGroupID> *blockedGroupIDs = [NSMutableSet new];
	const OCHTTPRequestGroupID defaultGroupID = @"_default_";
	NSError *enumerationError;

	enumerationError = [_backend enumerateTasksForPipeline:self enumerator:^(OCHTTPPipelineTask *task, BOOL *stop) {
		BOOL isRelevant = YES;
		BOOL isTiedToOtherProcess = NO;
		BOOL taskExecutingOtherProcessIsAlive = NO; // only relevant if isTiedToOtherProcess is YES
		OCHTTPPipelinePartitionID partitionID = nil;
		id<OCHTTPPipelinePartitionHandler> partitionHandler = nil;

		// Check if a partitionHandler is attached for this task - or if the task is deemed final and can be scheduled without
		if ((partitionID = task.partitionID) == nil)
		{
			// No partitionID?! => skip
			return;
		}

		@synchronized(self)
		{
			// Check if partition is being destroyed => skip
			if ([self->_partitionsInDestruction containsObject:partitionID])
			{
				return;
			}

			// Retrieve partition handler
			partitionHandler = [self partitionHandlerForPartitionID:partitionID];
		}

		if (!task.requestFinal)
		{
			// Request isn't final
			if (partitionHandler==nil)
			{
				// No partitionHandler for this task => skip
				return;
			}
		}

		// Check if this task originates from our process
		if (isRelevant)
		{
			if (![task.bundleID isEqual:self->_bundleIdentifier] &&    // not originating from this process ..
			    ![task.bundleID isEqual:OCHTTPPipelineTaskAnyBundleID]) // .. and tied to a specific process
			{
				isTiedToOtherProcess = YES;
				taskExecutingOtherProcessIsAlive = NO;

				// Task originates from a different process. Only process it, if that other process is no longer around
				OCProcessSession *processSession;

				if ((processSession = [[OCProcessManager sharedProcessManager] findLatestSessionForProcessWithBundleIdentifier:task.bundleID]) != nil)
				{
					taskExecutingOtherProcessIsAlive = [[OCProcessManager sharedProcessManager] isAnyInstanceOfSessionProcessRunning:processSession];
					isRelevant = !taskExecutingOtherProcessIsAlive;
				}
			}
		}

		// Task is relevant
		if (isRelevant)
		{
			OCHTTPRequestGroupID taskGroupID = task.groupID;

			// Check group association
			if (taskGroupID == nil)
			{
				// Task doesn't belong to a group. Assign default ID.
				taskGroupID = defaultGroupID;
			}
			else
			{
				// Task belongs to group
				if ([blockedGroupIDs containsObject:taskGroupID])
				{
					// Another task for the same task.groupID is already active
					return;
				}
			}

			// Check task state
			switch (task.state)
			{
				case OCHTTPPipelineTaskStatePending:
					// Task is pending
					if (taskGroupID != nil)
					{
						NSMutableArray <OCHTTPPipelineTask *> *schedulableTasks = nil;
						BOOL schedule = YES;

						// Check signal availability
						{
							NSError *failWithError = nil;

							// Only check for signals on final requests if more than one signal has been set (several unit tests with "final" requests depend on this) or the partitionHandler currently is available
							// !! For non-final requests, the Connection Validator depends on -meetsSignalRequirements:forTask:failWithError: being called !!
							if (!task.requestFinal || (task.requestFinal && (task.request.requiredSignals.count > 0)) || (partitionHandler != nil))
							{
								// This call is also made if partitionHandler is nil, resulting in schedule = NO
								schedule = [partitionHandler pipeline:self meetsSignalRequirements:task.request.requiredSignals forTask:task failWithError:&failWithError];
							}

							if (!schedule && (failWithError!=nil))
							{
								// Required signal check returned a failWithError => make request fail with that error
								[self _finishedTask:task withResponse:[OCHTTPResponse responseWithRequest:task.request HTTPError:failWithError]];
								return;
							}
						}

						// Check cellular switch availability
						if (schedule && (task.request.requiredCellularSwitch != nil))
						{
							NSUInteger transferSize = 0;
							BOOL wifiOnly = NO;

							if (task.request.bodyData != nil)
							{
								transferSize = task.request.bodyData.length;
							}
							else if (task.request.bodyURL != nil)
							{
								NSNumber *fileSize = nil;
								{
									NSError *error = nil;
									if (![task.request.bodyURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:&error])
									{
										OCLogError(@"Error determining size of %@: %@", task.request.bodyURL, error);
									}
									else
									{
										transferSize = fileSize.unsignedIntegerValue;
									}
								}
							}

							if ([OCCellularManager.sharedManager networkAccessAvailableFor:task.request.requiredCellularSwitch transferSize:transferSize onWifiOnly:&wifiOnly])
							{
								// Network access currently allowed for this request
								task.request.avoidCellular = wifiOnly; // Pass on enforcement of cellular setting on to the HTTP/NSURLSession layer
							}
							else
							{
								// Network access not currently allowed for this request based on the cellular switch settings
								schedule = NO;
							}
						}

						if (schedule)
						{
							if ((schedulableTasks = schedulableTasksByGroupID[taskGroupID]) == nil)
							{
								// First pending task with this taskGroupID
								schedulableTasks = [[NSMutableArray alloc] initWithObjects:task, nil];
								schedulableTasksByGroupID[taskGroupID] = schedulableTasks;
							}
							else if (task.groupID == nil)
							{
								// Pending task without groupID (ignore tasks with groupID here, as it'd be the second with the groupID or later)
								[schedulableTasks addObject:task];
							}
						}
						else
						{
							if (task.groupID != nil)
							{
								// Add groupID to list of blocked group IDs (to prevent out-of-order scheduling/execution of requests)
								[blockedGroupIDs addObject:task.groupID];
							}
						}
					}
				break;

				case OCHTTPPipelineTaskStateRunning:
					// Task is running
					if (task.groupID != nil)
					{
						// Add groupID to list of blocked group IDs
						[blockedGroupIDs addObject:task.groupID];

						[schedulableTasksByGroupID removeObjectForKey:task.groupID];
					}

					// Check if the task should be restarted
					if (isTiedToOtherProcess && !taskExecutingOtherProcessIsAlive)
					{
						// Tied to another process which is no longer alive
						if ([self.identifier isEqual:OCHTTPPipelineIDLocal])
						{
							// Task runs on "local" pipeline (for "ephermal" is memory-only and background can run even if the process is not)
							if ([OCLogger logsForLevel:OCLogLevelWarning] && (task.request != nil))
							{
								OCLogWarning(@"Determined that task has been dropped by process termination of %@ - restarting %@", task.bundleID, task);
							}

							// All conditions met to restart request
							[self finishedTask:task withResponse:[OCHTTPResponse responseWithRequest:task.request HTTPError:OCError(OCErrorRequestDroppedByOriginalProcessTermination)]];
						}
					}

					return;
				break;

				case OCHTTPPipelineTaskStateCompleted:
					// Task is completed
					return;
				break;
			}
		}
	}];

	if (enumerationError != nil)
	{
		OCLogError(@"Error enumerating tasks during scheduling: enumerationError=%@", enumerationError);
	}

	// OCLogVerbose(@"Scheduler state: schedulableTasksByGroupID=%@, blockedGroupIDs=%@, remainingSlots=%d, recentlyScheduledGroupIDs=%@", schedulableTasksByGroupID, blockedGroupIDs, remainingSlots, _recentlyScheduledGroupIDs);

	// Filter and sort tasks
	if (schedulableTasksByGroupID.count > 0)
	{
		NSMutableArray <OCHTTPPipelineTask *> *scheduleTasks = [NSMutableArray new];
		NSMutableArray <OCHTTPRequestGroupID> *schedulableGroupIDs = [schedulableTasksByGroupID.allKeys mutableCopy];

		NSComparator sortTasksByRequestPriorityComparator = ^NSComparisonResult(OCHTTPPipelineTask *task1, OCHTTPPipelineTask *task2) {
			OCHTTPRequestPriority task1Priority, task2Priority;

			task1Priority = task1.request.priority;
			task2Priority = task2.request.priority;

			if (task1Priority == task2Priority)
			{
				return (NSOrderedSame);
			}

			return ((task1Priority > task2Priority) ? NSOrderedAscending : NSOrderedDescending); // In reverse order, so highest value comes first
		};

		// Sort defaultGroup requests by request.priority
		[schedulableTasksByGroupID[defaultGroupID] sortUsingComparator:sortTasksByRequestPriorityComparator];

		// Prioritize requests from groups whose requests haven't been scheduled the longest
		for (OCHTTPRequestGroupID groupID in _recentlyScheduledGroupIDs)
		{
			NSMutableArray <OCHTTPPipelineTask *> *tasks;

			if ((tasks = schedulableTasksByGroupID[groupID]) != nil)
			{
				OCHTTPPipelineTask *task;

				// Add the oldest task from this group
				if ((task = tasks.firstObject) != nil)
				{
					[scheduleTasks addObject:task];
					[tasks removeObjectAtIndex:0];
				}

				[schedulableGroupIDs removeObject:groupID]; // Done with this group
			}
		}

		// OCLogVerbose(@"schedulableGroupIDs=%@", schedulableGroupIDs);

		// Prioritize requests from groups whose requests have never been scheduled even higher (by inserting them at the top)
		for (OCHTTPRequestGroupID groupID in schedulableGroupIDs)
		{
			NSMutableArray <OCHTTPPipelineTask *> *tasks;

			if ((tasks = schedulableTasksByGroupID[groupID]) != nil)
			{
				OCHTTPPipelineTask *task;

				// Add the oldest task from this group
				if ((task = tasks.firstObject) != nil)
				{
					[scheduleTasks insertObject:task atIndex:0];
					[tasks removeObjectAtIndex:0];
				}
			}
		}

		// Fill remaining spots (if any) with defaultGroup tasks
		NSMutableArray <OCHTTPPipelineTask *> *tasks;

		if ((tasks = schedulableTasksByGroupID[defaultGroupID]) != nil)
		{
			[scheduleTasks addObjectsFromArray:tasks];
		}

		// OCLogVerbose(@"scheduleTasks=%@", scheduleTasks);

		// Reduce to maximum of remainingSlots
		if (scheduleTasks.count > remainingSlots)
		{
			[scheduleTasks removeObjectsInRange:NSMakeRange(remainingSlots, scheduleTasks.count-remainingSlots)];
		}

		// OCLogVerbose(@"scheduleTasksShortened=%@", scheduleTasks);

		// Update recentlyScheduledGroupIDs
		for (OCHTTPPipelineTask *task in scheduleTasks)
		{
			OCHTTPRequestGroupID taskGroupID = task.groupID;

			if (taskGroupID == nil)
			{
				// Task doesn't belong to a group. Assign default ID.
				taskGroupID = defaultGroupID;
			}

			// Move taskGroupID to the end of recently scheduled group IDs
			// Eventually, every taskGroupID will bubble up to the top, even if only one slot was available
			[_recentlyScheduledGroupIDs removeObject:taskGroupID];
			[_recentlyScheduledGroupIDs addObject:taskGroupID];
		}

		// Schedule tasks
		for (OCHTTPPipelineTask *task in scheduleTasks)
		{
			[self _scheduleTask:task];
		}
	}
}

- (void)_scheduleTask:(OCHTTPPipelineTask *)task
{
	OCHTTPRequest *request = task.request;
	OCHTTPPipelinePartitionID partitionID = task.partitionID;
	NSError *error = nil;
	BOOL updateTask = NO;

	if ((partitionID = task.partitionID) == nil)
	{
		// PartitionID is mandatory. Remove and return if missing.
		OCLogWarning(@"Mandatory partitionID missing from task=%@. Removing task.", task);
		[_backend removePipelineTask:task];
		[self _triggerPartitionEmptyHandlers];
		return;
	}
	else if (request.cancelled)
	{
		// This request has been cancelled
		error = OCError(OCErrorRequestCancelled);
	}
	else if (_urlSessionInvalidated)
	{
		// The underlying NSURLSession has been invalidated
		error = OCError(OCErrorRequestURLSessionInvalidated);
	}
	else
	{
		// Get partitionHandler
		id<OCHTTPPipelinePartitionHandler> partitionHandler = nil;

		@synchronized(self)
		{
			partitionHandler = [_partitionHandlersByID objectForKey:partitionID];
		}

		// Prepare request
		[request prepareForScheduling];

		if (partitionHandler!=nil)
		{
			// Apply authentication and other pipeline-level changes
			request = [partitionHandler pipeline:self prepareRequestForScheduling:request];

			// Add cookies
			if ((partitionHandler != nil) && [partitionHandler respondsToSelector:@selector(partitionCookieStorage)])
			{
				[partitionHandler.partitionCookieStorage addCookiesForPipeline:self partitionID:partitionID toRequest:request];
			}

			// Save request to task
			task.request = request;

			updateTask = YES;
		}

		// Schedule request
		if (request != nil)
		{
			NSURLRequest *urlRequest;
			NSURLSessionTask *urlSessionTask = nil;
			BOOL createTask = YES;

			// Apply User-Agent (if any)
			NSString *userAgent;

			if ((userAgent = [OCHTTPPipeline userAgent]) != nil)
			{
				[request setValue:userAgent forHeaderField:OCHTTPHeaderFieldNameUserAgent];
			}

			// Invoke host simulation (if any)
			if ((partitionHandler!=nil) && [partitionHandler respondsToSelector:@selector(pipeline:partitionID:simulateRequestHandling:completionHandler:)])
			{
				createTask = [partitionHandler pipeline:self partitionID:partitionID simulateRequestHandling:request completionHandler:^(OCHTTPResponse * _Nonnull response) {
					[self finishedTask:task withResponse:response];
				}];
			}

			if (createTask)
			{
				// Generate NSURLRequest and create an NSURLSessionTask with it
				if ((urlRequest = [request generateURLRequest]) != nil)
				{
					@try
					{
						// Construct NSURLSessionTask
						if (request.downloadRequest)
						{
							// Request is a download request. Make it a download task.
							NSData *resumeData = nil;

							if (request.autoResume && ((resumeData = request.autoResumeInfo[OCHTTPRequestResumeInfoKeySystemResumeData]) != nil))
							{
								// Resume download
								urlSessionTask = [_urlSession downloadTaskWithResumeData:resumeData];
							}
							else
							{
								// Start new download
								urlSessionTask = [_urlSession downloadTaskWithRequest:urlRequest];
							}
						}
						else if (request.bodyURL != nil)
						{
							// Body comes from a file. Make it an upload task.
							urlSessionTask = [_urlSession uploadTaskWithRequest:urlRequest fromFile:request.bodyURL];
						}
						else
						{
							// Create a regular data task
							urlSessionTask = [_urlSession dataTaskWithRequest:urlRequest];
						}

						// Apply priority
						urlSessionTask.priority = request.priority;

						// Apply earliest date
						if (request.earliestBeginDate != nil)
						{
							urlSessionTask.earliestBeginDate = request.earliestBeginDate;
						}
					}
					@catch (NSException *exception)
					{
						OCLogError(@"Exception creating a task: %@", exception);
						error = OCErrorWithInfo(OCErrorException, @{ @"exception" : exception });
					}
				}

				if (urlSessionTask != nil)
				{
					BOOL resumeSessionTask = YES;

					// Save urlSessionTask to request
					task.urlSessionTask = urlSessionTask;

					task.urlSessionTaskID = @(urlSessionTask.taskIdentifier);
					task.urlSessionID = _urlSessionIdentifier;

					// Make sure .urlSessionTaskID and X-Request-ID (and any changes to it due to recreation) are persisted before calling -resume, as the
					// backend *could* take longer than the first callbacks from NSURLSession (particularly for the certificate), which would then not
					// be routable and lead to the NSURLSessionTask be deemed to be an UNKNOWN TASK
					[_backend updatePipelineTask:task];

					// Connect task progress to request progress
					request.progress.progress.totalUnitCount += 200;
					[request.progress.progress addChild:[OCProxyProgress cloneProgress:urlSessionTask.progress] withPendingUnitCount:200];

					// Update internal tracking collections
					task.state = OCHTTPPipelineTaskStateRunning;
					updateTask = YES;

					OCLogVerbose(@"saved request for [%@], request=%@, %p", urlSessionTask.requestIdentityDescription, urlRequest, self);

					// Start task
					if (resumeSessionTask)
					{
						// Prevent suspension of app process for as long as this runs
						if (!OCProcessManager.isProcessExtension && // UIApplication is not available in extensions
						    !self.backgroundSessionBacked) // Only use background tasks when not handling a background session
						{
							NSUInteger urlSessionTaskID = urlSessionTask.taskIdentifier;
							NSString *absoluteURLString = request.url.absoluteString;

							if (absoluteURLString==nil)
							{
								absoluteURLString = @"";
							}

							// Register background task

//							 BOOL autoResume = request.autoResume;
//							 __weak OCHTTPPipeline *weakPipeline = self;
//							 OCHTTPRequestID resumeRequestID = request.identifier;

							__weak OCHTTPPipeline *weakSelf = self;

							[[[OCBackgroundTask backgroundTaskWithName:[NSString stringWithFormat:@"OCHTTPPipeline <%ld>: %@", urlSessionTaskID, absoluteURLString] expirationHandler:^(OCBackgroundTask *backgroundTask){
								// Task needs to end in the expiration handler - or the app will be terminated by iOS
								OCWTLogWarning(nil, @"background task for request %@ with taskIdentifier <%ld> expired", absoluteURLString, urlSessionTaskID);

								// Cancel resumeable download and store resume data
								// (commented out for now as it raises additional issues/questions, like f.ex. preventing a restart right away while the app transitions to the background - letting iOS cancel the connection on our behalf works better as we won't get notified until after the app has been woken up again, at which point rescheduling is just fine)
//								OCHTTPPipeline *pipeline = weakPipeline;
//
//								[pipeline.backend queueBlock:^{
//									OCHTTPPipelineTask *task;
//
//									if ((task = [pipeline.backend retrieveTaskForRequestID:resumeRequestID error:NULL]) != nil)
//									{
//										NSURLSessionDownloadTask *downloadTask;
//
//										if (((downloadTask = OCTypedCast(task.urlSessionTask, NSURLSessionDownloadTask)) != nil) &&
//										    (downloadTask.state == NSURLSessionTaskStateRunning))
//										{
//											// Cancel to resume later
//											[downloadTask cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
//												if (resumeData != nil)
//												{
//													task.request.autoResumeInfo = @{
//														OCHTTPRequestResumeInfoKeySystemResumeData : resumeData
//													};
//
//													// TO ADD: reset request for rescheduling
//
//													[pipeline.backend updatePipelineTask:task];
//												}
//											}];
//										}
//									}
//								}];

								[backgroundTask end];
							}] start] endWhenDeallocating:task];
						}

						// Notify request observer
						if (request.requestObserver != nil)
						{
							resumeSessionTask = !request.requestObserver(task, request, OCHTTPRequestObserverEventTaskResume);
						}
					}

					if (resumeSessionTask)
					{
						OCLogVerbose(@"resuming request for [%@], request=%@, %p", urlSessionTask.requestIdentityDescription, urlRequest, self);
						urlSessionTask.resumeTaskDate = [NSDate new];
						[urlSessionTask resume];
					}
				}
				else
				{
					// Request failure
					if (error == nil)
					{
						error = OCError(OCErrorRequestURLSessionTaskConstructionFailed);
					}
				}
			}
			else
			{
				// Update internal tracking collections
				task.state = OCHTTPPipelineTaskStateRunning;
				updateTask = YES;
			}
		}
		else
		{
			request = task.request;
			error = OCError(OCErrorRequestRemovedBeforeScheduling);
		}
	}

	// Log request
	if (OCLogToggleEnabled(OCLogOptionLogRequestsAndResponses) && OCLoggingEnabled())
	{
		NSArray <OCLogTagName> *extraTags = [NSArray arrayWithObjects: @"HTTP", @"Request", request.method, OCLogTagTypedID(@"RequestID", request.identifier), OCLogTagTypedID(@"URLSessionTaskID", task.urlSessionTaskID), nil];
		OCHTTPPipelineLogFormat httpLogFormat = [self classSettingForOCClassSettingsKey:OCHTTPPipelineSettingTrafficLogFormat];

		if ([httpLogFormat isEqual:OCHTTPPipelineLogFormatJSON])
		{
			// OCHTTPPipelineLogFormatJSON: JSON logging
			NSMutableDictionary<NSString *, id> *infoDict = [NSMutableDictionary new];
			NSMutableDictionary<NSString *, NSString *> *headerDict = [NSMutableDictionary new];
			NSMutableDictionary<NSString *, id> *bodyDict = [NSMutableDictionary new];

			// ## Info
			// IDs
			infoDict[@"id"] = request.identifier;
			if (![request.headerFields[OCHTTPHeaderFieldNameOriginalRequestID] isEqual:request.identifier])
			{
				infoDict[@"original-id"] = request.headerFields[OCHTTPHeaderFieldNameOriginalRequestID];
			}
			infoDict[@"url-session-task-id"] = task.urlSessionTaskID;
			infoDict[@"required-signals"] = (request.requiredSignals.count > 0) ? request.requiredSignals.allObjects : nil;

			// Method + URL
			infoDict[@"method"] = request.method;
			infoDict[@"url"] = request.effectiveURL.absoluteString;

			// HTTP Error
			if (error != nil)
			{
				infoDict[@"error"] = error.description;
			}

			// ## Header
			[OCHTTPRequest formatHeaders:request.headerFields withConsumer:^(NSString *headerField, NSString *value) {
				headerDict[headerField] = value;
			}];

			// ## Body
			NSNumber *bodyLength = nil;
			NSString *readableContent = [OCHTTPRequest bodyDescriptionForURL:request.bodyURL data:request.bodyData headers:request.headerFields prefixed:NO bodyLength:&bodyLength altTextDescription:NULL];
			bodyDict[@"length"] = bodyLength;
			bodyDict[@"data"] = readableContent;
			bodyDict[@"local-data-url"] = request.bodyURL.absoluteString;

			// Compose JSON dict
			NSDictionary<NSString *, NSDictionary *> *jsonDict = @{
				@"request" : @{
					@"info"   : infoDict,
					@"header" : headerDict,
					@"body"   : bodyDict
				}
			};

			// Log JSON dict
			NSError *jsonError = nil;
			NSData *jsonData;
			NSString *jsonString = nil;

			if ((jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:&jsonError]) != nil)
			{
				jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
			}
			OCPFMLogDebug(OCLogOptionLogRequestsAndResponses, extraTags, @"REQUEST %@ %@", request.identifier, (jsonString != nil) ? jsonString : [NSString stringWithFormat:@"JSON log encoding error: %@", jsonError]);
		}
		else
		{
			// OCHTTPPipelineLogFormatPlainText + default: plain text logging
			BOOL prefixedLogging = [[OCLogger classSettingForOCClassSettingsKey:OCClassSettingsKeyLogSingleLined] boolValue];
			NSString *infoPrefix = (prefixedLogging ? @"[info] " : @"");
			NSString *errorDescription = (error != nil) ? (prefixedLogging ? [[error description] stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"\n"] withString:[NSString stringWithFormat:@"\n[info] "]] : [error description]) : @"-";

			OCTLogDebug([extraTags arrayByAddingObject:@"HTSum"], @"-> %@ %@", request.method, request.effectiveURL);
			OCPFMLogDebug(OCLogOptionLogRequestsAndResponses, extraTags, @"Sending request:\n%@# REQUEST ---------------------------------------------------------\n%@URL:         %@\n%@Error:       %@\n%@Req Signals: %@\n%@- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -\n%@-----------------------------------------------------------------", infoPrefix, infoPrefix, request.effectiveURL, infoPrefix, errorDescription, infoPrefix, [request.requiredSignals.allObjects componentsJoinedByString:@", "], infoPrefix, [request requestDescriptionPrefixed:prefixedLogging]);
		}
	}

	// Update task
	if (updateTask)
	{
		[_backend updatePipelineTask:task];
	}

	// Finish request with an error if one occurred
	if (error != nil)
	{
		[self queueBlock:^{
			[self finishedTask:task withResponse:[OCHTTPResponse responseWithRequest:request HTTPError:error]];
		}];
	}
}

#pragma mark - Request result handling
- (void)finishedTask:(OCHTTPPipelineTask *)task withResponse:(OCHTTPResponse *)response
{
	[self queueBlock:^{
		[self _finishedTask:task withResponse:response];
		[self setPipelineNeedsScheduling];
	}];
}

- (void)_finishedTask:(OCHTTPPipelineTask *)task withResponse:(OCHTTPResponse *)response
{
	OCHTTPRequest *request = task.request;

	if (task==nil) { return; }
	if (request==nil) { return; }

	if (task.finished)
	{
		OCLogWarning(@"Repeated calls to finishedTask:withResponse: for requestID=%@ (normal in case of reschedules)", task.requestID);
	}

	task.finished = YES;

	// Extract & store cookies from response
	if (task.partitionID != nil)
	{
		id<OCHTTPPipelinePartitionHandler> partitionHandler = nil;

		@synchronized(self)
		{
			partitionHandler = [_partitionHandlersByID objectForKey:task.partitionID];
		}

		if ((partitionHandler != nil) && [partitionHandler respondsToSelector:@selector(partitionCookieStorage)])
		{
			[partitionHandler.partitionCookieStorage extractCookiesForPipeline:self partitionID:task.partitionID fromResponse:response];
		}
	}

	// Check if this request should have a responseCertificate ..
	if ((response.error == nil) && (response.httpError == nil))
	{
		NSURL *requestURL = request.url;

		if ([requestURL.scheme.lowercaseString isEqualToString:@"https"])
		{
			// .. but hasn't ..
			if (response.certificate == nil)
			{
				NSString *hostnameAndPort;

				// .. and if we have one available in that case
				if ((hostnameAndPort = [NSString stringWithFormat:@"%@:%@", requestURL.host.lowercaseString, ((requestURL.port!=nil)?requestURL.port : @"443" )]) != nil)
				{
					@synchronized(self)
					{
						// Attach certificate from cache (NSURLSession probably didn't do because the certificate is still cached in its internal TLS cache and we were asked before. Also see https://developer.apple.com/library/content/qa/qa1727/_index.html and https://github.com/AFNetworking/AFNetworking/issues/991 .)
						if ((response.certificate = _cachedCertificatesByHostnameAndPort[hostnameAndPort]) != nil)
						{
							// Evaluate / prompt on delivery
							response.certificateValidationResult = OCCertificateValidationResultNone;
						}
						else
						{
							// Certificates can be entirely missing if:
							// A) the simulator is used but not set up fully
							// B) a request started on the background session
							//  & a request providing a certificate on the background session
							//  & process being terminated
							//  & result of the request being provided to the new process
							OCLogWarning(@"Certificate missing for %@: %@", response, OCError(OCErrorCertificateMissing));
							// response.httpError = OCError(OCErrorCertificateMissing);
						}
					}
				}
			}
		}
	}

	// Close streaming response stream
	if (task.request.shouldStreamResponse)
	{
		[task.request closeResponseStreamWithError:response.httpError forPipelineTask:task];
	}

	// Update task in backend
	if ((task.response != nil) && (task.response != response))
	{
		// has existing response
		OCLogWarning(@"Existing response for %@ overwritten: %@ replaces %@", task.requestID, [response responseDescriptionPrefixed:NO], [task.response responseDescriptionPrefixed:NO]);
	}

	task.response = response;
	task.state = OCHTTPPipelineTaskStateCompleted;
	[self.backend updatePipelineTask:task];

	// Log response
	if (OCLogToggleEnabled(OCLogOptionLogRequestsAndResponses) && OCLoggingEnabled())
	{
		NSArray <OCLogTagName> *extraTags = [NSArray arrayWithObjects: @"HTTP", @"Response", task.request.method, OCLogTagTypedID(@"RequestID", task.request.identifier), OCLogTagTypedID(@"URLSessionTaskID", task.urlSessionTaskID), nil];
		OCHTTPPipelineLogFormat httpLogFormat = [self classSettingForOCClassSettingsKey:OCHTTPPipelineSettingTrafficLogFormat];

		if ([httpLogFormat isEqual:OCHTTPPipelineLogFormatJSON])
		{
			// OCHTTPPipelineLogFormatJSON: JSON logging
			NSMutableDictionary<NSString *, id> *infoDict = [NSMutableDictionary new];
			NSMutableDictionary<NSString *, id> *replyDict = [NSMutableDictionary new];
			NSMutableDictionary<NSString *, NSString *> *headerDict = [NSMutableDictionary new];
			NSMutableDictionary<NSString *, id> *bodyDict = [NSMutableDictionary new];

			// ## Info
			// IDs
			infoDict[@"id"] = task.request.identifier;
			if (![task.request.headerFields[OCHTTPHeaderFieldNameOriginalRequestID] isEqual:task.request.identifier])
			{
				infoDict[@"original-id"] = task.request.headerFields[OCHTTPHeaderFieldNameOriginalRequestID];
			}
			infoDict[@"url-session-task-id"] = task.urlSessionTaskID;
			infoDict[@"required-signals"] = (task.request.requiredSignals.count > 0) ? task.request.requiredSignals.allObjects : nil;

			// Method + URL
			infoDict[@"method"] = task.request.method;
			infoDict[@"url"] = task.request.effectiveURL.absoluteString;

			// Reply status + HTTP Error
			replyDict[@"status"] = @(task.response.status.code);
			replyDict[@"status-name"] = task.response.status.name;
			replyDict[@"metrics"] = task.metrics.compactSummary;

			if (task.response.httpError != nil)
			{
				replyDict[@"error"] = [task.response.httpError description];
			}

			infoDict[@"reply"] = replyDict;

			// ## Header
			[OCHTTPRequest formatHeaders:task.response.headerFields withConsumer:^(NSString *headerField, NSString *value) {
				headerDict[headerField] = value;
			}];

			// ## Body
			NSNumber *bodyLength = nil;
			NSString *readableContent = [OCHTTPRequest bodyDescriptionForURL:task.response.bodyURL data:task.response.bodyData headers:task.response.headerFields prefixed:NO bodyLength:&bodyLength altTextDescription:NULL];
			bodyDict[@"length"] = bodyLength;
			bodyDict[@"data"] = readableContent;
			bodyDict[@"local-data-url"] = task.response.bodyURL.absoluteString;

			// Compose JSON dict
			NSDictionary<NSString *, NSDictionary *> *jsonDict = @{
				@"response" : @{
					@"info"   : infoDict,
					@"header" : headerDict,
					@"body"   : bodyDict
				}
			};

			// Log JSON dict
			NSError *jsonError = nil;
			NSData *jsonData;
			NSString *jsonString = nil;

			if ((jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:&jsonError]) != nil)
			{
				jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
			}
			OCPFMLogDebug(OCLogOptionLogRequestsAndResponses, extraTags, @"RESPONSE %@ %@", task.request.identifier, (jsonString != nil) ? jsonString : [NSString stringWithFormat:@"JSON log encoding error: %@", jsonError]);
		}
		else
		{
			// OCHTTPPipelineLogFormatPlainText + default: plain text logging
			BOOL prefixedLogging = [[OCLogger classSettingForOCClassSettingsKey:OCClassSettingsKeyLogSingleLined] boolValue];
			NSString *infoPrefix = (prefixedLogging ? @"[info] " : @"");
			NSString *errorDescription = (task.response.httpError != nil) ? (prefixedLogging ? [[task.response.httpError description] stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"\n"] withString:[NSString stringWithFormat:@"\n[info] "]] : [task.response.httpError description]) : @"-";

			OCTLogDebug([extraTags arrayByAddingObject:@"HTSum"], @"<- %lu %@ (%@ %@)%@", (unsigned long)task.response.status.code, task.response.status.name, task.request.method, task.request.effectiveURL, ((task.response.redirectURL != nil) ? [NSString stringWithFormat:@" -> %@ ",task.response.redirectURL] : @""));
			OCPFMLogDebug(OCLogOptionLogRequestsAndResponses, extraTags, @"Received response:\n%@# RESPONSE --------------------------------------------------------\n%@Method:      %@\n%@URL:         %@\n%@Request-ID:  %@%@\n%@Error:       %@\n%@Req Signals: %@\n%@Metrics:     %@\n%@- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -\n%@-----------------------------------------------------------------", infoPrefix, infoPrefix, task.request.method, infoPrefix, task.request.effectiveURL, infoPrefix, task.request.identifier, ((task.request.headerFields[OCHTTPHeaderFieldNameOriginalRequestID] != nil) ? (![task.request.headerFields[OCHTTPHeaderFieldNameOriginalRequestID] isEqual:task.request.identifier] ? [NSString stringWithFormat:@" (original: %@)", task.request.headerFields[OCHTTPHeaderFieldNameOriginalRequestID]] : @"") : @""), infoPrefix, errorDescription, infoPrefix, [task.request.requiredSignals.allObjects componentsJoinedByString:@", "], infoPrefix, task.metrics.compactSummary, infoPrefix, [task.response responseDescriptionPrefixed:prefixedLogging]);
		}
	}

	// Attempt delivery
	[self _deliverResultForTask:task];
}

- (BOOL)_deliverResultForTask:(OCHTTPPipelineTask *)task
{
	// Get partitionHandler
	id<OCHTTPPipelinePartitionHandler> partitionHandler = nil;
	BOOL removeTask = NO;

	if (task.partitionID != nil)
	{
		@synchronized(self)
		{
			partitionHandler = [_partitionHandlersByID objectForKey:task.partitionID];
		}
	}

	if (partitionHandler != nil)
	{
		NSError *error = task.response.httpError;
		NSMutableSet <OCHTTPPipelineTaskID> *taskIDsInDelivery = _taskIDsInDelivery;
		dispatch_block_t updateTaskAndRetryDelivery = ^{
			[self queueBlock:^{
				[self.backend updatePipelineTask:task];

				@synchronized(taskIDsInDelivery)
				{
					[taskIDsInDelivery removeObject:task.taskID];
				}

				[self _deliverResultForTask:task];
			}];
		};
		BOOL skipPartitionInstructionDecision = NO;

		OCLogVerbose(@"Delivering result for taskID=%@, requestID=%@ to partition handler %@", task.taskID, task.request.identifier, partitionHandler);

		// Add to _taskIDsInDelivery, so delivery isn't retried until async work has finished.
		// (=> since this tracked in-memory, a crash/app termination will automatically result in delivery being retried)
		@synchronized(taskIDsInDelivery)
		{
			if ([taskIDsInDelivery containsObject:task.taskID])
			{
				OCLogVerbose(@"Skipping delivering result for taskID=%@, requestID=%@ to partition handler %@", task.taskID, task.request.identifier, partitionHandler);
				return (NO);
			}

			[taskIDsInDelivery addObject:task.taskID];
		}

		// Make response available via OCHTTPRequest.httpResponse
		task.request.httpResponse = task.response;

		// Check certificate validation status (for post-response attached certificates)
		if ((task.response.certificate != nil) && (task.response.certificateValidationResult == OCCertificateValidationResultNone))
		{
			OCConnectionCertificateProceedHandler proceedHandler = ^(BOOL proceed, NSError *proceedError) {
				if (!proceed)
				{
					task.response.error = (proceedError != nil) ? proceedError : OCError(OCErrorRequestServerCertificateRejected);
					task.response.httpError = proceedError;
				}

				updateTaskAndRetryDelivery();
			};

			[self evaluateCertificate:task.response.certificate forTask:task proceedHandler:proceedHandler];

			OCLogVerbose(@"Certificate evaluation during delivery of taskID=%@, requestID=%@ to partition handler %@ halted delivery", task.taskID, task.request.identifier, partitionHandler);

			return (NO);
		}

		// If error is that request was cancelled, use request.error if set
		if ([error.domain isEqualToString:NSURLErrorDomain] && (error.code==NSURLErrorCancelled))
		{
			if (task.response.error!=nil)
			{
				error = task.response.error;
			}
			else
			{
				error = OCErrorFromError(OCErrorRequestCancelled, error);
			}
		}

		// Deliver request by default
		OCHTTPRequestInstruction requestInstruction = OCHTTPRequestInstructionDeliver;

		// Manage auto-resume
		if (task.request.autoResume)
		{
			NSData *resumeData = nil;

			if ((resumeData = error.userInfo[NSURLSessionDownloadTaskResumeData]) != nil)
			{
				// If error contains resume data and auto-resume is allowed, add it to the task's request
				task.request.autoResumeInfo = @{
					OCHTTPRequestResumeInfoKeySystemResumeData : resumeData
				};

				requestInstruction = OCHTTPRequestInstructionReschedule;
				skipPartitionInstructionDecision = YES;
			}
			else
			{
				// Remove resume data in case the last response didn't have any
				if (task.request.autoResumeInfo != nil)
				{
					task.request.autoResumeInfo = nil;
				}
			}
		}

		OCLogVerbose(@"Entering post-processing of result for taskID=%@, requestID=%@ with skipPartitionInstructionDecision=%d, error=%@", task.taskID, task.request.identifier, skipPartitionInstructionDecision, error);

		// Give connection a chance to pass it off to authentication methods / interpret the error before delivery to the sender
		if ([partitionHandler respondsToSelector:@selector(pipeline:postProcessFinishedTask:error:)])
		{
			error = [partitionHandler pipeline:self postProcessFinishedTask:task error:error];
		}

		// Determine request instruction
		if (!skipPartitionInstructionDecision)
		{
			if ([partitionHandler respondsToSelector:@selector(pipeline:instructionForFinishedTask:instruction:error:)])
			{
				requestInstruction = [partitionHandler pipeline:self instructionForFinishedTask:task instruction:requestInstruction error:error];
			}
		}

		OCLogVerbose(@"Leaving post-processing of result for taskID=%@, requestID=%@ with requestInstruction=%lu, error=%@", task.taskID, task.request.identifier, (unsigned long)requestInstruction, error);

		// Deliver to target
		if (requestInstruction == OCHTTPRequestInstructionDeliver)
		{
			BOOL undeliverable = YES;

			// Deliver Finished Request
			if (task.request.resultHandlerAction != NULL)
			{
				// Below is identical to [partitionHandler performSelector:task.request.resultHandlerAction withObject:task.request withObject:error], but in an ARC-friendly manner.
				void (*impFunction)(id, SEL, OCHTTPRequest *, NSError *) = (void *)[((NSObject *)partitionHandler) methodForSelector:task.request.resultHandlerAction];

				if (impFunction != NULL)
				{
					impFunction(partitionHandler, task.request.resultHandlerAction, task.request, error);
					removeTask = YES;
					undeliverable = NO;

					OCLogVerbose(@"Delivered result for taskID=%@, requestID=%@ to partition handler %@", task.taskID, task.request.identifier, partitionHandler);
				}
			}
			else
			{
				if (task.request.ephermalResultHandler != nil)
				{
					task.request.ephermalResultHandler(task.request, task.response, error);
					removeTask = YES;
					undeliverable = NO;

					OCLogVerbose(@"Delivered result for taskID=%@, requestID=%@ to ephermal result handler %@", task.taskID, task.request.identifier, task.request.ephermalResultHandler);
				}
			}

			// Handle case where no delivery mechanism is available
			if (undeliverable)
			{
				OCLogError(@"Response for requestID=%@ is undeliverable - removing undelivered", task.requestID);
				removeTask = YES;
			}
		}

		// Remove temporarily downloaded files
		if (task.response.bodyURLIsTemporary && (task.response.bodyURL!=nil))
		{
			NSError *error =nil;

			[[NSFileManager defaultManager] removeItemAtURL:task.response.bodyURL error:&error];

			OCFileOpLog(@"rm", error, @"Removed temporary body file at %@", task.response.bodyURL.path);

			task.response.bodyURL = nil;
		}

		// Reschedule request if instructed so
		if (requestInstruction == OCHTTPRequestInstructionReschedule)
		{
			[task.request scrubForRescheduling];

			task.urlSessionID = nil;
			task.urlSessionTaskID = nil;

			// Use new Request-ID for rescheduled request
			if (task.request.autoResumeInfo == nil)
			{
				// Only recreate request IDs for requests that are NOT based on auto resume info
				// as it appears that it is not possible to change the headers for these, so that
				// the response would trigger an "UNKNOWN TASK" error.
				OCHTTPRequestID oldRequestID = task.requestID;

				task.requestID = [task.request recreateRequestID];

				OCLogVerbose(@"Recreated identifier for request: %@ -> %@", oldRequestID, task.requestID);
			}
			else
			{
				OCLogVerbose(@"Reusing identifier %@ for request because it is resumed and headers can't be changed", task.requestID);
			}

			task.state = OCHTTPPipelineTaskStatePending;
			task.bundleID = self->_bundleIdentifier; // ensure binding to this bundle/component so that a drop of this request can be properly identified
			task.response = nil;

			[_backend updatePipelineTask:task];

			[self setPipelineNeedsScheduling];
		}

		// Remove task
		if (removeTask)
		{
			if (task.urlSessionTaskID != nil)
			{
				OCLogVerbose(@"Removing request %@ [%@] with taskIdentifier <%@>", OCLogPrivate(task.request.url), task.request.identifier, task.urlSessionTaskID);
			}

			[self.backend removePipelineTask:task];
			[self _triggerPartitionEmptyHandlers];
		}

		// Remove from tasks in delivery
		@synchronized(taskIDsInDelivery)
		{
			[taskIDsInDelivery removeObject:task.taskID];
		}

		OCLogVerbose(@"Delivery result for taskID=%@ [%@]: requestInstruction=%lu, removeTask=%d", task.taskID, task.request.identifier, (unsigned long)requestInstruction, removeTask);
	}
	else
	{
		// No partition handler attached, so delivery on same process assumed not to be critical
		BOOL allowHandlingByAnyProcess = [task.bundleID isEqual:self->_bundleIdentifier];

		if (allowHandlingByAnyProcess)
		{
			task.bundleID = OCHTTPPipelineTaskAnyBundleID;
			[_backend updatePipelineTask:task];
		}

		OCLogVerbose(@"Delivery result for taskID=%@ [%@]: removeTask=%d, bundleID=%@, allowHandlingByAnyProcess=%d", task.taskID, task.request.identifier, removeTask, task.bundleID, allowHandlingByAnyProcess);
	}

	return (removeTask);
}

- (void)_deliverResultsForPartition:(OCHTTPPipelinePartitionID)partitionID
{
	[self.backend enumerateCompletedTasksForPipeline:self partition:partitionID enumerator:^(OCHTTPPipelineTask *task, BOOL *stop) {
		[self _deliverResultForTask:task];
	}];
}

#pragma mark - Attach & detach partition handlers
- (void)attachPartitionHandler:(id<OCHTTPPipelinePartitionHandler>)partitionHandler completionHandler:(nullable OCCompletionHandler)completionHandler
{
	[self queueInline:^{
		OCHTTPPipelinePartitionID partitionID;

		if ((partitionID = [partitionHandler partitionID]) != nil)
		{
			id<OCHTTPPipelinePartitionHandler> existingPartitionHandler;

			@synchronized(self)
			{
				// Check for duplicate handlers
				if ((existingPartitionHandler = [self->_partitionHandlersByID objectForKey:partitionID]) != nil)
				{
					OCLogWarning(@"Attempt to attach a handler (%@) for partition %@ for which one is already attached (%@). Detaching previous one.", partitionHandler, partitionID, existingPartitionHandler);

					// Detach existing one
					[self detachPartitionHandler:existingPartitionHandler completionHandler:^(id sender, NSError *error) {
						// Once detached, attach the new one
						[self attachPartitionHandler:partitionHandler completionHandler:completionHandler];
					}];

					return;
				}

				// Add handler
				[self->_partitionHandlersByID setObject:partitionHandler forKey:partitionID];
			}

			// Deliver pending results
			[self queueBlock:^{
				[self _deliverResultsForPartition:partitionID];
			}];

			// Schedule any queued requests in the pipeline waiting for this partition handler
			[self setPipelineNeedsScheduling];
		}

		if (completionHandler != nil)
		{
			completionHandler(self, nil);
		}
	}];
}

- (void)detachPartitionHandler:(id<OCHTTPPipelinePartitionHandler>)partitionHandler completionHandler:(nullable OCCompletionHandler)completionHandler
{
	[self queueInline:^{
		OCHTTPPipelinePartitionID partitionID = [partitionHandler partitionID];

		OCLogVerbose(@"Enter detachPartitionHandler %@ (%@), _partitionHandlersByID=%@", partitionHandler, partitionID, self->_partitionHandlersByID);

		if (partitionID != nil)
		{
			@synchronized(self)
			{
				if (partitionHandler == [self->_partitionHandlersByID objectForKey:partitionID])
				{
					[self->_partitionHandlersByID removeObjectForKey:partitionID];
				}
				else
				{
					OCLogWarning(@"Attempt to detach a handler (%@) for partition %@ that wasn't attached.", partitionHandler, partitionID);
				}
			}
		}
		else
		{
			OCLogError(@"Can't detach handler (%@) since no partition could be retrieved from it: %@", partitionHandler, partitionID);
		}

		OCLogVerbose(@"Leave detachPartitionHandler %@ (%@), _partitionHandlersByID=%@", partitionHandler, partitionID, self->_partitionHandlersByID);

		if (completionHandler != nil)
		{
			completionHandler(self, nil);
		}
	}];
}

- (void)detachPartitionHandlerForPartitionID:(OCHTTPPipelinePartitionID)partitionID completionHandler:(nullable OCCompletionHandler)completionHandler
{
	id<OCHTTPPipelinePartitionHandler> partitionHandler = [self partitionHandlerForPartitionID:partitionID];

	if (partitionHandler != nil)
	{
		[self detachPartitionHandler:partitionHandler completionHandler:completionHandler];
	}
	else
	{
		completionHandler(self, nil);
	}
}

- (id<OCHTTPPipelinePartitionHandler>)partitionHandlerForPartitionID:(nullable OCHTTPPipelinePartitionID)partitionID
{
	id<OCHTTPPipelinePartitionHandler> partitionHandler = nil;

	if (partitionID != nil)
	{
		@synchronized(self)
		{
			partitionHandler = [_partitionHandlersByID objectForKey:partitionID];
		}
	}

	return (partitionHandler);
}

- (NSUInteger)tasksPendingDeliveryForPartitionID:(OCHTTPPipelinePartitionID)partitionID
{
	if (partitionID != nil)
	{
		NSError *error = nil;

		NSUInteger pendingDeliveryCount = ([[self.backend numberOfRequestsWithState:OCHTTPPipelineTaskStateCompleted inPipeline:self partition:partitionID error:&error] unsignedIntegerValue]);

		if (error != nil)
		{
			OCLogError(@"Error retrieving number of requests pending delivery: %@", error)
		}

		return (pendingDeliveryCount);
	}

	return (0);
}

#pragma mark - Remove partition
- (void)destroyPartition:(OCHTTPPipelinePartitionID)partitionID completionHandler:(nullable OCCompletionHandler)completionHandler
{
	OCLogVerbose(@"destroy partitionID=%@", partitionID);

	[self queueBlock:^{
		// Prevent further scheduling for partitionID
		@synchronized(self)
		{
			[self->_partitionsInDestruction addObject:partitionID];
		}

		// Cancel all requests for this partition
		[self cancelRequestsForPartitionID:partitionID queuedOnly:NO];

		dispatch_block_t completeDestruction = ^{
			// Detach the partition handler
			[self detachPartitionHandlerForPartitionID:partitionID completionHandler:^(id sender, NSError *error) {
				NSURL *temporaryPartitionRootURL;

				// Remove all records for this partition from the database
				[self.backend removeAllTasksForPipeline:self.identifier partition:partitionID];

				// Remove partition root dir for temporary files
				if ((temporaryPartitionRootURL = [self _URLForPartitionID:partitionID requestID:nil]) != nil)
				{
					NSError *removeError = error;

					if ([[NSFileManager defaultManager] fileExistsAtPath:temporaryPartitionRootURL.path])
					{
						[[NSFileManager defaultManager] removeItemAtURL:temporaryPartitionRootURL error:&removeError];

						OCFileOpLog(@"rm", removeError, @"Removed root partition folder at %@", temporaryPartitionRootURL.path);
					}

					if (completionHandler!=nil)
					{
						completionHandler(self, removeError);
					}
				}
				else
				{
					if (completionHandler!=nil)
					{
						completionHandler(self, error);
					}
				}
			}];
		};

		@synchronized(self)
		{
			if ([self->_partitionHandlersByID objectForKey:partitionID] != nil)
			{
				// Make sure all cancellations have been delivered
				[self addEmptyHandler:completeDestruction forPartition:partitionID];
			}
			else
			{
				// No handler attached that could take care => destroy right away
				[self queueBlock:completeDestruction];
			}
		}
	}];
}

#pragma mark - Partition empty handling
- (void)addEmptyHandler:(dispatch_block_t)emptyHandler forPartition:(OCHTTPPipelinePartitionID)partitionID
{
	@synchronized(_partitionEmptyHandlers)
	{
		NSMutableArray<dispatch_block_t> *emptyHandlers;
		if ((emptyHandlers = [_partitionEmptyHandlers objectForKey:partitionID]) == nil)
		{
			emptyHandlers = [[NSMutableArray alloc] initWithCapacity:1];
			_partitionEmptyHandlers[partitionID] = emptyHandlers;
		}

		[emptyHandlers addObject:[emptyHandler copy]];
	}
}

- (void)_triggerPartitionEmptyHandlers
{
	NSArray<OCHTTPPipelinePartitionID> *partitionIDs = nil;

	@synchronized(_partitionEmptyHandlers)
	{
		if (_partitionEmptyHandlers.count > 0)
		{
			partitionIDs = [_partitionEmptyHandlers allKeys];
		}
	}

	if (partitionIDs != nil)
	{
		for (OCHTTPPipelinePartitionID partitionID in partitionIDs)
		{
			NSError *error = nil;

			if ([self.backend numberOfRequestsInPipeline:self partition:partitionID error:&error].integerValue == 0)
			{
				@synchronized(_partitionEmptyHandlers)
				{
					NSMutableArray<dispatch_block_t> *emptyHandlers;
					if ((emptyHandlers = [_partitionEmptyHandlers objectForKey:partitionID]) != nil)
					{
						[_partitionEmptyHandlers removeObjectForKey:partitionID];

						[self queueBlock:^{
							for (dispatch_block_t emptyHandler in emptyHandlers)
							{
								emptyHandler();
							}
						}];
					}
				}
			}

			if (error != nil)
			{
				OCLogError(@"Error retrieving number of requests in pipeline: %@", error);
			}
		}
	}
}

#pragma mark - Shutdown
- (void)finishTasksAndInvalidateWithCompletionHandler:(dispatch_block_t)completionHandler
{
	OCLogVerbose(@"finish tasks and invalidate");

	_invalidationCompletionHandler = completionHandler;

	// Find and cancel non-critical requests
	[self cancelNonCriticalRequestsForPartitionID:nil];

	// Finish and invalidate remaining tasks in session
	[_urlSession finishTasksAndInvalidate];
}

- (void)invalidateAndCancelWithCompletionHandler:(dispatch_block_t)completionHandler
{
	OCLogVerbose(@"cancel tasks and invalidate");

	_invalidationCompletionHandler = completionHandler;

	[_urlSession invalidateAndCancel];
}

- (void)cancelNonCriticalRequestsForPartitionID:(nullable OCHTTPPipelinePartitionID)partitionID
{
	[self queueBlock:^{
		// Find and cancel non-critical requests
		NSError *enumerationError = [self.backend enumerateTasksForPipeline:self enumerator:^(OCHTTPPipelineTask *task, BOOL *stop) {
			if (((partitionID==nil) || ((partitionID!=nil) && [task.partitionID isEqual:partitionID])) && task.request.isNonCritial)
			{
				OCLogVerbose(@"Cancelling non-critical task %@", task.taskID);
				[self _cancelTask:task];
			}
		}];

		if (enumerationError != nil)
		{
			OCLogError(@"Error enumerating requests: %@", enumerationError);
		}
	}];
}

- (void)finishPendingRequestsForPartitionID:(OCHTTPPipelinePartitionID)partitionID withError:(NSError *)error filter:(BOOL(^)(OCHTTPPipeline *pipeline, OCHTTPPipelineTask *task))filter
{
	[self queueInline:^{
		NSError *enumerationError = [self.backend enumerateTasksForPipeline:self partition:partitionID enumerator:^(OCHTTPPipelineTask *task, BOOL *stop) {
			if (filter(self, task))
			{
				[self finishedTask:task withResponse:[OCHTTPResponse responseWithRequest:task.request HTTPError:error]];
			}
		}];

		if (enumerationError != nil)
		{
			OCLogError(@"Error enumerating requests: %@", enumerationError);
		}
	}];
}

#pragma mark - Background URL session finishing
- (void)attachBackgroundURLSessionWithConfiguration:(NSURLSessionConfiguration *)backgroundSessionConfiguration handlingCompletionHandler:(dispatch_block_t)handlingCompletionHandler
{
	@synchronized(self)
	{
		NSString *sessionIdentifier;

		if ((sessionIdentifier = backgroundSessionConfiguration.identifier) != nil)
		{
			[self queueBlock:^{
				NSURLSession *session;

				self->_sessionCompletionHandlersByIdentifiers[sessionIdentifier] = handlingCompletionHandler;

				if (![sessionIdentifier isEqual:self.urlSessionIdentifier])
				{
					if ((session = [NSURLSession sessionWithConfiguration:backgroundSessionConfiguration delegate:self delegateQueue:nil]) != nil)
					{
						self->_attachedURLSessionsByIdentifier[sessionIdentifier] = session;
					}
				}
			}];
		}
		else
		{
			OCLogError(@"Attempt to attach background URL session without identifier: %@", backgroundSessionConfiguration);
		}
	}
}

#pragma mark - Accessors
- (BOOL)backgroundSessionBacked
{
	return (_urlSessionIdentifier != nil);
}

#pragma mark - NSURLSessionDelegate
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session
{
	NSString *sessionIdentifier = session.configuration.identifier;

	OCLogDebug(@"URLSessionDidFinishEventsForBackgroundSession: %@", session);

	if (sessionIdentifier != nil)
	{
		// Call completion handler
		[self queueBlock:^{
			dispatch_block_t completionHandler;
			NSURLSession *urlSession;

			if ((completionHandler = self->_sessionCompletionHandlersByIdentifiers[sessionIdentifier]) != nil)
			{
				[self->_sessionCompletionHandlersByIdentifiers removeObjectForKey:sessionIdentifier];

				// Apple docs: "Because the provided completion handler is part of UIKit, you must call it on your main thread."
				dispatch_async(dispatch_get_main_queue(), ^{
					completionHandler();
				});
			}

			if ((completionHandler = [OCHTTPPipelineManager.sharedPipelineManager eventHandlingFinishedBlockForURLSessionIdentifier:sessionIdentifier remove:YES]) != nil)
			{
				// Apple docs: "Because the provided completion handler is part of UIKit, you must call it on your main thread."
				dispatch_async(dispatch_get_main_queue(), ^{
					completionHandler();
				});
			}

			if ((urlSession = self->_attachedURLSessionsByIdentifier[sessionIdentifier]) != nil)
			{
				// Drop any dropped requests now
				[self _recoverQueueForURLSession:urlSession completionHandler:^{
					// Terminate urlSession
					[urlSession finishTasksAndInvalidate];
				}];
			}
		}];
	}
}

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error
{
	NSString *sessionIdentifier = session.configuration.identifier;

	if (([sessionIdentifier isEqual:_urlSessionIdentifier]) || !self.backgroundSessionBacked)
	{
		_urlSessionInvalidated = YES;

		OCLogVerbose(@"did become invalid with error=%@, running invalidationCompletionHandler %p", error, _invalidationCompletionHandler);

		if (_invalidationCompletionHandler != nil)
		{
			_invalidationCompletionHandler();
			_invalidationCompletionHandler = nil;
		}
	}
	else
	{
		OCLogVerbose(@"%@ did become invalid with error=%@, removing from _attachedURLSessionsByIdentifier", session, error);

		[self queueBlock:^{
			// Drop urlSession
			if (self->_attachedURLSessionsByIdentifier[sessionIdentifier] != nil)
			{
				[self->_attachedURLSessionsByIdentifier removeObjectForKey:sessionIdentifier];
			}
		}];
	}
}

#pragma mark - NSURLSessionTaskDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)urlSessionTask didCompleteWithError:(nullable NSError *)error
{
	NSError *backendError = nil;
	OCHTTPPipelineTask *task;

	OCLogVerbose(@"Task [%@] didCompleteWithError=%@", urlSessionTask.requestIdentityDescription, error);

	if ((task = [self.backend retrieveTaskForPipeline:self URLSession:session task:urlSessionTask error:&backendError]) != nil)
	{
		OCLogVerbose(@"Known task [%@] didCompleteWithError=%@", urlSessionTask.requestIdentityDescription,  error);

		[self addMetrics:task.metrics withTask:urlSessionTask];

		if (error != nil)
		{
			OCHTTPResponse *response = [task responseFromURLSessionTask:urlSessionTask];

			response.requestID = task.request.identifier;
			response.httpError = error;

			[self finishedTask:task withResponse:response];
		}
		else
		{
			[self finishedTask:task withResponse:[task responseFromURLSessionTask:urlSessionTask]];
		}
	}
	else
	{
		OCLogError(@"UNKNOWN TASK [%@] didCompleteWithError=%@, backendError=%@", urlSessionTask.requestIdentityDescription, error, backendError);
		[_backend dumpDBTable];
	}
}

- (void)URLSession:(NSURLSession *)session taskIsWaitingForConnectivity:(NSURLSessionTask *)urlSessionTask
{
	OCLogVerbose(@"Task [%@] taskIsWaitingForConnectivity", urlSessionTask.requestIdentityDescription);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)urlSessionTask didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics
{
	OCHTTPPipelineTask *task = nil;
	NSError *backendError = nil;
	NSString *compactSummary = nil;

	if (OCLogToggleEnabled(OCLogOptionLogRequestsAndResponses) && OCLoggingEnabled())
	{
		compactSummary = [metrics compactSummaryWithTask:urlSessionTask];
	}

	if ((task = [self.backend retrieveTaskForPipeline:self URLSession:session task:urlSessionTask error:&backendError]) != nil)
	{
		task.metrics = [[OCHTTPPipelineTaskMetrics alloc] initWithURLSessionTaskMetrics:metrics];
		task.metrics.compactSummary = compactSummary;
	}
	else
	{
		OCLogError(@"UNKNOWN TASK [%@] didFinishCollectingMetrics, backendError=%@", urlSessionTask.requestIdentityDescription, backendError);
		[_backend dumpDBTable];
	}
}

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)urlSessionTask
        willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
        completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler
{
	OCLogVerbose(@"Task [%@] wants to perform redirection from %@ to %@ via %@", urlSessionTask.requestIdentityDescription, OCLogPrivate(urlSessionTask.currentRequest.URL), OCLogPrivate(request.URL), response);

	// Don't allow redirections. Deliver the redirect response instead - these really need to be handled locally on a case-by-case basis.
	if (completionHandler != nil)
	{
		completionHandler(nil);
	}
}

- (void)evaluateCertificate:(OCCertificate *)certificate forTask:(OCHTTPPipelineTask *)task proceedHandler:(OCConnectionCertificateProceedHandler)proceedHandler
{
	if ((task == nil) || (certificate==nil))
	{
		proceedHandler(NO, OCError(OCErrorInsufficientParameters));
		return;
	}

	[certificate evaluateWithCompletionHandler:^(OCCertificate *certificate, OCCertificateValidationResult validationResult, NSError *validationError) {
		[self queueBlock:^{
			OCHTTPResponse *response = [task responseFromURLSessionTask:nil];

			response.certificate = certificate;
			response.certificateValidationResult = validationResult;
			response.certificateValidationError = validationError;

			if (((validationResult == OCCertificateValidationResultUserAccepted) ||
			     (validationResult == OCCertificateValidationResultPassed)) &&
			     !task.request.forceCertificateDecisionDelegation)
			{
				proceedHandler(YES, nil);
			}
			else
			{
				if (task.request.ephermalRequestCertificateProceedHandler != nil)
				{
					task.request.ephermalRequestCertificateProceedHandler(task.request, certificate, validationResult, validationError, proceedHandler);
				}
				else
				{
					NSArray<id<OCHTTPPipelinePolicyHandler>> *policyHandlers;
					id<OCHTTPPipelinePartitionHandler> partitionHandler = [self partitionHandlerForPartitionID:task.partitionID];

					policyHandlers = (NSArray<id<OCHTTPPipelinePolicyHandler>> *)[OCHTTPPolicyManager.sharedManager applicablePoliciesForPipelinePartitionID:task.partitionID handler:partitionHandler];

					if (partitionHandler != nil)
					{
						if ([partitionHandler conformsToProtocol:@protocol(OCHTTPPipelinePolicyHandler)])
						{
							if (policyHandlers != nil)
							{
								policyHandlers = [policyHandlers arrayByAddingObject:(id<OCHTTPPipelinePolicyHandler>)partitionHandler];
							}
							else
							{
								policyHandlers = @[ (id<OCHTTPPipelinePolicyHandler>)partitionHandler ];
							}
						}
					}

					if (policyHandlers.count == 0)
					{
						// If no policy handlers are available, reject the certificate
						proceedHandler(NO, nil);
					}
					else
					{
						// Iterate through policy handlers
						[OCHTTPPipeline _iteratePolicyHandlers:policyHandlers index:0 pipeline:self certificate:certificate validationResult:validationResult validationError:validationError task:task proceedHandler:proceedHandler];
					}
				}
			}
		}];
	}];
}

+ (void)_iteratePolicyHandlers:(NSArray<id<OCHTTPPipelinePolicyHandler>> *)policyHandlers index:(NSUInteger)index pipeline:(OCHTTPPipeline *)pipeline certificate:(OCCertificate *)certificate validationResult:(OCCertificateValidationResult)validationResult validationError:(NSError *)validationError task:(OCHTTPPipelineTask *)task  proceedHandler:(OCConnectionCertificateProceedHandler)proceedHandler
{
	id<OCHTTPPipelinePolicyHandler> policyHandler = policyHandlers[index];

	[policyHandler pipeline:pipeline handleValidationOfRequest:task.request certificate:certificate validationResult:validationResult validationError:validationError proceedHandler:^(BOOL proceed, NSError * _Nullable error) {
		if (!proceed || ((index+1) >= policyHandlers.count))
		{
			proceedHandler(proceed, error);
		}
		else
		{
			[self _iteratePolicyHandlers:policyHandlers index:(index+1) pipeline:pipeline certificate:certificate validationResult:validationResult validationError:validationError task:task proceedHandler:proceedHandler];
		}
	}];
}

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)urlSessionTask
        didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
        completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler
{
	OCLogVerbose(@"[%@]: %@ => protection space: %@ method: %@", urlSessionTask.requestIdentityDescription, OCLogPrivate(challenge), OCLogPrivate(challenge.protectionSpace), challenge.protectionSpace.authenticationMethod);

	if ([challenge.protectionSpace.authenticationMethod isEqual:NSURLAuthenticationMethodServerTrust])
	{
		SecTrustRef serverTrust;

		if ((serverTrust = challenge.protectionSpace.serverTrust) != NULL)
		{
			// Handle server trust challenges
			OCCertificate *certificate = [OCCertificate certificateWithTrustRef:serverTrust hostName:urlSessionTask.currentRequest.URL.host];
			OCHTTPPipelineTask *task = nil;
			NSURL *requestURL = urlSessionTask.currentRequest.URL;
			NSString *hostnameAndPort;
			NSError *dbError = nil;

			if ((hostnameAndPort = [NSString stringWithFormat:@"%@:%@", requestURL.host.lowercaseString, ((requestURL.port!=nil)?requestURL.port : @"443" )]) != nil)
			{
				// Cache certificates
				@synchronized(self)
				{
					if (certificate != nil)
					{
						[_cachedCertificatesByHostnameAndPort setObject:certificate forKey:hostnameAndPort];
					}
					else
					{
						[_cachedCertificatesByHostnameAndPort removeObjectForKey:hostnameAndPort];
					}
				}
			}

			task = [self.backend retrieveTaskForPipeline:self URLSession:session task:urlSessionTask error:&dbError];

			OCConnectionCertificateProceedHandler proceedHandler = ^(BOOL proceed, NSError *error) {
				if (proceed)
				{
					completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:serverTrust]);
				}
				else
				{
					[task responseFromURLSessionTask:urlSessionTask].error = (error != nil) ? error : OCError(OCErrorRequestServerCertificateRejected);
					completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
				}
			};

			if (task != nil)
			{
				if (certificate == nil)
				{
					proceedHandler(NO, OCError(OCErrorCertificateMissing));
				}
				else
				{
					[self evaluateCertificate:certificate forTask:task proceedHandler:proceedHandler];
				}
			}
			else
			{
				OCLogError(@"UNKNOWN TASK [%@] task:didReceiveChallenge=%@, dbError=%@", urlSessionTask.requestIdentityDescription, OCLogPrivate(challenge), dbError);
				[_backend dumpDBTable];
			}
		}
		else
		{
			completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
		}
	}
	else
	{
		// All other challenges
		completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
	}
}


#pragma mark - NSURLSessionDataDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)urlSessionDataTask didReceiveData:(NSData *)data
{
	[self queueBlock:^{
		NSError *dbError = nil;
		OCHTTPPipelineTask *task;

		if ((task = [self.backend retrieveTaskForPipeline:self URLSession:session task:urlSessionDataTask error:&dbError]) != nil)
		{
			OCHTTPResponse *response;

			if (!task.request.downloadRequest)
			{
				if ((response = [task responseFromURLSessionTask:urlSessionDataTask]) != nil)
				{
					if (task.request.shouldStreamResponse)
					{
						// Stream response data
						[task.request handleResponseStreamData:data forPipelineTask:task];
					}
					else
					{
						// Append received data
						[response appendDataToResponseBody:data];
					}
				}
			}
		}
		else
		{
			OCLogError(@"UNKNOWN TASK [%@, dbError=%@] dataTask:didReceiveData:", urlSessionDataTask.requestIdentityDescription, dbError);
		}
	}];
}


#pragma mark - NSURLSessionDownloadDelegate
- (nullable NSURL *)_URLForPartitionID:(nullable OCHTTPPipelinePartitionID)partitionID requestID:(nullable OCHTTPRequestID)requestID
{
	NSURL *url = [_backend.temporaryFilesRoot URLByAppendingPathComponent:_identifier]; // Add pipeline ID

	if (partitionID != nil)
	{
		url = [url URLByAppendingPathComponent:partitionID isDirectory:YES];

		if (requestID != nil)
		{
			url = [url URLByAppendingPathComponent:requestID isDirectory:NO];
		}
	}
	else
	{
		if (requestID != nil)
		{
			OCLogError(@"Can't build URL for requestID=%@ without partitionID", requestID);
			url = nil;
		}
	}

	return (url);
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)urlSessionDownloadTask didFinishDownloadingToURL:(NSURL *)location
{
	NSError *dbError = nil;
	OCHTTPPipelineTask *task;

	if ((task = [self.backend retrieveTaskForPipeline:self URLSession:session task:urlSessionDownloadTask error:&dbError]) != nil)
	{
		OCHTTPRequest *request = task.request;
		OCHTTPResponse *response = [task responseFromURLSessionTask:urlSessionDownloadTask];

		if (request.downloadedFileURL == nil)
		{
			// Use partition- & request-specific subdirectory
			NSURL *partitionURL;

			if ((partitionURL = [self _URLForPartitionID:task.partitionID requestID:nil]) != nil)
			{
				if (![[NSFileManager defaultManager] fileExistsAtPath:partitionURL.path])
				{
					[[NSFileManager defaultManager] createDirectoryAtURL:partitionURL withIntermediateDirectories:YES attributes:@{ NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication } error:NULL];
				}
			}

			response.bodyURL = [self _URLForPartitionID:task.partitionID requestID:task.requestID];
			response.bodyURLIsTemporary = YES;
		}
		else
		{
			response.bodyURL = request.downloadedFileURL;
			response.bodyURLIsTemporary = request.downloadedFileIsTemporary;
		}

		if (response.bodyURL != nil)
		{
			NSError *error = nil;
			NSURL *parentURL = response.bodyURL.URLByDeletingLastPathComponent;

			if (![[NSFileManager defaultManager] fileExistsAtPath:parentURL.path])
			{
				[[NSFileManager defaultManager] createDirectoryAtURL:parentURL withIntermediateDirectories:YES attributes:@{ NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication } error:&error];
			}

			[[NSFileManager defaultManager] moveItemAtURL:location toURL:response.bodyURL error:&error];

			OCFileOpLog(@"mv", error, @"Moved downloaded file %@ from %@ to %@", OCLogPrivate(request.effectiveURL), location.path, response.bodyURL.path);
		}

		// Update task with results
		[self.backend updatePipelineTask:task];
	}

	OCLogVerbose(@"[%@]: downloadTask:didFinishDownloadingToURL: %@, dbError=%@", urlSessionDownloadTask.requestIdentityDescription, location, dbError);
	// OCLogVerbose(@"DOWNLOADTASK FINISHED: %@ %@ %@", downloadTask, location, request);
}

#pragma mark - Cellular Switch / Network observation
- (void)_cellularSwitchChanged:(NSNotification *)notification
{
	[self setPipelineNeedsScheduling];
}

- (void)_networkStatusChanged:(NSNotification *)notification
{
	[self setPipelineNeedsScheduling];
}

#pragma mark - Metrics
- (void)addMetrics:(OCHTTPPipelineTaskMetrics *)metrics withTask:(NSURLSessionTask *)task
{
	if ((metrics != nil) && (task != nil))
	{
		if ((metrics.totalTransferDuration.doubleValue > _metricsMinimumTotalTransferDurationRelevancyThreshold) &&
		    ((-[metrics.date timeIntervalSinceNow]) < _metricsHistoryMaxAge))
		{
			[metrics addTransferSizesFromURLSessionTask:task];

			@synchronized(_metricsHistory)
			{
				// Drop outdated records
				[_metricsHistory filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(OCHTTPPipelineTaskMetrics *filterMetrics, NSDictionary<NSString *,id> * _Nullable bindings) {
					return ((-[filterMetrics.date timeIntervalSinceNow]) < self->_metricsHistoryMaxAge);
				}]];

				// Add new record
				[_metricsHistory addObject:metrics];
			}
		}
	}
}

- (BOOL)weightedAverageSendBytesPerSecond:(NSNumber **)outSendBytesPerSecond receiveBytesPerSecond:(NSNumber **)outReceiveBytesPerSecond transportationDelaySeconds:(NSNumber **)outTransportationDelaySeconds largestSendBytes:(NSUInteger *)outLargestSendBytes largestReceiveBytes:(NSUInteger *)outLargestReceiveBytes forHostname:(NSString *)hostname
{
	@synchronized(_metricsHistory)
	{
		NSUInteger totalSendBytesPerSecond = 0;
		NSUInteger totalSendBytesPerSecondSamples = 0;

		NSUInteger totalReceiveBytesPerSecond = 0;
		NSUInteger totalReceiveBytesPerSecondSamples = 0;

		NSTimeInterval totalTransportationDelaySeconds = 0;
		NSUInteger     totalTransportationDelaySamples = 0;

		NSUInteger totalSentBytes = 0;
		NSUInteger totalReceivedBytes = 0;

		NSUInteger largestSentBytes = 0;
		NSUInteger largestReceiveBytes = 0;

		for (OCHTTPPipelineTaskMetrics *metrics in _metricsHistory)
		{
			if (((-[metrics.date timeIntervalSinceNow]) < _metricsHistoryMaxAge) && [metrics.hostname isEqual:hostname])
			{
				NSNumber *number;

				if ((number = metrics.sentBytesPerSecond) != nil)
				{
					NSUInteger totalBytes = metrics.totalRequestSizeBytes.unsignedIntegerValue;

					totalSendBytesPerSecond += number.unsignedIntegerValue * totalBytes;
					totalSendBytesPerSecondSamples += 1;

					totalSentBytes += totalBytes;

					if (largestSentBytes < totalBytes)
					{
						largestSentBytes = totalBytes;
					}
				}

				if ((number = metrics.receivedBytesPerSecond) != nil)
				{
					NSUInteger totalBytes = metrics.totalResponseSizeBytes.unsignedIntegerValue;

					totalReceiveBytesPerSecond += number.unsignedIntegerValue * totalBytes;
					totalReceiveBytesPerSecondSamples += 1;

					totalReceivedBytes += metrics.totalResponseSizeBytes.unsignedIntegerValue;

					if (largestReceiveBytes < totalBytes)
					{
						largestReceiveBytes = totalBytes;
					}
				}

				if ((number = metrics.serverProcessingTimeInterval) != nil)
				{
					totalTransportationDelaySeconds += number.doubleValue;
					totalTransportationDelaySamples += 1;
				}
			}
		}

		if ((totalSendBytesPerSecondSamples > 0) && (totalSentBytes > 0))
		{
			*outSendBytesPerSecond = @(totalSendBytesPerSecond / (totalSentBytes * totalSendBytesPerSecondSamples));
		}
		else
		{
			*outSendBytesPerSecond = nil;
		}

		if ((totalReceiveBytesPerSecondSamples > 0) && (totalReceivedBytes > 0))
		{
			*outReceiveBytesPerSecond = @(totalReceiveBytesPerSecond / (totalReceivedBytes * totalReceiveBytesPerSecondSamples));
		}
		else
		{
			*outReceiveBytesPerSecond = nil;
		}

		if (totalTransportationDelaySamples > 0)
		{
			*outTransportationDelaySeconds = @(totalTransportationDelaySeconds / ((NSTimeInterval)totalTransportationDelaySamples));
		}
		else
		{
			*outTransportationDelaySeconds = nil;
		}

		*outLargestReceiveBytes = largestReceiveBytes;
		*outLargestSendBytes = largestSentBytes;

		return ((totalSendBytesPerSecondSamples > 0) && (totalReceiveBytesPerSecondSamples > 0) && (totalTransportationDelaySeconds > 0));
	}
}

- (nullable NSNumber *)estimatedTimeForRequest:(OCHTTPRequest *)request withExpectedResponseLength:(NSUInteger)expectedResponseLength confidence:(double *)outConfidence
{
	NSNumber *averageSendBytesPerSecond=nil, *averageReceiveBytesPerSecond=nil, *averageTransportationDelay = nil;
	NSUInteger largestSendBytes = 0, largestReceivesBytes = 0;

	if ([self weightedAverageSendBytesPerSecond:&averageSendBytesPerSecond receiveBytesPerSecond:&averageReceiveBytesPerSecond transportationDelaySeconds:&averageTransportationDelay largestSendBytes:&largestSendBytes largestReceiveBytes:&largestReceivesBytes	 forHostname:request.url.host])
	{
		NSUInteger requestSize = 0, responseSize = expectedResponseLength;
		NSTimeInterval estimatedTimeToComplete = 0;
		CGFloat confidenceLevel = 0;

		[request prepareForScheduling];

		requestSize += [OCHTTPPipelineTaskMetrics lengthOfHeaderDictionary:request.headerFields method:request.method url:request.effectiveURL];

		if (request.bodyURL != nil)
		{
			NSNumber *fileSize = nil;

			if ([request.bodyURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL])
			{
				requestSize += fileSize.unsignedIntegerValue;
			}
		}
		else
		{
			requestSize += request.bodyData.length;
		}

		estimatedTimeToComplete = ((NSTimeInterval)requestSize / (NSTimeInterval)averageSendBytesPerSecond.unsignedIntegerValue) + ((NSTimeInterval)responseSize / (NSTimeInterval)averageReceiveBytesPerSecond.unsignedIntegerValue) + averageTransportationDelay.doubleValue;

		confidenceLevel = (CGFloat)1.0 / ((((CGFloat)(requestSize*requestSize) / (CGFloat)largestSendBytes) + ((CGFloat)(responseSize*responseSize) / (CGFloat)largestReceivesBytes)) / ((CGFloat)(requestSize + responseSize)));

		OCLogVerbose(@"weightedAverage sendBPS=%@, receiveBPS=%@, transportationDelay=%@ - bytesToSend=%lu, bytesToReceive=%lu - estimatedTimeToComplete=%.02f, confidenceLevel=%.03f", averageSendBytesPerSecond, averageReceiveBytesPerSecond, averageTransportationDelay, requestSize, responseSize, estimatedTimeToComplete, confidenceLevel);

		if (outConfidence != NULL)
		{
			*outConfidence = confidenceLevel;
		}

		return (@(estimatedTimeToComplete));
	}

	return (nil);
}

#pragma mark - Progress
- (nullable NSProgress *)progressForRequestID:(OCHTTPRequestID)requestID
{
	OCHTTPPipelineTask *task;

	if ((task = [self.backend retrieveTaskForRequestID:requestID error:nil]) != nil)
	{
		return (task.request.progress.progress);
	}

	return (nil);
}

#pragma mark - Class settings
INCLUDE_IN_CLASS_SETTINGS_SNAPSHOTS(OCHTTPPipeline)

+ (OCClassSettingsIdentifier)classSettingsIdentifier
{
	return (OCClassSettingsIdentifierHTTP);
}

+ (NSDictionary<NSString *,id> *)defaultSettingsForIdentifier:(OCClassSettingsIdentifier)identifier
{
	return (@{
		OCHTTPPipelineSettingUserAgent : @"OpenCloudApp/{{app.version}} ({{app.part}}/{{app.build}}; {{os.name}}/{{os.version}}; {{device.model}})",
		OCHTTPPipelineSettingTrafficLogFormat : OCHTTPPipelineLogFormatJSON
	});
}

+ (OCClassSettingsMetadataCollection)classSettingsMetadata
{
	return (@{
		// Connection
		OCHTTPPipelineSettingUserAgent : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeString,
			OCClassSettingsMetadataKeyDescription 	: @"A custom `User-Agent` to send with every HTTP request.",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusSupported,
			OCClassSettingsMetadataKeyCategory	: @"Connection",
		},

		OCHTTPPipelineSettingTrafficLogFormat : @{
			OCClassSettingsMetadataKeyType 		 : OCClassSettingsMetadataTypeString,
			OCClassSettingsMetadataKeyDescription 	 : @"If request and response logging is enabled, the format to use.",
			OCClassSettingsMetadataKeyStatus	 : OCClassSettingsKeyStatusSupported,
			OCClassSettingsMetadataKeyCategory	 : @"Connection",
			OCClassSettingsMetadataKeyPossibleValues : @{
				OCHTTPPipelineLogFormatPlainText : @"Plain text",
				OCHTTPPipelineLogFormatJSON	 : @"JSON"
			}
		}
	});
}

#pragma mark - Log tags
+ (nonnull NSArray<OCLogTagName> *)logTags
{
	return (@[@"HTTP"]);
}

- (nonnull NSArray<OCLogTagName> *)logTags
{
	NSArray<OCLogTagName> *logTags = nil;

	if (_cachedLogTags == nil)
	{
		@synchronized(self)
		{
			if (_cachedLogTags == nil)
			{
				_cachedLogTags = [NSArray arrayWithObjects:@"HTTP", (self.backgroundSessionBacked ? @"Background" : @"Local"), OCLogTagTypedID(@"PipelineID", _identifier), OCLogTagInstance(self), OCLogTagTypedID(@"URLSessionID", _urlSessionIdentifier), nil];
			}
		}
	}

	logTags = _cachedLogTags;

	return (logTags);
}

#pragma mark - Queue
- (void)queueInline:(dispatch_block_t)block
{
	if (_backend.isOnQueueThread)
	{
		block();
	}
	else
	{
		[self queueBlock:block];
	}
}

- (void)queueBlock:(dispatch_block_t)block
{
	[self queueBlock:block withBusy:YES];
}

- (void)queueBlock:(dispatch_block_t)block withBusy:(BOOL)withBusy
{
	if (withBusy)
	{
		dispatch_group_enter(_busyGroup);

		[_backend queueBlock:^{
			@autoreleasepool {
				block();
			}
			dispatch_group_leave(self->_busyGroup);
		}];
	}
	else
	{
		[_backend queueBlock:^{
			@autoreleasepool {
				block();
			}
		}];
	}
}

@end

OCClassSettingsIdentifier OCClassSettingsIdentifierHTTP = @"http";
OCClassSettingsKey OCHTTPPipelineSettingUserAgent = @"user-agent";
OCClassSettingsKey OCHTTPPipelineSettingTrafficLogFormat = @"traffic-log-format";

OCHTTPPipelineLogFormat OCHTTPPipelineLogFormatPlainText = @"plain";
OCHTTPPipelineLogFormat OCHTTPPipelineLogFormatJSON = @"json";
