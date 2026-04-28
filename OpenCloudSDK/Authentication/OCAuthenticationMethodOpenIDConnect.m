//
//  OCAuthenticationMethodOpenIDConnect.m
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

#import "OCAuthenticationMethodOpenIDConnect.h"
#import "OCAuthenticationMethod+OCTools.h"
#import "OCConnection.h"
#import "OCLogger.h"
#import "OCMacros.h"
#import "OCHTTPRequest+JSON.h"
#import "NSError+OCError.h"
#import "NSURL+OCURLQueryParameterExtensions.h"

#pragma mark - Internal OA2 keys
typedef NSString* OIDCDictKeyPath;
static OIDCDictKeyPath OIDCKeyPathClientRegistrationResponseSerialized	= @"clientRegistrationResponseSerialized";
static OIDCDictKeyPath OIDCKeyPathClientRegistrationEndpointURL 	= @"clientRegistrationEndpointURL";
static OIDCDictKeyPath OIDCKeyPathClientRegistrationExpirationDate	= @"clientRegistrationExpirationDate";
static OIDCDictKeyPath OIDCKeyPathClientID				= @"clientRegistrationClientID";
static OIDCDictKeyPath OIDCKeyPathClientSecret				= @"clientRegistrationClientSecret";
static OIDCDictKeyPath OIDCKeyPathWebFingerClientID			= @"webFingerClientID";
static OIDCDictKeyPath OIDCKeyPathWebFingerScope			= @"webFingerScope";
static OIDCDictKeyPath OIDCKeyPathWebFingerIssuerURL			= @"webFingerIssuerURL";
static OIDCDictKeyPath OIDCKeyPathPreferredUsername			= @"preferredUsername";
static OIDCDictKeyPath OIDCKeyPathIsPublicClient			= @"isPublicClient";

@implementation OCAuthenticationMethodOpenIDConnect
{
	NSDictionary<NSString *, id> *_clientRegistrationResponse; // JSON response from client registration
	NSURL *_clientRegistrationEndpointURL; // URL the client registration was last performed at
	NSDate *_clientRegistrationExpirationDate; // nil if it does not expire, the expiry date if it expires

	NSString *_clientName;
	NSString *_clientID;
	NSString *_clientSecret;

	BOOL _isPublicClientPersisted; // Persisted from OIDC discovery — survives token refresh when _openIDConfig is nil
}

#pragma mark - Class settings
+ (void)load
{
	// Automatically register
	OCAuthenticationMethodAutoRegisterLoadCommand

	[self registerOCClassSettingsDefaults:@{
		OCAuthenticationMethodOpenIDConnectRedirectURI : @"oc://ios.opencloud.eu",
		OCAuthenticationMethodOpenIDConnectScope       : @"openid offline_access email profile",
		OCAuthenticationMethodOpenIDConnectPrompt      : @"select_account consent",
		OCAuthenticationMethodOpenIDRegisterClient     : @(YES),
		OCAuthenticationMethodOpenIDRegisterClientNameTemplate : @"OpenCloud/{{os.name}} {{app.version}}",
		OCAuthenticationMethodOpenIDFallbackOnClientRegistrationFailure : @(YES)
	} metadata:@{
		OCAuthenticationMethodOpenIDConnectRedirectURI : @{
			OCClassSettingsMetadataKeyType 	      : OCClassSettingsMetadataTypeString,
			OCClassSettingsMetadataKeyDescription : @"OpenID Connect Redirect URI",
			OCClassSettingsMetadataKeyCategory    : @"OIDC",
		},
		OCAuthenticationMethodOpenIDConnectScope : @{
			OCClassSettingsMetadataKeyType        : OCClassSettingsMetadataTypeString,
			OCClassSettingsMetadataKeyDescription : @"OpenID Connect Scope",
			OCClassSettingsMetadataKeyCategory    : @"OIDC"
		},
		OCAuthenticationMethodOpenIDConnectPrompt : @{
			OCClassSettingsMetadataKeyType        : OCClassSettingsMetadataTypeString,
			OCClassSettingsMetadataKeyDescription : @"OpenID Connect Prompt",
			OCClassSettingsMetadataKeyCategory    : @"OIDC"
		},
		OCAuthenticationMethodOpenIDRegisterClient : @{
			OCClassSettingsMetadataKeyType        : OCClassSettingsMetadataTypeBoolean,
			OCClassSettingsMetadataKeyDescription : @"Use OpenID Connect Dynamic Client Registration if the `.well-known/openid-configuration` provides a `registration_endpoint`. If this option is enabled and a registration endpoint is available, `oa2-client-id` and `oa2-client-secret` will be ignored.",
			OCClassSettingsMetadataKeyCategory    : @"OIDC"
		},
		OCAuthenticationMethodOpenIDRegisterClientNameTemplate : @{
			OCClassSettingsMetadataKeyType        : OCClassSettingsMetadataTypeString,
			OCClassSettingsMetadataKeyDescription : @"Client Name Template to use during OpenID Connect Dynamic Client Registration. In addition to the placeholders available for `http.user-agent`, `{{url.hostname}}` can also be used.",
			OCClassSettingsMetadataKeyCategory    : @"OIDC"
		},
		OCAuthenticationMethodOpenIDFallbackOnClientRegistrationFailure : @{
			OCClassSettingsMetadataKeyType        : OCClassSettingsMetadataTypeBoolean,
			OCClassSettingsMetadataKeyDescription : @"If client registration is enabled, but registration fails, controls if the error should be ignored and the default client ID and secret should be used instead.",
			OCClassSettingsMetadataKeyCategory    : @"OIDC"
		}
	}];
}

#pragma mark - Identification
+ (OCAuthenticationMethodType)type
{
	return (OCAuthenticationMethodTypeToken);
}

+ (OCAuthenticationMethodIdentifier)identifier
{
	return (OCAuthenticationMethodIdentifierOpenIDConnect);
}

+ (NSString *)name
{
	return (@"OpenID Connect");
}

#pragma mark - OAuth2 extensions
- (NSURL *)authorizationEndpointURLForConnection:(OCConnection *)connection options:(OCAuthenticationMethodDetectionOptions)options
{
	NSString *authorizationEndpointURLString;

	if ((authorizationEndpointURLString = OCTypedCast(_openIDConfig[@"authorization_endpoint"], NSString)) != nil)
	{
		return ([NSURL URLWithString:authorizationEndpointURLString]);
	}

	return (nil);
}

