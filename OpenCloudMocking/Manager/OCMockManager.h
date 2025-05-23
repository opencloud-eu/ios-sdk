//
//  OCMockManager.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 11.07.18.
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

#import <Foundation/Foundation.h>

typedef NSString* OCMockLocation NS_TYPED_ENUM;

@interface OCMockManager : NSObject
{
	NSMutableDictionary <OCMockLocation, id> *_mockBlocksByLocation;
}

@property(class,readonly,nonatomic) OCMockManager *sharedMockManager;

- (void)addMockingBlocks:(NSDictionary <OCMockLocation, id> *)mockingBlocks; //!< Adds blocks to mock methods. Provide a dictionary that assigns the mocking blocks to the mock locations. CAUTION: do not use this API from Swift, as it will pass Swift functions, not Objective-C blocks in the dictionary. Instead, use an extension on OCMockManager that iterates through the dictionary and calls -setMockingBlock:forLocation: for every key/value pair.
- (void)setMockingBlock:(id)block forLocation:(OCMockLocation)location; //!< Add/remove a block to mock methods for a mock location.
- (void)removeAllMockingBlocks; //!< Remove all mocking blocks.
- (void)removeMockingBlockAtLocation:(OCMockLocation)mockLocation; //!< Remove the mocking block for a particular location.
- (void)removeMockingBlocksForClass:(Class)aClass; //!< Remove all mocking blocks for a particular class.

- (id)mockingBlockForLocation:(OCMockLocation)mockLocation; //!< Returns the mocking block for the provided location.

@end

#import "NSObject+OCMockManager.h"
