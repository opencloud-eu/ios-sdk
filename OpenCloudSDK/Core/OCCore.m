//
//  OCCore.m
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

#import <pthread/pthread.h>

#import "OCCore.h"
#import "OCQuery+Internal.h"
#import "OCShareQuery.h"
#import "OCLogger.h"
#import "NSProgress+OCExtensions.h"
#import "OCMacros.h"
#import "NSError+OCError.h"
#import "OCDatabase.h"
#import "OCDatabaseConsistentOperation.h"
#import "OCCore+Internal.h"
#import "OCCore+SyncEngine.h"
#import "OCSyncRecord.h"
#import "NSString+OCPath.h"
#import "OCCore+FileProvider.h"
#import "OCCore+ItemList.h"
#import "OCCoreManager.h"
#import "OCChecksumAlgorithmSHA1.h"
#import "OCIPNotificationCenter.h"
#import "OCCoreNetworkMonitorSignalProvider.h"
#import "OCCoreServerStatusSignalProvider.h"
#import "OCCore+ConnectionStatus.h"
#import "OCCore+Thumbnails.h"
#import "OCCore+ItemUpdates.h"
#import "OCHTTPPipelineManager.h"
#import "OCProgressManager.h"
#import "OCProxyProgress.h"
#import "OCRateLimiter.h"
#import "OCSyncActionDownload.h"
#import "OCSyncActionUpload.h"
#import "OCBookmark+IPNotificationNames.h"
#import "OCDeallocAction.h"
#import "OCCore+ItemPolicies.h"
#import "OCCore+MessageResponseHandler.h"
#import "OCCore+MessageAutoresolver.h"
#import "OCHostSimulatorManager.h"
#import "OCProcessManager.h"
#import "OCBookmark+DBMigration.h"
#import "OCMeasurement.h"
#import "OCResourceManager.h"
#import "OCResourceSourceAvatars.h"
#import "OCResourceSourceAvatarPlaceholders.h"
#import "OCResourceSourceItemThumbnails.h"
#import "OCResourceSourceItemLocalThumbnails.h"
#import "OCResourceSourceDriveItems.h"
#import "OCResourceSourceURLItems.h"
#import "OCConnection+GraphAPI.h"
#import "NSArray+OCFiltering.h"
#import "OCCore+DataSources.h"
#import "OCDataSourceKVO.h"
#import "OCVault+Internal.h"
#import "OCLocale+SystemLanguage.h"
#import "OCCore+DataSources.h"
#import "OCSignalManager.h"

@interface OCCore ()
{
	NSInteger _runningActivities;
	NSMutableArray <NSString *> *_runningActivitiesStrings;
	dispatch_block_t _runningActivitiesCompleteBlock;

	NSUInteger _pendingIPCChangeNotifications;
	OCRateLimiter *_ipChangeNotificationRateLimiter;

	OCIPCNotificationName _ipNotificationName;
	OCIPNotificationCenter *_ipNotificationCenter;
}

@end

@implementation OCCore

@synthesize bookmark = _bookmark;

@synthesize vault = _vault;
@synthesize connection = _connection;

@synthesize memoryConfiguration = _memoryConfiguration;

@synthesize state = _state;
@synthesize stateChangedHandler = _stateChangedHandler;

@synthesize connectionStatus = _connectionStatus;
@synthesize connectionStatusSignals = _connectionStatusSignals;
@synthesize connectionStatusShortDescription = _connectionStatusShortDescription;

@synthesize signalManager = _signalManager;

@synthesize activityManager = _activityManager;

@synthesize eventHandlerIdentifier = _eventHandlerIdentifier;

@synthesize latestSyncAnchor = _latestSyncAnchor;

@synthesize postFileProviderNotifications = _postFileProviderNotifications;

@synthesize delegate = _delegate;

@synthesize preferredChecksumAlgorithm = _preferredChecksumAlgorithm;

@synthesize automaticItemListUpdatesEnabled = _automaticItemListUpdatesEnabled;

@synthesize maximumSyncLanes = _maximumSyncLanes;

@synthesize rootQuotaBytesRemaining = _rootQuotaBytesRemaining;
@synthesize rootQuotaBytesUsed = _rootQuotaBytesUsed;
@synthesize rootQuotaBytesTotal = _rootQuotaBytesTotal;

@dynamic busyStatusHandler;

#pragma mark - Class settings
INCLUDE_IN_CLASS_SETTINGS_SNAPSHOTS(OCCore)

+ (OCClassSettingsIdentifier)classSettingsIdentifier
{
	return (@"core");
}

+ (NSArray<OCClassSettingsKey> *)publicClassSettingsIdentifiers
{
	return (@[
		OCCoreThumbnailAvailableForMIMETypePrefixes,
		OCCoreCookieSupportEnabled
	]);
}

+ (NSDictionary<NSString *,id> *)defaultSettingsForIdentifier:(OCClassSettingsIdentifier)identifier
{
	return (@{
		OCCoreThumbnailAvailableForMIMETypePrefixes : @[
			@"*"
		],
		OCCoreAddAcceptLanguageHeader : @(YES),
		OCCoreActionConcurrencyBudgets : @{
			// Concurrency "budgets" available for sync actions by action category
			OCSyncActionCategoryAll	: @(0), // No limit on the total number of concurrent sync actions

				OCSyncActionCategoryActions  : @(10),	// Limit concurrent execution of actions to 10

				OCSyncActionCategoryTransfer : @(6),	// Limit total number of concurrent transfers to 6

					OCSyncActionCategoryUpload   : @(3),	// Limit number of concurrent upload transfers to 3
						OCSyncActionCategoryUploadWifiOnly   	  : @(2), // Limit number of concurrent uploads by WiFi-only transfers to 2 (leaving at least one spot empty for cellular)
						OCSyncActionCategoryUploadWifiAndCellular : @(3), // Limit number of concurrent uploads by WiFi and Cellular transfers to 3

					OCSyncActionCategoryDownload : @(3),	// Limit number of concurrent download transfers to 3
						OCSyncActionCategoryDownloadWifiOnly   	    : @(2), // Limit number of concurrent downloads by WiFi-only transfers to 2 (leaving at least one spot empty for cellular)
						OCSyncActionCategoryDownloadWifiAndCellular : @(3) // Limit number of concurrent downloads by WiFi and Cellular transfers to 3
		},
		OCCoreCookieSupportEnabled : @(YES)
	});
}

+ (OCClassSettingsMetadataCollection)classSettingsMetadata
{
	return (@{
		// Connection
		OCCoreThumbnailAvailableForMIMETypePrefixes : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeStringArray,
			OCClassSettingsMetadataKeyDescription 	: @"Provide hints that thumbnails are available for items whose MIME-Type starts with any of the strings provided in this array. Providing an empty array turns off thumbnail loading. Providing `[\"*\"]` turns on thumbnail loading for all items.",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusDebugOnly,
			OCClassSettingsMetadataKeyCategory	: @"Connection",
		},

		OCCoreOverrideReachabilitySignal : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeBoolean,
			OCClassSettingsMetadataKeyDescription 	: @"Override the reachability signal, so the host is always considered reachable (`true`) or unreachable (`false`).",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusDebugOnly,
			OCClassSettingsMetadataKeyCategory	: @"Connection",
		},

		OCCoreOverrideAvailabilitySignal : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeBoolean,
			OCClassSettingsMetadataKeyDescription 	: @"Override the availability signal, so the host is considered to always be in maintenance mode (`true`) or never in maintenance mode (`false`).",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusDebugOnly,
			OCClassSettingsMetadataKeyCategory	: @"Connection",
		},

		OCCoreCookieSupportEnabled : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeBoolean,
			OCClassSettingsMetadataKeyDescription 	: @"Enable or disable per-process, in-memory cookie storage.",
			OCClassSettingsMetadataKeyCategory	: @"Connection",
		},

		OCCoreActionConcurrencyBudgets : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeDictionary,
			OCClassSettingsMetadataKeyDescription 	: @"Concurrency budgets available for sync actions by action category.",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusAdvanced,
			OCClassSettingsMetadataKeyCategory	: @"Connection"
		},

		OCCoreScanForChangesInterval : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeInteger,
			OCClassSettingsMetadataKeyDescription 	: @"Minimum number of milliseconds until the next scan for changes, measured from the completion of the previous scan. If no value is provided, uses the poll interval provided in the server's capabilities (in milliseconds) if it is greater or equal 5 seconds. Defaults to 10 seconds otherwise.",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusAdvanced,
			OCClassSettingsMetadataKeyCategory	: @"Connection",
		},

		OCCoreAddAcceptLanguageHeader : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeBoolean,
			OCClassSettingsMetadataKeyDescription 	: @"Add an `Accept-Language` HTTP header using the preferred languages set on the device.",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusAdvanced,
			OCClassSettingsMetadataKeyCategory	: @"Connection"
		},
	});
}

#pragma mark - Init
- (instancetype)init
{
	// Enforce use of designated initializer
	return (nil);
}

