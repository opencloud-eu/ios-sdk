//
//  OCAuthenticationMethodOAuth2.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 05.02.18.
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

#import "OCAuthenticationMethod.h"
#import "OCClassSettings.h"
#import "OCAuthenticationBrowserSession.h"
#import "OCPKCE.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OCAuthenticationOAuth2TokenRequestType)
{
	OCAuthenticationOAuth2TokenRequestTypeAuthorizationCode,
	OCAuthenticationOAuth2TokenRequestTypeRefreshToken
};

typedef NS_ENUM(NSInteger, OCAuthenticationBrowserSessionPrivacy)
{
	OCAuthenticationBrowserSessionPrivacyPrivate,		//!< Ephemeral ASWebAuthenticationSession: shares no cookies with Safari or other sessions. Used whenever *other* accounts exist - when adding one, or when re-authenticating one of several.
	OCAuthenticationBrowserSessionPrivacyShared,		//!< Shares Safari's cookies as the automatic choice, because this is the only account (or none exists yet): an existing identity provider session is presumed to be this user's, so setup and re-auth can use it.
	OCAuthenticationBrowserSessionPrivacySharedBySettings	//!< Shares cookies because class settings say so - `browser-session-prefers-ephermal` = false, or a `browser-session-class` naming an external browser. Either can come from MDM, branding, user preferences or the environment.
} __attribute__((enum_extensibility(closed)));

@interface OCAuthenticationMethodOAuth2 : OCAuthenticationMethod <OCClassSettingsSupport>

@property(strong,nullable,class,nonatomic) Class browserSessionClass;

+ (BOOL)startAuthenticationSession:(__autoreleasing id _Nonnull * _Nullable)authenticationSession forURL:(NSURL *)authorizationRequestURL scheme:(NSString *)scheme options:(nullable OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions)options completionHandler:(void(^)(NSURL *_Nullable callbackURL, NSError *_Nullable error))oauth2CompletionHandler; //!< Starts a system authentication session for the provided URL, scheme and completionHandler. Used by OCAuthenticationMethodOAuth2 as interface to ASWebAuthenticationSession.
+ (OCAuthenticationBrowserSessionPrivacy)browserSessionPrivacyWithOptions:(nullable OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions)options; //!< How the browser session that -startAuthenticationSession:… opens relates to other sessions' cookies. See OCAuthenticationBrowserSessionPrivacy.

#pragma mark - PKCE support
@property(strong,nullable) OCPKCE *pkce; //!< pre-configured PKCE object to use for Proof Key for Code Exchange

#pragma mark - State
@property(strong,nullable) NSString *state; //!< pre-filled UUID string to use as state parameter (specification: https://datatracker.ietf.org/doc/html/draft-ietf-oauth-v2-1-00#section-4.1.1.3)

#pragma mark - Subclassing points
- (nullable NSURL *)authorizationEndpointURLForConnection:(OCConnection *)connection options:(OCAuthenticationMethodDetectionOptions)options;
- (nullable NSURL *)tokenEndpointURLForConnection:(OCConnection *)connection options:(OCAuthenticationMethodDetectionOptions)options;
- (NSString *)redirectURIForConnection:(OCConnection *)connection;
- (NSDictionary<NSString *, NSString *> *)prepareAuthorizationRequestParameters:(NSDictionary<NSString *,NSString *> *)parameters forConnection:(OCConnection *)connection options:(nullable OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions)options;
- (NSDictionary<NSString *, NSString *> *)tokenRefreshParametersForRefreshToken:(NSString *)refreshToken connection:(OCConnection *)connection;
- (NSDictionary<NSString *, id> *)postProcessAuthenticationDataDict:(NSDictionary<NSString *, id> *)authDataDict;
- (void)retrieveEndpointInformationForConnection:(OCConnection *)connection options:(nullable OCAuthenticationMethodDetectionOptions)options completionHandler:(void(^)(NSError * _Nullable error))completionHandler;
- (nullable NSString *)scope;
- (nullable NSString *)prompt;
- (nullable NSString *)promptForBrowserSessionPrivacy:(OCAuthenticationBrowserSessionPrivacy)privacy; //!< The `prompt` value to send in the authorization request. Default implementation returns -prompt. Subclasses can adapt it to the browser session's privacy (see +browserSessionPrivacyWithOptions:).
- (NSString *)clientID;
- (NSString *)clientSecret;
- (NSString *)tokenRequestAuthorizationHeaderForType:(OCAuthenticationOAuth2TokenRequestType)requestType connection:(OCConnection *)connection;
- (BOOL)sendClientIDAndSecretInPOSTBody;

- (void)sendTokenRequestToConnection:(OCConnection *)connection withParameters:(NSDictionary<NSString*,NSString*> *)parameters options:(nullable OCAuthenticationMethodDetectionOptions)options requestType:(OCAuthenticationOAuth2TokenRequestType)requestType completionHandler:(void(^)(NSError * _Nullable error, NSDictionary * _Nullable jsonResponseDict, NSData * _Nullable authenticationData))completionHandler;

@end

extern OCAuthenticationMethodIdentifier OCAuthenticationMethodIdentifierOAuth2;

extern OCClassSettingsKey OCAuthenticationMethodOAuth2AuthorizationEndpoint;
extern OCClassSettingsKey OCAuthenticationMethodOAuth2TokenEndpoint;
extern OCClassSettingsKey OCAuthenticationMethodOAuth2RedirectURI;
extern OCClassSettingsKey OCAuthenticationMethodOAuth2ClientID;
extern OCClassSettingsKey OCAuthenticationMethodOAuth2ClientSecret;
extern OCClassSettingsKey OCAuthenticationMethodOAuth2ExpirationOverrideSeconds;
extern OCClassSettingsKey OCAuthenticationMethodOAuth2OmitAuthorizationParameters;
extern OCClassSettingsKey OCAuthenticationMethodOAuth2PostClientIDAndSecret;

NS_ASSUME_NONNULL_END
