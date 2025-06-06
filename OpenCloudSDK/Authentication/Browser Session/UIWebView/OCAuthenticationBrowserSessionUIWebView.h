//
//  OCAuthenticationBrowserSessionUIWebView.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 02.12.19.
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

#import "OCFeatureAvailability.h"

#if OC_FEATURE_AVAILABLE_UIWEBVIEW_BROWSER_SESSION

#import "OCAuthenticationBrowserSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface OCAuthenticationBrowserSessionUIWebView : OCAuthenticationBrowserSession

@property(strong,nonatomic) UIViewController *viewController;
@property(strong) UIWebView *webView;

@end

NS_ASSUME_NONNULL_END

#endif /* OC_FEATURE_AVAILABLE_UIWEBVIEW_BROWSER_SESSION */
