//
//  OCSyncRecord.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 07.02.18.
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

#import "OCSyncRecord.h"
#import "NSProgress+OCExtensions.h"
#import "OCSyncAction.h"
#import "OCSyncIssue.h"
#import "OCProcessManager.h"
#import "OCWaitConditionIssue.h"
#import "OCSyncRecordActivity.h"
#import "OCSignalManager.h"
#import "OCProxyProgress.h"

@implementation OCSyncRecord

@synthesize recordID = _recordID;
@synthesize originProcessSession = _originProcessSession;

@synthesize actionIdentifier = _actionIdentifier;
@synthesize action = _action;
@synthesize timestamp = _timestamp;

@synthesize state = _state;
@synthesize inProgressSince = _inProgressSince;

@synthesize resultSignalUUID = _resultSignalUUID;
@synthesize progress = _progress;

#pragma mark - Init & Dealloc
- (instancetype)initWithAction:(OCSyncAction *)action resultSignalUUID:(OCSignalUUID)resultSignalUUID
{
	if ((self = [self init]) != nil)
	{
		_originProcessSession = OCProcessManager.sharedProcessManager.processSession;

		_action = action;
		_actionIdentifier = action.identifier;
		_timestamp = [NSDate date];

		_state = OCSyncRecordStatePending;

		_resultSignalUUID = resultSignalUUID;
		_progressSignalUUID = OCSignal.generateUUID;

		_syncReason = action.syncReason;
	}

	return (self);
}

#pragma mark - Properties
- (void)setState:(OCSyncRecordState)state
{
	if ((_state == OCSyncRecordStateProcessing) && (state != OCSyncRecordStateProcessing))
	{
		self.waitConditions = nil;
	}

	_state = state;
}

- (OCLocalID)localID
{
	return (self.action.localItem.localID);
}

#pragma mark - Serialization
+ (instancetype)syncRecordFromSerializedData:(NSData *)serializedData
{
	if (serializedData==nil) { return(nil); }
	return ([NSKeyedUnarchiver unarchiveObjectWithData:serializedData]);
}

- (NSData *)serializedData
{
	return ([NSKeyedArchiver archivedDataWithRootObject:self]);
}

- (void)addProgress:(OCProgress *)progressToAdd
{
	if (progressToAdd != nil)
	{
		if (_progress == nil)
		{
			self.progress = progressToAdd;
		}
		else
		{
			_progress.userInfo = @{ OCSyncRecordProgressUserInfoKeySource : progressToAdd };

			if (progressToAdd.progress != nil)
			{
				if (_progress.progress == nil)
				{
					_progress.progress = progressToAdd.progress;
				}
				else
				{
					_progress.progress.localizedDescription = progressToAdd.progress.localizedDescription;
					_progress.progress.localizedAdditionalDescription = progressToAdd.progress.localizedAdditionalDescription;

					_progress.progress.totalUnitCount += 200;
					[_progress.progress addChild:[OCProxyProgress cloneProgress:progressToAdd.progress] withPendingUnitCount:200]; // Clone progress to avoid possibility of exception "NSProgress 0x... was already the child of another progress 0x..."
				}
			}
		}
	}
}

#pragma mark - Adding / Removing wait conditions
- (void)addWaitCondition:(OCWaitCondition *)waitCondition
{
	@synchronized(self)
	{
		NSMutableArray *waitConditions = (_waitConditions != nil) ? [[NSMutableArray alloc] initWithArray:_waitConditions] : [NSMutableArray new];

		[waitConditions addObject:waitCondition];

		self.waitConditions = waitConditions;
	}
}

- (void)removeWaitCondition:(OCWaitCondition *)waitCondition
{
	@synchronized(self)
	{
		if (self.waitConditions != nil)
		{
			NSMutableArray *waitConditions = [[NSMutableArray alloc] initWithArray:_waitConditions];

			[waitConditions removeObject:waitCondition];

			if (waitConditions.count == 0)
			{
				waitConditions = nil;
			}

			self.waitConditions = waitConditions;
		}
	}
}

