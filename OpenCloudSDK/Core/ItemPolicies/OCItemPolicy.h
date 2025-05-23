//
//  OCItemPolicy.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 10.07.19.
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
#import "OCQueryCondition.h"
#import "OCTypes.h"
#import "OCDataTypes.h"

typedef NSString* OCItemPolicyKind NS_TYPED_ENUM;
typedef NSString* OCItemPolicyIdentifier;

typedef NSString* OCItemPolicyUUID;

typedef NS_ENUM(NSUInteger, OCItemPolicyAutoRemovalMethod)
{
	OCItemPolicyAutoRemovalMethodNone,	//!< Do not automatically remove this item policy
	OCItemPolicyAutoRemovalMethodNoItems	//!< Automatically remove this item policy if a database-search for .policyAutoRemovalCondition returns no items
};

NS_ASSUME_NONNULL_BEGIN

@interface OCItemPolicy : NSObject <NSSecureCoding>

@property(strong) OCItemPolicyUUID uuid; //!< UUID of the item policy

#pragma mark - Database glue
@property(nullable,strong) OCDatabaseID databaseID; //!< OCDatabase-specific ID referencing the policy in the database

#pragma mark - Identification
@property(nullable,strong) OCItemPolicyIdentifier identifier; //!< Optional identifier uniquely identifying a policy (f.ex. to re-recognize an internal policy)
@property(nullable,strong) NSString *policyDescription; //!< Optional description of the policy (f.ex. to store a user-facing/editable description)

@property(nullable,strong) OCLocation *location; //!< Optional location for use by clients of the ItemPolicy system such as AvailableOffline.
@property(nullable,strong) OCLocalID localID; //!< Optional localID for use by clients of the ItemPolicy system such as AvailableOffline.

#pragma mark - Policy definition
@property(strong) OCItemPolicyKind kind; //!< The kind of policy, f.ex. "AvailableOffline"
@property(strong) OCQueryCondition *condition; //!< Query condition describing a selection of items

@property(assign) OCItemPolicyAutoRemovalMethod policyAutoRemovalMethod;
@property(nullable,strong) OCQueryCondition *policyAutoRemovalCondition; //!< Query condition describing when this policy should be removed

- (instancetype)initWithKind:(OCItemPolicyKind)kind condition:(OCQueryCondition *)condition;
- (instancetype)initWithKind:(OCItemPolicyKind)kind item:(OCItem *)item;

@end

extern OCItemPolicyIdentifier OCItemPolicyIdentifierInternalPrefix; //!< Prefix for identifier of internally used item policies

NS_ASSUME_NONNULL_END