- (instancetype)initWithBookmark:(OCBookmark *)bookmark
{
	if ((self = [super init]) != nil)
	{
		__weak OCCore *weakSelf = self;

		int pthreadKeyError;

		if ((pthreadKeyError = pthread_key_create(&_queueKey, NULL)) != 0)
		{
			OCLogError(@"Error creating pthread key: %d", pthreadKeyError);
		}

		OCLog(@"Priorities: default %f low %f high %f", NSURLSessionTaskPriorityDefault, NSURLSessionTaskPriorityLow, NSURLSessionTaskPriorityHigh);

		_runIdentifier = [NSUUID new];

		_bookmark = bookmark;

		_automaticItemListUpdatesEnabled = YES;

		_maximumSyncLanes = 0;

		_preferredChecksumAlgorithm = OCChecksumAlgorithmIdentifierSHA1;

		_eventHandlerIdentifier = [@"OCCore-" stringByAppendingString:_bookmark.uuid.UUIDString];
		_pendingThumbnailRequests = [NSMutableDictionary new];

		_ipNotificationCenter = OCIPNotificationCenter.sharedNotificationCenter;
		_ipChangeNotificationRateLimiter = [[OCRateLimiter alloc] initWithMinimumTime:0.1];

		_unsolvedIssueSignatures = [NSMutableSet new];
		_rejectedIssueSignatures = [NSMutableSet new];

		_shareRoles = [NSMutableArray new];

		_vault = [[OCVault alloc] initWithBookmark:bookmark];

		_queries = [NSMutableArray new];
		_shareQueries = [NSMutableArray new];

		_itemListTasksByLocationString = [NSMutableDictionary new];
		_queuedItemListTaskUpdateJobs = [NSMutableArray new];
		_scheduledItemListTasks = [NSMutableArray new];
		_scheduledDirectoryUpdateJobIDs = [NSMutableSet new];
		_itemListTasksRequestQueue = [OCAsyncSequentialQueue new];
		_itemListTasksRequestQueue.executor = ^(OCAsyncSequentialQueueJob  _Nonnull job, dispatch_block_t  _Nonnull completionHandler) {
			OCCore *strongSelf;

			if ((strongSelf = weakSelf) != nil)
			{
				[strongSelf queueBlock:^{
					job(completionHandler);
				}];
			}
		};

		_fetchUpdatesCompletionHandlers = [NSMutableArray new];

		_syncReasonCountChangeObservers = [NSMutableArray new];

		_progressByLocalID = [NSMutableDictionary new];

		_drives = [NSMutableArray new];
		_lastRootETagsByDriveID = [NSMutableDictionary new];

		_drivesDataSource = [[OCDataSourceKVO alloc] initWithObject:_vault keyPath:@"activeDrives" versionedItemUpdateHandler:nil];
		_subscribedDrivesDataSource = [[OCDataSourceKVO alloc] initWithObject:_vault keyPath:@"subscribedDrives" versionedItemUpdateHandler:nil];

		_projectDrivesDataSource = [[OCDataSourceKVO alloc] initWithObject:_vault keyPath:@"subscribedDrives" versionedItemUpdateHandler:^NSArray<id<OCDataItem,OCDataItemVersioning>> * _Nullable(NSObject * _Nonnull object, NSString * _Nonnull keyPath, NSArray<OCDrive *> *  _Nullable activeDrives) {
			return ([activeDrives filteredArrayUsingBlock:^BOOL(OCDrive * _Nonnull drive, BOOL * _Nonnull stop) {
				return ([drive.type isEqual:OCDriveTypeProject]);
			}]);
		}];
		_personalDriveDataSource = [[OCDataSourceKVO alloc] initWithObject:_vault keyPath:@"activeDrives" versionedItemUpdateHandler:^NSArray<id<OCDataItem,OCDataItemVersioning>> * _Nullable(NSObject * _Nonnull object, NSString * _Nonnull keyPath, NSArray<OCDrive *> *  _Nullable activeDrives) {
			return ([activeDrives filteredArrayUsingBlock:^BOOL(OCDrive * _Nonnull drive, BOOL * _Nonnull stop) {
				return ([drive.type isEqual:OCDriveTypePersonal]);
			}]);
		}];
		_shareJailDriveDataSource = [[OCDataSourceKVO alloc] initWithObject:_vault keyPath:@"activeDrives" versionedItemUpdateHandler:^NSArray<id<OCDataItem,OCDataItemVersioning>> * _Nullable(NSObject * _Nonnull object, NSString * _Nonnull keyPath, NSArray<OCDrive *> *  _Nullable activeDrives) {
			return ([activeDrives filteredArrayUsingBlock:^BOOL(OCDrive * _Nonnull drive, BOOL * _Nonnull stop) {
				return ([drive.type isEqual:OCDriveTypeVirtual] && [drive.identifier isEqual:OCDriveIDSharesJail]);
			}]);
		}];

		_activityManager = [[OCActivityManager alloc] initWithUpdateNotificationName:[@"OCCore.ActivityUpdate." stringByAppendingString:_bookmark.uuid.UUIDString]];
		_publishedActivitySyncRecordIDs = [NSMutableSet new];

		_itemPolicies = [NSMutableArray new];
		_itemPolicyProcessors = [NSMutableArray new];

		_availableOfflineFolderLocations = [NSMutableSet new];
		_availableOfflineIDs = [NSMutableSet new];

		_claimTokensByClaimIdentifier = [NSMapTable strongToWeakObjectsMapTable];

		_queue = dispatch_queue_create("OCCore work queue", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
		_connectivityQueue = dispatch_queue_create("OCCore connectivity queue", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);

		_signalManager = [[OCSignalManager alloc] initWithKeyValueStore:_vault.keyValueStore deliveryQueue:_queue];
		
		[OCEvent registerEventHandler:self forIdentifier:_eventHandlerIdentifier];

		_warnedCertificates = [NSMutableArray new];

		_connection = [[OCConnection alloc] initWithBookmark:bookmark];
		if (OCTypedCast([self classSettingForOCClassSettingsKey:OCCoreCookieSupportEnabled], NSNumber).boolValue == YES)
		{
			// Adding cookie storage enabled cookie support
			_connection.cookieStorage = [OCHTTPCookieStorage new];
			/*_connection.cookieStorage.cookieFilter = ^BOOL(NSHTTPCookie * _Nonnull cookie) {
				if ((cookie.expiresDate == nil) && (![cookie.name isEqual:@"oc_sessionPassphrase"]))
				{
					return (NO);
				}

				return (YES);
			};*/

			OCTLogDebug(@[@"Cookies"], @"Cookie support enabled with storage %@", _connection.cookieStorage);
		}
		_connection.hostSimulator = [OCHostSimulatorManager.sharedManager hostSimulatorForLocation:OCExtensionLocationIdentifierAllCores for:self];
		_connection.preferredChecksumAlgorithm = _preferredChecksumAlgorithm;
		_connection.actionSignals = [NSSet setWithObjects: OCConnectionSignalIDCoreOnline, OCConnectionSignalIDAuthenticationAvailable, nil];
		// _connection.propFindSignals = [NSSet setWithObjects: OCConnectionSignalIDCoreOnline, OCConnectionSignalIDAuthenticationAvailable, nil]; // not ready for this, yet ("update retrieved set" can never finish when offline)
		// _connection.propFindSignals = [NSSet setWithObjects: OCConnectionSignalIDNetworkAvailable, OCConnectionSignalIDAuthenticationAvailable, nil]; // will make sharing queries "hang", resulting in core not being able to stop
		_connection.authSignals = [NSSet setWithObjects: OCConnectionSignalIDNetworkAvailable, nil]; // avoid an endless loop where requests are rescheduled due to an expired token, the auth method can't fetch a new token due to an unreachable network, and then the original request is rescheduled, resulting in an endless loop of reschedules and failures due to an unreachable network
		_connection.delegate = self;

		if ([((NSNumber *)[self classSettingForOCClassSettingsKey:OCCoreAddAcceptLanguageHeader]) boolValue])
		{
			NSString *acceptLanguage;

			if ((acceptLanguage = OCLocale.sharedLocale.acceptLanguageString) != nil)
			{
				_connection.staticHeaderFields = @{ @"Accept-Language" : acceptLanguage };
			}
		}

		_connectionStatusSignalProviders = [NSMutableArray new];

		NSNumber *override = nil;
		if ((override = [self classSettingForOCClassSettingsKey:OCCoreOverrideAvailabilitySignal]) != nil)
		{
			// OCCore depends on OCCoreServerStatusSignalProvider interfaces, so we force-override this signal if told to
			OCCoreConnectionStatusSignalState signalState = (override.boolValue ? OCCoreConnectionStatusSignalStateForceTrue : OCCoreConnectionStatusSignalStateForceFalse);

			[self addSignalProvider:[[OCCoreConnectionStatusSignalProvider alloc] initWithSignal:OCCoreConnectionStatusSignalAvailable initialState:signalState stateProvider:nil]];
		}
		if ((override = [self classSettingForOCClassSettingsKey:OCCoreOverrideReachabilitySignal]) != nil)
		{
			OCCoreConnectionStatusSignalState signalState = (override.boolValue ? OCCoreConnectionStatusSignalStateTrue : OCCoreConnectionStatusSignalStateFalse);

			_reachabilityStatusSignalProvider = [[OCCoreConnectionStatusSignalProvider alloc] initWithSignal:OCCoreConnectionStatusSignalReachable initialState:signalState stateProvider:nil];
		}

		if (_reachabilityStatusSignalProvider == nil)
		{
			_reachabilityStatusSignalProvider = [OCCoreNetworkMonitorSignalProvider new];
		}

		_rejectedIssueSignalProvider = [[OCCoreConnectionStatusSignalProvider alloc] initWithSignal:OCCoreConnectionStatusSignalReachable initialState:OCCoreConnectionStatusSignalStateTrue stateProvider:nil];

		_pauseConnectionSignalProvider = [[OCCoreConnectionStatusSignalProvider alloc] initWithSignal:OCCoreConnectionStatusSignalReachable initialState:OCCoreConnectionStatusSignalStateTrue stateProvider:nil];

		_serverStatusSignalProvider = [OCCoreServerStatusSignalProvider new];
		_connectingStatusSignalProvider = [[OCCoreConnectionStatusSignalProvider alloc] initWithSignal:OCCoreConnectionStatusSignalConnecting initialState:OCCoreConnectionStatusSignalStateFalse stateProvider:nil];
		_connectionStatusSignalProvider = [[OCCoreConnectionStatusSignalProvider alloc] initWithSignal:OCCoreConnectionStatusSignalConnected  initialState:OCCoreConnectionStatusSignalStateFalse stateProvider:nil];

		[self addSignalProvider:_reachabilityStatusSignalProvider];
		[self addSignalProvider:_rejectedIssueSignalProvider];
		[self addSignalProvider:_pauseConnectionSignalProvider];

		[self addSignalProvider:_serverStatusSignalProvider];
		[self addSignalProvider:_connectingStatusSignalProvider];
		[self addSignalProvider:_connectionStatusSignalProvider];

		self.memoryConfiguration = OCPlatform.current.memoryConfiguration;

		[self startIPCObservation];
	}

	return(self);
}

- (void)dealloc
{
	OCLogTagName runIDTag = OCLogTagTypedID(@"RunID", _runIdentifier);
	NSArray<OCLogTagName> *deallocTags = (runIDTag != nil) ? @[@"DEALLOC", runIDTag] : @[@"DEALLOC"];

	[self unsubscribeFromPollingDatasourcesTimer:OCCoreDataSourcePollTypeAll withForcedStop:YES];
	[self _updateSharedWithMeQueryForceStop:YES];
	[self _updateAllSharedByMeQueryForceStop:YES];

	[self stopIPCObserveration];

	[self removeSignalProviders];

	OCTLogDebug(deallocTags, @"core deallocated");
}

- (void)unregisterEventHandler
{
	[OCEvent unregisterEventHandlerForIdentifier:_eventHandlerIdentifier];
}

- (void)_updateState:(OCCoreState)newState
{
	[self willChangeValueForKey:@"state"];
	_state = newState;
	[self didChangeValueForKey:@"state"];

	if (_stateChangedHandler)
	{
		_stateChangedHandler(self);
	}
}

#pragma mark - Managed
- (void)setIsManaged:(BOOL)isManaged
{
	_isManaged = isManaged;
}

#pragma mark - Start / Stop
- (void)startWithCompletionHandler:(nullable OCCompletionHandler)completionHandler
{
	OCLogTagName runIDTag = OCLogTagTypedID(@"RunID", _runIdentifier);
	NSArray<OCLogTagName> *startTags = (runIDTag != nil) ? @[@"START", runIDTag] : @[@"START"];

	OCTLogDebug(startTags, @"queuing start request in work queue");

	[self queueBlock:^{
		OCTLogDebug(startTags, @"performing start request");

		if (self->_state == OCCoreStateStopped)
		{
			__block NSError *startError = nil;

			[self recomputeConnectionStatus];

			[self _updateState:OCCoreStateStarting];

			if (self.bookmark.needsHostUpdate)
			{
				// Do not start for bookmarks that are using a newer database version
				startError = OCError(OCErrorHostUpdateRequired);
			}

			// Open vault (incl. database)
			if (startError == nil)
			{
				// Configure vault / database
				self.vault.database.sqlDB.allowMigrations = !OCProcessManager.isProcessExtension;

				OCSyncExec(openVault, {
					[self.vault openWithCompletionHandler:^(id sender, NSError *error) {
						startError = error;

						if ([startError.domain isEqual:OCSQLiteDBErrorDomain] && (startError.code == OCSQLiteDBErrorMigrationsNotAllowed))
						{
							startError = OCError(OCErrorDatabaseMigrationRequired);
						}

						OCSyncExecDone(openVault);
					}];
				});
			}

			// Find and restart stuck sync records
			[self restartStuckSyncRecordsWithFilter:nil];

			// Get latest sync anchor
			if (startError == nil)
			{
				OCSyncExec(retrieveSyncAnchor, {
					[self retrieveLatestSyncAnchorWithCompletionHandler:^(NSError *error, OCSyncAnchor latestSyncAnchor) {
						OCSyncExecDone(retrieveSyncAnchor);
					}];
				});
			}

			// Get latest drive list
			if (startError == nil)
			{
				[self initializeWithDrives];

				self->_connection.drives = self.vault.activeDrives;
			}

			// Proceed with connecting - or stop
			if (startError == nil)
			{
				// Setup sync engine
				[self setupSyncEngine];

				// Setup item policies
				[self setupItemPolicies];

				// Core is ready
				[self _updateState:OCCoreStateReady];

				// Attempt connecting
				self->_attemptConnect = YES;
				[self _attemptConnect];

				// Register as message autoResolver
				[self.messageQueue addAutoResolver:self];

				// Register as message response handler
				[self.messageQueue addResponseHandler:self];

				// Register resource sources
				[self.vault.resourceManager addSource:[[OCResourceSourceAvatarPlaceholders alloc] initWithCore:self]];
				[self.vault.resourceManager addSource:[[OCResourceSourceAvatars alloc] initWithCore:self]];
				[self.vault.resourceManager addSource:[[OCResourceSourceItemThumbnails alloc] initWithCore:self]];
				[self.vault.resourceManager addSource:[[OCResourceSourceItemLocalThumbnails alloc] initWithCore:self]];
				[self.vault.resourceManager addSource:[[OCResourceSourceDriveItems alloc] initWithCore:self]];
				[self.vault.resourceManager addSource:[[OCResourceSourceURLItems alloc] initWithCore:self]];
			}
			else
			{
				OCLogError(@"STOPPED CORE due to startError=%@", startError);
				self->_attemptConnect = NO;
				[self _updateState:OCCoreStateStopped];
			}

			if (completionHandler != nil)
			{
				completionHandler(self, startError);
			}
		}
		else
		{
			if (completionHandler != nil)
			{
				completionHandler(self, nil);
			}
		}
	}];
}

- (void)stopWithCompletionHandler:(nullable OCCompletionHandler)completionHandler
{
	OCLogTagName runIDTag = OCLogTagTypedID(@"RunID", _runIdentifier);
	NSArray<OCLogTagName> *stopTags = (runIDTag != nil) ? @[@"STOP", runIDTag] : @[@"STOP"];

	OCTLogDebug(stopTags, @"queuing stop request in connectivity queue");

	[self queueConnectivityBlock:^{
		OCTLogDebug(stopTags, @"queuing stop request in work queue");

		[self queueBlock:^{
			__block NSError *stopError = nil;

			OCTLogDebug(stopTags, @"performing stop request");

			if ((self->_state == OCCoreStateRunning) || (self->_state == OCCoreStateReady) || (self->_state == OCCoreStateStarting))
			{
				__weak OCCore *weakSelf = self;

				[self _updateState:OCCoreStateStopping];

				// Cancel non-critical requests
				OCTLogDebug(stopTags, @"cancelling non-critical requests");
				[self.connection cancelNonCriticalRequests];

				// Wait for running operations to finish
				self->_runningActivitiesCompleteBlock = ^{
					// Shut down fetch updates
					{
						OCCore *strongSelf = weakSelf;

						@synchronized(strongSelf->_fetchUpdatesCompletionHandlers)
						{
							NSMutableArray <OCCoreItemListFetchUpdatesCompletionHandler> *fetchUpdatesCompletionHandlers = strongSelf->_fetchUpdatesCompletionHandlers;
							strongSelf->_fetchUpdatesCompletionHandlers = [NSMutableArray new];

							for (OCCoreItemListFetchUpdatesCompletionHandler completionHandler in fetchUpdatesCompletionHandlers)
							{
								completionHandler(OCError(OCErrorCancelled), NO);
							}

							[strongSelf->_fetchUpdatesCompletionHandlers removeAllObjects];
						}
					}

					// Shutdown drives
					[weakSelf shutdownWithDrives];

					// Tear down item policies
					[weakSelf teardownItemPolicies];

					// Release scan for changes lock
					OCWTLogDebug(stopTags, @"shutting down coordinated scan for changes");
					[weakSelf shutdownCoordinatedScanForChanges];

					// Shut down Sync Engine
					OCWTLogDebug(stopTags, @"shutting down sync engine");
					[weakSelf shutdownSyncEngine];

					// Shut down progress
					OCWTLogDebug(stopTags, @"shutting down progress observation");
					[weakSelf _shutdownProgressObservation];

					// Close connection
					OCWTLogDebug(stopTags, @"connection: disconnecting");
					OCCore *strongSelf;
					if ((strongSelf = weakSelf) != nil)
					{
						strongSelf->_attemptConnect = NO;
					}

					[weakSelf.connection disconnectWithCompletionHandler:^{
						OCWTLogDebug(stopTags, @"connection: disconnected");

						[weakSelf queueBlock:^{
							// Close vault (incl. database)
							OCWTLogDebug(stopTags, @"vault: closing");

							OCSyncExec(waitForVaultClosing, {
								[weakSelf.vault closeWithCompletionHandler:^(OCDatabase *db, NSError *error) {
									OCWTLogDebug(stopTags, @"vault: closed");
									stopError = error;

									OCWTLogDebug(stopTags, @"STOPPED");
									[weakSelf _updateState:OCCoreStateStopped];

									OCSyncExecDone(waitForVaultClosing);

									if (completionHandler != nil)
									{
										completionHandler(weakSelf, stopError);
									}
								}];
							});
						}];
					}];
				};

				if (self->_runningActivities <= 0)
				{
					if (self->_runningActivities < 0)
					{
						OCTLogWarning(stopTags, @"BUG: negative runningActivities count (%ld)! Look for endActivity errors in the log! runningActivitiesStrings=%@", (long)self->_runningActivities, self->_runningActivitiesStrings);
					}
					else
					{
						OCTLogDebug(stopTags, @"No running activities left. Proceeding.");
					}
					if (self->_runningActivitiesCompleteBlock != nil)
					{
						dispatch_block_t runningActivitiesCompleteBlock = self->_runningActivitiesCompleteBlock;

						self->_runningActivitiesCompleteBlock = nil;
						runningActivitiesCompleteBlock();
					}
				}
				else
				{
					OCTLogDebug(stopTags, @"Waiting for running activities to complete: %@", self->_runningActivitiesStrings);
				}
			}
			else if (self->_state != OCCoreStateStopping)
			{
				OCTLogError(stopTags, @"core already in the process of stopping");
				if (completionHandler != nil)
				{
					completionHandler(self, OCError(OCErrorRunningOperation));
				}
			}
			else if (completionHandler != nil)
			{
				OCTLogWarning(stopTags, @"core already stopped");
				completionHandler(self, stopError);
			}
		}];
	}];
}

#pragma mark - Attempt Connect
- (void)_attemptConnect
{
	if (self.connection.authenticationMethod.authenticationDataKnownInvalidDate != nil)
	{
		__weak OCCore *weakCore = self;

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), self->_queue, ^{
			[weakCore __attemptConnect];
		});
	}
	else
	{
		[self __attemptConnect];
	}
}

