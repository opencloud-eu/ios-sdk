//
//  UIDevice+ModelID.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 11.11.19.
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

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIDevice (ModelID)

@property(readonly,nonatomic,strong) NSString *ocModelIdentifier;

@end

NS_ASSUME_NONNULL_END
