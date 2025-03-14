//
//  OCSQLiteQueryCondition.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 13.06.18.
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCSQLiteQueryCondition : NSObject

@property(strong) NSString *sqlOperator; //!< I.e. "!="
@property(nullable,strong) id value; //!< I.e. "admin"
@property(assign) BOOL apply; //!< YES if this condition should be used as part of the WHERE clause, NO if it should be ignored

+ (instancetype)queryConditionWithOperator:(NSString *)sqlOperator value:(nullable id)value apply:(BOOL)apply;

@end

NS_ASSUME_NONNULL_END
