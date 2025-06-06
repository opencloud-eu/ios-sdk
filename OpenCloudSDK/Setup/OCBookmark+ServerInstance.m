//
//  OCBookmark+ServerInstance.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 07.03.23.
//  Copyright © 2023 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2023, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import "OCBookmark+ServerInstance.h"
#import "OCServerInstance.h"

@implementation OCBookmark (ServerInstance)

- (void)applyServerInstance:(OCServerInstance *)serverInstance
{
	self.url = serverInstance.url;
}

@end
