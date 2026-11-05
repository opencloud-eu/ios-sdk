//
//  AuthenticationTests.m
//  OpenCloudSDKTests
//
//  Created by Felix Schwarz on 24.02.18.
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

#import <XCTest/XCTest.h>
#import <OpenCloudSDK/OpenCloudSDK.h>
#import <OpenCloudMocking/OpenCloudMocking.h>

#import "OCTestTarget.h"

@interface AuthenticationTests : XCTestCase <OCConnectionDelegate>

@end

@implementation AuthenticationTests

- (void)setUp
{
	[super setUp];
	// Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
	// Put teardown code here. This method is called after the invocation of each test method in the class.
	[super tearDown];
}

#pragma mark - Infrastructure
- (void)testAuthenticatioMethodAutoRegistration
{
	NSArray <Class> *authenticationMethodClasses;
	
	if ((authenticationMethodClasses = [OCAuthenticationMethod registeredAuthenticationMethodClasses]) != nil)
	{
		NSMutableArray <OCAuthenticationMethodIdentifier> *expectedIdentifiers = [NSMutableArray arrayWithObjects:
			OCAuthenticationMethodIdentifierOAuth2,
			OCAuthenticationMethodIdentifierBasicAuth,
		nil];
		
		for (Class authenticationMethodClass in authenticationMethodClasses)
		{
			[expectedIdentifiers removeObject:[authenticationMethodClass identifier]];
		}
		
		XCTAssert((expectedIdentifiers.count == 0), @"Expected Authentication Methods did not auto-register: %@", expectedIdentifiers);
	}
}

#pragma mark - Basic auth
- (void)_performBasicAuthenticationTestWithURL:(NSURL *)url user:(NSString *)user password:(NSString *)password allowUpgrades:(BOOL)allowUpgrades expectsSuccess:(BOOL)expectsSuccess
{
	XCTestExpectation *receivedReplyExpectation = [self expectationWithDescription:@"Received reply"];

	OCBookmark *bookmark;
	OCConnection *connection;

	bookmark = [OCBookmark bookmarkForURL:url];

	if ((connection = [[OCConnection alloc] initWithBookmark:bookmark]) != nil)
	{
		[connection generateAuthenticationDataWithMethod:OCAuthenticationMethodIdentifierBasicAuth
							 options:@{
							 		OCAuthenticationMethodUsernameKey : user,
							 		OCAuthenticationMethodPassphraseKey : password,
							 		OCAuthenticationMethodAllowURLProtocolUpgradesKey : @(allowUpgrades)
								  }
					       completionHandler:^(NSError *error, OCAuthenticationMethodIdentifier authenticationMethodIdentifier, NSData *authenticationData) {
					       		if (expectsSuccess)
					       		{
								XCTAssert((error==nil), @"Authentication failed: %@", error);
							}
							else
							{
								XCTAssert((error!=nil), @"Authentication succeeded unexpectedly");
								if (error!=nil)
								{
									OCLog(@"Failed as expected. Error: %@", error);
								}
							}

						       	if (error == nil)
						       	{
							       	// Success! Save authentication data to bookmark.
								bookmark.authenticationMethodIdentifier = authenticationMethodIdentifier;
							       	bookmark.authenticationData = authenticationData;

							       	// Verify userName is accessible
							       	XCTAssert([bookmark.userName isEqual:user], @"Username from bookmark (%@) doesn't match user used for creation (%@)", bookmark.name, user);
								
							       	// Request resource
							       	OCHTTPRequest *request = nil;
								request = [OCHTTPRequest requestWithURL:[connection URLForEndpoint:OCConnectionEndpointIDCapabilities options:nil]];
								[request setValue:@"json" forParameter:@"format"];
								
							       	[connection sendRequest:request ephermalCompletionHandler:^(OCHTTPRequest *request, OCHTTPResponse *response, NSError *error) {
									OCLog(@"Result of request: %@ (error: %@):\n\n## Response: %@\n\n## Body: %@", request, error, response.httpURLResponse, response.bodyAsString);
									
									if (response.status.isSuccess)
									{
										NSError *error = nil;
										NSDictionary *capabilitiesDict;
										
										capabilitiesDict = [response bodyConvertedDictionaryFromJSONWithError:&error];
										XCTAssert((capabilitiesDict!=nil), @"Conversion from JSON successful");
										XCTAssert(([capabilitiesDict valueForKeyPath:@"ocs.data.version.string"]!=nil), @"Capabilities structure intact");
										
										OCLog(@"Capabilities: %@", capabilitiesDict);
										OCLog(@"Version: %@", [capabilitiesDict valueForKeyPath:@"ocs.data.version.string"]);
									}
									
									[receivedReplyExpectation fulfill];
							       	}];
						       	}
						       	else
						       	{
						       		// Operation failed here. No need to wait until 60 seconds run out
								[receivedReplyExpectation fulfill];
							}
					       }
		 ];
	}

	[self waitForExpectationsWithTimeout:60 handler:nil];
}

- (void)testBasicAuthenticationSuccess
{
	XCTSkip(@"demo.opencloud.eu does not accept Basic Auth for the test account (HTTP 401) - needs a server with Basic Auth enabled");

	[self _performBasicAuthenticationTestWithURL:OCTestTarget.insecureTargetURL user:OCTestTarget.userLogin password:OCTestTarget.userPassword allowUpgrades:YES expectsSuccess:YES];
}

- (void)testBasicAuthenticationRedirectFailure
{
	[self _performBasicAuthenticationTestWithURL:OCTestTarget.insecureTargetURL user:OCTestTarget.userLogin password:OCTestTarget.userPassword allowUpgrades:NO expectsSuccess:NO];
}

- (void)testBasicAuthenticationFailure
{
	[self _performBasicAuthenticationTestWithURL:OCTestTarget.secureTargetURL user:@"nosuchuser" password:@"nosuchpass" allowUpgrades:YES expectsSuccess:NO];
}