- (void)__attemptConnect
{
	[self queueConnectivityBlock:^{
		if ((self->_state == OCCoreStateReady) && self->_attemptConnect)
		{
			// Open connection
			dispatch_suspend(self->_connectivityQueue);

			[self beginActivity:@"Connection connect"];

			[self.connection connectWithCompletionHandler:^(NSError *error, OCIssue *issue) {
				if (error == nil)
				{
					OCChecksumAlgorithmIdentifier preferredUploadChecksumType;

					// Use preferred upload checksum type if information is provided as part of capabilities and algorith is available locally
					if ((preferredUploadChecksumType = self.connection.capabilities.preferredUploadChecksumType) != nil)
					{
						if (([OCChecksumAlgorithm algorithmForIdentifier:preferredUploadChecksumType] != nil) && (![self->_preferredChecksumAlgorithm isEqual:preferredUploadChecksumType]))
						{
							self->_preferredChecksumAlgorithm = preferredUploadChecksumType;
						}
					}

					// If app provider is available and enabled
					if (self.memoryConfiguration != OCPlatformMemoryConfigurationMinimum) // only load app providers in memory configurations other than minimum
					{
						OCAppProvider *latestSupportedAppProvider = self.connection.capabilities.latestSupportedAppProvider;

						if ((latestSupportedAppProvider != nil) && latestSupportedAppProvider.enabled)
						{
							[self.connection retrieveAppProviderListWithCompletionHandler:^(NSError * _Nullable error, OCAppProvider * _Nullable appProvider) {
								OCLogDebug(@"AppProviderList: error=%@, appProvider=%@", error, appProvider);

								if (error == nil)
								{
									[self willChangeValueForKey:@"appProvider"];
									self->_appProvider = appProvider;
									[self didChangeValueForKey:@"appProvider"];
								}
								else
								{
									OCLogWarning(@"Error retrieving app provider list: %@", error);
								}
							}];
						}
					}
				}

				[self queueBlock:^{
					// Change state
					if (error == nil)
					{
						[self _updateState:OCCoreStateRunning];

						[self setNeedsToProcessSyncRecords];

						if (self.automaticItemListUpdatesEnabled)
						{
							[self startCheckingForUpdates];
						}

						[self recoverPendingUpdateJobs];
					}

					// Relay error and issues to delegate
					if ((error != nil) || (issue != nil))
					{
						[self sendError:error issue:issue];
					}

					dispatch_resume(self->_connectivityQueue);

					[self endActivity:@"Connection connect"];
				}];
			}];
		}
	}];
}

#pragma mark - Query
- (void)_startItemListTaskForQuery:(OCQuery *)query
{
	OCMeasureEventBegin(query, @"core.queue", coreQueueRef, @"Enqueing query item task list start");

	[self queueBlock:^{
		OCMeasureEventEnd(query, @"core.queue", coreQueueRef, @"Performing query start");

		// Update query state to "started"
		query.state = OCQueryStateStarted;

		// Start task
		if (query.queryLocation != nil)
		{
			// Start item list task for queried directory
			[self scheduleItemListTaskForLocation:query.queryLocation forDirectoryUpdateJob:nil withMeasurement:[query extractedMeasurement]];
		}
		else
		{
			if (query.queryItem.path != nil)
			{
				// Start item list task for parent directory of queried item
				[self scheduleItemListTaskForLocation:query.queryItem.location.parentLocation forDirectoryUpdateJob:nil withMeasurement:[query extractedMeasurement]];
			}
		}
	}];
}

