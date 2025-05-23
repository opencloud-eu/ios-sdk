//
//  OCItemPolicyProcessor.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 12.07.19.
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

#import <Foundation/Foundation.h>
#import "OCItemPolicy.h"
#import "OCClassSettings.h"
#import "OCClassSettingsUserPreferences.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, OCItemPolicyProcessorTrigger)
{
	OCItemPolicyProcessorTriggerItemsChanged = (1<<0),		//!< Triggered whenever items change (f.ex. following sync actions, PROPFINDs, etc.)
	OCItemPolicyProcessorTriggerItemListUpdateCompleted = (1<<1),	//!< Triggered whenever an item list update was completed with changes and the database of cache items is considered consistent with server contents
	OCItemPolicyProcessorTriggerItemListUpdateCompletedWithoutChanges = (1<<2),	//!< Triggered whenever an item list update was completed without changes and the database of cache items is considered consistent with server contents
	OCItemPolicyProcessorTriggerPoliciesChanged = (1<<3),		//!< Triggered whenever an item policy was added, removed or updated
	OCItemPolicyProcessorTriggerSyncReason = (1<<4),		//!< Triggered whenever the amount of actions with the provided Sync Reason has changed and is below maximumActiveSyncActions.

	OCItemPolicyProcessorTriggerAll = NSUIntegerMax
};

@interface OCItemPolicyProcessor : NSObject <OCClassSettingsSupport, OCClassSettingsUserPreferencesSupport>
{
	OCQueryCondition *_policyCondition;
}

@property(weak) OCCore *core;

@property(strong) OCItemPolicyKind kind; //!< Kind of policies this processor processes

@property(readonly) OCItemPolicyProcessorTrigger triggerMask; //!< Mask of when the processor should be triggered

@property(nullable,strong,nonatomic) NSArray<OCItemPolicy *> *policies;	//!< Policies that serve as basis for the processor (typically all policies with the same OCItemPolicyIdentifier)
@property(nullable,strong,nonatomic) OCQueryCondition *policyCondition;	//!< Query condition combining - with ANY-OF - all the query conditions from the policies. Updated when .policies is set.

@property(nullable,strong,nonatomic) OCQueryCondition *matchCondition;	//!< Query condition matching relevant items that may require the policy processor to perform actions on them
@property(nullable,strong,nonatomic) OCQueryCondition *cleanupCondition;//!< Query condition matching items that may require cleanup by the policy processor

@property(nullable,strong) NSString *localizedName; //!< Localized name of the policy
@property(nullable,strong,nonatomic) OCQueryCondition *customQueryCondition;	//!< Query condition that can be used to present items matched by the policy (typically equals .matchCondition). nil if it shouldn't.

@property(nullable,strong) OCSyncReason syncReason; //!< The Sync Reason that Sync Actions started from this policy use. If there's no longer any action with this Sync Reason;
@property(nullable,strong) NSNumber *maximumActiveSyncActions; //!< The maximum number of Sync Actions
@property(nullable,strong) NSNumber *maximumQueriedItems; //!< Limits queries into the database to .maximumQueriedItems in advance. Should only be used if -performActionOn: ALWAYS schedules an action in the Sync Engine. Otherwise, the active Sync Action count for the Sync Reason will not change - and the Policy Processor not be triggered again. Also, the Policy Processor may be fed with the same items that do not trigger any Sync Action again, effectively preventing the necessary handling to take place.

@property(assign) BOOL hasPendingActionItems; //!< Internal, tracks if there are (possibly) pending items if .syncReason != nil, maximumActiveSyncActions != nil AND the number of active sync actions with this Sync Reason is less than .maximumActiveSyncActions
@property(nullable,strong) NSNumber *activeSyncActionCount; //!< Internal, if .syncReason != nil, tracks the number of active sync actions with that Sync Reason

- (instancetype)initWithKind:(OCItemPolicyKind)kind core:(OCCore *)core;

#pragma mark - Policy updates
- (void)updateWithPolicies:(nullable NSArray<OCItemPolicy *> *)policies; //!< Called whenever policies have been updated. The processor is responsible for filtering and using them.

- (void)performPreflightOnPoliciesWithTrigger:(OCItemPolicyProcessorTrigger)trigger withItems:(nullable NSArray<OCItem *> *)newUpdatedAndRemovedItems; //!< Called on matching triggers, before -willEnterTrigger:, to give the OCItemPolicyProcessor an opportunity to refresh the policies without triggering an OCItemPolicyProcessorTriggerPoliciesChanged event

#pragma mark - Match handling
- (void)beginMatchingWithTrigger:(OCItemPolicyProcessorTrigger)trigger;
- (void)performActionOn:(OCItem *)matchingItem withTrigger:(OCItemPolicyProcessorTrigger)trigger;
- (void)endMatchingWithTrigger:(OCItemPolicyProcessorTrigger)trigger;

#pragma mark - Cleanup handling
- (void)beginCleanupWithTrigger:(OCItemPolicyProcessorTrigger)trigger;
- (void)performCleanupOn:(OCItem *)cleanupItem withTrigger:(OCItemPolicyProcessorTrigger)trigger;
- (void)endCleanupWithTrigger:(OCItemPolicyProcessorTrigger)trigger;

#pragma mark - Events
- (void)willEnterTrigger:(OCItemPolicyProcessorTrigger)trigger;
- (void)didPassTrigger:(OCItemPolicyProcessorTrigger)trigger;

#pragma mark - Cleanup policies
- (void)performPoliciesAutoRemoval;
- (BOOL)shouldAutoRemoveItemPolicy:(OCItemPolicy *)itemPolicy; //!< Return YES if the item policy should be auto-removed
- (nullable OCItemPolicy *)attemptRecoveryOfPolicy:(OCItemPolicy *)itemPolicy; //!< Return nil to remove the policy, an updated/replacement OCItemPolicy to keep the policy

/*
	Ideas for policies:
	- BurnAfterReading (BAR => to bar, probably nice wordplay here)
		- No matchCondition
		- Cleanup if: matchingPolicies && isLocalCopy + claims==0 check
		- use OCClaim to allow FP and viewer to claim files affected by BurnAfterReading policy
*/

@end

extern NSNotificationName OCCoreItemPolicyProcessorUpdated; //!< Notification sent when an item policy processor was updated. The object is the OCItemPolicyProcessor.

extern OCClassSettingsIdentifier OCClassSettingsIdentifierItemPolicy;

NS_ASSUME_NONNULL_END
