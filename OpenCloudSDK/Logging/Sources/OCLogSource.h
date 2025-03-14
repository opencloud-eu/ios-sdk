//
//  OCLogSource.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 01.11.18.
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
#import "OCLogger.h"

NS_ASSUME_NONNULL_BEGIN

@interface OCLogSource : NSObject

@property(weak) OCLogger *logger;
@property(strong) NSString *name;

- (instancetype)initWithName:(NSString *)name logger:(OCLogger *)logger;

#pragma mark - Start / Stop source
- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