- (void)_startSyncAnchorDatabaseRequestForQuery:(OCQuery *)query
{
	[self queueBlock:^{
		// Update query state to "started"
		query.state = OCQueryStateStarted;

		// Retrieve known changes from the cache
		[self.vault.database retrieveCacheItemsUpdatedSinceSyncAnchor:query.querySinceSyncAnchor foldersOnly:YES completionHandler:^(OCDatabase *db, NSError *error, OCSyncAnchor syncAnchor, NSArray<OCItem *> *items) {
			[self queueBlock:^{
				if ((error == nil) && (items != nil))
				{
					[query performUpdates:^{
						[query mergeItemsToFullQueryResults:items syncAnchor:syncAnchor];
						query.state = OCQueryStateContentsFromCache;
					}];
				}

				query.state = OCQueryStateIdle;
			}];
		}];
	}];
}

- (void)_startCustomQuery:(OCQuery *)query
{
	[self beginActivity:@"Retrieving full query results from custom query"];

	[self queueBlock:^{
		// Update query state to "started"
		if (query.state == OCQueryStateStopped)
		{
			if (query.stopAction.cancelled)
			{
				// Replaced cancelled stop actions
				query.stopAction = [OCCancelAction new];
			}

			query.state = OCQueryStateStarted;
		}

		// Retrieve initial items from query
		[query provideFullQueryResultsForCore:self resultHandler:^(NSError * _Nullable error, NSArray<OCItem *> * _Nullable initialItems) {
			[self queueBlock:^{
				if ((error == nil) && (initialItems != nil))
				{
					[query performUpdates:^{
						[query setFullQueryResults:[[NSMutableArray alloc] initWithArray:initialItems]];
						query.state = OCQueryStateContentsFromCache;

						[query setNeedsRecomputation];
					}];
				}
				else
				{
					OCLogError(@"Error=%@, initialItems=%@ asking query=%@ to provide full query results.", error, initialItems, query);
				}

				query.state = OCQueryStateIdle;

				[self endActivity:@"Retrieving full query results from custom query"];
			}];
		}];
	}];
}

- (void)startQuery:(OCCoreQuery *)coreQuery
{
	if (coreQuery == nil) { return; }

	OCQuery *query = OCTypedCast(coreQuery, OCQuery);
	OCShareQuery *shareQuery = OCTypedCast(coreQuery, OCShareQuery);

	OCMeasureEvent(coreQuery, @"query", @"Starting");

	if ((query != nil) && self.useDrives)
	{
		// Adapt query location from; legacy root to personal folder
		OCLocation *queryLocation;

		if ((queryLocation = query.queryLocation) != nil)
		{
			// No drive ID? => legacy/old server location
			if (queryLocation.driveID == nil)
			{
				// Find personal drive
				OCDrive *personalDrive;

				if ((personalDrive = self.personalDrive) != nil)
				{
					// Set personal drive ID from personal drive
					queryLocation.driveID = personalDrive.identifier;
				}
			}
		}
	}

	if (query != nil)
	{
		// Add query to list of queries
		[self queueBlock:^{
			@synchronized(self->_queries)
			{
				[self->_queries addObject:query];
			}
		}];

		if (!query.isCustom)
		{
			if (query.querySinceSyncAnchor == nil)
			{
				[self _startItemListTaskForQuery:query];
			}
			else
			{
				[self _startSyncAnchorDatabaseRequestForQuery:query];
			}
		}
		else
		{
			[self _startCustomQuery:query];
		}
	}

	if (shareQuery != nil)
	{
		[self startShareQuery:shareQuery];
	}
}

- (void)reloadQuery:(OCCoreQuery *)coreQuery
{
	if (coreQuery == nil) { return; }

	if (self.state != OCCoreStateRunning) { return; }

	OCQuery *query = OCTypedCast(coreQuery, OCQuery);
	OCShareQuery *shareQuery = OCTypedCast(coreQuery, OCShareQuery);

	if (query != nil)
	{
		if (!query.isCustom)
		{
			if (query.querySinceSyncAnchor == nil)
			{
				[self _startItemListTaskForQuery:query];
			}
		}
		else
		{
			[self _startCustomQuery:query];
		}
	}

	if (shareQuery != nil)
	{
		[self reloadShareQuery:shareQuery];
	}
}

- (void)stopQuery:(OCCoreQuery *)coreQuery
{
	if (coreQuery == nil) { return; }

	OCQuery *query = OCTypedCast(coreQuery, OCQuery);
	OCShareQuery *shareQuery = OCTypedCast(coreQuery, OCShareQuery);

	if (query != nil)
	{
		[self queueBlock:^{
			[query.stopAction cancel];

			query.state = OCQueryStateStopped;
			@synchronized(self->_queries)
			{
				[self->_queries removeObject:query];
			}
		}];
	}

	if (shareQuery != nil)
	{
		[self stopShareQuery:shareQuery];
	}
}

#pragma mark - Tools
- (OCDatabase *)database
{
	return (_vault.database);
}

- (void)retrieveLatestDatabaseVersionOfItem:(OCItem *)item completionHandler:(void(^)(NSError *error, OCItem *requestedItem, OCItem *databaseItem))completionHandler
{
	[self.vault.database retrieveCacheItemsAtLocation:item.location itemOnly:YES completionHandler:^(OCDatabase *db, NSError *error, OCSyncAnchor syncAnchor, NSArray<OCItem *> *items) {
		completionHandler(error, item, items.firstObject);
	}];
}

#pragma mark - Message queue
- (OCMessageQueue *)messageQueue
{
	return (OCMessageQueue.globalQueue);
}

#pragma mark - Memory configuration
- (void)setMemoryConfiguration:(OCPlatformMemoryConfiguration)memoryConfiguration
{
	_memoryConfiguration = memoryConfiguration;

	self.vault.resourceManager.memoryConfiguration = memoryConfiguration;
}

#pragma mark - Inter-Process change notification/handling
- (void)startIPCObservation
{
	[_ipNotificationCenter addObserver:self forName:self.bookmark.coreUpdateNotificationName withHandler:^(OCIPNotificationCenter * _Nonnull notificationCenter, OCCore *  _Nonnull core, OCIPCNotificationName  _Nonnull notificationName) {
		[core handleIPCChangeNotification];
	}];

	[_ipNotificationCenter addObserver:self forName:self.bookmark.bookmarkAuthUpdateNotificationName withHandler:^(OCIPNotificationCenter * _Nonnull notificationCenter, OCCore *  _Nonnull core, OCIPCNotificationName  _Nonnull notificationName) {
		[core handleAuthDataChangedNotification:nil];
	}];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleAuthDataChangedNotification:) name:OCBookmarkAuthenticationDataChangedNotification object:nil];
}

- (void)stopIPCObserveration
{
	[NSNotificationCenter.defaultCenter removeObserver:self name:OCBookmarkAuthenticationDataChangedNotification object:self.bookmark];

	[_ipNotificationCenter removeObserver:self forName:self.bookmark.bookmarkAuthUpdateNotificationName];
	[_ipNotificationCenter removeObserver:self forName:self.bookmark.coreUpdateNotificationName];
}

- (void)postIPCChangeNotification
{
	// Wait for database transaction to settle and current task on the queue to finish before posting the notification
	@synchronized(_ipChangeNotificationRateLimiter)
	{
		_pendingIPCChangeNotifications++;

		if (_pendingIPCChangeNotifications == 1)
		{
			[self beginActivity:@"Post IPC change notification"];
		}
	}

	// Rate-limit IP change notifications
	[_ipChangeNotificationRateLimiter runRateLimitedBlock:^{
		[self queueBlock:^{
			// Transaction is not yet closed, so post IPC change notification only after changes have settled
			[self.database.sqlDB executeOperation:^NSError *(OCSQLiteDB *db) {
				// Post IPC change notification
				@synchronized(self->_ipChangeNotificationRateLimiter)
				{
					if (self->_pendingIPCChangeNotifications != 0)
					{
						self->_pendingIPCChangeNotifications = 0;
						[self->_ipNotificationCenter postNotificationForName:self.bookmark.coreUpdateNotificationName ignoreSelf:YES];

						[self endActivity:@"Post IPC change notification"];
					}
				}
				return(nil);
			} completionHandler:nil];
		}];
	}];
}

- (void)handleIPCChangeNotification
{
	if (self.state == OCCoreStateStopped)
	{
		OCLogWarning(@"IPC change notification received by stopped core - possibly caused by strong references to the core (1)");
		return;
	}

	OCLogDebug(@"Received IPC change notification");

	[self queueBlock:^{
		if (self.state == OCCoreStateStopped)
		{
			OCLogWarning(@"IPC change notification received by stopped core - possibly caused by strong references to the core (2)");
			return;
		}

		[self _checkForChangesByOtherProcessesAndUpdateQueries];
	}];
}

- (void)handleAuthDataChangedNotification:(NSNotification *)notification
{
	OCBookmark *notificationBookmark = OCTypedCast(notification.object, OCBookmark);

	if (!((notification == nil) || ((notificationBookmark != nil) && [notificationBookmark.uuid isEqual:_bookmark.uuid])))
	{
		return;
	}

	[self queueBlock:^{
		if (self->_state == OCCoreStateRunning)
		{
			// Trigger a small request to check auth availability
			[self startCheckingForUpdates];
		}

		if ((self->_state == OCCoreStateReady) && (self->_connection.state != OCConnectionStateConnecting))
		{
			// Re-attempt connection
			[self _attemptConnect];
		}
	}];
}

#pragma mark - Check for changes by other processes
- (void)_checkForChangesByOtherProcessesAndUpdateQueries
{
	// Needs to run in queue
	OCSyncAnchor lastKnownSyncAnchor = _latestSyncAnchor;
	OCSyncAnchor latestSyncAnchor = nil;
	NSError *error = nil;

	OCTLogDebug(@[@"IPC"], @"Checking for changes by other processes and updating queries..");

	if ((latestSyncAnchor = [self retrieveLatestSyncAnchorWithError:&error]) != nil)
	{
		if (![lastKnownSyncAnchor isEqual:latestSyncAnchor])
		{
			OCTLogDebug(@[@"IPC"], @"Sync anchors differ (%@ < %@)", lastKnownSyncAnchor, latestSyncAnchor);

			// Sync anchor changed, so there may be changes => replay any you can find
			_latestSyncAnchor = lastKnownSyncAnchor;
			[self _replayChangesSinceSyncAnchor:lastKnownSyncAnchor];
		}
		else
		{
			OCTLogDebug(@[@"IPC"], @"Sync anchors unchanged (%@ == %@)", lastKnownSyncAnchor, latestSyncAnchor);
		}
	}
	else
	{
		OCTLogDebug(@[@"IPC"], @"Could not retrieve latst sync anchor.");
	}
}