- (NSURL *)tokenEndpointURLForConnection:(OCConnection *)connection options:(OCAuthenticationMethodDetectionOptions)options
{
	NSString *tokenEndpointURLString;

	if ((tokenEndpointURLString = OCTypedCast(_openIDConfig[@"token_endpoint"], NSString)) != nil)
	{
		return ([NSURL URLWithString:tokenEndpointURLString]);
	}

	return (nil);
}

- (NSString *)redirectURIForConnection:(OCConnection *)connection
{
	return ([self classSettingForOCClassSettingsKey:OCAuthenticationMethodOpenIDConnectRedirectURI]);
}

- (NSDictionary<NSString *, NSString *> *)tokenRefreshParametersForRefreshToken:(NSString *)refreshToken connection:(OCConnection *)connection
{
	NSMutableDictionary<NSString *, NSString *> *refreshParameters = [[super tokenRefreshParametersForRefreshToken:refreshToken connection:connection] mutableCopy];

	refreshParameters[@"client_id"] = self.clientID;

	NSString *secret = self.clientSecret;
	if (secret != nil)
	{
		refreshParameters[@"client_secret"] = secret;
	}

	refreshParameters[@"scope"] = self.scope;

	return (refreshParameters);
}

- (NSString *)tokenRequestAuthorizationHeaderForType:(OCAuthenticationOAuth2TokenRequestType)requestType connection:(OCConnection *)connection
{
	// Public client (auth method "none") — no Authorization header
	if ([self _isPublicClient])
	{
		return (nil);
	}

	if (requestType == OCAuthenticationOAuth2TokenRequestTypeRefreshToken)
	{
		// Use the client_id and client_secret used when the token was issued
		NSString *clientID = nil, *clientSecret = nil;
		NSDictionary<NSString *, id> *authSecret;

		if ((authSecret = [self cachedAuthenticationSecretForConnection:connection]) != nil)
		{
			clientID = authSecret[OIDCKeyPathClientID];
			clientSecret = authSecret[OIDCKeyPathClientSecret];
		}

		if (clientID == nil) { clientID = self.clientID; }
		if (clientSecret == nil) { clientSecret = self.clientSecret; }

		OCTLogDebug(@[@"ClientRegistration"], @"Sending token refresh request with clientID=%@, clientSecret=%@", OCLogPrivate(clientID), OCLogPrivate(clientSecret));

		return ([OCAuthenticationMethod basicAuthorizationValueForUsername:clientID passphrase:clientSecret]);
	}

	return ([super tokenRequestAuthorizationHeaderForType:requestType connection:connection]);
}

- (void)retrieveEndpointInformationForConnection:(OCConnection *)connection options:(nullable OCAuthenticationMethodDetectionOptions)options completionHandler:(nonnull void (^)(NSError * _Nullable))completionHandler
{
	NSURL *openidConfigURL;

	// Extract WebFinger values from options (initial login / re-auth)
	if (options != nil)
	{
		NSString *wfClientID = OCTypedCast(options[OCAuthenticationMethodWebFingerClientIDKey], NSString);
		if (wfClientID != nil)
		{
			_webFingerClientID = wfClientID;
		}

		NSString *wfScope = OCTypedCast(options[OCAuthenticationMethodWebFingerScopeKey], NSString);
		if (wfScope != nil)
		{
			_webFingerScope = wfScope;
		}

		NSURL *wfIssuerURL = OCTypedCast(options[OCAuthenticationMethodWebFingerAlternativeIDPKey], NSURL);
		if (wfIssuerURL != nil)
		{
			_webFingerIssuerURL = wfIssuerURL;
		}
	}

	// Prefer stored issuer URL for OIDC discovery (critical for federated IDPs like Keycloak on a different domain)
	if (_webFingerIssuerURL != nil)
	{
		openidConfigURL = [_webFingerIssuerURL URLByAppendingPathComponent:@".well-known/openid-configuration"];
	}
	else
	{
		openidConfigURL = [self.class _openIDConfigurationURLForConnection:connection options:options];
	}

	if (openidConfigURL != nil)
	{
		OCHTTPRequest *openidConfigRequest = [OCHTTPRequest requestWithURL:openidConfigURL];

		openidConfigRequest.redirectPolicy = OCHTTPRequestRedirectPolicyHandleLocally;

		NSURL *refererForIDPURL;
		if ((refererForIDPURL = options[OCAuthenticationMethodAuthenticationRefererURL]) != nil)
		{
			[openidConfigRequest setValue:refererForIDPURL.absoluteString forHeaderField:@"Referer"];
		}

		[connection sendRequest:openidConfigRequest ephermalCompletionHandler:^(OCHTTPRequest * _Nonnull request, OCHTTPResponse * _Nullable response, NSError * _Nullable error) {
			NSError *jsonError;

			if ((error == nil) && ((self->_openIDConfig = [response bodyConvertedDictionaryFromJSONWithError:&jsonError]) != nil))
			{
				self.pkce = [OCPKCE new]; // Enable PKCE

				// Skip dynamic client registration if WebFinger provided a client_id
				if (self->_webFingerClientID != nil)
				{
					OCTLogDebug(@[@"WebFinger"], @"Using WebFinger-provided client_id=%@, scope=%@", OCLogPrivate(self->_webFingerClientID), self->_webFingerScope);
					completionHandler(nil);
					return;
				}

				// Dynamic Client Registration support
				if ([[self classSettingForOCClassSettingsKey:OCAuthenticationMethodOpenIDRegisterClient] boolValue])
				{
					if (self->_openIDConfig[@"registration_endpoint"] != nil)
					{
						NSURL *registrationEndpointURL;

						if ((registrationEndpointURL = [NSURL URLWithString:self->_openIDConfig[@"registration_endpoint"]]) != nil)
						{
							OCTLogDebug(@[@"ClientRegistration"], @"Found OIDC dynamic client registration endpoint: %@", registrationEndpointURL);

							// Perform dynamic client registration
							[self registerClientWithRegistrationEndpointURL:registrationEndpointURL connection:connection completionHandler:^(NSError *error) {
								if (error != nil) // could be more specific, too, but then would also not ignore network errors / non-success response codes: if ([error isOCErrorWithCode:OCErrorAuthorizationClientRegistrationFailed])
								{
									if ([[self classSettingForOCClassSettingsKey:OCAuthenticationMethodOpenIDFallbackOnClientRegistrationFailure] boolValue])
									{
										completionHandler(nil);
										return;
									}
								}

								completionHandler(error);
							}];

							return;
						}
					}
				}

				completionHandler(nil);
			}
			else
			{
				if ((error == nil) && (response.status.code == OCHTTPStatusCodeMOVED_PERMANENTLY) && (response.redirectURL != nil) && (request.url != nil))
				{
					NSURL *alternativeBaseURL;

					if ((alternativeBaseURL = [connection extractBaseURLFromRedirectionTargetURL:response.redirectURL originalURL:request.url fallbackToRedirectionTargetURL:YES]) != nil)
					{
						error = OCErrorWithInfo(OCErrorAuthorizationRedirect, (@{
							OCAuthorizationMethodAlternativeServerURLKey : alternativeBaseURL,
							OCAuthorizationMethodAlternativeServerURLOriginURLKey : request.url
						}));
					}
				}

				if (error == nil) { error = jsonError; }
				if (error == nil) { error = OCError(OCErrorInternal); }

				completionHandler(error);
			}
		}];
	}
	else
	{
		completionHandler(OCError(OCErrorInsufficientParameters));
	}
}

