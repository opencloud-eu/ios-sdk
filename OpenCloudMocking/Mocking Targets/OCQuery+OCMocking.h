//
//  OCQuery+OCMocking.h
//  OpenCloudMocking
//
//  Created by Javier Gonzalez on 13/11/2018.
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

#import <OpenCloudSDK/OpenCloudSDK.h>
#import "OCMockManager.h"

@interface OCQuery (OCMocking)

- (void)ocm_requestChangeSetWithFlags:(OCQueryChangeSetRequestFlag)flags completionHandler:(void(^)(OCQueryChangeSetRequestCompletionHandler))completionHandler;

@end

typedef void *(^OCMockOCQueryRequestChangeSetWithFlagsBlock)(OCQueryChangeSetRequestFlag flags, void(^completionHandler)(OCQueryChangeSetRequestCompletionHandler));
extern OCMockLocation OCMockLocationOCQueryRequestChangeSetWithFlags;