- (void)_replayChangesSinceSyncAnchor:(OCSyncAnchor)fromSyncAnchor
{
	[self beginActivity:@"Replaying changes since sync anchor"];

	[self.database retrieveCacheItemsUpdatedSinceSyncAnchor:fromSyncAnchor foldersOnly:NO completionHandler:^(OCDatabase *db, NSError *error, OCSyncAnchor syncAnchor, NSArray<OCItem *> *items) {
		NSMutableArray <OCItem *> *addedOrUpdatedItems = [NSMutableArray new];
		NSMutableArray <OCItem *> *removedItems = [NSMutableArray new];

		for (OCItem *item in items)
		{
			if (item.removed)
			{
				[removedItems addObject:item];
			}
			else
			{
				[addedOrUpdatedItems addObject:item];
			}
		}

		OCTLogDebug(@[@"Replay"], @"Found removedItems=%@, addedOrUpdatedItems=%@ since fromSyncAnchor=%@", removedItems, addedOrUpdatedItems, fromSyncAnchor);

		if ((addedOrUpdatedItems.count > 0) || (removedItems.count > 0))
		{
			OCCoreItemList *addedOrUpdatedItemsList = [OCCoreItemList itemListWithItems:addedOrUpdatedItems];

			[self performUpdatesForAddedItems:nil
			   	removedItems:removedItems
				updatedItems:addedOrUpdatedItems
				refreshLocations:nil
				newSyncAnchor:syncAnchor
				beforeQueryUpdates:^(dispatch_block_t  _Nonnull completionHandler) {
					// Find items that moved to a different path
					NSArray *queries;

					@synchronized(self->_queries)
					{
						queries = [self->_queries copy];
					}

					for (OCQuery *query in queries)
					{
						OCCoreItemList *queryItemList;

						if ((queryItemList = [OCCoreItemList itemListWithItems:query.fullQueryResults]) != nil)
						{
							NSMutableSet <OCFileID> *sharedFileIDs = [[NSMutableSet alloc] initWithSet:addedOrUpdatedItemsList.itemFileIDsSet];
							[sharedFileIDs intersectSet:queryItemList.itemFileIDsSet];

							for (OCFileID sharedFileID in sharedFileIDs)
							{
								OCItem *queryItem = queryItemList.itemsByFileID[sharedFileID];
								OCItem *newItem = addedOrUpdatedItemsList.itemsByFileID[sharedFileID];

								if (![newItem.path.stringByDeletingLastPathComponent isEqual:queryItem.path.stringByDeletingLastPathComponent])
								{
									OCTLogDebug(@[@"Replay"], @"Found moved item (from=%@ to=%@)", queryItem.path, newItem.path);

									newItem.previousPath = queryItem.path;
								}
								else
								{
									OCTLogDebug(@[@"Replay"], @"Found item didn't move (queryItem=%@ newItem=%@)", queryItem, newItem);
								}
							}
						}
					}

					completionHandler();
				}
				afterQueryUpdates:nil
				queryPostProcessor:nil
				skipDatabase:YES
			];
		}

		[self endActivity:@"Replaying changes since sync anchor"];
	}];
}

#pragma mark - Error handling
- (BOOL)sendError:(NSError *)error issue:(OCIssue *)issue
{
	if ((error != nil) || (issue != nil))
	{
		id<OCCoreDelegate> delegate;

		if ([error isOCErrorWithCode:OCErrorAuthorizationMethodNotAllowed])
		{
			// Stop all connectivity via signal provider if an authentication method is not allowed
			[_pauseConnectionSignalProvider setState:OCCoreConnectionStatusSignalStateFalse];
		}

		if (((delegate = self.delegate) != nil) && [self.delegate respondsToSelector:@selector(core:handleError:issue:)])
		{
			if (issue != nil)
			{
				OCIssueSignature issueSignature = nil;

				switch (issue.type)
				{
					case OCIssueTypeCertificate:
					case OCIssueTypeURLRedirection:
						if ((issueSignature = issue.signature) != nil)
						{
							@synchronized(_unsolvedIssueSignatures)
							{
								// Do not re-send unsolved issues
								if ([_unsolvedIssueSignatures containsObject:issueSignature])
								{
									OCLogDebug(@"Blocked duplicate issue %@ (signature: %@)", issue, issueSignature);
									return (NO);
								}

								// New unsolved issue -> add and add handler to issue
								[_unsolvedIssueSignatures addObject:issueSignature];

								__weak OCCore *weakCore = self;

								[issue appendIssueHandler:^(OCIssue * _Nonnull issue, OCIssueDecision decision) {
									OCCore *strongCore;
									NSMutableSet<OCIssueSignature> *unsolvedIssueSignatures;
									NSMutableSet<OCIssueSignature> *rejectedIssueSignatures;

									if (((strongCore = weakCore) != nil) &&
									    ((unsolvedIssueSignatures = strongCore->_unsolvedIssueSignatures) != nil) &&
									    ((rejectedIssueSignatures = strongCore->_rejectedIssueSignatures) != nil))
									{
										BOOL unsolvedListIsEmpty = NO;

										if (decision == OCIssueDecisionApprove)
										{
											OCLogDebug(@"Issue %@ approved, removing from list of unsolved issue (signature: %@)", issue, issueSignature);

											@synchronized(unsolvedIssueSignatures)
											{
												[unsolvedIssueSignatures removeObject:issueSignature];
												[rejectedIssueSignatures removeObject:issueSignature];

												unsolvedListIsEmpty = (unsolvedIssueSignatures.count == 0);
											}
										}

										if (decision == OCIssueDecisionReject)
										{
											OCLogDebug(@"Issue %@ rejected, removing from list of unsolved issue, adding to list of rejected issues (signature: %@)", issue, issueSignature);

											@synchronized(unsolvedIssueSignatures)
											{
												[unsolvedIssueSignatures removeObject:issueSignature];
												[rejectedIssueSignatures addObject:issueSignature];

												unsolvedListIsEmpty = (unsolvedIssueSignatures.count == 0);
											}
										}

										if ((strongCore.state != OCCoreStateStopping) && (strongCore.state != OCCoreStateStopped))
										{
											[strongCore _updateRejectedIssueSignalProvider];

											if (unsolvedListIsEmpty)
											{
												[strongCore connectionChangedState:strongCore.connection];
											}
										}
									}
								}];
							}
						}
					break;

					default:
					break;
				}
			}

			if ([error.domain isEqual:OCHTTPStatusErrorDomain])
			{
				if (error.code >= 400)
				{
					[_serverStatusSignalProvider reportConnectionRefusedError:error];
					return (YES);
				}
			}

			[delegate core:self handleError:error issue:issue];

			return (YES);
		}
	}

	return (NO);
}

- (void)_updateRejectedIssueSignalProvider
{
	BOOL rejectedListIsEmpty;

	@synchronized(_unsolvedIssueSignatures)
	{
		rejectedListIsEmpty = (_rejectedIssueSignatures.count == 0);
	}

	_rejectedIssueSignalProvider.state = (rejectedListIsEmpty ? OCCoreConnectionStatusSignalStateTrue : OCCoreConnectionStatusSignalStateFalse);
}

#pragma mark - Busy handling
- (OCCoreBusyStatusHandler)busyStatusHandler
{
	return (self.database.sqlDB.busyStatusHandler);
}

- (void)setBusyStatusHandler:(OCCoreBusyStatusHandler)busyStatusHandler
{
	self.database.sqlDB.busyStatusHandler = busyStatusHandler;
}

#pragma mark - ## Commands

#pragma mark - Progress tracking
- (void)registerProgress:(NSProgress *)progress forItem:(OCItem *)item
{
	OCLocalID localID;
	BOOL startsHavingProgress = NO;

	if ((localID = item.localID) != nil)
	{
		@synchronized(_progressByLocalID)
		{
			NSMutableArray <NSProgress *> *progressObjects;

			if ((progressObjects = _progressByLocalID[localID]) == nil)
			{
				progressObjects = (_progressByLocalID[localID] = [NSMutableArray new]);
				startsHavingProgress = YES;
			}

			if ([progressObjects indexOfObjectIdenticalTo:progress] == NSNotFound)
			{
				[progressObjects addObject:progress];

				progress.localID = localID;

				[progress addObserver:self forKeyPath:@"finished" options:NSKeyValueObservingOptionInitial context:(__bridge void *)_progressByLocalID];
				[progress addObserver:self forKeyPath:@"cancelled" options:0 context:(__bridge void *)_progressByLocalID];
			}
		}
	}

	if (startsHavingProgress)
	{
		[[NSNotificationCenter defaultCenter] postNotificationName:OCCoreItemBeginsHavingProgress object:item.localID];
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:OCCoreItemChangedProgress object:item.localID];
}

- (void)unregisterProgress:(NSProgress *)progress forItem:(OCItem *)item
{
	OCLocalID localID;

	if ((localID = item.localID) != nil)
	{
		[self unregisterProgress:progress forLocalID:localID];
	}
}

- (void)unregisterProgress:(NSProgress *)progress forLocalID:(OCLocalID)localID
{
	BOOL stopsHavingProgress = NO;

	if (localID != nil)
	{
		@synchronized(_progressByLocalID)
		{
			NSMutableArray <NSProgress *> *progressObjects;

			if ((progressObjects = _progressByLocalID[localID]) != nil)
			{
				if ([progressObjects indexOfObjectIdenticalTo:progress] != NSNotFound)
				{
					[progress removeObserver:self forKeyPath:@"finished" context:(__bridge void *)_progressByLocalID];
					[progress removeObserver:self forKeyPath:@"cancelled" context:(__bridge void *)_progressByLocalID];

					[progressObjects removeObjectIdenticalTo:progress];

					if (progressObjects.count == 0)
					{
						[_progressByLocalID removeObjectForKey:localID];
						stopsHavingProgress = YES;
					}
				}
			}
		}
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:OCCoreItemChangedProgress object:localID];

	if (stopsHavingProgress)
	{
		[[NSNotificationCenter defaultCenter] postNotificationName:OCCoreItemStopsHavingProgress object:localID];
	}
}