#pragma mark - OAuth2
- (void)testOAuth2TokenGeneration
{
	XCTSkip(@"Written for ownCloud 10's built-in OAuth2 app (index.php/apps/oauth2/...), which OpenCloud doesn't have; also passes unsimulated requests through to demo.opencloud.eu");

	XCTestExpectation *expectAuthControllerInvocation = [self expectationWithDescription:@"Auth controller invocation"];
	XCTestExpectation *expectAuthCodeGrantRequest = [self expectationWithDescription:@"Auth code grant request sent"];
	XCTestExpectation *expectBookmarkDataCompletenHandlerCall = [self expectationWithDescription:@"Bookmark data completion handler called"];

	OCBookmark *bookmark = [OCBookmark bookmarkForURL:OCTestTarget.insecureTargetURL];
	NSString *basicAuthString = [OCAuthenticationMethod basicAuthorizationValueForUsername:OCTestTarget.userLogin passphrase:OCTestTarget.userPassword];
	NSString *refreshAuthString = [OCAuthenticationMethod basicAuthorizationValueForUsername:[OCAuthenticationMethodOAuth2 classSettingForOCClassSettingsKey:OCAuthenticationMethodOAuth2ClientID] passphrase:[OCAuthenticationMethodOAuth2 classSettingForOCClassSettingsKey:OCAuthenticationMethodOAuth2ClientSecret]];

	OCConnection *connection;
	OCHostSimulator *hostSimulator;

	if ((connection = [[OCConnection alloc] initWithBookmark:bookmark]) != nil)
	{
		// Add host simulator
		hostSimulator = [[OCHostSimulator alloc] init];
		hostSimulator.unroutableRequestHandler = nil; // Pass through requests we don't handle

		connection.hostSimulator = hostSimulator;

		// Intercept endpoints
		hostSimulator.requestHandler = ^BOOL(OCConnection *connection, OCHTTPRequest *request, OCHostSimulatorResponseHandler responseHandler) {
			BOOL fixAuthentication = YES;

			OCLogDebug(@"headerFields[Authorization]=%@", request.headerFields[@"Authorization"]);

			if ([request.url.absoluteString hasSuffix:@"ocs/v2.php/cloud/user"])
			{
				responseHandler(nil, [OCHostSimulatorResponse responseWithURL:request.url statusCode:OCHTTPStatusCodeOK headers:@{} contentType:@"application/json; charset=utf-8" body:@"{\"ocs\":{\"meta\":{\"status\":\"ok\",\"statuscode\":200,\"message\":\"OK\",\"totalitems\":\"\",\"itemsperpage\":\"\"},\"data\":{\"id\":\"demo\",\"display-name\":\"demo\",\"email\":null}}}"]);

				return (YES);
			}

			if ([request.url.absoluteString hasSuffix:@"index.php/apps/oauth2/api/v1/token"])
			{
				NSString *requestGrantType = nil, *requestCode = nil, *requestRedirectURI = nil;
				NSURLComponents *urlComponents = [[NSURLComponents alloc] init];

				urlComponents.query = [[NSString alloc] initWithData:request.bodyData encoding:NSUTF8StringEncoding];

				for (NSURLQueryItem *urlQueryItem in urlComponents.queryItems)
				{
					if ([urlQueryItem.name isEqual:@"grant_type"])
					{
						requestGrantType = urlQueryItem.value;
					}

					if ([urlQueryItem.name isEqual:@"code"])
					{
						requestCode = urlQueryItem.value;
					}

					if ([urlQueryItem.name isEqual:@"redirect_uri"])
					{
						requestRedirectURI = urlQueryItem.value;
					}
				}

				XCTAssert([request.headerFields[@"Authorization"] isEqualToString:refreshAuthString]);

				if ([requestGrantType isEqualToString:@"authorization_code"])
				{
					XCTAssert([requestCode isEqualToString:@"issuedAuthCode"]);
					XCTAssert([requestRedirectURI isEqualToString:@"oc://ios.opencloud.eu"]);

					[expectAuthCodeGrantRequest fulfill];

					responseHandler(nil, [OCHostSimulatorResponse responseWithURL:request.url statusCode:OCHTTPStatusCodeOK headers:@{} contentType:@"application/json; charset=utf-8" body:@"{\"access_token\":\"issuedAccessToken\",\"token_type\":\"Bearer\",\"expires_in\":125,\"refresh_token\":\"issuedRefreshToken\",\"user_id\":\"joe\",\"message_url\":\"https:\\/\\/www.opencloud.eu\\/apps\\/oauth2\\/authorization-successful\"}"]);
				}

				return (YES);
			}

			if (fixAuthentication)
			{
				if ([request.headerFields[@"Authorization"] containsString:@"Bearer "])
				{
					[request setValue:basicAuthString forHeaderField:OCHTTPHeaderFieldNameAuthorization];
				}
			}

			return (NO);
		};

		OCMockAuthenticationMethodOAuth2StartAuthenticationSessionForURLSchemeCompletionHandlerBlock mockBlock;

		mockBlock = ^(id *authenticationSession, NSURL *authorizationRequestURL, NSString *scheme, OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions options, void(^completionHandler)(NSURL *_Nullable callbackURL, NSError *_Nullable error)) {

			NSLog(@"authenticationSession=%@, authorizationRequestURL=%@, scheme=%@", *authenticationSession, authorizationRequestURL, scheme);

			[expectAuthControllerInvocation fulfill];

			completionHandler([NSURL URLWithString:@"oc://ios.opencloud.eu/?code=issuedAuthCode"], nil);

			return (YES);
		};

		[OCMockManager.sharedMockManager addMockingBlocks:@{
			OCMockLocationAuthenticationMethodOAuth2StartAuthenticationSessionForURLSchemeCompletionHandler : mockBlock
		}];

		[connection generateAuthenticationDataWithMethod:OCAuthenticationMethodIdentifierOAuth2 options:@{
			OCAuthenticationMethodPresentingViewControllerKey : [UIViewController new]
		} completionHandler:^(NSError *error, OCAuthenticationMethodIdentifier authenticationMethodIdentifier, NSData *authenticationData) {
			XCTAssert([authenticationMethodIdentifier isEqualToString:OCAuthenticationMethodIdentifierOAuth2]);
			XCTAssert(authenticationData!=nil);
			XCTAssert(error==nil);

			bookmark.authenticationMethodIdentifier = authenticationMethodIdentifier;
			bookmark.authenticationData = authenticationData;

			NSDictionary *authSecretDict = [connection.authenticationMethod cachedAuthenticationSecretForConnection:connection];

			OCLog(@"authSecretDict=%@", authSecretDict);

			XCTAssert([authSecretDict[@"bearerString"] isEqualToString:@"Bearer issuedAccessToken"]);
			XCTAssert([(NSDate *)authSecretDict[@"expirationDate"] timeIntervalSinceNow] > 110);
			XCTAssert([(NSDate *)authSecretDict[@"expirationDate"] timeIntervalSinceNow] < 126);
			XCTAssert([[(NSDictionary *)authSecretDict[@"tokenResponse"] objectForKey:@"access_token"] isEqualToString:@"issuedAccessToken"]);
			XCTAssert([[(NSDictionary *)authSecretDict[@"tokenResponse"] objectForKey:@"refresh_token"] isEqualToString:@"issuedRefreshToken"]);

			XCTAssert([[OCAuthenticationMethodOAuth2 userNameFromAuthenticationData:authenticationData] isEqualToString:@"joe"]);
			XCTAssert([OCAuthenticationMethodOAuth2 type] == OCAuthenticationMethodTypeToken);
			XCTAssert([[OCAuthenticationMethodOAuth2 name] isEqualToString:@"OAuth2"]);

			[expectBookmarkDataCompletenHandlerCall fulfill];
		}];
	}

	[self waitForExpectationsWithTimeout:60 handler:nil];

	OCLogDebug(@"hostSimulator=%@", hostSimulator);

	[OCMockManager.sharedMockManager removeAllMockingBlocks];
}

