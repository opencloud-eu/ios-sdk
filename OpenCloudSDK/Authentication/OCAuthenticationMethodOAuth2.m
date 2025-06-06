//
//  OCAuthenticationMethodOAuth2.m
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

#import <UIKit/UIKit.h>
#import "OCFeatureAvailability.h"
#if OC_FEATURE_AVAILABLE_AUTHENTICATION_SESSION
#import <AuthenticationServices/AuthenticationServices.h>
#endif /* OC_FEATURE_AVAILABLE_AUTHENTICATION_SESSION */

#import "OCAuthenticationMethodOAuth2.h"
#import "OCAuthenticationMethod+OCTools.h"
#import "OCConnection.h"
#import "NSError+OCError.h"
#import "NSURL+OCURLQueryParameterExtensions.h"
#import "OCLogger.h"
#import "OCMacros.h"
#import "OCLockManager.h"
#import "OCLockRequest.h"
#import "NSError+OCNetworkFailure.h"

#pragma mark - Internal OA2 keys
typedef NSString* OA2DictKeyPath;
static OA2DictKeyPath OA2ExpirationDate		= @"expirationDate";
static OA2DictKeyPath OA2ExpirationTimePeriod	= @"expirationTimePeriod";

static OA2DictKeyPath OA2TokenResponse  = @"tokenResponse";
static OA2DictKeyPath OA2BearerString   = @"bearerString";

// FOR ADDITIONS, ALSO UPDATE -postProcessAuthenticationDataDict: !!
static OA2DictKeyPath OA2AccessToken    = @"tokenResponse.access_token";
static OA2DictKeyPath OA2RefreshToken   = @"tokenResponse.refresh_token";
static OA2DictKeyPath OA2ExpiresInSecs  = @"tokenResponse.expires_in";
static OA2DictKeyPath OA2UserID         = @"tokenResponse.user_id";

#define OA2RefreshSafetyMarginInSeconds 120

#ifndef __IPHONE_13_0
#define __IPHONE_13_0    130000
#endif /* __IPHONE_13_0 */

static Class sBrowserSessionClass;

#if OC_FEATURE_AVAILABLE_AUTHENTICATION_SESSION
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_13_0
@interface OCAuthenticationMethodOAuth2ContextProvider : NSObject <ASWebAuthenticationPresentationContextProviding>

@property(readonly,class,strong,nonatomic) OCAuthenticationMethodOAuth2ContextProvider* sharedContextProvider;

@property(nullable,weak) UIWindow *window;

@end

@implementation OCAuthenticationMethodOAuth2ContextProvider

+ (OCAuthenticationMethodOAuth2ContextProvider *)sharedContextProvider
{
	static dispatch_once_t onceToken;
	static OCAuthenticationMethodOAuth2ContextProvider *sharedContextProvider;

	dispatch_once(&onceToken, ^{
		sharedContextProvider = [self new];
	});

	return (sharedContextProvider);
}

- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session API_AVAILABLE(ios(12.0))
{
	return (self.window);
}

@end

#endif /* __IPHONE_13_0 */
#endif /* OC_FEATURE_AVAILABLE_AUTHENTICATION_SESSION */

@interface OCAuthenticationMethodOAuth2 ()
{
	id _authenticationSession;
	BOOL _receivedUnauthorizedResponse;
	BOOL _tokenRefreshFollowingUnauthorizedResponseFailed;
}
@end

@implementation OCAuthenticationMethodOAuth2

// Automatically register
OCAuthenticationMethodAutoRegister

#pragma mark - Class settings
+ (OCClassSettingsIdentifier)classSettingsIdentifier
{
	return (@"authentication-oauth2");
}

+ (NSDictionary<NSString *,id> *)defaultSettingsForIdentifier:(OCClassSettingsIdentifier)identifier
{
	return (@{
		OCAuthenticationMethodOAuth2AuthorizationEndpoint : @"index.php/apps/oauth2/authorize",
		OCAuthenticationMethodOAuth2TokenEndpoint 	  : @"index.php/apps/oauth2/api/v1/token",
		OCAuthenticationMethodOAuth2RedirectURI 	  : @"oc://ios.opencloud.eu",
		OCAuthenticationMethodOAuth2ClientID 		  : @"OpenCloudIOS",
		OCAuthenticationMethodOAuth2ClientSecret 	  : @"",
		OCAuthenticationMethodOAuth2PostClientIDAndSecret : @(NO)
	});
    // Ref https://github.com/opencloud-eu/opencloud/blob/main/services/idp/pkg/config/defaults/defaultconfig.go#L106
}

+ (OCClassSettingsMetadataCollection)classSettingsMetadata
{
	return (@{
		// Authentication
		OCAuthenticationMethodOAuth2AuthorizationEndpoint : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeString,
			OCClassSettingsMetadataKeyDescription 	: @"OAuth2 authorization endpoint.",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusAdvanced,
			OCClassSettingsMetadataKeyCategory	: @"OAuth2"
		},
		OCAuthenticationMethodOAuth2TokenEndpoint : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeString,
			OCClassSettingsMetadataKeyDescription 	: @"OAuth2 token endpoint.",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusAdvanced,
			OCClassSettingsMetadataKeyCategory	: @"OAuth2"
		},
		OCAuthenticationMethodOAuth2RedirectURI : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeString,
			OCClassSettingsMetadataKeyDescription 	: @"OAuth2 Redirect URI.",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusAdvanced,
			OCClassSettingsMetadataKeyCategory	: @"OAuth2"
		},
		OCAuthenticationMethodOAuth2ClientID : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeString,
			OCClassSettingsMetadataKeyDescription 	: @"OAuth2 Client ID.",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusAdvanced,
			OCClassSettingsMetadataKeyCategory	: @"OAuth2"
		},
		OCAuthenticationMethodOAuth2ClientSecret : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeString,
			OCClassSettingsMetadataKeyDescription 	: @"OAuth2 Client Secret.",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusAdvanced,
			OCClassSettingsMetadataKeyCategory	: @"OAuth2"
		},
		OCAuthenticationMethodOAuth2ExpirationOverrideSeconds : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeInteger,
			OCClassSettingsMetadataKeyDescription 	: @"OAuth2 Expiration Override - lets OAuth2 tokens expire after the provided number of seconds (useful to prompt quick `refresh_token` requests for testing)",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusDebugOnly,
			OCClassSettingsMetadataKeyCategory	: @"OAuth2"
		},
		OCAuthenticationMethodOAuth2OmitAuthorizationParameters : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeStringArray,
			OCClassSettingsMetadataKeyDescription 	: @"Omit Authorization Request Parameters - parameter names provided here are omitted from OAuth2 authorization requests.",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusAdvanced,
			OCClassSettingsMetadataKeyCategory	: @"OAuth2"
		},
		OCAuthenticationMethodOAuth2PostClientIDAndSecret : @{
			OCClassSettingsMetadataKeyType 		: OCClassSettingsMetadataTypeBoolean,
			OCClassSettingsMetadataKeyDescription 	: @"Send Client ID and Client Secret in the body of POST requests to the token endpoint. As per RFC 6749 section 2.3.1, this should only be used if the token endpoint does not support receiving these via Basic authentication.",
			OCClassSettingsMetadataKeyStatus	: OCClassSettingsKeyStatusAdvanced,
			OCClassSettingsMetadataKeyCategory	: @"OAuth2"
		}
	});
}

