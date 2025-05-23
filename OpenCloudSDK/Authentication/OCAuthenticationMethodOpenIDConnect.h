//
//  OCAuthenticationMethodOpenIDConnect.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 22.05.19.
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

#import "OCAuthenticationMethodOAuth2.h"
#import "OCClassSettings.h"

NS_ASSUME_NONNULL_BEGIN

@interface OCAuthenticationMethodOpenIDConnect : OCAuthenticationMethodOAuth2
{
	NSDictionary<NSString *, id> *_openIDConfig;
}

@end

extern OCAuthenticationMethodIdentifier OCAuthenticationMethodIdentifierOpenIDConnect;

extern OCClassSettingsKey OCAuthenticationMethodOpenIDConnectRedirectURI;
extern OCClassSettingsKey OCAuthenticationMethodOpenIDConnectScope;
extern OCClassSettingsKey OCAuthenticationMethodOpenIDConnectPrompt;
extern OCClassSettingsKey OCAuthenticationMethodOpenIDRegisterClient;
extern OCClassSettingsKey OCAuthenticationMethodOpenIDRegisterClientNameTemplate;
extern OCClassSettingsKey OCAuthenticationMethodOpenIDFallbackOnClientRegistrationFailure;

NS_ASSUME_NONNULL_END
