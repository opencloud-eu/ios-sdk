//
//  OCCoreManager.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 08.06.18.
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

#import "OCCoreManager.h"
#import "NSError+OCError.h"
#import "OCBookmarkManager.h"
#import "OCHTTPPipelineManager.h"
#import "OCLogger.h"
#import "OCCore+FileProvider.h"
#import "OCCore+Internal.h"
#import "OCMacros.h"
#import "OCCoreProxy.h"

@interface OCCoreManager ()
{
	BOOL _useCoreProxies;
	NSMapTable <OCCore *, OCCoreProxy *> *_coreProxiesByCore;
}
@end


@implementation OCCoreManager

@synthesize postFileProviderNotifications = _postFileProviderNotifications;

#pragma mark - Shared instance
+ (instancetype)sharedCoreManager
{
	static dispatch_once_t onceToken;
	static OCCoreManager *sharedManager = nil;

	dispatch_once(&onceToken, ^{
		sharedManager = [OCCoreManager new];
		sharedManager.postFileProviderNotifications = OCVault.hostHasFileProvider;
	});

	return (sharedManager);
}

- (instancetype)init
{
	if ((self = [super init]) != nil)
	{
		_coresByUUID = [NSMutableDictionary new];
		_requestCountByUUID = [NSMutableDictionary new];

		_queuedOfflineOperationsByUUID = [NSMutableDictionary new];

		_adminQueueByUUID = [NSMutableDictionary new];

		_activeCoresRunIdentifiers = [NSMutableArray new];

		// _useCoreProxies = YES; // Uncomment to use core proxies and enable zombie core detection 
		_coreProxiesByCore = [NSMapTable weakToStrongObjectsMapTable];
	}

	return(self);
}

#pragma mark - Admin queues
- (dispatch_queue_t)_adminQueueForBookmark:(OCBookmark *)bookmark
{
	dispatch_queue_t adminQueue = nil;

	if (bookmark.uuid != nil)
	{
		@synchronized (_adminQueueByUUID)
		{
			if ((adminQueue = _adminQueueByUUID[bookmark.uuid]) == nil)
			{
				if ((adminQueue = dispatch_queue_create("OCCoreManager admin queue", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL)) != nil)
				{
					_adminQueueByUUID[bookmark.uuid] = adminQueue;
				}
			}
		}
	}

	return (adminQueue);
}

#pragma mark - Requesting and returning cores
- (void)requestCoreForBookmark:(OCBookmark *)bookmark setup:(nullable void(^)(OCCore *core, NSError *))setupHandler completionHandler:(void (^)(OCCore *core, NSError *error))completionHandler
{
	OCLogDebug(@"queuing core request for bookmark %@", bookmark);

	dispatch_async([self _adminQueueForBookmark:bookmark], ^{
		[self _requestCoreForBookmark:bookmark setup:setupHandler completionHandler:completionHandler];
	});
}

- (OCCore *)protectedCoreForCore:(OCCore *)core
{
	if (_useCoreProxies)
	{
		@synchronized(self)
		{
			OCCoreProxy *coreProxy;

			if ((coreProxy = [_coreProxiesByCore objectForKey:core]) == nil)
			{
				coreProxy = [[OCCoreProxy alloc] initWithCore:core];
				[_coreProxiesByCore setObject:coreProxy forKey:core];
			}

			return ((OCCore *)coreProxy);
		}
	}

	return (core);
}