- (instancetype)init
{
	if ((self = [super init]) != nil)
	{
		self.state = NSUUID.UUID.UUIDString;
	}

	return (self);
}

#pragma mark - Identification
+ (OCAuthenticationMethodType)type
{
	return (OCAuthenticationMethodTypeToken);
}

+ (OCAuthenticationMethodIdentifier)identifier
{
	return (OCAuthenticationMethodIdentifierOAuth2);
}

+ (NSString *)name
{
	return (@"OAuth2");
}

#pragma mark - Subclassing points
- (NSURL *)authorizationEndpointURLForConnection:(OCConnection *)connection options:(OCAuthenticationMethodDetectionOptions)options
{
	return ([connection URLForEndpointPath:[self classSettingForOCClassSettingsKey:OCAuthenticationMethodOAuth2AuthorizationEndpoint] withAlternativeURL:options[OCAuthenticationMethodWebFingerAlternativeIDPKey]]);
}

+ (NSURL *)tokenEndpointURLForConnection:(OCConnection *)connection options:(OCAuthenticationMethodDetectionOptions)options
{
	return ([connection URLForEndpointPath:[self classSettingForOCClassSettingsKey:OCAuthenticationMethodOAuth2TokenEndpoint] withAlternativeURL:options[OCAuthenticationMethodWebFingerAlternativeIDPKey]]);
}

- (NSURL *)tokenEndpointURLForConnection:(OCConnection *)connection options:(OCAuthenticationMethodDetectionOptions)options
{
	return ([self.class tokenEndpointURLForConnection:connection options:options]);
}

- (NSString *)redirectURIForConnection:(OCConnection *)connection
{
	return ([self classSettingForOCClassSettingsKey:OCAuthenticationMethodOAuth2RedirectURI]);
}

- (void)retrieveEndpointInformationForConnection:(OCConnection *)connection options:(nullable OCAuthenticationMethodDetectionOptions)options completionHandler:(nonnull void (^)(NSError * _Nullable))completionHandler
{
	completionHandler(OCError(OCErrorFeatureNotImplemented));
}

- (NSDictionary<NSString *, id> *)postProcessAuthenticationDataDict:(NSDictionary<NSString *, id> *)authDataDict
{
	NSDictionary<NSString *, id> *tokenResponseDict;

	// JSON *could* contain unneeded/unrelated NSNull.null values, which can't be serialized as NSPropertyList, so limit
	// the entries in the response dictionary to what is actually needed
	if ((tokenResponseDict = authDataDict[OA2TokenResponse]) != nil)
	{
		NSMutableDictionary<NSString *, id> *condensedAuthDataDict = [authDataDict mutableCopy];
		NSMutableDictionary<NSString *, id> *condensedTokenResponse = [NSMutableDictionary new];

		condensedTokenResponse[@"access_token"] = tokenResponseDict[@"access_token"];
		condensedTokenResponse[@"refresh_token"] = tokenResponseDict[@"refresh_token"];
		condensedTokenResponse[@"expires_in"] = tokenResponseDict[@"expires_in"];
		condensedTokenResponse[@"user_id"] = tokenResponseDict[@"user_id"];

		condensedAuthDataDict[OA2TokenResponse] = condensedTokenResponse;

		return (condensedAuthDataDict);
	}

	return (authDataDict);
}

- (nullable NSString *)scope
{
	return (nil);
}

- (nullable NSString *)prompt
{
	return (nil);
}

- (NSString *)clientID
{
	return ([self classSettingForOCClassSettingsKey:OCAuthenticationMethodOAuth2ClientID]);
}

- (NSString *)clientSecret
{
	return ([self classSettingForOCClassSettingsKey:OCAuthenticationMethodOAuth2ClientSecret]);
}

#pragma mark - Authentication / Deauthentication ("Login / Logout")
- (NSDictionary<NSString *, NSString *> *)authorizationHeadersForConnection:(OCConnection *)connection error:(NSError **)outError
{
	NSDictionary *authSecret;

	if ((authSecret = [self cachedAuthenticationSecretForConnection:connection]) != nil)
	{
		NSString *authorizationHeaderValue;

		if ((authorizationHeaderValue = [authSecret valueForKeyPath:OA2BearerString]) != nil)
		{
			return (@{
				OCHTTPHeaderFieldNameAuthorization : authorizationHeaderValue
			});
		}
	}

	return (nil);
}

#pragma mark - Authentication Method Detection
+ (NSArray<OCHTTPRequest *> *)detectionRequestsForConnection:(OCConnection *)connection options:(nullable OCAuthenticationMethodDetectionOptions)options
{
	if (OCTypedCast(options[OCAuthenticationMethodSkipWWWAuthenticateChecksKey], NSNumber).boolValue)
	{
 		// Skip if WWW-Authenticate checks are not allowed
 		return @[];
	}

	NSArray <OCHTTPRequest *> *detectionRequests = [self detectionRequestsBasedOnWWWAuthenticateMethod:@"Bearer" forConnection:connection];
	NSURL *tokenEndpointURL = [self tokenEndpointURLForConnection:connection options:options]; // Add token endpoint for detection / differenciation between OC-OAuth2 and other bearer-based auth methods (like OIDC)

	detectionRequests = [detectionRequests arrayByAddingObject:[OCHTTPRequest requestWithURL:tokenEndpointURL]];

	return (detectionRequests);
}