- (void)_shutdownProgressObservation
{
	@synchronized(_progressByLocalID)
	{
		[_progressByLocalID enumerateKeysAndObjectsUsingBlock:^(OCFileID  _Nonnull key, NSMutableArray<NSProgress *> * _Nonnull progressObjects, BOOL * _Nonnull stop) {
			for (NSProgress *progress in progressObjects)
			{
				[progress removeObserver:self forKeyPath:@"finished" context:(__bridge void *)self->_progressByLocalID];
				[progress removeObserver:self forKeyPath:@"cancelled" context:(__bridge void *)self->_progressByLocalID];
			}
		}];

		[_progressByLocalID removeAllObjects];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context == (__bridge void *)_progressByLocalID)
	{
		if ([object isKindOfClass:[NSProgress class]])
		{
			NSProgress *progress = object;

			if ((progress.isFinished || progress.isCancelled) && (progress.localID != nil))
			{
				[self queueBlock:^{
					[self unregisterProgress:progress forLocalID:progress.localID];

					if (progress.isCancelled)
					{
						self->_nextSchedulingDate = nil;
						[self setNeedsToProcessSyncRecords];
					}
				}];
			}
		}
	}
	else
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (NSArray<NSProgress *> *)progressForItemWithLocalID:(OCLocalID)localID matchingEventType:(OCEventType)eventType
{
	NSMutableArray <NSProgress *> *resultProgressObjects = nil;

	if (localID != nil)
	{
		@synchronized(_progressByLocalID)
		{
			NSMutableArray <NSProgress *> *progressObjects;

			if ((progressObjects = _progressByLocalID[localID]) != nil)
			{
				if (eventType == OCEventTypeNone)
				{
					resultProgressObjects = [[NSMutableArray alloc] initWithArray:progressObjects];
				}
				else
				{
					for (NSProgress *progress in progressObjects)
					{
						if (progress.eventType == eventType)
						{
							if (resultProgressObjects == nil)
							{
								resultProgressObjects = [NSMutableArray new];
							}

							[resultProgressObjects addObject:progress];
						}
					}
				}
			}
		}
	}

	return (resultProgressObjects);
}


#pragma mark - Item lookup and information
- (OCCoreItemTracking)trackItemAtLocation:(OCLocation *)location trackingHandler:(void(^)(NSError * _Nullable error, OCItem * _Nullable item, BOOL isInitial))trackingHandler
{
	NSObject *trackingObject = [NSObject new];
	__weak NSObject *weakTrackingObject = trackingObject;
	__weak OCCore *weakSelf = self;

	// Detect unnormalized path
	if ([location.path isUnnormalizedPath])
	{
		trackingHandler(OCError(OCErrorUnnormalizedPath), nil, YES);
		return (nil);
	}

	// Detect unresolvable paths
	if ((location.driveID == nil) && self.useDrives) // Legacy WebDAV is not available in drive-based accounts
	{
		trackingHandler(OCError(OCErrorItemNotFound), nil, YES);
		return (nil);
	}

	[self queueBlock:^{
		OCPath path = location.path;
		OCDriveID driveID = location.driveID;
		NSError *error = nil;
		OCItem *item = nil;
		OCQuery *query = nil;
		NSObject *trackingObject = weakTrackingObject;
		__block BOOL isFirstInvocation = YES;
		OCCore *core = weakSelf;

		if (trackingObject == nil)
		{
			return;
		}

		if (core == nil)
		{
			trackingHandler(OCError(OCErrorInternal), nil, YES);
			return;
		}

		if ((item = [core cachedItemAtLocation:location error:&error]) == nil)
		{
			// No item for this path found in cache
			if (path.itemTypeByPath == OCItemTypeFile)
			{
				// This path indicates a file - but maybe that's what's wanted: retry by looking for a folder at that location instead.
				if ((item = [core cachedItemAtLocation:[[OCLocation alloc] initWithBookmarkUUID:core.bookmark.uuid driveID:driveID path:path.normalizedDirectoryPath] error:&error]) != nil)
				{
					path = path.normalizedDirectoryPath;
				}
			}
		}

		if (item != nil)
		{
			// Item in cache

			// Check if path type matches item type
			if (path.itemTypeByPath != item.type)
			{
				// Path type doesn't match path normalization -> fix the path
				path = [path normalizedPathForItemType:item.type];
			}

			// Start custom query to track changes (won't touch network, but will provide updates)
			OCQueryCondition *queryCondition = nil;
			if (driveID != nil)
			{
				queryCondition = [OCQueryCondition require:@[
					[OCQueryCondition where:OCItemPropertyNameDriveID isEqualTo:driveID],
					[OCQueryCondition where:OCItemPropertyNamePath isEqualTo:path]
				]];
			}
			else
			{
				queryCondition = [OCQueryCondition where:OCItemPropertyNamePath isEqualTo:path];
			}

			query = [OCQuery queryWithCondition:queryCondition inputFilter:nil];
			query.changesAvailableNotificationHandler = ^(OCQuery * _Nonnull query) {
				if (weakTrackingObject != nil)
				{
					if ((query.state == OCQueryStateContentsFromCache) || (query.state == OCQueryStateIdle))
					{
						trackingHandler(nil, query.queryResults.firstObject, isFirstInvocation);
						isFirstInvocation = NO;
					}
				}
			};
		}
		else
		{
			// Item not in cache - create full-fledged query
			__block BOOL lastSentItemWasNil = YES;

			query = [OCQuery queryForLocation:[[OCLocation alloc] initWithDriveID:driveID path:path]];
			query.includeRootItem = YES;

			NSString *pathAsDirectory = path.normalizedDirectoryPath;

			query.changesAvailableNotificationHandler = ^(OCQuery * _Nonnull query) {
				if (weakTrackingObject != nil)
				{
					OCItem *item = nil;

					for (OCItem *queryItem in query.queryResults)
					{
						if ([queryItem.path isEqual:path] || [queryItem.path isEqual:pathAsDirectory])
						{
							item = queryItem;
							break;
						}
					}

					if ((item == nil) &&
					    lastSentItemWasNil &&
					    !isFirstInvocation)
					{
						// Avoid multiple invocations of tracking handler if the item is still nil
						return;
					}

					lastSentItemWasNil = (item == nil);

					if (item != nil)
					{
						trackingHandler(nil, item, isFirstInvocation);
						isFirstInvocation = NO;
					}
					else
					{
						if (query.state == OCQueryStateTargetRemoved)
						{
							trackingHandler(nil, nil, isFirstInvocation);
							isFirstInvocation = NO;
						}
					}
				}
			};
		}

		if (query != nil)
		{
			__weak OCCore *weakCore = core;
			__weak OCQuery *weakQuery = query;

			[core startQuery:query];

			// Stop query as soon as trackingObject is deallocated
			[OCDeallocAction addAction:^{
				OCCore *core = weakCore;
				OCQuery *query = weakQuery;

				if ((core != nil) && (query != nil))
				{
					[core stopQuery:query];
				}
			} forDeallocationOfObject:trackingObject];
		}
	}];

	return (trackingObject);
}

- (OCCoreItemTracking)trackItemWithCondition:(OCQueryCondition *)queryCondition trackingHandler:(void(^)(NSError * _Nullable error, OCItem * _Nullable item, BOOL isInitial))trackingHandler
{
	NSObject *trackingObject = [NSObject new];
	__weak NSObject *weakTrackingObject = trackingObject;
	__weak OCCore *weakSelf = self;

	// Detect unnormalized path
	if (queryCondition == nil)
	{
		trackingHandler(OCError(OCErrorInsufficientParameters), nil, YES);
		return (nil);
	}

	[self queueBlock:^{
		OCQuery *query = nil;
		NSObject *trackingObject = weakTrackingObject;
		__block BOOL isFirstInvocation = YES;
		OCCore *core = weakSelf;

		if (trackingObject == nil)
		{
			return;
		}

		if (core == nil)
		{
			trackingHandler(OCError(OCErrorInternal), nil, YES);
			return;
		}

		query = [OCQuery queryWithCondition:queryCondition inputFilter:nil];
		query.changesAvailableNotificationHandler = ^(OCQuery * _Nonnull query) {
			if (weakTrackingObject != nil)
			{
				if ((query.state == OCQueryStateContentsFromCache) || (query.state == OCQueryStateIdle))
				{
					trackingHandler(nil, query.queryResults.firstObject, isFirstInvocation);
					isFirstInvocation = NO;
				}
			}
		};

		if (query != nil)
		{
			__weak OCCore *weakCore = core;
			__weak OCQuery *weakQuery = query;

			[core startQuery:query];

			// Stop query as soon as trackingObject is deallocated
			[OCDeallocAction addAction:^{
				OCCore *core = weakCore;
				OCQuery *query = weakQuery;

				if ((core != nil) && (query != nil))
				{
					[core stopQuery:query];
				}
			} forDeallocationOfObject:trackingObject];
		}
	}];

	return (trackingObject);
}

- (nullable OCItem *)cachedItemAtLocation:(OCLocation *)location error:(__autoreleasing NSError * _Nullable * _Nullable)outError
{
	__block OCItem *cachedItem = nil;

	if (location.path != nil)
	{
		OCSyncExec(retrieveCachedItem, {
			[self.vault.database retrieveCacheItemsAtLocation:location itemOnly:YES completionHandler:^(OCDatabase *db, NSError *error, OCSyncAnchor syncAnchor, NSArray<OCItem *> *items) {
				cachedItem = items.firstObject;

				if (outError != NULL)
				{
					*outError = error;
				}

				OCSyncExecDone(retrieveCachedItem);
			}];
		});
	}
	else
	{
		if (outError != NULL)
		{
			*outError = OCError(OCErrorInsufficientParameters);
		}
	}

	return (cachedItem);
}

- (void)cachedItemAtLocation:(OCLocation *)location resultHandler:(void (^)(NSError * _Nullable, OCItem * _Nullable))resultHandler
{
	if (location.path != nil)
	{
		[self.vault.database retrieveCacheItemsAtLocation:location itemOnly:YES completionHandler:^(OCDatabase *db, NSError *error, OCSyncAnchor syncAnchor, NSArray<OCItem *> *items) {
			resultHandler(error, items.firstObject);
		}];
	}
	else
	{
		resultHandler(OCError(OCErrorInsufficientParameters), nil);
	}
}

- (nullable OCItem *)cachedItemInParentLocation:(OCLocation *)parentLocation withName:(NSString *)name isDirectory:(BOOL)isDirectory error:(__autoreleasing NSError * _Nullable * _Nullable)outError
{
	NSString *path = [parentLocation.path stringByAppendingPathComponent:name];

	if (isDirectory)
	{
		path = [path normalizedDirectoryPath];
	}

	return ([self cachedItemAtLocation:[[OCLocation alloc] initWithBookmarkUUID:_bookmark.uuid driveID:parentLocation.driveID path:path] error:outError]);
}

- (nullable OCItem *)cachedItemInParent:(OCItem *)parentItem withName:(NSString *)name isDirectory:(BOOL)isDirectory error:(__autoreleasing NSError * _Nullable * _Nullable)outError
{
	return ([self cachedItemInParentLocation:parentItem.location withName:name isDirectory:isDirectory error:outError]);
}

- (NSURL *)localCopyOfItem:(OCItem *)item
{
	if (item.localRelativePath != nil)
	{
		return ([self localURLForItem:item]);
	}

	return (nil);
}

#pragma mark - Item location & directory lifecycle
- (NSURL *)localURLForItem:(OCItem *)item
{
	if (item.localRelativePath != nil)
	{
		return ([[self.vault localDriveRootURLForDriveID:item.driveID] URLByAppendingPathComponent:item.localRelativePath isDirectory:NO]);
	}

	return ([self.vault localURLForItem:item]);
}

- (NSURL *)localParentDirectoryURLForItem:(OCItem *)item
{
	return ([[self localURLForItem:item] URLByDeletingLastPathComponent]);
}

- (nullable NSURL *)availableTemporaryURLAlongsideItem:(OCItem *)item fileName:(__autoreleasing NSString **)returnFileName
{
	NSURL *temporaryURL = nil;
	NSURL *baseURL = [self localParentDirectoryURLForItem:item];

	for (NSUInteger attempt=0; attempt < 100; attempt++)
	{
		NSString *filename;

		if ((filename = [NSString stringWithFormat:@"%lu-%@.tmp", (unsigned long)attempt, NSUUID.UUID.UUIDString]) != nil)
		{
			NSURL *temporaryURLCandidate;

			if ((temporaryURLCandidate = [baseURL URLByAppendingPathComponent:filename]) != nil)
			{
				if (![[NSFileManager defaultManager] fileExistsAtPath:temporaryURLCandidate.path])
				{
					temporaryURL = temporaryURLCandidate;

					if (returnFileName != NULL)
					{
						*returnFileName = filename;
					}
				}
			}
		}
	}

	return (temporaryURL);
}

- (BOOL)isURL:(NSURL *)url temporaryAlongsideItem:(OCItem *)item
{
	return ([[url URLByDeletingLastPathComponent] isEqual:[self localParentDirectoryURLForItem:item]] && [url.pathExtension isEqual:@"tmp"]);
}

- (NSError *)createDirectoryForItem:(OCItem *)item
{
	NSError *error = nil;
	NSURL *parentURL;

	if ((parentURL = [self localParentDirectoryURLForItem:item]) != nil)
	{
		if (![[NSFileManager defaultManager] fileExistsAtPath:[parentURL path]])
		{
			if (![[NSFileManager defaultManager] createDirectoryAtURL:parentURL withIntermediateDirectories:YES attributes:@{ NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication } error:&error])
			{
				OCLogError(@"Item parent directory creation at %@ failed with error %@", OCLogPrivate(parentURL), error);
			}
		}
	}
	else
	{
		error = OCError(OCErrorInternal);
	}

	return (error);
}

- (NSError *)deleteDirectoryForItem:(OCItem *)item
{
	NSError *error = nil;
	NSURL *parentURL;

	if ((parentURL = [self localParentDirectoryURLForItem:item]) != nil)
	{
		if ([[NSFileManager defaultManager] fileExistsAtPath:[parentURL path]])
		{
			if (![[NSFileManager defaultManager] removeItemAtURL:parentURL error:&error])
			{
				OCLogError(@"Item parent directory deletion at %@ failed with error %@", OCLogPrivate(parentURL), error);
			}

			OCFileOpLog(@"rm", error, @"Deleted item folder at %@", parentURL.path);
		}
	}
	else
	{
		error = OCError(OCErrorInternal);
	}

	return (error);
}

- (NSError *)renameDirectoryFromItem:(OCItem *)fromItem forItem:(OCItem *)toItem adjustLocalMetadata:(BOOL)adjustLocalMetadata
{
	NSURL *fromItemParentURL = [self localParentDirectoryURLForItem:fromItem];
	NSURL *toItemParentURL = [self localParentDirectoryURLForItem:toItem];
	NSError *error = nil;

	if ((fromItemParentURL != nil) && (toItemParentURL != nil))
	{
		// Move parent directory as needed
		if (![fromItemParentURL isEqual:toItemParentURL])
		{
			BOOL success = [[NSFileManager defaultManager] moveItemAtURL:fromItemParentURL toURL:toItemParentURL error:&error];

			OCFileOpLog(@"mv", error, @"Rename item directory from %@ to %@", fromItemParentURL.path, toItemParentURL.path);

			if (!success)
			{
				OCLogError(@"Item parent directory %@ could not be renamed to %@, error=%@", OCLogPrivate(fromItemParentURL), OCLogPrivate(toItemParentURL), error);
				return (error);
			}
		}

		// Rename local file as needed
		if (fromItem.localRelativePath != nil)
		{
			NSString *fromName = fromItem.localRelativePath.lastPathComponent;
			NSString *toName = toItem.name;

			if ((fromName != nil) && (toName != nil) && (![fromName isEqual:toName]))
			{
				// Renamed
				NSURL *fromLocalFileURL = [toItemParentURL URLByAppendingPathComponent:fromName];
				NSURL *toLocalFileURL = [toItemParentURL URLByAppendingPathComponent:toName];

				BOOL success = [[NSFileManager defaultManager] moveItemAtURL:fromLocalFileURL toURL:toLocalFileURL error:&error];

				OCFileOpLog(@"mv", error, @"Rename item file from %@ to %@", fromLocalFileURL.path, toLocalFileURL.path);

				if (!success)
				{
					OCLogError(@"Item file %@ could not be moved to %@, error=%@", OCLogPrivate(fromLocalFileURL), OCLogPrivate(toLocalFileURL), error);
					return (error);
				}
				else if (adjustLocalMetadata)
				{
					toItem.locallyModified = fromItem.locallyModified;
					toItem.localCopyVersionIdentifier = fromItem.localCopyVersionIdentifier;
					toItem.localRelativePath = [_vault relativePathForItem:toItem];
					toItem.downloadTriggerIdentifier = fromItem.downloadTriggerIdentifier;
					toItem.fileClaim = fromItem.fileClaim;
				}
			}
			else if (adjustLocalMetadata)
			{
				// Name unchanged
				toItem.locallyModified = fromItem.locallyModified;
				toItem.localCopyVersionIdentifier = fromItem.localCopyVersionIdentifier;
				toItem.localRelativePath = fromItem.localRelativePath;
				toItem.downloadTriggerIdentifier = fromItem.downloadTriggerIdentifier;
				toItem.fileClaim = fromItem.fileClaim;
			}
		}
	}
	else
	{
		error = OCError(OCErrorInsufficientParameters);
	}

	return (error);
}

#pragma mark - Event target tools
- (OCEventTarget *)_eventTargetWithCoreSelector:(SEL)selector userInfo:(NSDictionary *)userInfo ephermalUserInfo:(NSDictionary *)ephermalUserInfo
{
	NSMutableDictionary *targetUserInfo = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
		NSStringFromSelector(selector), OCEventUserInfoKeySelector,
	nil];

	if (userInfo != nil)
	{
		[targetUserInfo addEntriesFromDictionary:userInfo];
	}

	return ([OCEventTarget eventTargetWithEventHandlerIdentifier:self.eventHandlerIdentifier userInfo:targetUserInfo ephermalUserInfo:ephermalUserInfo]);
}