- (NSString *)scope
{
	if (_webFingerScope != nil) { return (_webFingerScope); }
	return ([self classSettingForOCClassSettingsKey:OCAuthenticationMethodOpenIDConnectScope]);
}

- (NSString *)prompt
{
	return ([self classSettingForOCClassSettingsKey:OCAuthenticationMethodOpenIDConnectPrompt]);
}

#pragma mark - Dynamic Client Registration
- (void)registerClientWithRegistrationEndpointURL:(NSURL *)registrationEndpointURL connection:(OCConnection *)connection completionHandler:(void(^)(NSError *error))completionHandler
{
	NSError *error = nil;
	NSDictionary<NSString *,id> *jsonRequestDict = nil;
	OCHTTPRequest *openidClientRegistrationRequest;

	// Check if we have a valid registration
	if ((self.clientID != nil) && (self.clientSecret != nil) && // clientID and clientSecret exist
	    [self.clientRegistrationEndpointURL isEqual:registrationEndpointURL] && // the registration endpoint hasn't changed
	    ( (self.clientRegistrationExpirationDate==nil) || // either: a) the combination does not expire
	      ((self.clientRegistrationExpirationDate != nil) && (self.clientRegistrationExpirationDate.timeIntervalSinceNow > 60)) // or: b) it expires, but the expiry date has not yet been reached (with a safety margin of 60 seconds)
	    )
	   )
	{
		OCTLogDebug(@[@"ClientRegistration"], @"Using cached client ID/secret from previous registration (expiring %@): %@/%@", self.clientRegistrationExpirationDate, OCLogPrivate(self.clientID), OCLogPrivate(self.clientSecret));
		completionHandler(nil);
		return;
	}

	// Generate the client name from the template
	self->_clientName = [OCHTTPPipeline stringForTemplate:[self classSettingForOCClassSettingsKey:OCAuthenticationMethodOpenIDRegisterClientNameTemplate] variables:@{ @"url.hostname" : connection.bookmark.url.host }];

	// Compose JSON request
	jsonRequestDict = @{
		@"application_type" 		: @"native",

		@"token_endpoint_auth_method" 	: @"client_secret_basic",

		@"client_name" 	    		: self->_clientName,
		@"redirect_uris"   		: @[
			[self classSettingForOCClassSettingsKey:OCAuthenticationMethodOpenIDConnectRedirectURI]
		]
	};

	// Create HTTP request
	if ((openidClientRegistrationRequest = [OCHTTPRequest requestWithURL:registrationEndpointURL jsonObject:jsonRequestDict error:&error]) != nil)
	{
		OCTLogDebug(@[@"ClientRegistration"], @"Registering client %@", self->_clientName);

		// Send client registration request
		[connection sendRequest:openidClientRegistrationRequest ephermalCompletionHandler:^(OCHTTPRequest * _Nonnull request, OCHTTPResponse * _Nullable response, NSError * _Nullable error) {
			/*
			Example response:

			201 CREATED
			Access-Control-Allow-Origin: *
			Content-Type: application/json; encoding=utf-8
			Pragma: no-cache
			x-xss-protection: 1; mode=block
			Expires: Thu, 01 Jan 1970 00:00:00 GMT
			x-konnectd-version: 17a22705
			referrer-policy: origin
			Cache-Control: no-cache, no-store, must-revalidate
			Date: Fri, 08 Jan 2021 11:31:16 GMT
			Content-Length: 1671
			x-content-type-options: nosniff
			x-frame-options: DENY
			Last-Modified: Fri, 08 Jan 2021 11:31:16 GMT

			{
			  "client_id": "dyn.eyJhbGciOiJQUzI1NiIsImtpZCI6Imtvbm5lY3RkX3ByaXZhdGUiLCJ0eXAiOiJKV1QifQ.eyJleHAiOjE2MTAxMDkwNzYsImlhdCI6MTYxMDEwNTQ3Niwic3ViIjoiYW9nTnF1cm5xSHZyYVhFQi1sSUduOC1oc1AwZlJmS293aGljZ2ZrUWxSMnlGUDNmcG9qM1FsSGtYQ0g5c0ZmNEVuR0VVOHRwQTQyb0FycTZhaXdwNXciLCJuYW1lIjoib3duQ2xvdWQvaU9TIDExLjUgb24gb2Npcy5vd25jbG91ZC53b3JrcyIsImdyYW50X3R5cGVzIjpbImF1dGhvcml6YXRpb25fY29kZSJdLCJhcHBsaWNhdGlvbl90eXBlIjoibmF0aXZlIiwicmVkaXJlY3RfdXJpcyI6WyJvYzovL2lvcy5vd25jbG91ZC5jb20iXSwiaWRfdG9rZW5fc2lnbmVkX3Jlc3BvbnNlX2FsZyI6IlJTMjU2IiwidG9rZW5fZW5kcG9pbnRfYXV0aF9tZXRob2QiOiJjbGllbnRfc2VjcmV0X2Jhc2ljIn0.kIg1eYH6lnj7CVeHENtX9ZLzewAi93soi506GHX4zStlChQxKDz_p0BLtSVtY-XzquAT8Xt2w177-yduV1YHMsXN5mbXJ8zd2M4lHN5SRwu--eEZJyH9QmtO5f87-wFg3_pxAnYhYtbKoOQatvYiEw66RvgfJ3TT1LikcRDfdg83yO7FsMONv9qmTJsp-wKX8ZT51TVecn8AMXiF-AKYijK9ZE3XO0XpJaL_U3NDxrta2ASllxvvP0da8eAsxJX7DQK2zME62wvPMcQI1l0t4eqaL0i3wGRXH2w5VNgZIaMzJt4-W6UWNfrcJ_75pT6ommsM1kVecid4qyyP4Eckbw",
			  "client_secret": "TsbAsXmeOZnNzEJN8T2UQGO2oZE8zCNKcyj4pVM2mpVfOcGznVIWRuMoupx8V7hnZqVVMuOBlxT5A1QO6wgR8Q",
			  "client_id_issued_at": 1610105476,
			  "client_secret_expires_at": 1610109076,
			  "redirect_uris": [
			    "oc://ios.opencloud.eu"
			  ],
			  "response_types": [
			    "code"
			  ],
			  "grant_types": [
			    "authorization_code"
			  ],
			  "application_type": "native",
			  "contacts": null,
			  "client_name": "OpenCloud/iOS 11.5 on klaasihasi.opencloud.works",
			  "client_uri": "",
			  "jwks": null,
			  "id_token_signed_response_alg": "RS256",
			  "userinfo_signed_response_alg": "",
			  "request_object_signing_alg": "",
			  "token_endpoint_auth_method": "client_secret_basic",
			  "token_endpoint_auth_signing_alg": "",
			  "post_logout_redirect_uris": null
			}
			*/

			if (response.status.code == OCHTTPStatusCodeCREATED)
			{
				// OIDC spec: "A successful response SHOULD use the HTTP 201 Created status code
				// and return a JSON document [RFC4627] using the application/json content type"
				NSDictionary<NSString *, id> *registrationResponseDict;
				NSError *jsonError = nil;

				if ((registrationResponseDict = [response bodyConvertedDictionaryFromJSONWithError:&jsonError]) != nil)
				{
					NSString *clientID=nil, *clientSecret=nil;
					NSNumber *clientSecretExpiresAt=nil;

					if (((clientID = OCTypedCast(registrationResponseDict[@"client_id"], NSString)) != nil) &&
					    ((clientSecret = OCTypedCast(registrationResponseDict[@"client_secret"], NSString)) != nil) &&
					    ((clientSecretExpiresAt = OCTypedCast(registrationResponseDict[@"client_secret_expires_at"], NSNumber)) != nil))
					{
						self->_clientRegistrationResponse = registrationResponseDict;
						self->_clientRegistrationEndpointURL = registrationEndpointURL;

						OCTLogDebug(@[@"ClientRegistration"], @"Registered clientID=%@, clientSecret=%@", OCLogPrivate(clientID), OCLogPrivate(clientSecret));

						self->_clientID = clientID;
						self->_clientSecret = clientSecret;

						// OIDC spec: "REQUIRED if client_secret is issued. Time at which the client_secret will
						// expire or 0 if it will not expire. Its value is a JSON number representing the number
						// of seconds from 1970-01-01T0:0:0Z as measured in UTC until the date/time."

						// As per https://github.com/owncloud/openidconnect/issues/142#issuecomment-771732045,
						// implementations may return 0 for non-expiring client_id_client_secret pairs
						if (clientSecretExpiresAt.intValue != 0)
						{
							self->_clientRegistrationExpirationDate = [NSDate dateWithTimeIntervalSince1970:clientSecretExpiresAt.doubleValue];
						}

						error = nil;
					}
					else
					{
						error = OCErrorWithDescriptionAndUserInfo(OCErrorAuthorizationClientRegistrationFailed, @"client_id, client_secret or client_secret_expires_at missing from registration response.", @"jsonResponse", registrationResponseDict);
					}
				}
				else
				{
					error = OCErrorFromError(OCErrorAuthorizationClientRegistrationFailed, jsonError);
				}
			}
			else if (response.status.code == OCHTTPStatusCodeBAD_REQUEST)
			{
				// OIDC spec: "When a registration error condition occurs, the Client Registration Endpoint returns a
				// HTTP 400 Bad Request status code including a JSON object describing the error in the response body."
				NSDictionary<NSString *, id> *errorResponseDict;
				NSError *jsonError = nil;

				if ((errorResponseDict = [response bodyConvertedDictionaryFromJSONWithError:&jsonError]) != nil)
				{
					error = OCErrorWithDescriptionAndUserInfo(OCErrorAuthorizationClientRegistrationFailed, ([NSString stringWithFormat:@"Error registering client: %@ (%@)", errorResponseDict[@"error_description"], errorResponseDict[@"error"]]), @"errorResponse", errorResponseDict);
				}
				else
				{
					error = OCErrorFromError(OCErrorAuthorizationClientRegistrationFailed, jsonError);
				}
			}
			else
			{
				error = OCErrorFromError(OCErrorAuthorizationClientRegistrationFailed, response.status.error);
			}

			if (error != nil)
			{
				OCErrorAddDateFromResponse(error, response);
				OCTLogError(@[@"ClientRegistration"], @"Registration failed with error=%@", error);
			}
			else
			{
				OCTLogDebug(@[@"ClientRegistration"], @"Successfully registered client");
			}

			completionHandler(error);
		}];
	}
	else
	{
		OCTLogError(@[@"ClientRegistration"], @"Error serializing request JSON %@: %@", jsonRequestDict, error);

		completionHandler(error);
	}
}