+ (void)detectAuthenticationMethodSupportForConnection:(OCConnection *)connection withServerResponses:(NSDictionary<NSURL *, OCHTTPRequest *> *)serverResponses options:(OCAuthenticationMethodDetectionOptions)options completionHandler:(void(^)(OCAuthenticationMethodIdentifier identifier, BOOL supported))completionHandler
{
	NSURL *tokenEndpointURL;

	if (OCTypedCast(options[OCAuthenticationMethodSkipWWWAuthenticateChecksKey], NSNumber).boolValue)
	{
		// Skip if WWW-Authenticate checks are not allowed
		completionHandler(self.identifier, NO);
		return;
	}

	if ((tokenEndpointURL = [self tokenEndpointURLForConnection:connection options:options]) != nil)
	{
		OCHTTPRequest *tokenEndpointRequest;

		if ((tokenEndpointRequest = serverResponses[tokenEndpointURL]) != nil)
		{
			if ((tokenEndpointRequest.httpResponse.status.isRedirection) ||
			    (tokenEndpointRequest.httpResponse.status.code == OCHTTPStatusCodeNOT_FOUND))
			{
				// Consider OAuth2 to be unavailable if the OAuth2 token endpoint responds with a redirect or 404
				completionHandler(self.identifier, NO);
				return;
			}
		}
	}

	[self detectAuthenticationMethodSupportBasedOnWWWAuthenticateMethod:@"Bearer" forConnection:connection withServerResponses:serverResponses completionHandler:completionHandler];
}

#pragma mark - Authentication Data Access
+ (NSString *)userNameFromAuthenticationData:(NSData *)authenticationData
{
	NSString *userName = nil;

	if (authenticationData != nil)
	{
		NSDictionary <NSString *, id> *authDataDict;

		if ((authDataDict = [NSPropertyListSerialization propertyListWithData:authenticationData options:NSPropertyListImmutable format:NULL error:NULL]) != nil)
		{
			return (authDataDict[OA2TokenResponse][@"user_id"]);
		}
	}

	return (userName);
}

#pragma mark - Generate bookmark authentication data
- (NSDictionary<NSString *,NSString *> *)prepareAuthorizationRequestParameters:(NSDictionary<NSString *,NSString *> *)parameters forConnection:(OCConnection *)connection options:(OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions)options
{
	// ** Implementation for OC OAuth2 - commented out because ASWebAuthenticationSession and Safari crash (in Simulator and iOS device - 14.2.1) **
	// ** Test URL: https://demo.opencloud.eu/index.php/apps/oauth2/authorize?response_type=code&redirect_uri=oc://ios.opencloud.eu&client_id=OpenCloudIOS&user=test **

	// Limited to iOS 15+, because with previous server and iOS versions, providing the user name
	// led to a crash in ASWebAuthenticationSession and Safari in Simulator + on device (see above).
	// Successfully tested with iOS 15.1 and OpenCloud 10.8.0.4.
	if (@available(iOS 15.1, *))
	{
		NSString *username;

		// From options: used with webfinger server locator
		username = options[OCAuthenticationMethodUsernameKey];

		// From bookmark: used for re-authentication
		if (username == nil)
		{
			username = connection.bookmark.userName;
		}

		if (username != nil)
		{
			NSMutableDictionary<NSString *,NSString *> *mutableParameters = [parameters mutableCopy];

			mutableParameters[@"user"] = username;

			return (mutableParameters);
		}
	}

	return (parameters);
}

