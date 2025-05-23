//
//  OCResourceSourceURL.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 22.05.23.
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

#import "OCResourceSource.h"
#import "OCTypes.h"

NS_ASSUME_NONNULL_BEGIN

typedef OCHTTPRequest * _Nonnull (^OCResourceSourceURLHTTPRequestCustomizer)(OCHTTPRequest *httpRequest);

@interface OCResourceSourceURL : OCResourceSource

- (void)provideResourceForRequest:(OCResourceRequest *)request url:(NSURL *)url eTag:(nullable OCFileETag)eTag customizeRequest:(nullable OCResourceSourceURLHTTPRequestCustomizer)requestCustomizer resultHandler:(OCResourceSourceResultHandler)resultHandler;

@end

NS_ASSUME_NONNULL_END
