//
//  NSError+OpenCloudError.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 19.09.22.
//  Copyright © 2022 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2022, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import "NSError+OCError.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSError (OpenCloudError)

+ (nullable NSError *)errorFromOpenCloudErrorDictionary:(NSDictionary<NSString *, NSString *> *)openCloudErrorDict underlyingError:(nullable NSError *)underlyingError;

@end

extern NSErrorUserInfoKey OCOpenCloudErrorCodeKey;

NS_ASSUME_NONNULL_END