- (void)generateBookmarkAuthenticationDataWithConnection:(OCConnection *)connection options:(OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions)options completionHandler:(void(^)(NSError *error, OCAuthenticationMethodIdentifier authenticationMethodIdentifier, NSData *authenticationData))completionHandler
{
	if (completionHandler==nil) { return; }
	
	if ((options[OCAuthenticationMethodPresentingViewControllerKey] != nil) && (connection!=nil))
	{
		NSURL *authorizationRequestURL;
		NSArray<NSString *> *omitAuthorizationParameters;

		// Generate Authorization Request URL
		NSDictionary<NSString *,NSString *> *parameters = @{
			// OAuth2
			@"response_type"  	 : @"code",
			@"client_id" 	  	 : [self clientID],
			@"redirect_uri"   	 : [self redirectURIForConnection:connection],

			@"state"		 : (self.state != nil) ? self.state : ((NSString *)NSNull.null),

			// OAuth2 PKCE
			@"code_challenge" 	 : (self.pkce.codeChallenge != nil) ? self.pkce.codeChallenge : ((NSString *)NSNull.null),
			@"code_challenge_method" : (self.pkce.method != nil) ? self.pkce.method : ((NSString *)NSNull.null),

			// OIDC
			@"scope"	  	 : (self.scope != nil)  ? self.scope  : ((NSString *)NSNull.null),
			@"prompt"		 : (self.prompt != nil) ? self.prompt : ((NSString *)NSNull.null)
		};

		parameters = [self prepareAuthorizationRequestParameters:parameters forConnection:connection options:options];

		// Omit parameters from authorization as per settings (default: none)
		if ((parameters != nil) && ((omitAuthorizationParameters = [self classSettingForOCClassSettingsKey:OCAuthenticationMethodOAuth2OmitAuthorizationParameters]) != nil))
		{
			NSMutableDictionary<NSString *, NSString *> *mutableParameters = [parameters mutableCopy];

			for (NSString *omitParameter in omitAuthorizationParameters)
			{
				[mutableParameters removeObjectForKey:omitParameter];
			}

			parameters = mutableParameters;
		}

		// Compose authorization request
		authorizationRequestURL = [[self authorizationEndpointURLForConnection:connection options:options] urlByAppendingQueryParameters:parameters replaceExisting:NO];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			void (^oauth2CompletionHandler)(NSURL *callbackURL, NSError *error) = ^(NSURL *callbackURL, NSError *error) {

				OCLogDebug(@"Auth session returned with callbackURL=%@, error=%@", OCLogPrivate(callbackURL), error);

				// Handle authentication session result
				if ((error == nil) && (self.state != nil))
				{
					// Verify "state" requirements from https://datatracker.ietf.org/doc/html/draft-ietf-oauth-v2-1-00#name-authorization-response
					NSString *returnedState;

					if ((returnedState = callbackURL.queryParameters[@"state"]) != nil)
					{
						if (![returnedState isEqual:self.state])
						{
							// Returned "state" differs from the "state" that was sent
							error = OCError(OCErrorAuthorizationFailed);
						}
					}
					else
					{
						// If "state" was sent with the authorization request, it is REQUIRED to be returned
						error = OCError(OCErrorAuthorizationFailed);
					}
				}

				if (error == nil)
				{
					NSString *authorizationCode;

					// Obtain Authorization Code
					if ((authorizationCode = callbackURL.queryParameters[@"code"]) != nil)
					{
						OCLogDebug(@"Auth session concluded with authorization code: %@", OCLogPrivate(authorizationCode));

						// Send Access Token Request
						[self 	sendTokenRequestToConnection:connection
						       	withParameters:@{
								// OAuth2
								@"grant_type"    : @"authorization_code",
								@"code"		 : authorizationCode,
								@"redirect_uri"  : [self redirectURIForConnection:connection],

								// OAuth2 PKCE
								@"code_verifier" : (self.pkce.codeVerifier != nil) ? self.pkce.codeVerifier : ((NSString *)NSNull.null)
							}
							options:options
							requestType:OCAuthenticationOAuth2TokenRequestTypeAuthorizationCode
							completionHandler:^(NSError *error, NSDictionary *jsonResponseDict, NSData *authenticationData){
								OCLogDebug(@"Bookmark generation concludes with error=%@", error);
								completionHandler(error, self.class.identifier, authenticationData);
							}
						];
					}
					else
					{
						// No code was supplied in callback URL
						error = OCError(OCErrorAuthorizationFailed);
					}
				}

				if (error != nil)
				{
					#if OC_FEATURE_AVAILABLE_AUTHENTICATION_SESSION
					if ([error.domain isEqual:ASWebAuthenticationSessionErrorDomain] && (error.code == ASWebAuthenticationSessionErrorCodeCanceledLogin))
					{
						// User cancelled authorization
						error = OCError(OCErrorAuthorizationCancelled);
					}
					#endif /* OC_FEATURE_AVAILABLE_AUTHENTICATION_SESSION */

					// Return errors
					completionHandler(error, self.class.identifier, nil);

					OCLogDebug(@"Auth session concluded with error=%@", error);
				}

				// Release Authentication Session
				self->_authenticationSession = nil;
			};

			// Create and start authentication session on main thread
			BOOL authSessionDidStart;
			id authSession = nil;

			OCLogDebug(@"Starting auth session with URL %@", authorizationRequestURL);

			authSessionDidStart = [self.class startAuthenticationSession:&authSession forURL:authorizationRequestURL scheme:[[NSURL URLWithString:[self redirectURIForConnection:connection]] scheme] options:options completionHandler:oauth2CompletionHandler];

			self->_authenticationSession = authSession;

			OCLogDebug(@"Started (%d) auth session %@", authSessionDidStart, self->_authenticationSession);
		});
	}
	else
	{
		completionHandler(OCError(OCErrorInsufficientParameters), self.class.identifier, nil);
	}
}

+ (Class)browserSessionClass
{
	if (sBrowserSessionClass == nil)
	{
		NSString *className;

		if ((className = [OCAuthenticationMethod classSettingForOCClassSettingsKey:OCAuthenticationMethodBrowserSessionClass]) != nil)
		{
			if (![className isEqual:@"operating-system"])
			{
				Class browserSessionClass;

				if ((browserSessionClass = NSClassFromString([@"OCAuthenticationBrowserSession" stringByAppendingString:className])) != Nil)
				{
					return (browserSessionClass);
				}
			}
		}
	}

	return (sBrowserSessionClass);
}

+ (void)setBrowserSessionClass:(Class)browserSessionClass
{
	sBrowserSessionClass = browserSessionClass;
}

+ (BOOL)startAuthenticationSession:(__autoreleasing id *)authenticationSession forURL:(NSURL *)authorizationRequestURL scheme:(NSString *)scheme options:(nullable OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions)options completionHandler:(void(^)(NSURL *_Nullable callbackURL, NSError *_Nullable error))oauth2CompletionHandler
{
	BOOL authSessionDidStart = NO;

	if (self.browserSessionClass != Nil)
	{
		OCAuthenticationBrowserSession *browserSession;

		// Create custom browser session class
		if ((browserSession = [[self.browserSessionClass alloc] initWithURL:authorizationRequestURL callbackURLScheme:scheme options:options completionHandler:oauth2CompletionHandler]) != nil)
		{
			*authenticationSession = browserSession;

			// Start authentication session
			authSessionDidStart = [browserSession start];
		}
	}
	#if OC_FEATURE_AVAILABLE_AUTHENTICATION_SESSION
	else
	{
		ASWebAuthenticationSession *webAuthenticationSession;

		webAuthenticationSession = [[ASWebAuthenticationSession alloc] initWithURL:authorizationRequestURL callbackURLScheme:scheme completionHandler:oauth2CompletionHandler];

		#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_13_0
		if (@available(iOS 13, *))
		{
			NSNumber *prefersEphermalNumber;

			if ((prefersEphermalNumber = OCTypedCast([OCAuthenticationMethod classSettingForOCClassSettingsKey:OCAuthenticationMethodBrowserSessionPrefersEphermal], NSNumber)) != nil)
			{
				webAuthenticationSession.prefersEphemeralWebBrowserSession = prefersEphermalNumber.boolValue;
			}

			UIWindow *window = OCTypedCast(options[OCAuthenticationMethodPresentingViewControllerKey], UIViewController).view.window;

			if (window == nil)
			{
				Class uiApplicationClass = NSClassFromString(@"UIApplication");
				UIApplication *sharedApplication = [uiApplicationClass valueForKey:@"sharedApplication"];
				window = sharedApplication.delegate.window;
			}

			OCAuthenticationMethodOAuth2ContextProvider.sharedContextProvider.window = window;
			webAuthenticationSession.presentationContextProvider = OCAuthenticationMethodOAuth2ContextProvider.sharedContextProvider;
		}
		#endif /* __IPHONE_13_0 */

		*authenticationSession = webAuthenticationSession;

		// Start authentication session
		authSessionDidStart = [webAuthenticationSession start];
	}
	#endif /* OC_FEATURE_AVAILABLE_AUTHENTICATION_SESSION */

	return (authSessionDidStart);
}

