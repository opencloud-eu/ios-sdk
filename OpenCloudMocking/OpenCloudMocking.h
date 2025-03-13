//
//  OpenCloudMocking.h
//  OpenCloudMocking
//
//  Created by Felix Schwarz on 11.07.18.
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

#import <UIKit/UIKit.h>

//! Project version number for OpenCloudMocking.
FOUNDATION_EXPORT double OpenCloudMockingVersionNumber;

//! Project version string for OpenCloudMocking.
FOUNDATION_EXPORT const unsigned char OpenCloudMockingVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <OpenCloudMocking/PublicHeader.h>

#import <OpenCloudMocking/OCMockManager.h>
#import <OpenCloudMocking/NSObject+OCMockManager.h>

#import <OpenCloudMocking/OCAuthenticationMethod+OCMocking.h>
#import <OpenCloudMocking/OCAuthenticationMethodBasicAuth+OCMocking.h>
#import <OpenCloudMocking/OCAuthenticationMethodOAuth2+OCMocking.h>
#import <OpenCloudMocking/OCConnection+OCMocking.h>
#import <OpenCloudMocking/OCCoreManager+OCMocking.h>
#import <OpenCloudMocking/OCQuery+OCMocking.h>