- (void)_requestCoreForBookmark:(OCBookmark *)bookmark setup:(nullable void(^)(OCCore *core, NSError *))setupHandler completionHandler:(void (^)(OCCore *core, NSError *error))completionHandler
{
	OCLogDebug(@"core requested for bookmark %@", bookmark);

	NSNumber *requestCount = _requestCountByUUID[bookmark.uuid];

	requestCount = @(requestCount.integerValue + 1);
	_requestCountByUUID[bookmark.uuid] = requestCount;

	if (requestCount.integerValue == 1)
	{
		OCCore *core;

		OCLog(@"creating core for bookmark %@", bookmark);

		// Create and start core
		if ((core = [[OCCore alloc] initWithBookmark:bookmark]) != nil)
		{
			core.isManaged = YES;

			core.postFileProviderNotifications = self.postFileProviderNotifications;

			[self willChangeValueForKey:@"activeCoresRunIdentifiers"];
			@synchronized(self)
			{
				_coresByUUID[bookmark.uuid] = core;

				[_activeCoresRunIdentifiers addObject:core.runIdentifier];
				_activeCoresRunIdentifiersReadOnly = nil;
			}
			[self didChangeValueForKey:@"activeCoresRunIdentifiers"];

			if (setupHandler != nil)
			{
				setupHandler([self protectedCoreForCore:core], nil);
			}

			OCLog(@"starting core for bookmark %@", bookmark);

			OCSyncExec(waitForCoreStart, {
				[core startWithCompletionHandler:^(OCCore *sender, NSError *error) {
					OCLog(@"core=%@ started for bookmark=%@ with error=%@", sender, bookmark, error);

					if (completionHandler != nil)
					{
						if (error != nil)
						{
							[self willChangeValueForKey:@"activeCoresRunIdentifiers"];
							@synchronized(self)
							{
								self->_requestCountByUUID[bookmark.uuid] = @(self->_requestCountByUUID[bookmark.uuid].integerValue - 1);
								self->_coresByUUID[bookmark.uuid] = nil;

								[self->_activeCoresRunIdentifiers removeObject:core.runIdentifier];
								self->_activeCoresRunIdentifiersReadOnly = nil;

								[core unregisterEventHandler];

								if (self->_useCoreProxies)
								{
									[self->_coreProxiesByCore objectForKey:core].core = nil;
								}
							}
							[self didChangeValueForKey:@"activeCoresRunIdentifiers"];

							completionHandler(nil, error);
						}
						else
						{
							completionHandler([self protectedCoreForCore:sender], error);
						}
					}

					OCSyncExecDone(waitForCoreStart);
				}];
			});
		}
		else
		{
			if (completionHandler != nil)
			{
				completionHandler(nil, OCError(OCErrorInternal));
			}
		}
	}
	else
	{
		OCCore *core;

		OCLog(@"re-using core for bookmark %@", bookmark);

		@synchronized(self)
		{
			core = _coresByUUID[bookmark.uuid];
		}

		if (core != nil)
		{
			if (setupHandler != nil)
			{
				setupHandler([self protectedCoreForCore:core], nil);
			}

			if (completionHandler != nil)
			{
				completionHandler([self protectedCoreForCore:core], nil);
			}
		}
		else
		{
			OCLogError(@"no core found for bookmark %@, although one should exist", bookmark);
		}
	}
}

- (void)returnCoreForBookmark:(OCBookmark *)bookmark completionHandler:(dispatch_block_t)completionHandler
{
	OCLogDebug(@"queuing core return for bookmark %@", bookmark);

	dispatch_async([self _adminQueueForBookmark:bookmark], ^{
		[self _returnCoreForBookmark:bookmark completionHandler:completionHandler];
	});
}

- (void)_returnCoreForBookmark:(OCBookmark *)bookmark completionHandler:(dispatch_block_t)completionHandler
{
	NSNumber *requestCount = _requestCountByUUID[bookmark.uuid];

	OCLogDebug(@"core returned for bookmark %@ (%@)", bookmark.uuid.UUIDString, bookmark.name);

	if (requestCount.integerValue > 0)
	{
		requestCount = @(requestCount.integerValue - 1);
		_requestCountByUUID[bookmark.uuid] = requestCount;
	}

	if (requestCount.integerValue == 0)
	{
		// Stop and release core
		OCCore *core;

		OCLog(@"shutting down core for bookmark %@", bookmark);

		@synchronized(self)
		{
			core = _coresByUUID[bookmark.uuid];
		}

		if (core != nil)
		{
			OCLog(@"stopping core for bookmark %@", bookmark);

			// Remove core from LUT
			@synchronized(self)
			{
				[_coresByUUID removeObjectForKey:bookmark.uuid];
				[_activeCoresRunIdentifiers removeObject:core.runIdentifier];
				_activeCoresRunIdentifiersReadOnly = nil;
			}

			// Stop core
			OCSyncExec(waitForCoreStop, {
				[core stopWithCompletionHandler:^(id sender, NSError *error) {
					[core unregisterEventHandler];

					if (self->_useCoreProxies)
					{
						[self->_coreProxiesByCore objectForKey:core].core = nil;
					}

					OCLog(@"core stopped for bookmark %@", bookmark);

					if (completionHandler != nil)
					{
						completionHandler();
					}

					OCSyncExecDone(waitForCoreStop);
				}];
			});

			// Run offline operation
			[self _runNextOfflineOperationForBookmark:bookmark];
		}
		else
		{
			OCLogError(@"no core found for bookmark %@, although one should exist", bookmark);
		}
	}
	else
	{
		OCLog(@"core still in use for bookmark %@", bookmark);

		if (completionHandler != nil)
		{
			completionHandler();
		}
	}
}