#pragma mark - Authentication Secret Caching
- (id)loadCachedAuthenticationSecretForConnection:(OCConnection *)connection
{
	NSData *authenticationData;
	
	if ((authenticationData = connection.bookmark.authenticationData) != nil)
	{
		_cachedAuthenticationDataID = [self.class authenticationDataIDForAuthenticationData:authenticationData];
		return ([NSPropertyListSerialization propertyListWithData:authenticationData options:NSPropertyListImmutable format:NULL error:NULL]);
	}
	
	return (nil);
}

#pragma mark - Wait for authentication
- (BOOL)canSendAuthenticatedRequestsForConnection:(OCConnection *)connection withAvailabilityHandler:(OCConnectionAuthenticationAvailabilityHandler)availabilityHandler
{
	NSDictionary<NSString *, id> *authSecret;

	if (self.authenticationDataKnownInvalidDate != nil)
	{
		// Authentication data known to be invalid
		availabilityHandler(OCErrorWithDescription(OCErrorAuthorizationFailed, OCLocalizedString(@"Previous token refresh attempts indicated an invalid refresh token.",nil)), NO);
		return (NO);
	}

	if ((authSecret = [self cachedAuthenticationSecretForConnection:connection]) != nil)
	{
		NSTimeInterval timeLeftUntilExpiration = [((NSDate *)[authSecret valueForKeyPath:OA2ExpirationDate]) timeIntervalSinceNow];
		NSTimeInterval preemtiveRefreshThreshold = 0;
		NSNumber *expiresInSeconds = [authSecret valueForKeyPath:OA2ExpirationTimePeriod];
		BOOL preemtiveTokenRenewal = NO;

		if (expiresInSeconds.integerValue > (OA2RefreshSafetyMarginInSeconds + 20))
		{
			// Expiration happening not before (OA2RefreshSafetyMarginInSeconds + 20) seconds
			preemtiveRefreshThreshold = OA2RefreshSafetyMarginInSeconds;
		}
		else
		{
			// Expiration happening before (OA2RefreshSafetyMarginInSeconds + 20) seconds, do not perform preemtive refresh (would lead to infinite loop)
			preemtiveRefreshThreshold = 0;
		}

		// Get a new token up to OA2RefreshSafetyMarginInSeconds seconds before the old one expires - or when an unauthorized response was received
		preemtiveTokenRenewal = (timeLeftUntilExpiration < preemtiveRefreshThreshold);

		if (preemtiveTokenRenewal)
		{
			// Ensure there wasn't a token refresh in the meantime we didn't get notified about (yet)
			// - flush cached secret
			[self flushCachedAuthenticationSecret];

			// - load secret from keychain
			if ((authSecret = [self cachedAuthenticationSecretForConnection:connection]) != nil)
			{
				timeLeftUntilExpiration = [((NSDate *)[authSecret valueForKeyPath:OA2ExpirationDate]) timeIntervalSinceNow];

				// - check preemtive condition again
				preemtiveTokenRenewal = (timeLeftUntilExpiration < preemtiveRefreshThreshold);
			}
		}

		if (preemtiveTokenRenewal || _receivedUnauthorizedResponse)
		{
			OCLogDebug(@"OAuth2 token expired (reason: %d:%d, date: %@, timeout period: %@ secs) - refreshing token for connection..", preemtiveTokenRenewal, _receivedUnauthorizedResponse, authSecret[OA2ExpirationDate], authSecret[OA2ExpirationTimePeriod]);
			[self _refreshTokenForConnection:connection availabilityHandler:availabilityHandler];

			return (NO);
		}
		
		// Token is still valid
		return (YES);
	}
	
	// No secret
	availabilityHandler(OCError(OCErrorAuthorizationNoMethodData), NO);

	return (NO);
}

#pragma mark - Handle responses before they are delivered to the request senders
- (NSError *)handleRequest:(OCHTTPRequest *)request response:(OCHTTPResponse *)response forConnection:(OCConnection *)connection withError:(NSError *)error
{
	if ((error = [super handleRequest:request response:response forConnection:connection withError:error]) != nil)
	{
		if (response.status.code == OCHTTPStatusCodeUNAUTHORIZED)
		{
			// Check if the token has changed between sending the request and receiving the response
			if (OCNANotEqual(response.authenticationDataID, connection.bookmark.authenticationDataID))
			{
				// Force reload of secret from authentication data
				[self flushCachedAuthenticationSecret];

				// Reschedule the request
				error = OCError(OCErrorAuthorizationRetry);

				OCLogWarning(@"Received UNAUTHORIZED response to a request with an outdated token. Retrying request to %@ with latest token.", request.url.absoluteString);
			}
			else
			{
				// Token unchanged and probably invalid.
				// => Attempt token refresh. If that fails, too, the token has become invalid and an error should be issued to the user.
				if (!_receivedUnauthorizedResponse)
				{
					// Unexpected 401 response - request a retry that'll also invoke canSendAuthenticatedRequestsForConnection:withAvailabilityHandler:
					// which will attempt a token refresh
					_receivedUnauthorizedResponse = YES;
					OCLogError(@"Received unexpected UNAUTHORIZED response. tokenRefreshFollowingUnauthorizedResponseFailed=%d (known invalid %@)", _tokenRefreshFollowingUnauthorizedResponseFailed, self.authenticationDataKnownInvalidDate);
				}

				if (!_tokenRefreshFollowingUnauthorizedResponseFailed)
				{
					error = OCError(OCErrorAuthorizationRetry);
				}
			}
		}

		OCErrorAddDateFromResponse(error, response);
	}

	return (error);
}

