//
//  TestTools.h
//  OpenCloudSDKTests
//
//  Created by Felix Schwarz on 07.06.18.
//  Copyright © 2018 ownCloud GmbH. All rights reserved.
//

#import <OpenCloudSDK/OpenCloudSDK.h>
#import <XCTest/XCTest.h>

@interface OCVault (TestTools)

- (void)eraseSyncWithCompletionHandler:(OCCompletionHandler)completionHandler;

@end

@interface XCTestCase (LocalIDIntegrity)

- (OCDatabaseItemFilter)databaseSanityCheckFilter;

@end