#pragma mark - Background session recovery
- (void)handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(dispatch_block_t)completionHandler
{
	OCLogDebug(@"Handle events for background URL session: %@", identifier);

	[OCHTTPPipelineManager.sharedPipelineManager handleEventsForBackgroundURLSession:identifier completionHandler:completionHandler];
}

#pragma mark - Scheduling offline operations on cores
- (void)scheduleOfflineOperation:(OCCoreManagerOfflineOperation)offlineOperation forBookmark:(OCBookmark *)bookmark
{
	OCLogDebug(@"scheduling offline operation for bookmark %@", bookmark);

	@synchronized(self)
	{
		NSMutableArray<OCCoreManagerOfflineOperation> *queuedOfflineOperations;

		if ((queuedOfflineOperations = _queuedOfflineOperationsByUUID[bookmark.uuid]) == nil)
		{
			queuedOfflineOperations = [NSMutableArray new];
			_queuedOfflineOperationsByUUID[bookmark.uuid] = queuedOfflineOperations;
		}

		[queuedOfflineOperations addObject:offlineOperation];
	}

	dispatch_async([self _adminQueueForBookmark:bookmark], ^{
		[self _runNextOfflineOperationForBookmark:bookmark];
	});
}

- (void)_runNextOfflineOperationForBookmark:(OCBookmark *)bookmark
{
	OCCoreManagerOfflineOperation offlineOperation = nil;

	OCLogDebug(@"trying to run next offline operation for bookmark %@", bookmark);

	if (_requestCountByUUID[bookmark.uuid].integerValue == 0)
	{
		@synchronized(self)
		{
			if ((offlineOperation = _queuedOfflineOperationsByUUID[bookmark.uuid].firstObject) != nil)
			{
				OCLogDebug(@"running offline operation for bookmark %@: %@", bookmark, offlineOperation);

				[_queuedOfflineOperationsByUUID[bookmark.uuid] removeObjectAtIndex:0];
			}
			else
			{
				OCLogDebug(@"no queued offline operation for bookmark %@", bookmark);
			}
		}
	}
	else
	{
		OCLogDebug(@"won't run offline operation for bookmark %@ at this time (requestCount=%lu)", bookmark, _requestCountByUUID[bookmark.uuid].integerValue);
	}

	if (offlineOperation != nil)
	{
		OCSyncExec(waitForOfflineOperationToFinish, {
			offlineOperation(bookmark, ^{
				OCSyncExecDone(waitForOfflineOperationToFinish);
			});
		});

		[self _runNextOfflineOperationForBookmark:bookmark];
	}
}

#pragma mark - Progress resolution
- (id<OCProgressResolver>)resolverForPathElement:(OCProgressPathElementIdentifier)pathElementIdentifier withContext:(OCProgressResolutionContext)context
{
	NSUUID *pathUUID;

	if ((pathUUID = [[NSUUID alloc] initWithUUIDString:pathElementIdentifier]) != nil)
	{
		@synchronized(self)
		{
			return ([_coresByUUID objectForKey:pathUUID]);
		}
	}

	return (nil);
}

#pragma mark - Active run identifiers
- (NSArray<OCCoreRunIdentifier> *)activeRunIdentifiers
{
	@synchronized(self)
	{
		if (_activeCoresRunIdentifiersReadOnly == nil)
		{
			_activeCoresRunIdentifiersReadOnly = [_activeCoresRunIdentifiers copy];
		}
	}

	return (_activeCoresRunIdentifiersReadOnly);
}

#pragma mark - Log tagging
+ (NSArray<OCLogTagName> *)logTags
{
	return (@[@"CORE", @"Manager"]);
}

- (NSArray<OCLogTagName> *)logTags
{
	return (@[@"CORE", @"Manager"]);
}

@end