#pragma mark - OCEventHandler methods
- (void)handleEvent:(OCEvent *)event sender:(id)sender
{
	dispatch_block_t queueBlock = nil, completionHandler = nil;
	NSString *eventActivityString = [[NSString alloc] initWithFormat:@"Handling event %@", event];

	[self beginActivity:eventActivityString];

	completionHandler = ^{
		[self endActivity:eventActivityString];
	};

	NSString *selectorName;

	if ((selectorName = OCTypedCast(event.userInfo[OCEventUserInfoKeySelector], NSString)) != nil)
	{
		// Selector specified -> route event directly to selector
		SEL eventHandlingSelector;

		if ((eventHandlingSelector = NSSelectorFromString(selectorName)) != NULL)
		{
			// Below is identical to [self performSelector:eventHandlingSelector withObject:event withObject:sender], but in an ARC-friendly manner.
			void (*impFunction)(id, SEL, OCEvent *, id) = (void *)[((NSObject *)self) methodForSelector:eventHandlingSelector];

			queueBlock = ^{
				if (impFunction != NULL)
				{
					impFunction(self, eventHandlingSelector, event, sender);
				}
			};
		}
	}
	else
	{
		// Handle by event type
		switch (event.eventType)
		{
			case OCEventTypeRetrieveThumbnail:
				// Legacy thumbnail event (pre-OCResourceManager era)
				OCLogWarning(@"Dropping legacy thumbnail event: %@", event);
				completionHandler();
			break;

			case OCEventTypeRetrieveItemList: {
				queueBlock = ^{
					[self _handleRetrieveItemListEvent:event sender:sender];
				};
			}
			break;

			default:
				// Critical event - queue synchronously
				[self queueSyncEvent:event sender:sender];
				completionHandler();
			break;
		}
	}

	if (queueBlock != nil)
	{
		[self queueBlock:^{
			queueBlock();
			completionHandler();
		}];
	}
}

#pragma mark - Item usage
- (void)registerUsageOfItem:(OCItem *)item completionHandler:(nullable OCCompletionHandler)completionHandler
{
	// Do not register item usage updates if the last usage was less than 5 seconds ago
	if (item.lastUsed.timeIntervalSinceNow > -5)
	{
		if (completionHandler != nil)
		{
			completionHandler(self, nil);
		}
		return;
	}

	[self beginActivity:@"Registering item usage"];

	[self queueBlock:^{
		OCItem *updatedItem = item;

		if (updatedItem.databaseID != nil)
		{
			OCItem *latestItem;

			if ((latestItem = [self retrieveLatestVersionForLocalIDOfItem:updatedItem withError:NULL]) != nil)
			{
				updatedItem = latestItem;
			}
		}

		if (updatedItem.lastUsed.timeIntervalSinceNow < -5)
		{
			updatedItem.lastUsed = [NSDate new];

			[self performUpdatesForAddedItems:nil removedItems:nil updatedItems:@[ updatedItem ] refreshLocations:nil newSyncAnchor:nil beforeQueryUpdates:nil afterQueryUpdates:nil queryPostProcessor:nil skipDatabase:NO];
		}

		[self endActivity:@"Registering item usage"];

		if (completionHandler != nil)
		{
			completionHandler(self, nil);
		}
	}];
}

#pragma mark - Drives
- (BOOL)useDrives
{
	return (_connection.useDriveAPI);
}

- (void)initializeWithDrives
{
	@synchronized(_lastRootETagsByDriveID)
	{
		for (OCDrive *drive in self.vault.activeDrives)
		{
			_lastRootETagsByDriveID[drive.identifier] = drive.rootETag;
		}

		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_handleSubscribedDrivesUpdate:) name:OCVaultSubscribedDrivesListChanged object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_handleDetachedDrivesUpdate:) name:OCVaultDetachedDrivesListChanged object:nil];
	}
}

- (void)shutdownWithDrives
{
	[NSNotificationCenter.defaultCenter removeObserver:self name:OCVaultSubscribedDrivesListChanged object:nil];
	[NSNotificationCenter.defaultCenter removeObserver:self name:OCVaultDetachedDrivesListChanged object:nil];
}

- (void)subscribeToDrive:(OCDrive *)drive
{
	[self.vault subscribeToDrives:@[ drive ]];
}

- (void)unsubscribeFromDrive:(OCDrive *)drive
{
	[self.vault unsubscribeFromDrives:@[ drive ]];
}

- (NSArray<OCDrive *> *)drives
{
	return (self.vault.activeDrives);
}

- (NSArray<OCDrive *> *)subscribedDrives
{
	return (self.vault.subscribedDrives);
}

- (NSArray<OCDrive *> *)detachedDrives
{
	return (self.vault.detachedDrives);
}

- (OCDrive *)driveWithIdentifier:(OCDriveID)driveID attachedOnly:(BOOL)attachedOnly
{
	if (driveID == nil) { return (nil); }

	return ([self.vault driveWithIdentifier:driveID attachedOnly:attachedOnly]);
}

- (OCDrive *)personalDrive
{
	return ([self.drives firstObjectMatching:^BOOL(OCDrive * _Nonnull drive) {
		return ([drive.specialType isEqual:OCDriveSpecialTypePersonal]);
	}]);
}

