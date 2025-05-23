//
//  OCWaitConditionMetaDataRefresh.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 24.02.20.
//  Copyright © 2020 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2020, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import "OCWaitCondition.h"
#import "OCItemVersionIdentifier.h"
#import "OCLocation.h"

NS_ASSUME_NONNULL_BEGIN

@interface OCWaitConditionMetaDataRefresh : OCWaitCondition <NSSecureCoding>

#pragma mark - Item path
@property(strong) OCLocation *itemLocation;

#pragma mark - Metadata
@property(strong,nullable) OCItemVersionIdentifier *itemVersionIdentifier;

#pragma mark - Condition expiration
@property(strong,nullable) NSDate *expirationDate;

+ (instancetype)waitForLocation:(OCLocation *)location versionOtherThan:(OCItemVersionIdentifier *)itemVersionIdentifier until:(NSDate * _Nullable)expirationDate;

@end

NS_ASSUME_NONNULL_END
