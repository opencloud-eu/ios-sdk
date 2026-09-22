//
//  ODataTests.m
//  OpenCloudSDKTests
//
//  Created by Markus Goetz on 22.09.26.
//  Copyright © 2026 OpenCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2026, OpenCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import <XCTest/XCTest.h>

#import <OpenCloudSDK/OpenCloudSDK.h>
#import "OCTestTarget.h"
#import "OCConnection+OData.h"
#import "GADrive.h"

// Tests for the OData request path, all driven through OCHostSimulator: no test in here touches the
// network, so the whole class is safe to run unattended (f.ex. from CI).
@interface ODataTests : XCTestCase
@end

@implementation ODataTests

// Runs a drive-list-shaped OData request against a simulated host answering every request with the
// given status code and body, then hands the outcome to resultHandler.
- (void)_runODataRequestWithStatusCode:(OCHTTPStatusCode)statusCode contentType:(NSString *)contentType body:(NSString *)body resultHandler:(void(^)(NSError * _Nullable error, id _Nullable result))resultHandler
{
	OCBookmark *bookmark = [OCBookmark bookmarkForURL:OCTestTarget.secureTargetURL];
	OCConnection *connection = [[OCConnection alloc] initWithBookmark:bookmark];
	OCHostSimulator *simulator = [OCHostSimulator new];
	XCTestExpectation *expectation = [self expectationWithDescription:@"OData request finished"];

	simulator.requestHandler = ^BOOL(OCConnection *connection, OCHTTPRequest *request, OCHostSimulatorResponseHandler responseHandler) {
		responseHandler(nil, [OCHostSimulatorResponse responseWithURL:request.url statusCode:statusCode headers:nil contentType:contentType body:body]);
		return (YES);
	};

	connection.hostSimulator = simulator;

	[connection requestODataAtURL:[bookmark.url URLByAppendingPathComponent:@"graph/v1.0/me/drives"]
		requireSignals:nil
		selectEntityID:nil
		selectProperties:nil
		filterString:nil
		entityClass:GADrive.class
		completionHandler:^(NSError * _Nullable error, id  _Nullable response) {
			resultHandler(error, response);
			[expectation fulfill];
		}];

	[self waitForExpectationsWithTimeout:20 handler:nil];
}

#pragma mark - Error responses (opencloud-eu/ios-sdk#18)

// The regression: a reverse proxy whose upstream is down answers 502 with an empty body. Before the
// fix this completed as (nil error, nil result), which the vault read as "this account has no drives"
// and used to detach every drive, purge its cached items and auto-remove Available Offline policies.
- (void)testODataGatewayErrorWithEmptyBodyIsAnError
{
	[self _runODataRequestWithStatusCode:OCHTTPStatusCodeBAD_GATEWAY contentType:@"text/plain" body:@"" resultHandler:^(NSError *error, id result) {
		XCTAssertNotNil(error, @"502 with an empty body must produce an error, not an empty drive list");
		XCTAssertNil(result, @"502 must not yield a result");
	}];
}

// Same failure reached with a body, as proxies that do write an error page produce.
- (void)testODataGatewayErrorWithHTMLBodyIsAnError
{
	[self _runODataRequestWithStatusCode:OCHTTPStatusCodeBAD_GATEWAY contentType:@"text/html" body:@"<html><body>502 Bad Gateway</body></html>" resultHandler:^(NSError *error, id result) {
		XCTAssertNotNil(error, @"502 with an HTML body must produce an error");
		XCTAssertNil(result, @"502 must not yield a result");
	}];
}

// A 200 with no body is not an empty collection either - it carries no OData payload at all.
- (void)testODataSuccessWithEmptyBodyIsAnError
{
	[self _runODataRequestWithStatusCode:OCHTTPStatusCodeOK contentType:@"application/json" body:@"" resultHandler:^(NSError *error, id result) {
		XCTAssertNotNil(error, @"200 without a body must produce an error rather than silent success");
		XCTAssertNil(result, @"200 without a body must not yield a result");
	}];
}

#pragma mark - Successful responses

// Guards the fix against over-reach: a genuinely empty collection must still succeed, and must arrive
// as an empty (non-nil) array so callers can tell it apart from "no data".
- (void)testODataEmptyCollectionIsSuccess
{
	[self _runODataRequestWithStatusCode:OCHTTPStatusCodeOK contentType:@"application/json" body:@"{\"value\":[]}" resultHandler:^(NSError *error, id result) {
		XCTAssertNil(error, @"An empty OData collection is a valid, successful response");
		XCTAssertNotNil(result, @"An empty collection must decode into an empty array, not nil");
		XCTAssertTrue([result isKindOfClass:NSArray.class], @"Result is an array");
		XCTAssertEqual(((NSArray *)result).count, 0, @"Result is empty");
	}];
}

// A populated collection still decodes as before.
- (void)testODataPopulatedCollectionIsSuccess
{
	NSString *body = @"{\"value\":[{\"id\":\"drive-1\",\"name\":\"Personal\",\"driveType\":\"personal\"}]}";

	[self _runODataRequestWithStatusCode:OCHTTPStatusCodeOK contentType:@"application/json" body:body resultHandler:^(NSError *error, id result) {
		XCTAssertNil(error, @"A populated collection is a successful response");
		XCTAssertTrue([result isKindOfClass:NSArray.class], @"Result is an array");
		XCTAssertEqual(((NSArray *)result).count, 1, @"Result carries the one drive");
	}];
}

// An OData error object in the body still wins over the status code mapping.
- (void)testODataErrorObjectIsReported
{
	NSString *body = @"{\"error\":{\"code\":\"invalidRequest\",\"message\":\"Nope\"}}";

	[self _runODataRequestWithStatusCode:OCHTTPStatusCodeOK contentType:@"application/json" body:body resultHandler:^(NSError *error, id result) {
		XCTAssertNotNil(error, @"An OData error object must be surfaced as an error");
		XCTAssertNil(result, @"An OData error must not yield a result");
	}];
}

@end