- (NSDictionary<NSString *,id> *)postProcessAuthenticationDataDict:(NSDictionary<NSString *,id> *)authDataDict
{
	// Extract preferred_username from id_token JWT BEFORE super strips it from tokenResponse
	// (super condenses tokenResponse to only access_token, refresh_token, expires_in, user_id)
	NSString *preferredUsername = nil;
	NSDictionary<NSString *, id> *originalTokenResponse = authDataDict[@"tokenResponse"];
	NSString *idToken = OCTypedCast(originalTokenResponse[@"id_token"], NSString);
	if (idToken != nil)
	{
		preferredUsername = [self _extractPreferredUsernameFromIDToken:idToken];
	}

	authDataDict = [super postProcessAuthenticationDataDict:authDataDict];

	NSMutableDictionary<NSString *,id> *newAuthDataDict = nil;

	if (_clientRegistrationResponse != nil)
	{
		newAuthDataDict = [authDataDict mutableCopy];

		NSError *error = nil;

		newAuthDataDict[OIDCKeyPathClientRegistrationResponseSerialized] = [NSJSONSerialization dataWithJSONObject:_clientRegistrationResponse options:0 error:&error];

		if (error != nil)
		{
			OCTLogError(@[@"ClientRegistration"], @"Error %@ encoding to JSON: %@", error, _clientRegistrationResponse);
		}

		if (_clientRegistrationEndpointURL != nil)
		{
			newAuthDataDict[OIDCKeyPathClientRegistrationEndpointURL] = _clientRegistrationEndpointURL.absoluteString;
		}
		if (_clientRegistrationExpirationDate != nil)
		{
			newAuthDataDict[OIDCKeyPathClientRegistrationExpirationDate] = _clientRegistrationExpirationDate;
		}
		if (_clientID != nil)
		{
			newAuthDataDict[OIDCKeyPathClientID] = _clientID;
		}
		if (_clientSecret != nil)
		{
			newAuthDataDict[OIDCKeyPathClientSecret] = _clientSecret;
		}
	}

	// Persist WebFinger values
	if (_webFingerClientID != nil || _webFingerScope != nil || _webFingerIssuerURL != nil)
	{
		if (newAuthDataDict == nil) { newAuthDataDict = [authDataDict mutableCopy]; }

		if (_webFingerClientID != nil)
		{
			newAuthDataDict[OIDCKeyPathWebFingerClientID] = _webFingerClientID;
		}
		if (_webFingerScope != nil)
		{
			newAuthDataDict[OIDCKeyPathWebFingerScope] = _webFingerScope;
		}
		if (_webFingerIssuerURL != nil)
		{
			newAuthDataDict[OIDCKeyPathWebFingerIssuerURL] = _webFingerIssuerURL.absoluteString;
		}
	}

	// Store preferred_username separately for login_hint on re-auth
	// (NOT as user_id — user_id may be a UUID, preferred_username is what the user types at the IDP)
	if (preferredUsername != nil)
	{
		if (newAuthDataDict == nil) { newAuthDataDict = [authDataDict mutableCopy]; }
		newAuthDataDict[OIDCKeyPathPreferredUsername] = preferredUsername;
	}

	// Persist public client flag so token refresh works when _openIDConfig is nil
	if (_isPublicClientPersisted)
	{
		if (newAuthDataDict == nil) { newAuthDataDict = [authDataDict mutableCopy]; }
		newAuthDataDict[OIDCKeyPathIsPublicClient] = @YES;
	}

	return (newAuthDataDict != nil) ? newAuthDataDict : authDataDict;
}

