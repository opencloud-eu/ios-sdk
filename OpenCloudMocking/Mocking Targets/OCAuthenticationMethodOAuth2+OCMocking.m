//
//  OCAuthenticationMethodOAuth2+OCMocking.m
//  OpenCloudMocking
//
//  Created by Felix Schwarz on 17.12.18.
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

#import "OCAuthenticationMethodOAuth2+OCMocking.h"

@implementation OCAuthenticationMethodOAuth2 (OCMocking)

+ (void)load
{
	[self addMockLocation:OCMockLocationAuthenticationMethodOAuth2StartAuthenticationSessionForURLSchemeCompletionHandler
	      forClassSelector:@selector(startAuthenticationSession:forURL:scheme:options:completionHandler:)
	      with:@selector(ocm_oa2_startAuthenticationSession:forURL:scheme:options:completionHandler:)];
}

+ (BOOL)ocm_oa2_startAuthenticationSession:(__autoreleasing id *)authenticationSession forURL:(NSURL *)authorizationRequestURL scheme:(NSString *)scheme options:(nullable OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions)options completionHandler:(void(^)(NSURL *_Nullable callbackURL, NSError *_Nullable error))oauth2CompletionHandler
{
	OCMockAuthenticationMethodOAuth2StartAuthenticationSessionForURLSchemeCompletionHandlerBlock mockBlock;

	if ((mockBlock = [[OCMockManager sharedMockManager] mockingBlockForLocation:OCMockLocationAuthenticationMethodOAuth2StartAuthenticationSessionForURLSchemeCompletionHandler]) != nil)
	{
		return (mockBlock(authenticationSession, authorizationRequestURL, scheme, options, oauth2CompletionHandler));
	}
	else
	{
		return ([self ocm_oa2_startAuthenticationSession:authenticationSession forURL:authorizationRequestURL scheme:scheme options:options completionHandler:oauth2CompletionHandler]);
	}
}

@end

OCMockLocation OCMockLocationAuthenticationMethodOAuth2StartAuthenticationSessionForURLSchemeCompletionHandler = @"OCAuthenticationMethodOAUth2.startAuthenticationSessionForURLSchemeCompletionHandler";