#pragma mark - Token management
- (NSDictionary<NSString *, NSString *> *)tokenRefreshParametersForRefreshToken:(NSString *)refreshToken connection:(OCConnection *)connection
{
	return (@{
		@"grant_type"    : @"refresh_token",
		@"refresh_token" : refreshToken,
	});
}

- (NSString *)tokenRequestAuthorizationHeaderForType:(OCAuthenticationOAuth2TokenRequestType)requestType connection:(OCConnection *)connection
{
	return ([OCAuthenticationMethod basicAuthorizationValueForUsername:self.clientID passphrase:self.clientSecret]);
}

- (void)_refreshTokenForConnection:(OCConnection *)connection availabilityHandler:(OCConnectionAuthenticationAvailabilityHandler)availabilityHandler
{
	__weak OCAuthenticationMethodOAuth2 *weakSelf = self;

	OCLockRequest *lockRequest = [[OCLockRequest alloc] initWithResourceIdentifier:[NSString stringWithFormat:@"authentication-data-update:%@", connection.bookmark.uuid.UUIDString] acquiredHandler:^(NSError * _Nullable error, OCLock * _Nullable lock) {
		// Wait for exclusive lock on authentication data before performing the refresh
		[weakSelf __refreshTokenForConnection:connection availabilityHandler:^(NSError *error, BOOL authenticationIsAvailable) {
			// Invoke original availabilityHandler
			availabilityHandler(error, authenticationIsAvailable);

			// Release lock
			[lock releaseLock];
		}];
	}];

	[OCLockManager.sharedLockManager requestLock:lockRequest];
}

- (void)__refreshTokenForConnection:(OCConnection *)connection availabilityHandler:(OCConnectionAuthenticationAvailabilityHandler)availabilityHandler
{
	NSDictionary<NSString *, id> *authSecret;
	NSError *error=nil;

	OCLogDebug(@"Token refresh started");

	[self flushCachedAuthenticationSecret];

	if ((authSecret = [self cachedAuthenticationSecretForConnection:connection]) != nil)
	{
		NSString *refreshToken;

		if ((refreshToken = [authSecret valueForKeyPath:OA2RefreshToken]) != nil)
		{
			OCLogDebug(@"Sending token refresh request for connection (expiry=%@)..", authSecret[OA2ExpirationDate]);

			[self 	sendTokenRequestToConnection:connection
				withParameters:[self tokenRefreshParametersForRefreshToken:refreshToken connection:connection]
				options:nil
				requestType:OCAuthenticationOAuth2TokenRequestTypeRefreshToken
				completionHandler:^(NSError *error, NSDictionary *jsonResponseDict, NSData *authenticationData){
					OCLogDebug(@"Token refresh finished with error=%@, jsonResponseDict=%@", error, OCLogPrivate(jsonResponseDict));

					// Update authentication data of the bookmark
					if ((error==nil) && (authenticationData!=nil))
					{
						OCLogDebug(@"Updating authentication data for bookmarkUUID=%@", connection.bookmark.uuid);
						connection.bookmark.authenticationData = authenticationData;

						OCLogDebug(@"Authentication data updated: flush auth secret for bookmarkUUID=%@", connection.bookmark.uuid);
						[self flushCachedAuthenticationSecret];
					}
					else
					{
						// Did not receive update
						if ((error == nil) || ((error != nil) && !error.isNetworkFailureError))
						{
							// Not a network failure, either, so handle as actual error refreshing the token
							[self willChangeValueForKey:@"authenticationDataKnownInvalidDate"];
							self->_authenticationDataKnownInvalidDate = [NSDate new];
							[self didChangeValueForKey:@"authenticationDataKnownInvalidDate"];
						}
					}

					if (self->_receivedUnauthorizedResponse)
					{
						if (error != nil)
						{
							// Token refresh following UNAUTHORIZED response failed
							self->_tokenRefreshFollowingUnauthorizedResponseFailed = YES;
						}
						else
						{
							// Token refresh fixed the issue
							self->_receivedUnauthorizedResponse = NO;
							self->_tokenRefreshFollowingUnauthorizedResponseFailed = NO;
						}
					}
				
					availabilityHandler(error, (error==nil));
				}
			];
		}
		else
		{
			// Missing data in secret
			error = OCError(OCErrorAuthorizationMissingData);
		}
	}
	else
	{
		// No secret
		error = OCError(OCErrorAuthorizationNoMethodData);
	}

	if (error != nil)
	{
		OCLogDebug(@"Token can't be refreshed due to error=%@", error);

		if (availabilityHandler!=nil)
		{
			availabilityHandler(error, NO);
		}
	}
}

