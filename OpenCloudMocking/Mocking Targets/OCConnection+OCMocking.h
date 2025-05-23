//
//  OCConnection+OCMocking.h
//  OpenCloudMocking
//
//  Created by Javier Gonzalez on 19/10/2018.
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

@interface OCConnection (OCMocking)

- (void)ocm_prepareForSetupWithOptions:(NSDictionary<NSString *, id> *)options completionHandler:(void(^)(OCIssue *issue, NSURL *suggestedURL, NSArray <OCAuthenticationMethodIdentifier> *supportedMethods, NSArray <OCAuthenticationMethodIdentifier> *preferredAuthenticationMethods))completionHandler;

- (void)ocm_generateAuthenticationDataWithMethod:(OCAuthenticationMethodIdentifier)methodIdentifier options:(OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions)options completionHandler:(void(^)(NSError *error, OCAuthenticationMethodIdentifier authenticationMethodIdentifier, NSData *authenticationData))completionHandler;

@end

// Block and mock location for every mockable method
typedef void(^OCMockOCConnectionPrepareForSetupWithOptionsBlock)(OCConnection *connection, NSDictionary<NSString *, id> *options, void(^completionHandler)(OCIssue *issue, NSURL *suggestedURL, NSArray <OCAuthenticationMethodIdentifier> *supportedMethods, NSArray <OCAuthenticationMethodIdentifier> *preferredAuthenticationMethods));
extern OCMockLocation OCMockLocationOCConnectionPrepareForSetupWithOptions;

typedef void(^OCMockOCConnectionGenerateAuthenticationDataWithMethodBlock)(OCConnection *connection, OCAuthenticationMethodIdentifier methodIdentifier, OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions options, void(^completionHandler)(NSError *error, OCAuthenticationMethodIdentifier authenticationMethodIdentifier, NSData *authenticationData));
extern OCMockLocation OCMockLocationOCConnectionGenerateAuthenticationDataWithMethod;

typedef NSProgress *(^OCMockOCConnectionConnectWithCompletionHandlerBlock)(OCConnection *connection, void (^completionHandler)(NSError *, OCIssue *));
extern OCMockLocation OCMockLocationOCConnectionConnectWithCompletionHandler;

typedef void(^OCMockOCConnectionDisconnectWithCompletionHandlerBlock)(OCConnection *connection, dispatch_block_t completionHandler, BOOL invalidate);
extern OCMockLocation OCMockLocationOCConnectionDisconnectWithCompletionHandlerInvalidate;