- (void)testOAuth2TokenRefresh
{
	XCTSkip(@"Written for ownCloud 10's built-in OAuth2 app (index.php/apps/oauth2/...), which OpenCloud doesn't have; also passes unsimulated requests through to demo.opencloud.eu");

	// Create expectations
	__block XCTestExpectation *expectFirstRequestWithRefreshedAccessToken = [self expectationWithDescription:@"received first PROPFIND request with refreshed refresh token"];
	__block XCTestExpectation *expectSecondRequestWithRefreshedAccessToken = [self expectationWithDescription:@"received second PROPFIND request with refreshed twice refresh token"];
	XCTestExpectation *expectSecondDisconnect = [self expectationWithDescription:@"Second disconnect returned"];
	__block NSUInteger tokenRequestCount = 0;

	// Create fake OAuth2 bookmark in need of a refresh
	OCBookmark *bookmark = [OCBookmark bookmarkForURL:OCTestTarget.secureTargetURL];
	NSDictionary *originalJSONResponseDict = [NSJSONSerialization JSONObjectWithData:[@"{\"access_token\":\"originalAccessToken\",\"token_type\":\"Bearer\",\"expires_in\":3600,\"refresh_token\":\"originalRefreshToken\",\"user_id\":\"joe\",\"message_url\":\"https:\\/\\/demo.opencloud.eu\\/apps\\/oauth2\\/authorization-successful\"}" dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
	NSString *basicAuthString = [OCAuthenticationMethod basicAuthorizationValueForUsername:OCTestTarget.userLogin passphrase:OCTestTarget.userPassword];
	NSString *refreshAuthString = [OCAuthenticationMethod basicAuthorizationValueForUsername:[OCAuthenticationMethodOAuth2 classSettingForOCClassSettingsKey:OCAuthenticationMethodOAuth2ClientID] passphrase:[OCAuthenticationMethodOAuth2 classSettingForOCClassSettingsKey:OCAuthenticationMethodOAuth2ClientSecret]];

	bookmark.authenticationMethodIdentifier = OCAuthenticationMethodIdentifierOAuth2;
	bookmark.authenticationData = [NSPropertyListSerialization dataWithPropertyList:@{
		@"expirationDate" : [NSDate distantPast],
		@"bearerString"  : [NSString stringWithFormat:@"Bearer %@", originalJSONResponseDict[@"access_token"]],
		@"tokenResponse" : originalJSONResponseDict
	} format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];

	// Create connection
	OCConnection *connection;
	OCHostSimulator *hostSimulator;

	if ((connection = [[OCConnection alloc] initWithBookmark:bookmark]) != nil)
	{
		__block BOOL firstPropfindRequest = YES;

		// Add host simulator
		hostSimulator = [[OCHostSimulator alloc] init];
		hostSimulator.unroutableRequestHandler = nil; // Pass through requests we don't handle

		connection.hostSimulator = hostSimulator;

		// Intercept endpoints
		hostSimulator.requestHandler = ^BOOL(OCConnection *connection, OCHTTPRequest *request, OCHostSimulatorResponseHandler responseHandler) {
			BOOL fixAuthentication = YES;

			OCLogDebug(@"headerFields[Authorization]=%@, path=%@", request.headerFields[@"Authorization"], request.url.absoluteString);

			if ([request.url.absoluteString hasSuffix:@"index.php/apps/oauth2/api/v1/token"])
			{
				NSString *requestGrantType = nil, *requestRefreshToken = nil;
				NSURLComponents *urlComponents = [[NSURLComponents alloc] init];

				urlComponents.query = [[NSString alloc] initWithData:request.bodyData encoding:NSUTF8StringEncoding];

				for (NSURLQueryItem *urlQueryItem in urlComponents.queryItems)
				{
					if ([urlQueryItem.name isEqual:@"grant_type"])
					{
						requestGrantType = urlQueryItem.value;
					}

					if ([urlQueryItem.name isEqual:@"refresh_token"])
					{
						requestRefreshToken = urlQueryItem.value;
					}
				}

				XCTAssert([request.headerFields[@"Authorization"] isEqualToString:refreshAuthString]);

				switch (tokenRequestCount)
				{
					case 0:
						XCTAssert([requestGrantType isEqual:@"refresh_token"]);
						XCTAssert([requestRefreshToken isEqual:@"originalRefreshToken"]);

						responseHandler(nil, [OCHostSimulatorResponse responseWithURL:request.url statusCode:OCHTTPStatusCodeOK headers:@{} contentType:@"application/json; charset=utf-8" body:@"{\"access_token\":\"refreshedAccessToken\",\"token_type\":\"Bearer\",\"expires_in\":10,\"refresh_token\":\"refreshedRefreshToken\",\"user_id\":\"joe\",\"message_url\":\"https:\\/\\/www.opencloud.eu\\/apps\\/oauth2\\/authorization-successful\"}"]);
					break;

					case 1:
						XCTAssert([requestGrantType isEqual:@"refresh_token"]);
						XCTAssert([requestRefreshToken isEqual:@"refreshedRefreshToken"]);

						responseHandler(nil, [OCHostSimulatorResponse responseWithURL:request.url statusCode:OCHTTPStatusCodeOK headers:@{} contentType:@"application/json; charset=utf-8" body:@"{\"access_token\":\"refreshedTwiceAccessToken\",\"token_type\":\"Bearer\",\"expires_in\":125,\"refresh_token\":\"refreshedTwiceRefreshToken\",\"user_id\":\"joe\",\"message_url\":\"https:\\/\\/www.opencloud.eu\\/apps\\/oauth2\\/authorization-successful\"}"]);
					break;

					default:
						XCTFail(@"Token endpoint should not be contacted more than twice");
					break;
				}

				tokenRequestCount++;

				return (YES);
			}

			if ([request.url.absoluteString hasSuffix:@"ocs/v2.php/cloud/capabilities"])
			{
				if ([request.headerFields[@"Authorization"] isEqualToString:@"Bearer refreshedAccessToken"])
				{
					XCTAssert(firstPropfindRequest);
					XCTAssert(expectFirstRequestWithRefreshedAccessToken!=nil);
					XCTAssert(expectSecondRequestWithRefreshedAccessToken!=nil);

					[expectFirstRequestWithRefreshedAccessToken fulfill];
					expectFirstRequestWithRefreshedAccessToken = nil;
				}

				if ([request.headerFields[@"Authorization"] isEqualToString:@"Bearer refreshedTwiceAccessToken"])
				{
					XCTAssert(!firstPropfindRequest);
					XCTAssert(expectFirstRequestWithRefreshedAccessToken==nil);
					XCTAssert(expectSecondRequestWithRefreshedAccessToken!=nil);

					[expectSecondRequestWithRefreshedAccessToken fulfill];
					expectSecondRequestWithRefreshedAccessToken = nil;
				}

				firstPropfindRequest = NO;
			}

			if (fixAuthentication)
			{
				if ([request.headerFields[@"Authorization"] containsString:@"Bearer "])
				{
					[request setValue:basicAuthString forHeaderField:OCHTTPHeaderFieldNameAuthorization];
				}
			}

			return (NO);
		};

		[connection connectWithCompletionHandler:^(NSError *error, OCIssue *issue) {
			OCLog(@"error=%@, issue=%@", error, issue);
			XCTAssert(expectFirstRequestWithRefreshedAccessToken==nil);

			[connection disconnectWithCompletionHandler:^{
				sleep (12);

				[connection connectWithCompletionHandler:^(NSError *error, OCIssue *issue) {
					OCLog(@"error=%@, issue=%@", error, issue);

					[connection disconnectWithCompletionHandler:^{
						[expectSecondDisconnect fulfill];
					}];
				}];
			}];
		}];
	}

	[self waitForExpectationsWithTimeout:60 handler:nil];

	XCTAssert(tokenRequestCount==2);

	OCLogDebug(@"hostSimulator=%@", hostSimulator);
}

#pragma mark - OpenID Connect
- (void)testOpenIDConnect
{
	// Ensure OIDC test target is available
	OCBookmark *bookmark = OCTestTarget.oidcBookmark;
	if (bookmark == nil) { XCTSkip(@"No OIDC test target configured (OCTestTarget.oidcBookmark returns nil)"); }

	XCTestExpectation *detectionExpectation = [self expectationWithDescription:@"OIDC detected"];
	OCConnection *connection;

	if ((connection = [[OCConnection alloc] initWithBookmark:bookmark]) != nil)
	{
		connection.delegate = self;

		[connection prepareForSetupWithOptions:nil completionHandler:^(OCIssue * _Nullable issue, NSURL * _Nullable suggestedURL, NSArray<OCAuthenticationMethodIdentifier> * _Nullable supportedMethods, NSArray<OCAuthenticationMethodIdentifier> * _Nullable preferredAuthenticationMethods, OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions _Nullable generationOptions) {
			OCLog(@"preferredAuthenticationMethods: %@ supportedMethods: %@", preferredAuthenticationMethods, supportedMethods);

			if ([preferredAuthenticationMethods.firstObject isEqual:OCAuthenticationMethodIdentifierOpenIDConnect])
			{
				[detectionExpectation fulfill];
			}
		}];
	}

	[self waitForExpectationsWithTimeout:60 handler:nil];
}

// opencloud-eu/ios#99: with token_endpoint_auth_methods_supported = ["none"] (public client,
// PKCE) there is no client_secret, but client_id still has to be sent - Kanidm answers the code
// exchange with HTTP 401 otherwise. Offline: OCHostSimulator IDP, browser session mocked away.
- (void)testOpenIDConnectPublicClientSendsClientIDInTokenRequest
{
	NSString *idpClientID = @"opencloud-web";					// what WebFinger hands us, as in the issue
	NSURL *idpIssuerURL = [NSURL URLWithString:@"https://idm.kanidm.test/oauth2/openid/opencloud-web"];
	NSString *tokenEndpointPath = @"/oauth2/token";

	// Kanidm 1.12's .well-known/openid-configuration, trimmed to the keys the SDK reads
	NSDictionary<NSString *, id> *openIDConfiguration = @{
		@"issuer" 				: idpIssuerURL.absoluteString,
		@"authorization_endpoint" 		: @"https://idm.kanidm.test/ui/oauth2",
		@"token_endpoint" 			: [@"https://idm.kanidm.test" stringByAppendingString:tokenEndpointPath],
		@"userinfo_endpoint" 			: [idpIssuerURL.absoluteString stringByAppendingString:@"/userinfo"],
		@"jwks_uri" 				: [idpIssuerURL.absoluteString stringByAppendingString:@"/public_key.jwk"],
		@"response_types_supported" 		: @[ @"code" ],
		@"grant_types_supported" 		: @[ @"authorization_code" ],
		@"subject_types_supported" 		: @[ @"public" ],
		@"id_token_signing_alg_values_supported": @[ @"ES256" ],
		@"scopes_supported" 			: @[ @"openid", @"profile", @"email", @"groups", @"offline_access" ],
		@"code_challenge_methods_supported" 	: @[ @"S256" ],
		@"token_endpoint_auth_methods_supported": @[ @"none" ]	// <- this is what makes us a public client
	};

	XCTestExpectation *expectConfigurationRequest = [self expectationWithDescription:@"openid-configuration requested"];
	XCTestExpectation *expectAuthSession = [self expectationWithDescription:@"Browser session started"];
	XCTestExpectation *expectTokenRequest = [self expectationWithDescription:@"Authorization code exchanged"];
	XCTestExpectation *expectUserRequest = [self expectationWithDescription:@"Logged in user retrieved"];
	XCTestExpectation *expectCompletion = [self expectationWithDescription:@"Authentication data generated"];

	OCBookmark *bookmark = [OCBookmark bookmarkForURL:[NSURL URLWithString:@"https://files.kanidm.test/"]];
	OCConnection *connection = [[OCConnection alloc] initWithBookmark:bookmark];

	XCTAssertNotNil(connection);

	connection.delegate = self;

	__block NSString *authorizationRequestRedirectURI = nil;

	OCHostSimulator *hostSimulator = [OCHostSimulator new];

	hostSimulator.requestHandler = ^BOOL(OCConnection *simulatedConnection, OCHTTPRequest *request, OCHostSimulatorResponseHandler responseHandler) {
		if ([request.url.path hasSuffix:@"/.well-known/openid-configuration"])
		{
			[expectConfigurationRequest fulfill];

			responseHandler(nil, [OCHostSimulatorResponse responseWithURL:request.url statusCode:OCHTTPStatusCodeOK headers:@{} contentType:@"application/json" bodyData:[NSJSONSerialization dataWithJSONObject:openIDConfiguration options:0 error:NULL]]);

			return (YES);
		}

		if ([request.url.path isEqual:tokenEndpointPath])
		{
			// Decode the form-encoded POST body as it goes on the wire
			NSURLComponents *bodyComponents = [NSURLComponents new];
			bodyComponents.query = [[NSString alloc] initWithData:request.bodyData encoding:NSUTF8StringEncoding];

			NSMutableDictionary<NSString *, NSString *> *body = [NSMutableDictionary new];

			for (NSURLQueryItem *queryItem in bodyComponents.queryItems)
			{
				if (queryItem.value != nil)
				{
					body[queryItem.name] = queryItem.value;
				}
			}

			// The actual regression (opencloud-eu/ios#99): no client_id anywhere in the request
			XCTAssertEqualObjects(body[@"client_id"], idpClientID, @"a public client still has to identify itself with client_id in the token request body");
			XCTAssertNil(body[@"client_secret"], @"a public client has no secret to send");
			XCTAssertNil(request.headerFields[OCHTTPHeaderFieldNameAuthorization], @"a public client must not fall back to Basic auth");

			// … and the remainder of the code exchange is still well-formed
			XCTAssertEqualObjects(body[@"grant_type"], @"authorization_code");
			XCTAssertEqualObjects(body[@"code"], @"kanidmAuthCode");
			XCTAssertEqualObjects(body[@"redirect_uri"], authorizationRequestRedirectURI, @"redirect_uri has to match the one from the authorization request");
			XCTAssertNotNil(body[@"code_verifier"], @"PKCE code_verifier missing");

			[expectTokenRequest fulfill];

			responseHandler(nil, [OCHostSimulatorResponse responseWithURL:request.url statusCode:OCHTTPStatusCodeOK headers:@{} contentType:@"application/json" body:@"{\"access_token\":\"kanidmAccessToken\",\"token_type\":\"bearer\",\"expires_in\":900,\"refresh_token\":\"kanidmRefreshToken\",\"scope\":\"openid profile email offline_access\"}"]);

			return (YES);
		}

		// Right after the code exchange the SDK resolves the user name through the server
		// (the token response carries no user_id), so that has to be answered as well
		if ([request.url.path hasSuffix:@"ocs/v2.php/cloud/user"])
		{
			XCTAssertEqualObjects(request.headerFields[OCHTTPHeaderFieldNameAuthorization], @"Bearer kanidmAccessToken");

			[expectUserRequest fulfill];

			responseHandler(nil, [OCHostSimulatorResponse responseWithURL:request.url statusCode:OCHTTPStatusCodeOK headers:@{} contentType:@"application/json" body:@"{\"ocs\":{\"meta\":{\"status\":\"ok\",\"statuscode\":200,\"message\":\"OK\"},\"data\":{\"id\":\"kanidmuser\",\"display-name\":\"Kanidm User\",\"email\":null}}}"]);

			return (YES);
		}

		return (NO);
	};

	connection.hostSimulator = hostSimulator;

	// Stand in for ASWebAuthenticationSession: check the authorization request, hand back the callback URL
	OCMockAuthenticationMethodOAuth2StartAuthenticationSessionForURLSchemeCompletionHandlerBlock mockBlock;

	mockBlock = ^(__autoreleasing id *authenticationSession, NSURL *authorizationRequestURL, NSString *scheme, OCAuthenticationMethodBookmarkAuthenticationDataGenerationOptions options, void(^completionHandler)(NSURL *_Nullable callbackURL, NSError *_Nullable error)) {
		NSDictionary<NSString *, NSString *> *authorizationParameters = authorizationRequestURL.queryParameters;

		XCTAssertEqualObjects(authorizationParameters[@"response_type"], @"code");
		XCTAssertEqualObjects(authorizationParameters[@"client_id"], idpClientID);
		XCTAssertEqualObjects(authorizationParameters[@"code_challenge_method"], @"S256");
		XCTAssertNotNil(authorizationParameters[@"code_challenge"]);

		authorizationRequestRedirectURI = authorizationParameters[@"redirect_uri"];
		XCTAssertNotNil(authorizationRequestRedirectURI);

		[expectAuthSession fulfill];

		NSURLComponents *callbackComponents = [NSURLComponents componentsWithString:authorizationRequestRedirectURI];
		NSMutableArray<NSURLQueryItem *> *callbackQueryItems = [NSMutableArray arrayWithObject:[NSURLQueryItem queryItemWithName:@"code" value:@"kanidmAuthCode"]];
		NSString *state;

		if ((state = authorizationParameters[@"state"]) != nil)
		{
			[callbackQueryItems addObject:[NSURLQueryItem queryItemWithName:@"state" value:state]];
		}

		callbackComponents.queryItems = callbackQueryItems;

		completionHandler(callbackComponents.URL, nil);

		return (YES);
	};

	[OCMockManager.sharedMockManager addMockingBlocks:@{
		OCMockLocationAuthenticationMethodOAuth2StartAuthenticationSessionForURLSchemeCompletionHandler : mockBlock
	}];

	// WebFinger values are passed in as the setup flow would, which also skips dynamic client registration
	[connection generateAuthenticationDataWithMethod:OCAuthenticationMethodIdentifierOpenIDConnect options:@{
		OCAuthenticationMethodPresentingViewControllerKey : [UIViewController new],
		OCAuthenticationMethodWebFingerAlternativeIDPKey : idpIssuerURL,
		OCAuthenticationMethodWebFingerClientIDKey : idpClientID,
		OCAuthenticationMethodWebFingerScopeKey : @"openid profile email offline_access"
	} completionHandler:^(NSError *error, OCAuthenticationMethodIdentifier authenticationMethodIdentifier, NSData *authenticationData) {
		XCTAssertNil(error, @"the code exchange must succeed");
		XCTAssertNotNil(authenticationData);
		XCTAssertEqualObjects(authenticationMethodIdentifier, OCAuthenticationMethodIdentifierOpenIDConnect);
		XCTAssertEqualObjects([OCAuthenticationMethodOpenIDConnect userNameFromAuthenticationData:authenticationData], @"kanidmuser");

		[expectCompletion fulfill];
	}];

	[self waitForExpectationsWithTimeout:30 handler:nil];

	[OCMockManager.sharedMockManager removeAllMockingBlocks];
}

#pragma mark - Detection
- (void)testAuthenticationMethodDetection
{
	XCTestExpectation *receivedReplyExpectation = [self expectationWithDescription:@"Received reply"];

	OCBookmark *bookmark;
	OCConnection *connection;

	// bookmark = [OCBookmark bookmarkForURL:[NSURL URLWithString:@"https://opencloud-io.lan/"]];
	bookmark = [OCBookmark bookmarkForURL:OCTestTarget.secureTargetURL];

	if ((connection = [[OCConnection alloc] initWithBookmark:bookmark]) != nil)
	{
		connection.delegate = self;
	
		[connection requestSupportedAuthenticationMethodsWithOptions:nil completionHandler:^(NSError *error, NSArray<OCAuthenticationMethodIdentifier> *supportMethods) {
			OCLog(@"Error: %@ Supported methods: %@", error, supportMethods);
			
			[receivedReplyExpectation fulfill];
		}];
	}

	[self waitForExpectationsWithTimeout:60 handler:nil];
}

- (void)connection:(OCConnection *)connection request:(OCHTTPRequest *)request certificate:(OCCertificate *)certificate validationResult:(OCCertificateValidationResult)validationResult validationError:(NSError *)validationError recommendsProceeding:(BOOL)recommendsProceeding proceedHandler:(OCConnectionCertificateProceedHandler)proceedHandler
{
	OCLog(@"Connection asked for user confirmation of certificate for %@, would recommend: %d", certificate.hostName, recommendsProceeding);
	proceedHandler(YES, nil);
}

- (void)testAuthenticationMethodDetectionManualRedirectHandling
{
	XCTestExpectation *receivedReplyExpectation = [self expectationWithDescription:@"Received reply"];
	XCTestExpectation *receivedRedirectExpectation = [self expectationWithDescription:@"Received redirect"];
	XCTestExpectation *receivedMethodsExpectation = [self expectationWithDescription:@"Received methods"];

	OCBookmark *bookmark;
	OCConnection *connection;

	bookmark = [OCBookmark bookmarkForURL:OCTestTarget.insecureTargetURL];

	if ((connection = [[OCConnection alloc] initWithBookmark:bookmark]) != nil)
	{
		[connection requestSupportedAuthenticationMethodsWithOptions:nil completionHandler:^(NSError *error, NSArray<OCAuthenticationMethodIdentifier> *supportMethods) {
			OCLog(@"1 - Error: %@ - Supported methods: %@", error, supportMethods);

			if ([error isOCErrorWithCode:OCErrorAuthorizationRedirect])
			{
				NSURL *redirectURLBase;
				
				[receivedRedirectExpectation fulfill];
			
				if ((redirectURLBase = [error ocErrorInfoDictionary][OCAuthorizationMethodAlternativeServerURLKey]) != nil)
				{
					connection.bookmark.url = redirectURLBase;

					[connection requestSupportedAuthenticationMethodsWithOptions:nil completionHandler:^(NSError *error, NSArray<OCAuthenticationMethodIdentifier> *supportMethods) {
						OCLog(@"2 - Error: %@ - Supported methods: %@", error, supportMethods);
			
						[receivedReplyExpectation fulfill];
						
						if (supportMethods.count > 0)
						{
							[receivedMethodsExpectation fulfill];
						}
					}];
				}
			}
		}];
	}

	[self waitForExpectationsWithTimeout:60 handler:nil];
}

- (void)testAuthenticationMethodDetectionAutomaticRedirectHandling
{
	XCTestExpectation *receivedReplyExpectation = [self expectationWithDescription:@"Received reply"];
	XCTestExpectation *receivedAuthMethodsExpectation = [self expectationWithDescription:@"Retrieved auth methods"];

	OCBookmark *bookmark;
	OCConnection *connection;

	// bookmark = [OCBookmark bookmarkForURL:[NSURL URLWithString:@"http://opencloud-io.lan/"]];
	bookmark = [OCBookmark bookmarkForURL:OCTestTarget.insecureTargetURL];

	if ((connection = [[OCConnection alloc] initWithBookmark:bookmark]) != nil)
	{
		[connection requestSupportedAuthenticationMethodsWithOptions:@{ OCAuthenticationMethodAllowURLProtocolUpgradesKey : @(YES) } completionHandler:^(NSError *error, NSArray<OCAuthenticationMethodIdentifier> *supportMethods) {
			OCLog(@"Supported methods: %@", supportMethods);
			
			if (supportMethods.count > 0)
			{
				[receivedAuthMethodsExpectation fulfill];
			}
			
			[receivedReplyExpectation fulfill];
		}];
	}

	[self waitForExpectationsWithTimeout:60 handler:nil];
}

- (void)testAuthenticationMethodDetectionWithoutAutomaticRedirectHandling
{
	XCTestExpectation *receivedReplyExpectation = [self expectationWithDescription:@"Received reply"];
	XCTestExpectation *receivedAuthMethodsExpectation = [self expectationWithDescription:@"Retrieved auth methods"];

	OCBookmark *bookmark;
	OCConnection *connection;

	// bookmark = [OCBookmark bookmarkForURL:[NSURL URLWithString:@"http://opencloud-io.lan/"]];
	bookmark = [OCBookmark bookmarkForURL:OCTestTarget.insecureTargetURL];

	if ((connection = [[OCConnection alloc] initWithBookmark:bookmark]) != nil)
	{
		[connection requestSupportedAuthenticationMethodsWithOptions:nil completionHandler:^(NSError *error, NSArray<OCAuthenticationMethodIdentifier> *supportMethods) {
			OCLog(@"Supported methods: %@", supportMethods);
			
			if (supportMethods.count == 0)
			{
				[receivedAuthMethodsExpectation fulfill];
			}
			
			[receivedReplyExpectation fulfill];
		}];
	}

	[self waitForExpectationsWithTimeout:60 handler:nil];
}

- (void)testRedirectionBaseExtraction
{
	NSURL *baseURL;

	// https://origin.server/status.php -> https://target.server/status.php
	baseURL = [OCConnection extractBaseURLFromRedirectionTargetURL:[NSURL URLWithString:@"https://target.server/status.php"] originalURL:[NSURL URLWithString:@"https://origin.server/status.php"] originalBaseURL:[NSURL URLWithString:@"https://origin.server/"] fallbackToRedirectionTargetURL:NO];

	NSLog(@"baseURL=%@", baseURL);
	XCTAssert([baseURL.absoluteString isEqual:@"https://target.server/"]);

	// https://origin.server/ -> https://target.server/status.php
	baseURL = [OCConnection extractBaseURLFromRedirectionTargetURL:[NSURL URLWithString:@"https://target.server/status.php"] originalURL:[NSURL URLWithString:@"https://origin.server/"] originalBaseURL:[NSURL URLWithString:@"https://origin.server/"] fallbackToRedirectionTargetURL:YES];

	NSLog(@"baseURL=%@", baseURL);
	XCTAssert([baseURL.absoluteString isEqual:@"https://target.server/"]);

	// https://origin.server/ -> https://target.server/opencloud/status.php
	baseURL = [OCConnection extractBaseURLFromRedirectionTargetURL:[NSURL URLWithString:@"https://target.server/opencloud/status.php"] originalURL:[NSURL URLWithString:@"https://origin.server/"] originalBaseURL:[NSURL URLWithString:@"https://origin.server/"] fallbackToRedirectionTargetURL:YES];

	NSLog(@"baseURL=%@", baseURL);
	XCTAssert([baseURL.absoluteString isEqual:@"https://target.server/opencloud/"]);

	// https://origin.server/status.php -> https://target.server/
	baseURL = [OCConnection extractBaseURLFromRedirectionTargetURL:[NSURL URLWithString:@"https://target.server/"] originalURL:[NSURL URLWithString:@"https://origin.server/status.php"] originalBaseURL:[NSURL URLWithString:@"https://origin.server/"] fallbackToRedirectionTargetURL:YES];

	NSLog(@"baseURL=%@", baseURL);
	XCTAssert([baseURL.absoluteString isEqual:@"https://target.server/"]);

	// https://origin.server/ -> https://target.server/
	baseURL = [OCConnection extractBaseURLFromRedirectionTargetURL:[NSURL URLWithString:@"https://target.server/"] originalURL:[NSURL URLWithString:@"https://origin.server/"] originalBaseURL:[NSURL URLWithString:@"https://origin.server/"] fallbackToRedirectionTargetURL:YES];

	NSLog(@"baseURL=%@", baseURL);
	XCTAssert([baseURL.absoluteString isEqual:@"https://target.server/"]);

	// https://origin.server/status.php -> https://target.server/opencloud/
	baseURL = [OCConnection extractBaseURLFromRedirectionTargetURL:[NSURL URLWithString:@"https://target.server/opencloud/"] originalURL:[NSURL URLWithString:@"https://origin.server/status.php"] originalBaseURL:[NSURL URLWithString:@"https://origin.server/"] fallbackToRedirectionTargetURL:YES];

	NSLog(@"baseURL=%@", baseURL);
	XCTAssert([baseURL.absoluteString isEqual:@"https://target.server/opencloud/"]);

	// https://origin.server/status.php -> https://target.server/opencloud/status.php
	baseURL = [OCConnection extractBaseURLFromRedirectionTargetURL:[NSURL URLWithString:@"https://target.server/opencloud/status.php"] originalURL:[NSURL URLWithString:@"https://origin.server/status.php"] originalBaseURL:[NSURL URLWithString:@"https://origin.server/"] fallbackToRedirectionTargetURL:YES];

	NSLog(@"baseURL=%@", baseURL);
	XCTAssert([baseURL.absoluteString isEqual:@"https://target.server/opencloud/"]);

	// https://origin.server/status.php -> https://origin.server/opencloud/status.php
	baseURL = [OCConnection extractBaseURLFromRedirectionTargetURL:[NSURL URLWithString:@"https://origin.server/opencloud/status.php"] originalURL:[NSURL URLWithString:@"https://origin.server/status.php"] originalBaseURL:[NSURL URLWithString:@"https://origin.server/"] fallbackToRedirectionTargetURL:NO];

	NSLog(@"baseURL=%@", baseURL);
	XCTAssert([baseURL.absoluteString isEqual:@"https://origin.server/opencloud/"]);

	// https://origin.server/dav/files/ -> https://origin.server/opencloud/dav/files/
	baseURL = [OCConnection extractBaseURLFromRedirectionTargetURL:[NSURL URLWithString:@"https://origin.server/opencloud/dav/files/"] originalURL:[NSURL URLWithString:@"https://origin.server/dav/files/"] originalBaseURL:[NSURL URLWithString:@"https://origin.server/"] fallbackToRedirectionTargetURL:NO];

	NSLog(@"baseURL=%@", baseURL);
	XCTAssert([baseURL.absoluteString isEqual:@"https://origin.server/opencloud/"]);

	// https://origin.server/dav/files/ -> https://target.server/opencloud/dav/files/
	baseURL = [OCConnection extractBaseURLFromRedirectionTargetURL:[NSURL URLWithString:@"https://target.server/opencloud/dav/files/"] originalURL:[NSURL URLWithString:@"https://origin.server/dav/files/"] originalBaseURL:[NSURL URLWithString:@"https://origin.server/"] fallbackToRedirectionTargetURL:NO];

	NSLog(@"baseURL=%@", baseURL);
	XCTAssert([baseURL.absoluteString isEqual:@"https://target.server/opencloud/"]);

	// https://origin.server/status.php -> https://origin.server/opencloud/
	baseURL = [OCConnection extractBaseURLFromRedirectionTargetURL:[NSURL URLWithString:@"https://origin.server/opencloud/"] originalURL:[NSURL URLWithString:@"https://origin.server/status.php"] originalBaseURL:[NSURL URLWithString:@"https://origin.server/"] fallbackToRedirectionTargetURL:NO];

	NSLog(@"baseURL=%@", baseURL);
	XCTAssert(baseURL == nil);

	baseURL = [OCConnection extractBaseURLFromRedirectionTargetURL:[NSURL URLWithString:@"https://origin.server/opencloud/"] originalURL:[NSURL URLWithString:@"https://origin.server/status.php"] originalBaseURL:[NSURL URLWithString:@"https://origin.server/"] fallbackToRedirectionTargetURL:YES];

	NSLog(@"baseURL=%@", baseURL);
	XCTAssert([baseURL.absoluteString isEqual:@"https://origin.server/opencloud/"]);
}

#pragma mark - Sorting and filtering
- (void)testAuthenticationMethodSorting
{
	NSArray <OCAuthenticationMethodIdentifier> *authMethods = @[ OCAuthenticationMethodIdentifierBasicAuth, @"other-method", OCAuthenticationMethodIdentifierOAuth2 ];
	NSArray <OCAuthenticationMethodIdentifier> *expectedMethods = @[ OCAuthenticationMethodIdentifierOAuth2, OCAuthenticationMethodIdentifierBasicAuth, @"other-method"];

	NSArray <OCAuthenticationMethodIdentifier> *filteredAndSorted = [OCConnection filteredAndSortedMethodIdentifiers:authMethods allowedMethodIdentifiers:nil preferredMethodIdentifiers:@[OCAuthenticationMethodIdentifierOAuth2, OCAuthenticationMethodIdentifierBasicAuth]];
	
	XCTAssert([filteredAndSorted isEqualToArray:expectedMethods], @"Result has expected order and content");
}

- (void)testAuthenticationMethodFiltering
{
	NSArray <OCAuthenticationMethodIdentifier> *authMethods = @[ OCAuthenticationMethodIdentifierBasicAuth, @"other-method", OCAuthenticationMethodIdentifierOAuth2 ];
	NSArray <OCAuthenticationMethodIdentifier> *expectedMethods = @[ OCAuthenticationMethodIdentifierOAuth2];

	NSArray <OCAuthenticationMethodIdentifier> *filteredAndSorted = [OCConnection filteredAndSortedMethodIdentifiers:authMethods allowedMethodIdentifiers:@[OCAuthenticationMethodIdentifierOAuth2] preferredMethodIdentifiers:@[OCAuthenticationMethodIdentifierOAuth2, OCAuthenticationMethodIdentifierBasicAuth]];
	
	XCTAssert([filteredAndSorted isEqualToArray:expectedMethods], @"Result has expected order and content");
}


- (void)testAuthenticationMethodSortingAndFiltering
{
	NSArray <OCAuthenticationMethodIdentifier> *authMethods = @[ OCAuthenticationMethodIdentifierBasicAuth, @"other-method", OCAuthenticationMethodIdentifierOAuth2 ];
	NSArray <OCAuthenticationMethodIdentifier> *expectedMethods = @[ OCAuthenticationMethodIdentifierOAuth2, OCAuthenticationMethodIdentifierBasicAuth];

	NSArray <OCAuthenticationMethodIdentifier> *filteredAndSorted = [OCConnection filteredAndSortedMethodIdentifiers:authMethods allowedMethodIdentifiers:expectedMethods preferredMethodIdentifiers:expectedMethods];
	
	XCTAssert([filteredAndSorted isEqualToArray:expectedMethods], @"Result has expected order and content");
}

@end