- (void)sendTokenRequestToConnection:(OCConnection *)connection withParameters:(NSDictionary<NSString*,NSString*> *)parameters options:(OCAuthenticationMethodDetectionOptions)options requestType:(OCAuthenticationOAuth2TokenRequestType)requestType completionHandler:(void(^)(NSError *error, NSDictionary *jsonResponseDict, NSData *authenticationData))completionHandler
{
	OCHTTPRequest *tokenRequest;
	NSDictionary<NSString *, id> *previousAuthSecret = (requestType == OCAuthenticationOAuth2TokenRequestTypeRefreshToken) ? [self cachedAuthenticationSecretForConnection:connection] : nil;
	NSString *previousRefreshToken = (requestType == OCAuthenticationOAuth2TokenRequestTypeRefreshToken) ? parameters[@"refresh_token"] : nil;

	OCLogDebug(@"Sending token request with parameters: %@", OCLogPrivate(parameters));

	// Remove nil values
	NSMutableDictionary *sanitizedParameters = [NSMutableDictionary new];

	for (NSString *key in parameters)
	{
		if (![parameters[key] isKindOfClass:[NSNull class]])
		{
			sanitizedParameters[key] = parameters[key];
		}
	}

	parameters = sanitizedParameters;

	// Check for endpoint
	NSURL *tokenEndpointURL = [self tokenEndpointURLForConnection:connection options:options];

	if (tokenEndpointURL == nil)
	{
		// No token endpoint URL known => retrieve it first.
		[self retrieveEndpointInformationForConnection:connection options:options completionHandler:^(NSError * _Nonnull error) {
			if (error == nil)
			{
				[self sendTokenRequestToConnection:connection withParameters:parameters options:options requestType:requestType completionHandler:completionHandler];
			}
			else
			{
				if (completionHandler != nil)
				{
					completionHandler(error, nil, nil);
				}
			}
		}];

		// Don't proceed past this point
		return;
	}

	// Compose Token Request
	if ((tokenRequest = [OCHTTPRequest requestWithURL:tokenEndpointURL]) != nil)
	{
		tokenRequest.method = OCHTTPMethodPOST; // Use POST
		tokenRequest.requiredSignals = connection.authSignals;
		
		[tokenRequest addParameters:parameters];

		// Add client ID and client secret as authentication header or as parameters
		if ([self sendClientIDAndSecretInPOSTBody])
		{
			// Include Client ID and Client Secret as parameters in the POST body
			//
			// As per https://datatracker.ietf.org/doc/html/rfc6749#section-2.3.1:
			// > Alternatively, the authorization server MAY support including the
			// > client credentials in the request-body using the following parameters:
			// > 	client_id …
			// > 	client_secret …
			// > …
			// > Including the client credentials in the request-body using the two
			// > parameters is NOT RECOMMENDED and SHOULD be limited to clients unable
			// > to directly utilize the HTTP Basic authentication scheme (or other
			// > password-based HTTP authentication schemes).  The parameters can only
			// > be transmitted in the request-body and MUST NOT be included in the
			// > request URI.

			NSString *clientID = self.clientID, *clientSecret = self.clientSecret;

			if ((clientID != nil) && (clientSecret != nil))
			{
				[tokenRequest addParameters:@{
					@"client_id" : clientID,
					@"client_secret" : clientSecret
				}];
			}
		}
		else
		{
			// Include Client ID and Client Secret as header
			[tokenRequest setValue:[self tokenRequestAuthorizationHeaderForType:requestType connection:connection] forHeaderField:OCHTTPHeaderFieldNameAuthorization];
		}

		// Send Token Request
		[connection sendRequest:tokenRequest ephermalCompletionHandler:^(OCHTTPRequest *request, OCHTTPResponse *response, NSError *error) {
			OCLogDebug(@"Received token request result (error=%@)", error);

			// Handle Token Request Result
			if (error == nil)
			{
				NSDictionary<NSString *, id> *jsonResponseDict;
				NSError *jsonDecodeError = nil;
				
				if ((jsonResponseDict = [response bodyConvertedDictionaryFromJSONWithError:&jsonDecodeError]) != nil)
				{
					NSString *jsonError;

					OCLogDebug(@"Received token request response: %@", OCLogPrivate(jsonResponseDict));

					if ((jsonError = jsonResponseDict[@"error"]) != nil)
					{
						// Handle errors coming from JSON response
						NSDictionary *errorInfo = @{
							@"authMethod" : self.class.identifier,
							@"jsonError" : jsonError
						};

						OCLogDebug(@"Token authorization failed with error=%@", OCLogPrivate(jsonError));

						error = OCErrorWithInfo(OCErrorAuthorizationFailed, errorInfo);
					}
					else if ((jsonResponseDict[@"refresh_token"] == nil) && (previousRefreshToken == nil) && (requestType == OCAuthenticationOAuth2TokenRequestTypeRefreshToken))
					{
						// Token response did not contain a new refresh_token! Authentication refresh would fail with next token renewal.
						OCLogError(@"Token response did not contain a new refresh_token! Next token refresh would fail. Returning authorization failed error.");

						error = OCErrorWithDescription(OCErrorAuthorizationFailed, @"The token refresh response did not contain a new refresh_token.");
					}
					else
					{
						// Success
						NSDate *validUntil = nil;
						NSNumber *expiresInSeconds = nil;
						NSString *bearerString;

						// Compute expiration date
						if (jsonResponseDict[@"expires_in"] != nil)
						{
							validUntil = [NSDate dateWithTimeIntervalSinceNow:[jsonResponseDict[@"expires_in"] integerValue]];
							expiresInSeconds = @([jsonResponseDict[@"expires_in"] integerValue]);
						}
						else
						{
							validUntil = [NSDate dateWithTimeIntervalSinceNow:3600];
							expiresInSeconds = @(3600);
						}

						// #warning !! REMOVE LINE BELOW - FOR TESTING TOKEN RENEWAL ONLY !!
						// validUntil = [NSDate dateWithTimeIntervalSinceNow:130];
						NSNumber *expirationOverrideSeconds;

						if ((expirationOverrideSeconds = [self classSettingForOCClassSettingsKey:OCAuthenticationMethodOAuth2ExpirationOverrideSeconds]) != nil)
						{
							OCLogWarning(@"Overriding expiration time of %@ with %@ as per class settings", jsonResponseDict[@"expires_in"], expirationOverrideSeconds);
							validUntil = [NSDate dateWithTimeIntervalSinceNow:OA2RefreshSafetyMarginInSeconds + expirationOverrideSeconds.doubleValue];
							expiresInSeconds = @(OA2RefreshSafetyMarginInSeconds + expirationOverrideSeconds.integerValue);
						}

						// Reuse refresh_token if no new one was provided
						if ((jsonResponseDict[@"refresh_token"] == nil) && (previousRefreshToken != nil) && (requestType == OCAuthenticationOAuth2TokenRequestTypeRefreshToken))
						{
							jsonResponseDict = [jsonResponseDict mutableCopy];
							[((NSMutableDictionary *)jsonResponseDict) setObject:parameters[@"refresh_token"] forKey:@"refresh_token"];
						}

						// Compute bearer string
						bearerString = [NSString stringWithFormat:@"Bearer %@", jsonResponseDict[@"access_token"]];

						// Finalize
						void (^CompleteWithJSONResponseDict)(NSDictionary *jsonResponseDict, BOOL tolerateMissingUserID) = ^(NSDictionary *jsonResponseDict, BOOL tolerateMissingUserID) {
							NSError *error = nil;
							NSDictionary *authenticationDataDict;
							NSData *authenticationData;
							NSString *requiredUserID;

							if ((requiredUserID = options[OCAuthenticationMethodRequiredUsernameKey]) != nil)
							{
								NSString *newUserID;
								NSError *error = nil;

								if ((newUserID = jsonResponseDict[@"user_id"]) != nil)
								{
									if (![requiredUserID isEqual:newUserID])
									{
										error = OCErrorWithDescription(OCErrorAuthorizationNotMatchingRequiredUserID, ([NSString stringWithFormat:OCLocalizedString(@"You logged in as user %@, but must log in as user %@. Please retry.",nil), newUserID, requiredUserID]));
									}
								}
								else if (!tolerateMissingUserID)
								{
									error = OCErrorWithDescription(OCErrorAuthorizationNotMatchingRequiredUserID, ([NSString stringWithFormat:OCLocalizedString(@"Login as user %@ required. Please retry.",nil), requiredUserID]));
								}

								if (error != nil)
								{
									completionHandler(error, nil, nil);
									return;
								}
							}

							authenticationDataDict = @{
								OA2ExpirationDate 	: validUntil,
								OA2ExpirationTimePeriod	: expiresInSeconds,
								OA2BearerString   	: bearerString,
								OA2TokenResponse  	: jsonResponseDict
							};

							// Give opportunity to add additional keys
							authenticationDataDict = [self postProcessAuthenticationDataDict:authenticationDataDict];

							OCLogDebug(@"Token authorization succeeded with: %@", OCLogPrivate(authenticationDataDict));

							if ((authenticationData = [NSPropertyListSerialization dataWithPropertyList:authenticationDataDict format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error]) != nil)
							{
								completionHandler(nil, jsonResponseDict, authenticationData);
							}
							else if (error != nil)
							{
								completionHandler(OCErrorFromError(OCErrorInternal, error), nil, nil);
							}
							else if (error == nil)
							{
								completionHandler(OCError(OCErrorInternal), nil, nil);
							}
						};

						if ((jsonResponseDict[@"user_id"] == nil) && (requestType == OCAuthenticationOAuth2TokenRequestTypeRefreshToken) && (previousAuthSecret != nil) && ([previousAuthSecret valueForKeyPath:OA2UserID] != nil))
						{
							// Reuse user name if it was already known
							jsonResponseDict = [jsonResponseDict mutableCopy];
							[((NSMutableDictionary *)jsonResponseDict) setObject:[previousAuthSecret valueForKeyPath:OA2UserID] forKey:@"user_id"];
						}

						if (jsonResponseDict[@"user_id"] == nil)
						{
							// Retrieve user_id if it wasn't provided with the token request response
							if (options[OCAuthenticationMethodWebFingerAccountLookupURLKey] != nil)
							{
								// user_id can't be retrieved at this time as final instance is still to be determined - will be fetched on first full -connect:
								CompleteWithJSONResponseDict(jsonResponseDict, YES);
							}
							else
							{
								// Retrieve user_id from the user endpoint
								[connection retrieveLoggedInUserWithRequestCustomization:^(OCHTTPRequest * _Nonnull request) {
									request.requiredSignals = nil;
									[request setValue:bearerString forHeaderField:OCHTTPHeaderFieldNameAuthorization];
								} completionHandler:^(NSError * _Nullable error, OCUser * _Nullable loggedInUser) {
									if (error == nil)
									{
										NSMutableDictionary *jsonResponseUpdated = [jsonResponseDict mutableCopy];

										jsonResponseUpdated[@"user_id"] = loggedInUser.userName;

										CompleteWithJSONResponseDict(jsonResponseUpdated, NO);
									}
									else
									{
										// Return error
										completionHandler(error, nil, nil);
									}
								}];
							}
						}
						else
						{
							// user_id was already provided - we're all set!
							CompleteWithJSONResponseDict(jsonResponseDict, NO);
						}
					}
				}
				else
				{
					OCLogError(@"Decoding token response JSON failed with error %@", jsonDecodeError);

					if (jsonDecodeError == nil)
					{
						// Empty response
						error = OCErrorWithDescription(OCErrorAuthorizationFailed, @"The token refresh response was empty.");
					}
					else
					{
						// Malformed response
						error = OCErrorWithDescription(OCErrorAuthorizationFailed, @"Malformed token refresh response.");
					}
				}
			}
			
			if (error != nil)
			{
				// Return error
				completionHandler(error, nil, nil);
			}
		}];
	}
	else
	{
		// Internal error
		completionHandler(OCError(OCErrorInternal), nil, nil);
	}
}

