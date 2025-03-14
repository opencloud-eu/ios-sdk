//
//  OCProgressManager.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 19.02.19.
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
#import "OCProgress.h"

NS_ASSUME_NONNULL_BEGIN

@interface OCProgressManager : NSObject <OCProgressResolver>

@property(class,readonly,nonatomic,strong) OCProgressManager *sharedProgressManager;

#pragma mark - Registered progress objects
- (nullable OCProgress *)registeredProgressWithIdentifier:(OCProgressID)progressID;

- (void)registerProgress:(OCProgress *)progress;
- (void)unregisterProgress:(OCProgress *)progress;

@end

extern OCProgressPathElementIdentifier OCProgressPathElementIdentifierManagerRoot;

NS_ASSUME_NONNULL_END