- (OCWaitCondition *)waitConditionForUUID:(NSUUID *)uuid
{
	@synchronized(self)
	{
		for (OCWaitCondition *waitCondition in _waitConditions)
		{
			if ([waitCondition.uuid isEqual:uuid])
			{
				return (waitCondition);
			}
		}
	}

	return (nil);
}

#pragma mark - State
- (void)transitionToState:(OCSyncRecordState)state withWaitConditions:(nullable NSArray <OCWaitCondition *> *)waitConditions
{
	if (_state != state)
	{
		switch (state)
		{
			case OCSyncRecordStateProcessing:
				self.inProgressSince = [NSDate date];
			break;

			case OCSyncRecordStateCompleted:
				// Indicate "done" to progress object
				self.progress.progress.totalUnitCount = 1;
				self.progress.progress.completedUnitCount = 1;
			break;

			default:
			break;
		}
	}

	self.state = state;
	self.waitConditions = waitConditions;
}

- (void)completeWithError:(nullable NSError *)error core:(OCCore *)core item:(nullable OCItem *)item parameter:(nullable id)parameter
{
	OCLogDebug(@"Sync record %@ completed with error=%@ item=%@ parameter=%@, resultSignalUUID=%@", OCLogPrivate(self), OCLogPrivate(error), OCLogPrivate(item), OCLogPrivate(parameter), _resultSignalUUID);

 	if ((_resultSignalUUID != nil) && (core.signalManager != nil))
 	{
 		OCMutableCodableDict payload = [[NSMutableDictionary alloc] initWithCapacity:3];

 		payload[@"error"] = error;
 		payload[@"item"] = item;
 		payload[@"parameter"] = parameter;

 		[core.signalManager postSignal:[[OCSignal alloc] initWithUUID:_resultSignalUUID payload:payload]];
 	}
}

#pragma mark - Secure Coding
+ (BOOL)supportsSecureCoding
{
	return (YES);
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [self init]) != nil)
	{
		_recordID = [decoder decodeObjectOfClass:NSNumber.class forKey:@"recordID"];

		_laneID = [decoder decodeObjectOfClass:NSNumber.class forKey:@"laneID"];

		_originProcessSession = [decoder decodeObjectOfClass:OCProcessSession.class forKey:@"originProcessSession"];

		_actionIdentifier = [decoder decodeObjectOfClass:NSString.class forKey:@"actionID"];
		_action = [decoder decodeObjectOfClass:OCSyncRecord.class forKey:@"action"];

		_timestamp = [decoder decodeObjectOfClass:[NSDate class] forKey:@"timestamp"];

		_state = (OCSyncRecordState)[decoder decodeIntegerForKey:@"state"];
		_inProgressSince = [decoder decodeObjectOfClass:NSDate.class forKey:@"inProgressSince"];
		_syncReason = [decoder decodeObjectOfClass:NSString.class forKey:@"syncReason"];

		_resultSignalUUID = [decoder decodeObjectOfClass:NSString.class forKey:@"resultSignalUUID"];
		_progressSignalUUID = [decoder decodeObjectOfClass:NSString.class forKey:@"progressSignalUUID"];

		_isProcessIndependent = [decoder decodeBoolForKey:@"isProcessIndependent"];
		_progress = [decoder decodeObjectOfClass:OCProgress.class forKey:@"progress"];

		_waitConditions = [decoder decodeObjectOfClasses:[[NSSet alloc] initWithObjects:NSArray.class, OCWaitCondition.class, nil] forKey:@"waitConditions"];
	}
	
	return (self);
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_recordID forKey:@"recordID"];

	[coder encodeObject:_laneID forKey:@"laneID"];

	[coder encodeObject:_originProcessSession forKey:@"originProcessSession"];

	[coder encodeObject:_actionIdentifier forKey:@"actionID"];
	[coder encodeObject:_action forKey:@"action"];

	[coder encodeObject:_timestamp forKey:@"timestamp"];

	[coder encodeInteger:(NSInteger)_state forKey:@"state"];
	[coder encodeObject:_inProgressSince forKey:@"inProgressSince"];
	[coder encodeObject:_syncReason forKey:@"syncReason"];

	[coder encodeObject:_resultSignalUUID forKey:@"resultSignalUUID"];

	[coder encodeObject:_progressSignalUUID forKey:@"progressSignalUUID"];

	[coder encodeBool:_isProcessIndependent forKey:@"isProcessIndependent"];
	[coder encodeObject:_progress forKey:@"progress"];

	[coder encodeObject:_waitConditions forKey:@"waitConditions"];
}

