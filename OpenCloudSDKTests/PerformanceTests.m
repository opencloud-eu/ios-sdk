//
//  PerformanceTests.m
//  OpenCloudSDKTests
//
//  Created by Felix Schwarz on 07.12.18.
//  Copyright © 2018 ownCloud GmbH. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OpenCloudSDK/OpenCloudSDK.h>

#import "OCDetailedPerformanceTestCase.h"

//@interface PerformanceTests : OCDetailedPerformanceTestCase
//
//@end
//
//@implementation PerformanceTests
//
//#pragma mark - PROPFIND XML decoding performance
//// Test deactivated because the private API used in this test (+knownMemoryMetrics) is no longer available
//- (void)testPROPFINDXMLDecodingPerformance
//{
//	[self measureBlock:^{
//		NSURL *xmlResponseDataURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"largePropFindResponse1000" withExtension:@"xml"];
//		NSData *xmlResponseData = [NSData dataWithContentsOfURL:xmlResponseDataURL];
//
//		OCXMLParser *xmlParser = [[OCXMLParser alloc] initWithData:xmlResponseData];
//
//		[xmlParser addObjectCreationClasses:@[ [OCItem class], [NSError class] ]];
//
//		[xmlParser parse];
//
//		OCLog(@"%lu parsed objects, %lu errors", (unsigned long)xmlParser.parsedObjects.count, xmlParser.errors.count);
//	}];
//}
//
//@end