- (void)_handleDetachedDrivesUpdate:(NSNotification *)notification
{
	if (notification.object != _vault)
	{
		// Only react to notifications from our vault
		return;
	}

	[self beginActivity:@"Drive detach handling"];

	[self queueBlock:^{
		[self incrementSyncAnchorWithProtectedBlock:^NSError *(OCSyncAnchor previousSyncAnchor, OCSyncAnchor newSyncAnchor) {
			NSArray<OCDrive *> *detachedDrives = self.vault.detachedDrives;
			__block NSError *returnError = nil;

			for (OCDrive *detachedDrive in detachedDrives)
			{
				OCDriveID driveID = detachedDrive.identifier;

				if ((detachedDrive.detachedState == OCDriveDetachedStateNew) && (driveID != nil))
				{
					[self.database removeCacheItemsWithDriveID:driveID syncAnchor:newSyncAnchor completionHandler:^(OCDatabase *db, NSError *error) {
						returnError = error;
					}];

					if (returnError != nil)
					{
						return (returnError);
					}

					[self.vault changeDetachedState:OCDriveDetachedStateItemsRemoved forDriveID:driveID];
				}
			}

			return ((NSError *)returnError);
		} completionHandler:^(NSError *error, OCSyncAnchor previousSyncAnchor, OCSyncAnchor newSyncAnchor) {
			[self endActivity:@"Drive detach handling"];
		}];
	}];
}

- (void)_handleSubscribedDrivesUpdate:(NSNotification *)notification
{
	if (notification.object != _vault)
	{
		// Only react to notifications from our vault
		return;
	}

	[self beginActivity:@"Subscribed drives update handling"];

	[self queueBlock:^{
		NSArray<OCQuery *> *queries;

		@synchronized(self->_queries)
		{
			queries = [self->_queries copy];
		}

		for (OCQuery *query in queries)
		{
			if (query.isCustom)
			{
				// Reload all custom queries as drives are added/removed
				[self reloadQuery:query];
			}
		}

		[self endActivity:@"Subscribed drives update handling"];
	}];
}

#pragma mark - Indicating activity requiring the core
- (void)performInRunningCore:(void(^)(dispatch_block_t completionHandler))activityBlock withDescription:(NSString *)description
{
	if ((activityBlock != nil) && (description != nil))
	{
		[self beginActivity:description];

		activityBlock(^{
			[self endActivity:description];
		});
	}
	else
	{
		OCLogError(@"Paramter(s) missing from %s call", __PRETTY_FUNCTION__);
	}
}

#pragma mark - Schedule work in the core's queue
- (void)scheduleInCoreQueue:(dispatch_block_t)block
{
	[self queueBlock:block];
}

#pragma mark - Busy count
- (void)beginActivity:(NSString *)description
{
	OCLogVerbose(@"Beginning activity '%@' ..", description);
	
	@synchronized(OCCore.class)
	{
		self->_runningActivities++;

		if (self->_runningActivities == 1)
		{
			if (self->_runningActivitiesStrings == nil)
			{
				self->_runningActivitiesStrings = [NSMutableArray new];
			}
		}

		[self->_runningActivitiesStrings addObject:description];
	}
}

- (void)endActivity:(NSString *)description
{
	OCLogVerbose(@"Ended activity '%@' ..", description);
	[self queueBlock:^{
		BOOL allActivitiesEnded = NO;

		@synchronized(OCCore.class)
		{
			self->_runningActivities--;

			NSUInteger oldestIndex;

			if ((oldestIndex = [self->_runningActivitiesStrings indexOfObject:description]) != NSNotFound)
			{
				[self->_runningActivitiesStrings removeObjectAtIndex:oldestIndex];
			}
			else
			{
				OCLogError(@"ERROR! Over-ending activity - core may shutdown abruptly! Activity: %@", description);
			}

			if (self->_runningActivities == 0)
			{
				allActivitiesEnded = YES;
			}
		}

		if (allActivitiesEnded)
		{
			if (self->_runningActivitiesCompleteBlock != nil)
			{
				dispatch_block_t runningActivitiesCompleteBlock = self->_runningActivitiesCompleteBlock;

				self->_runningActivitiesCompleteBlock = nil;
				runningActivitiesCompleteBlock();
			}
		}
	}];
}

#pragma mark - Queues
- (void)queueBlock:(dispatch_block_t)block
{
	[self queueBlock:block allowInlining:NO];
}

- (void)queueBlock:(dispatch_block_t)block allowInlining:(BOOL)allowInlining
{
	if (block == nil) { return; }

	if (allowInlining)
	{
		if (pthread_getspecific(_queueKey) == (__bridge void *)self)
		{
			block();
			return;
		}
	}

	block = [block copy];

	dispatch_async(_queue, ^{
		pthread_setspecific(self->_queueKey, (__bridge void *)self);

		block();

		pthread_setspecific(self->_queueKey, NULL);
	});
}

- (void)queueConnectivityBlock:(dispatch_block_t)block
{
	if (block != nil)
	{
		dispatch_async(_connectivityQueue, block);
	}
}

#pragma mark - Progress resolution
- (NSProgress *)resolveProgress:(OCProgress *)progress withContext:(OCProgressResolutionContext)context
{
	NSProgress *resolvedProgress = nil;

	if (!progress.nextPathElementIsLast)
	{
		OCProgressPathElementIdentifier nextPathElement = progress.nextPathElement;
		OCProgress *sourceProgress = nil;

		if ([nextPathElement isEqual:OCProgressPathElementIdentifierCoreSyncRecordPath])
		{
			if (progress.nextPathElementIsLast)
			{
				// OCSyncRecordID syncRecordID = @([progress.nextPathElement integerValue]);
				__weak OCCore *weakCore = self;

				resolvedProgress = [NSProgress indeterminateProgress];
				resolvedProgress.cancellable = progress.cancellable;

				resolvedProgress.cancellationHandler = ^{
					[progress cancel];
					[weakCore setNeedsToProcessSyncRecords];
				};

				sourceProgress = OCTypedCast((id)progress.userInfo[OCSyncRecordProgressUserInfoKeySource], OCProgress);
			}
		}

		if ([nextPathElement isEqual:OCProgressPathElementIdentifierCoreConnectionPath])
		{
			if (progress.nextPathElementIsLast)
			{
				OCActionTrackingID actionTrackingID;

				if ((actionTrackingID = progress.nextPathElement) != nil)
				{
					resolvedProgress = [self.connection progressForActionTrackingID:actionTrackingID provider:nil];
				}
			}
		}

		if (sourceProgress != nil)
		{
			NSProgress *sourceNSProgress;

			if ((sourceNSProgress = [sourceProgress resolveWith:nil]) != nil)
			{
				resolvedProgress.localizedDescription = sourceNSProgress.localizedDescription;
				resolvedProgress.localizedAdditionalDescription = sourceNSProgress.localizedAdditionalDescription;

				resolvedProgress.totalUnitCount += 200;
				[resolvedProgress addChild:[OCProxyProgress cloneProgress:sourceNSProgress] withPendingUnitCount:200];
			}
		}
	}

	return (resolvedProgress);
}

#pragma mark - Log tags
+ (void)initialize
{
	if (self == [OCCore self])
	{
		[[OCLogger sharedLogger] addFilter:^BOOL(OCLogger * _Nonnull logger, OCLogLevel logLevel, NSString * _Nullable functionName, NSString * _Nullable file, NSUInteger line, NSArray<OCLogTagName> *__autoreleasing * _Nullable pTags, NSString *__autoreleasing *pLogMessage, uint64_t threadID, NSDate * _Nonnull timestamp) {
			NSString *fileName = [file lastPathComponent];

			// Automatically detect messages from OCCore+[Category].m and add [Category] as tag
			if ([fileName hasPrefix:@"OCCore+"])
			{
				NSString *autoTag;

				if ((autoTag = [fileName substringWithRange:NSMakeRange(7, fileName.length-(7+2))]) != nil)
				{
					if (pTags!=NULL)
					{
						if (*pTags!=nil)
						{
							*pTags = [*pTags arrayByAddingObject:autoTag];
						}
						else
						{
							*pTags = @[autoTag];
						}
					}
				}
			}

			return (YES);
		}];
	}
}

+ (NSArray<OCLogTagName> *)logTags
{
	return (@[@"CORE"]);
}

- (NSArray<OCLogTagName> *)logTags
{
	return (@[@"CORE"]);
}

@end

OCClassSettingsKey OCCoreAddAcceptLanguageHeader = @"add-accept-language-header";
OCClassSettingsKey OCCoreThumbnailAvailableForMIMETypePrefixes = @"thumbnail-available-for-mime-type-prefixes";
OCClassSettingsKey OCCoreOverrideReachabilitySignal = @"override-reachability-signal";
OCClassSettingsKey OCCoreOverrideAvailabilitySignal = @"override-availability-signal";
OCClassSettingsKey OCCoreActionConcurrencyBudgets = @"action-concurrency-budgets";
OCClassSettingsKey OCCoreCookieSupportEnabled = @"cookie-support-enabled";
OCClassSettingsKey OCCoreScanForChangesInterval = @"scan-for-changes-interval";

OCDatabaseCounterIdentifier OCCoreSyncAnchorCounter = @"syncAnchor";
OCDatabaseCounterIdentifier OCCoreSyncJournalCounter = @"syncJournal";

OCConnectionSignalID OCConnectionSignalIDCoreOnline = @"coreOnline";
OCConnectionSignalID OCConnectionSignalIDNetworkAvailable = @"networkAvailable";

OCCoreOption OCCoreOptionImportByCopying = @"importByCopying";
OCCoreOption OCCoreOptionImportTransformation = @"importTransformation";
OCCoreOption OCCoreOptionReturnImmediatelyIfOfflineOrUnavailable = @"returnImmediatelyIfOfflineOrUnavailable";
OCCoreOption OCCoreOptionPlaceholderCompletionHandler = @"placeHolderCompletionHandler";
OCCoreOption OCCoreOptionAutomaticConflictResolutionNameStyle = @"automaticConflictResolutionNameStyle";
OCCoreOption OCCoreOptionDownloadTriggerID = @"downloadTriggerID";
OCCoreOption OCCoreOptionSyncReason = @"syncReason";
OCCoreOption OCCoreOptionAddFileClaim = @"addFileClaim";
OCCoreOption OCCoreOptionAddTemporaryClaimForPurpose = @"addTemporaryClaimForPurpose";
OCCoreOption OCCoreOptionSkipRedundancyChecks = @"skipRedundancyChecks";
OCCoreOption OCCoreOptionConvertExistingLocalDownloads = @"convertExistingLocalDownloads";
OCCoreOption OCCoreOptionLastModifiedDate = @"lastModifiedDate";
OCCoreOption OCCoreOptionDependsOnCellularSwitch = @"dependsOnCellularSwitch";
OCCoreOption OCCoreOptionWaitConditions = @"waitConditions";

OCKeyValueStoreKey OCCoreSkipAvailableOfflineKey = @"core.skip-available-offline";

OCSyncReason OCSyncReasonUserInteraction = @"userInteraction";

NSNotificationName OCCoreItemBeginsHavingProgress = @"OCCoreItemBeginsHavingProgress";
NSNotificationName OCCoreItemChangedProgress = @"OCCoreItemChangedProgress";
NSNotificationName OCCoreItemStopsHavingProgress = @"OCCoreItemStopsHavingProgress";