- (id)loadCachedAuthenticationSecretForConnection:(OCConnection *)connection
{
	NSDictionary<NSString *, id> *authSecret;

	if ((authSecret = [super loadCachedAuthenticationSecretForConnection:connection]) != nil)
	{
		if (_clientRegistrationResponse == nil)
		{
			NSData *responseSerialized;

			if ((responseSerialized = [authSecret valueForKeyPath:OIDCKeyPathClientRegistrationResponseSerialized]) != nil)
			{
				NSError *error = nil;

				_clientRegistrationResponse = [NSJSONSerialization JSONObjectWithData:responseSerialized options:0 error:&error];

				if (error != nil)
				{
					OCTLogError(@[@"ClientRegistration"], @"Error decoding JSON: %@", error);
				}
			}
		}

		if (_clientRegistrationExpirationDate == nil)
		{
			_clientRegistrationExpirationDate = [authSecret valueForKeyPath:OIDCKeyPathClientRegistrationExpirationDate];
		}

		if ((_clientRegistrationEndpointURL == nil) && ([authSecret valueForKeyPath:OIDCKeyPathClientRegistrationEndpointURL] != nil))
		{
			_clientRegistrationEndpointURL = [NSURL URLWithString:[authSecret valueForKeyPath:OIDCKeyPathClientRegistrationEndpointURL]];
		}

		if (_clientID == nil)
		{
			_clientID = [authSecret valueForKeyPath:OIDCKeyPathClientID];
		}

		if (_clientSecret == nil)
		{
			_clientSecret = [authSecret valueForKeyPath:OIDCKeyPathClientSecret];
		}

		// Restore WebFinger values
		if (_webFingerClientID == nil)
		{
			_webFingerClientID = OCTypedCast(authSecret[OIDCKeyPathWebFingerClientID], NSString);
		}

		if (_webFingerScope == nil)
		{
			_webFingerScope = OCTypedCast(authSecret[OIDCKeyPathWebFingerScope], NSString);
		}

		if (_webFingerIssuerURL == nil)
		{
			NSString *issuerURLString = OCTypedCast(authSecret[OIDCKeyPathWebFingerIssuerURL], NSString);
			if (issuerURLString != nil)
			{
				_webFingerIssuerURL = [NSURL URLWithString:issuerURLString];
			}
		}

		if (_preferredUsername == nil)
		{
			_preferredUsername = OCTypedCast(authSecret[OIDCKeyPathPreferredUsername], NSString);
		}

		// Sync preferred_username from auth data to bookmark.userInfo so the
		// app layer can copy it to temp bookmarks during re-auth
		if (_preferredUsername != nil && connection.bookmark.userInfo[OCBookmarkUserInfoKeyPreferredUsername] == nil)
		{
			connection.bookmark.userInfo[OCBookmarkUserInfoKeyPreferredUsername] = _preferredUsername;
		}

		NSNumber *isPublicClientValue = OCTypedCast(authSecret[OIDCKeyPathIsPublicClient], NSNumber);
		if (isPublicClientValue != nil)
		{
			_isPublicClientPersisted = isPublicClientValue.boolValue;
		}

		OCTLogDebug(@[@"ClientRegistration"], @"Loaded from secret: clientID=%@, clientSecret=%@, webFingerClientID=%@, webFingerIssuerURL=%@, isPublicClient=%d", OCLogPrivate(_clientID), OCLogPrivate(_clientSecret), OCLogPrivate(_webFingerClientID), _webFingerIssuerURL, _isPublicClientPersisted);
	}

	return (authSecret);

}

- (NSString *)clientID
{
	if (_webFingerClientID != nil) { return (_webFingerClientID); }
	if (self.hasClientRegistration) { return (_clientID); }
	return ([super clientID]);
}

- (NSDictionary<NSString *, id> *)clientRegistrationResponse
{
	return (_clientRegistrationResponse);
}

- (NSURL *)clientRegistrationEndpointURL
{
	return(_clientRegistrationEndpointURL);
}

