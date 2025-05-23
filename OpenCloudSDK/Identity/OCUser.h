//
//  OCUser.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 22.02.18.
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

NS_ASSUME_NONNULL_BEGIN

typedef NSString* OCUserIdentifier; //!< Internal SDK unique identifier for the user

@interface OCUser : NSObject <NSSecureCoding, NSCopying>
{
	UIImage *_avatar;
	NSNumber *_forceIsRemote;
}

@property(nullable,strong) NSString *displayName; //!< Display name of the user (f.ex. "John Appleseed")

@property(nullable,strong) NSString *userName; //!< User name of the user (f.ex. "jappleseed")

@property(nullable,strong) NSString *emailAddress; //!< Email address of the user (f.ex. "jappleseed@opencloud.eu")

@property(nonatomic,readonly) BOOL isRemote; //!< Returns YES if the userName contains an @ sign
@property(nullable,readonly) NSString *remoteUserName; //!< Returns the part before the @ sign for usernames containing an @ sign (nil otherwise)
@property(nullable,readonly) NSString *remoteHost; //!< Returns the part after the @ sign for usernames containing an @ sign (nil otherwise)

@property(nullable,readonly) OCUserIdentifier userIdentifier; //!< Unique SDK internal identifier for the user
@property(nullable,readonly) NSString *localizedInitials; //!< Returns localized initials for user

+ (nullable NSString *)localizedInitialsForName:(NSString *)name;

+ (instancetype)userWithUserName:(nullable NSString *)userName displayName:(nullable NSString *)displayName;
+ (instancetype)userWithUserName:(nullable NSString *)userName displayName:(nullable NSString *)displayName isRemote:(BOOL)isRemote;

@end

NS_ASSUME_NONNULL_END
