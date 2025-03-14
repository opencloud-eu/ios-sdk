//
//  OCProxyProgress.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 21.02.19.
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

NS_ASSUME_NONNULL_BEGIN

@interface OCProxyProgress : NSObject

@property(readonly,strong) NSProgress *observedProgress;
@property(readonly,weak) NSProgress *clonedProgress;

+ (NSProgress *)cloneProgress:(NSProgress *)progress;

- (instancetype)initWithProgress:(NSProgress *)progress;

@end

NS_ASSUME_NONNULL_END