- (NSDate *)clientRegistrationExpirationDate
{
	return (_clientRegistrationExpirationDate);
}

- (BOOL)hasClientRegistration
{
	return ((_clientID != nil) && (_clientSecret != nil));
}

- (void)_clearClientRegistrationData
{
	OCTLogDebug(@[@"ClientRegistration"], @"Clearing client registration data");

	_openIDConfig = nil;

	_clientRegistrationResponse = nil;
	_clientRegistrationEndpointURL = nil;
	_clientRegistrationExpirationDate = nil;

	_clientName = nil;
	_clientID = nil;
	_clientSecret = nil;

	_webFingerClientID = nil;
	_webFingerScope = nil;
	_webFingerIssuerURL = nil;

	_preferredUsername = nil;
	_isPublicClientPersisted = NO;
}

#pragma mark - Authentication Method Detection
+ (NSURL *)_openIDConfigurationURLForConnection:(OCConnection *)connection options:(nullable OCAuthenticationMethodDetectionOptions)options
{
	OCAuthenticationMethodDetectionOptions detectionOptions = @{ OCConnectionEndpointURLOptionWellKnownSubPath : @"openid-configuration" };

	if (options != nil)
	{
		NSMutableDictionary<OCAuthenticationMethodKey, id> *mutableOptions = [[NSMutableDictionary alloc] initWithDictionary:options];
		[mutableOptions addEntriesFromDictionary:detectionOptions];
		detectionOptions = mutableOptions;
	}

	return ([connection URLForEndpoint:OCConnectionEndpointIDWellKnown options:detectionOptions]);
}

+ (NSArray<OCHTTPRequest *> *)detectionRequestsForConnection:(OCConnection *)connection options:(nullable OCAuthenticationMethodDetectionOptions)options
{
	NSURL *openidConfigURL;
	NSArray <OCHTTPRequest *> *oidcDetectionURLs = nil;

	if (OCTypedCast(options[OCAuthenticationMethodSkipWWWAuthenticateChecksKey],NSNumber).boolValue)
	{
		// Do not perform "Bearer" check requests to determine OIDC support
		oidcDetectionURLs = @[];
	}
	else
	{
		// Do not use super method here because OAuth2 verifies additional URLs to specifically determine OAuth2 availability
		oidcDetectionURLs = [self detectionRequestsBasedOnWWWAuthenticateMethod:@"Bearer" forConnection:connection];
	}

	if (oidcDetectionURLs != nil)
	{
		if ((openidConfigURL = [self _openIDConfigurationURLForConnection:connection options:options]) != nil)
		{
			OCHTTPRequest *openidConfigRequest = [OCHTTPRequest requestWithURL:openidConfigURL];

			NSURL *refererForIDPURL;
			if ((refererForIDPURL = options[OCAuthenticationMethodAuthenticationRefererURL]) != nil)
			{
				[openidConfigRequest setValue:refererForIDPURL.absoluteString forHeaderField:@"Referer"];
			}

			return ([oidcDetectionURLs arrayByAddingObject:openidConfigRequest]);
		}
	}

	return (nil);
}

+ (void)detectAuthenticationMethodSupportForConnection:(OCConnection *)connection withServerResponses:(NSDictionary<NSURL *, OCHTTPRequest *> *)serverResponses options:(OCAuthenticationMethodDetectionOptions)options completionHandler:(void(^)(OCAuthenticationMethodIdentifier identifier, BOOL supported))completionHandler
{
	if (OCTypedCast(options[OCAuthenticationMethodSkipWWWAuthenticateChecksKey],NSNumber).boolValue)
	{
		// No "Bearer" check requests were performed, so perform just a validity check for the OIDC configuration response
		[self detectOIDCSupportForConnection:connection withServerResponses:serverResponses options:options completionHandler:completionHandler];
	}
	else
	{
		// Since OIDC is a superset of OAuth2, ensure criteria for OAuth2 are also met
		[super detectAuthenticationMethodSupportForConnection:connection withServerResponses:serverResponses options:options completionHandler:^(OCAuthenticationMethodIdentifier identifier, BOOL supported) {
			if (supported)
			{
				// OAuth2 supported => continue
				[self detectOIDCSupportForConnection:connection withServerResponses:serverResponses options:options completionHandler:completionHandler];
			}
			else
			{
				// OAuth2 not supported => OIDC requirement not met
				completionHandler(OCAuthenticationMethodIdentifierOpenIDConnect, NO);
			}
		}];
	}
}

+ (void)detectOIDCSupportForConnection:(OCConnection *)connection withServerResponses:(NSDictionary<NSURL *, OCHTTPRequest *> *)serverResponses options:(OCAuthenticationMethodDetectionOptions)options completionHandler:(void(^)(OCAuthenticationMethodIdentifier identifier, BOOL supported))completionHandler
{
	NSURL *wellKnownURL;
	BOOL completeWithNotSupported = YES;

	if ((wellKnownURL = [self _openIDConfigurationURLForConnection:connection options:options]) != nil)
	{
		OCHTTPRequest *wellKnownRequest;

		if ((wellKnownRequest = [serverResponses objectForKey:wellKnownURL]) != nil)
		{
			OCHTTPResponse *response = wellKnownRequest.httpResponse;

			if (response.status.isSuccess)
			{
				if ([response.contentType hasSuffix:@"/json"])
				{
					NSError *error = nil;

					if ([response bodyConvertedDictionaryFromJSONWithError:&error] != nil)
					{
						// OIDC supported
						completionHandler(OCAuthenticationMethodIdentifierOpenIDConnect, YES);
						completeWithNotSupported = NO;
					}
					else
					{
						OCLogError(@"Error decoding OIDC configuration JSON: %@", OCLogPrivate(error));
					}
				}
			}
		}
	}

	// Fallback completion handler call
	if (completeWithNotSupported)
	{
		// OIDC not supported
		completionHandler(OCAuthenticationMethodIdentifierOpenIDConnect, NO);
	}
}

#pragma mark - Requests
- (void)sendTokenRequestToConnection:(OCConnection *)connection withParameters:(NSDictionary<NSString*,NSString*> *)parameters options:(nullable OCAuthenticationMethodDetectionOptions)options requestType:(OCAuthenticationOAuth2TokenRequestType)requestType completionHandler:(void(^)(NSError *error, NSDictionary *jsonResponseDict, NSData *authenticationData))completionHandler
{
	[super sendTokenRequestToConnection:connection withParameters:parameters options:options requestType:requestType completionHandler:^(NSError *error, NSDictionary *jsonResponseDict, NSData *authenticationData) {
		if (error != nil)
		{
			// Force client re-registration in case of an error
			OCTLogDebug(@[@"ClientRegistration"], @"Token request error %@ => clear registration", error);
			[self _clearClientRegistrationData];
		}
		completionHandler(error, jsonResponseDict, authenticationData);
	}];
}