#pragma mark - Activity Source
+ (OCActivityIdentifier)activityIdentifierForSyncRecordID:(OCSyncRecordID)recordID
{
	return ([NSString stringWithFormat:@"syncRecord:%@", recordID]);
}

- (OCActivityIdentifier)activityIdentifier
{
	if (_activityIdentifier == nil)
	{
		_activityIdentifier = [OCSyncRecord activityIdentifierForSyncRecordID:_recordID];
	}

	return (_activityIdentifier);
}

- (OCActivity *)provideActivity
{
	return ([[OCSyncRecordActivity alloc] initWithSyncRecord:self identifier:self.activityIdentifier]);
}

#pragma mark - Progress setup
- (void)setProgress:(OCProgress *)progress
{
	_progress = progress;

	if (progress.progress!=nil)
	{
		if (progress.progress.eventType == OCEventTypeNone)
		{
			progress.progress.eventType = _action.actionEventType;
		}
	}
}

#pragma mark - Sync Lane support
- (NSSet<OCSyncLaneTag> *)laneTags
{
	return (self.action.laneTags);
}

#pragma mark - Description
- (NSString *)description
{
	return ([NSString stringWithFormat:@"<%@: %p, recordID: %@, actionID: %@, timestamp: %@, state: %lu, inProgressSince: %@, isProcessIndependent: %d, signalUUID: %@, action: %@>", NSStringFromClass(self.class), self, _recordID, _actionIdentifier, _timestamp, _state, _inProgressSince, _isProcessIndependent, _resultSignalUUID, _action]);
}

- (NSString *)privacyMaskedDescription
{
	return ([NSString stringWithFormat:@"<%@: %p, recordID: %@, actionID: %@, timestamp: %@, state: %lu, inProgressSince: %@, isProcessIndependent: %d, signalUUID: %@, action: %@>", NSStringFromClass(self.class), self, _recordID, _actionIdentifier, _timestamp, _state, _inProgressSince, _isProcessIndependent, _resultSignalUUID, OCLogPrivate(_action)]);
}

@end

static NSString *SyncRecordIDActionTrackingIDPrefix = @"syncRecordID:";

OCSyncRecordID _Nullable OCSyncRecordIDFromActionTrackingID(OCActionTrackingID _Nullable actionTrackingID)
{
	if (actionTrackingID == nil) { return(nil); }

	if ([actionTrackingID hasPrefix:SyncRecordIDActionTrackingIDPrefix])
	{
		return (@([[actionTrackingID substringFromIndex:SyncRecordIDActionTrackingIDPrefix.length] integerValue]));
	}

	return (nil);
}

OCActionTrackingID _Nullable OCActionTrackingIDFromSyncRecordID(OCSyncRecordID _Nullable syncRecordID)
{
	if (syncRecordID == nil) { return(nil); }
	return ([SyncRecordIDActionTrackingIDPrefix stringByAppendingString:syncRecordID.stringValue]);
}

OCSyncActionIdentifier OCSyncActionIdentifierDeleteLocal = @"deleteLocal";
OCSyncActionIdentifier OCSyncActionIdentifierDeleteLocalCopy = @"deleteLocalCopy";
OCSyncActionIdentifier OCSyncActionIdentifierDeleteRemote = @"deleteRemote";
OCSyncActionIdentifier OCSyncActionIdentifierMove = @"move";
OCSyncActionIdentifier OCSyncActionIdentifierCopy = @"copy";
OCSyncActionIdentifier OCSyncActionIdentifierCreateFolder = @"createFolder";
OCSyncActionIdentifier OCSyncActionIdentifierDownload = @"download";
OCSyncActionIdentifier OCSyncActionIdentifierUpload = @"upload";
OCSyncActionIdentifier OCSyncActionIdentifierUpdate = @"update";

NSString *OCSyncRecordProgressUserInfoKeySource = @"sourceProgress";