- (BOOL)sendClientIDAndSecretInPOSTBody
{
	NSNumber *forcePostClientIDAndSecret = [self classSettingForOCClassSettingsKey:OCAuthenticationMethodOAuth2PostClientIDAndSecret];
	return ((forcePostClientIDAndSecret != nil) && forcePostClientIDAndSecret.boolValue);
}

@end

OCAuthenticationMethodIdentifier OCAuthenticationMethodIdentifierOAuth2 = @"com.opencloud.oauth2";

OCClassSettingsKey OCAuthenticationMethodOAuth2AuthorizationEndpoint = @"oa2-authorization-endpoint";
OCClassSettingsKey OCAuthenticationMethodOAuth2TokenEndpoint = @"oa2-token-endpoint";
OCClassSettingsKey OCAuthenticationMethodOAuth2RedirectURI = @"oa2-redirect-uri";
OCClassSettingsKey OCAuthenticationMethodOAuth2ClientID = @"oa2-client-id";
OCClassSettingsKey OCAuthenticationMethodOAuth2ClientSecret = @"oa2-client-secret";
OCClassSettingsKey OCAuthenticationMethodOAuth2ExpirationOverrideSeconds = @"oa2-expiration-override-seconds";
OCClassSettingsKey OCAuthenticationMethodOAuth2OmitAuthorizationParameters = @"omit-authorization-parameters";
OCClassSettingsKey OCAuthenticationMethodOAuth2PostClientIDAndSecret = @"post-client-id-and-secret";