- (BOOL)_isPublicClient
{
	// Public client detection based on OIDC discovery only.
	// We do NOT infer public/confidential from WebFinger — the realm-wide
	// token_endpoint_auth_methods_supported is the only reliable signal.
	// For public PKCE clients, sending Basic auth with client_id and empty
	// secret works fine (Keycloak ignores the empty secret for public clients).
	if (_openIDConfig != nil)
	{
		NSArray<NSString *>* supportedEndpointAuthMethods = OCTypedCast(_openIDConfig[@"token_endpoint_auth_methods_supported"], NSArray);
		BOOL supportsNone = [supportedEndpointAuthMethods containsObject:@"none"];
		BOOL supportsBasicAuth = [supportedEndpointAuthMethods containsObject:@"client_secret_basic"];
		BOOL supportsPost = [supportedEndpointAuthMethods containsObject:@"client_secret_post"];

		BOOL isPublic = (supportsNone && !supportsBasicAuth && !supportsPost);
		_isPublicClientPersisted = isPublic;
		return (isPublic);
	}

	// When _openIDConfig is nil (token refresh path), use persisted flag
	return (_isPublicClientPersisted);
}

- (BOOL)sendClientIDAndSecretInPOSTBody
{
	if (_openIDConfig != nil)
	{
		NSArray<NSString *>* supportedEndpointAuthMethods = OCTypedCast(_openIDConfig[@"token_endpoint_auth_methods_supported"], NSArray);

		// Determine supported auth methods (reference: https://openid.net/specs/openid-connect-discovery-1_0.html)
		BOOL supportsBasicAuth = [supportedEndpointAuthMethods containsObject:@"client_secret_basic"];
		BOOL supportsPost = [supportedEndpointAuthMethods containsObject:@"client_secret_post"];
		BOOL supportsNone = [supportedEndpointAuthMethods containsObject:@"none"];

		if (supportsNone && !supportsBasicAuth && !supportsPost)
		{
			// Public client — send client_id in POST body without client_secret
			return (YES);
		}
		else if (!supportsBasicAuth && supportsPost)
		{
			// Basic auth is not supported, only POST
			return (YES);
		}
		else if (!supportsPost && !supportsBasicAuth && !supportsNone)
		{
			// None of the implemented methods is supported
			OCLogWarning(@"OpenID configuration token_endpoint_auth_methods_supported does not contain any supported auth methods.")
		}
	}
	else if (_isPublicClientPersisted)
	{
		// _openIDConfig is nil (token refresh path) — use persisted flag
		return (YES);
	}

	return ([super sendClientIDAndSecretInPOSTBody]);
}

- (NSString *)clientSecret
{
	// Public client — no client_secret
	if ([self _isPublicClient])
	{
		return (nil);
	}

	if (self.hasClientRegistration)
	{
		return (_clientSecret);
	}

	return ([super clientSecret]);
}

#pragma mark - Generate bookmark authentication data
- (NSDictionary<NSString *,NSString *> *)prepareAuthorizationRequestParameters:(NSDictionary<NSString *,NSString *> *)parameters forConnection:(OCConnection *)connection options:(OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions)options
{
	// Prefer preferred_username from JWT (what the user types at the IDP),
	// fall back to value stored on bookmark (survives re-auth with temp bookmark),
	// then to bookmark.userName
	NSString *loginHint = _preferredUsername;
	if (loginHint == nil)
	{
		loginHint = OCTypedCast(connection.bookmark.userInfo[OCBookmarkUserInfoKeyPreferredUsername], NSString);
	}
	if (loginHint == nil)
	{
		loginHint = connection.bookmark.userName;
	}

	if (loginHint != nil)
	{
		NSMutableDictionary<NSString *,NSString *> *mutableParameters = [parameters mutableCopy];

		/*
			As per https://openid.net/specs/openid-connect-core-1_0.html#AuthRequest:

			OPTIONAL. Hint to the Authorization Server about the login identifier the End-User might use to log in (if necessary). This hint can be used by an RP if it first asks the End-User for their e-mail address (or other identifier) and then wants to pass that value as a hint to the discovered authorization service. It is RECOMMENDED that the hint value match the value used for discovery. This value MAY also be a phone number in the format specified for the phone_number Claim. The use of this parameter is left to the OP's discretion.
		*/

		mutableParameters[@"login_hint"] = loginHint;

		return (mutableParameters);
	}

	return (parameters);
}

- (void)generateBookmarkAuthenticationDataWithConnection:(OCConnection *)connection options:(OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions)options completionHandler:(void(^)(NSError *error, OCAuthenticationMethodIdentifier authenticationMethodIdentifier, NSData *authenticationData))completionHandler
{
	// Wrap completionHandler to store preferredUsername on bookmark after successful auth
	void(^wrappedCompletionHandler)(NSError *, OCAuthenticationMethodIdentifier, NSData *) = ^(NSError *error, OCAuthenticationMethodIdentifier identifier, NSData *authData) {
		if (error == nil && self->_preferredUsername != nil)
		{
			connection.bookmark.userInfo[OCBookmarkUserInfoKeyPreferredUsername] = self->_preferredUsername;
		}
		completionHandler(error, identifier, authData);
	};

	// Re-query WebFinger if options don't already contain WebFinger values (re-auth scenario)
	BOOL hasWebFingerInOptions = (options[OCAuthenticationMethodWebFingerAlternativeIDPKey] != nil) ||
	                             (options[OCAuthenticationMethodWebFingerClientIDKey] != nil);

	if (!hasWebFingerInOptions && _webFingerClientID == nil && _webFingerIssuerURL == nil)
	{
		// Re-auth path: no WebFinger values from setup flow or memory — query WebFinger fresh
		OCTLogDebug(@[@"WebFinger"], @"Re-querying WebFinger for re-authentication");
		[self queryWebFingerForConnection:connection completionHandler:^(NSError * _Nullable wfError) {
			if (wfError != nil)
			{
				OCTLogDebug(@[@"WebFinger"], @"WebFinger re-query failed (non-fatal): %@", wfError);
				// Non-fatal: server may not support WebFinger, fall through to normal flow
			}

			[self retrieveEndpointInformationForConnection:connection options:options completionHandler:^(NSError * _Nonnull error) {
				if (error == nil)
				{
					[super generateBookmarkAuthenticationDataWithConnection:connection options:options completionHandler:wrappedCompletionHandler];
				}
				else
				{
					completionHandler(error, nil, nil);
				}
			}];
		}];
	}
	else
	{
		[self retrieveEndpointInformationForConnection:connection options:options completionHandler:^(NSError * _Nonnull error) {
			if (error == nil)
			{
				[super generateBookmarkAuthenticationDataWithConnection:connection options:options completionHandler:wrappedCompletionHandler];
			}
			else
			{
				completionHandler(error, nil, nil);
			}
		}];
	}
}

#pragma mark - Token refresh hook
- (void)didRefreshTokenForConnectionBookmark:(OCBookmark *)bookmark
{
	// After a successful token refresh, postProcessAuthenticationDataDict: has
	// already extracted preferred_username from the new id_token and stored it
	// in _preferredUsername + the auth data dict.  Persist it on the bookmark's
	// userInfo as well so the app layer can copy it to temp bookmarks for re-auth.
	if (_preferredUsername != nil)
	{
		bookmark.userInfo[OCBookmarkUserInfoKeyPreferredUsername] = _preferredUsername;
	}
}

#pragma mark - JWT id_token parsing
- (nullable NSString *)_extractPreferredUsernameFromIDToken:(NSString *)idToken
{
	// JWT format: header.payload.signature — decode the base64url-encoded payload
	NSArray<NSString *> *parts = [idToken componentsSeparatedByString:@"."];
	if (parts.count < 2)
	{
		return nil;
	}

	NSString *payloadBase64 = parts[1];

	// Base64URL → Base64: replace URL-safe chars and add padding
	NSMutableString *base64 = [payloadBase64 mutableCopy];
	[base64 replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, base64.length)];
	[base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, base64.length)];

	NSUInteger remainder = base64.length % 4;
	if (remainder > 0)
	{
		NSUInteger paddingLength = 4 - remainder;
		for (NSUInteger i = 0; i < paddingLength; i++)
		{
			[base64 appendString:@"="];
		}
	}

	NSData *payloadData = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
	if (payloadData == nil) { return nil; }

	NSDictionary *claims = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil];
	if (![claims isKindOfClass:[NSDictionary class]]) { return nil; }

	// Prefer preferred_username → email → sub
	NSString *result = OCTypedCast(claims[@"preferred_username"], NSString);
	if (result == nil) { result = OCTypedCast(claims[@"email"], NSString); }
	if (result == nil) { result = OCTypedCast(claims[@"sub"], NSString); }

	return result;
}

#pragma mark - WebFinger re-query
- (void)queryWebFingerForConnection:(OCConnection *)connection completionHandler:(void(^)(NSError * _Nullable error))completionHandler
{
	NSURL *bookmarkURL = connection.bookmark.url;
	if (bookmarkURL == nil)
	{
		completionHandler(OCError(OCErrorInsufficientParameters));
		return;
	}

	NSURL *webFingerURL = [[bookmarkURL URLByAppendingPathComponent:@".well-known/webfinger" isDirectory:NO] urlByAppendingQueryParameters:@{
		@"resource" : bookmarkURL.rootURL.absoluteString,
		@"rel" : @"http://openid.net/specs/connect/1.0/issuer",
		@"platform" : @"ios"
	} replaceExisting:YES];

	OCHTTPRequest *request = [OCHTTPRequest requestWithURL:webFingerURL];
	request.redirectPolicy = OCHTTPRequestRedirectPolicyHandleLocally;

	[connection sendRequest:request ephermalCompletionHandler:^(OCHTTPRequest * _Nonnull request, OCHTTPResponse * _Nullable response, NSError * _Nullable error) {
		if (error != nil)
		{
			completionHandler(error);
			return;
		}

		NSDictionary *jsonDict = [response bodyConvertedDictionaryFromJSONWithError:&error];
		if (jsonDict == nil)
		{
			completionHandler(error ?: OCError(OCErrorInternal));
			return;
		}

		// Parse properties
		NSDictionary<NSString*,id> *propertiesDict = OCTypedCast(jsonDict[@"properties"], NSDictionary);
		if (propertiesDict != nil)
		{
			NSString *clientIDValue = OCTypedCast(propertiesDict[@"http://opencloud.eu/ns/oidc/client_id"], NSString);
			if (clientIDValue != nil)
			{
				self->_webFingerClientID = clientIDValue;
			}

			NSArray *scopesArray = OCTypedCast(propertiesDict[@"http://opencloud.eu/ns/oidc/scopes"], NSArray);
			if (scopesArray != nil)
			{
				self->_webFingerScope = [scopesArray componentsJoinedByString:@" "];
			}
		}

		// Parse issuer link
		NSArray *linksArray = OCTypedCast(jsonDict[@"links"], NSArray);
		if (linksArray != nil)
		{
			for (id link in linksArray)
			{
				NSDictionary<NSString*,id> *linkDict = OCTypedCast(link, NSDictionary);
				if (linkDict != nil && [linkDict[@"rel"] isEqual:@"http://openid.net/specs/connect/1.0/issuer"])
				{
					NSString *urlString = OCTypedCast(linkDict[@"href"], NSString);
					if (urlString != nil)
					{
						self->_webFingerIssuerURL = [NSURL URLWithString:urlString];
						break;
					}
				}
			}
		}

		completionHandler(nil);
	}];
}

@end

OCAuthenticationMethodIdentifier OCAuthenticationMethodIdentifierOpenIDConnect = @"com.opencloud.openid-connect";

OCClassSettingsKey OCAuthenticationMethodOpenIDConnectRedirectURI = @"oidc-redirect-uri";
OCClassSettingsKey OCAuthenticationMethodOpenIDConnectScope = @"oidc-scope";
OCClassSettingsKey OCAuthenticationMethodOpenIDConnectPrompt = @"oidc-prompt";
OCClassSettingsKey OCAuthenticationMethodOpenIDRegisterClient = @"oidc-register-client";
OCClassSettingsKey OCAuthenticationMethodOpenIDRegisterClientNameTemplate = @"oidc-register-client-name-template";
OCClassSettingsKey OCAuthenticationMethodOpenIDFallbackOnClientRegistrationFailure = @"oidc-fallback-on-client-registration-failure";
