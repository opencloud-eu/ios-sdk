//
//  OCBookmark.h
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

#import <Foundation/Foundation.h>
#import "OCAuthenticationMethod.h"
#import "OCCertificate.h"
#import "OCDatabase+Versions.h"
#import "OCViewProvider.h"
#import "OCUser.h"
#import "OCCertificateStore.h"

typedef NSUUID* OCBookmarkUUID;
typedef NSString* OCBookmarkUUIDString;

typedef NS_ENUM(NSUInteger, OCBookmarkAuthenticationDataStorage)
{
	OCBookmarkAuthenticationDataStorageKeychain, 	//!< Store authenticationData in the keychain. Default.
	OCBookmarkAuthenticationDataStorageMemory	//!< Store authenticationData in memory. Should only be used temporarily, for f.ex. editing contexts, where temporarily decoupling the data from the keychain can be desirable.
};

typedef NSString* OCBookmarkUserInfoKey NS_TYPED_ENUM;

typedef NSString* OCBookmarkCapability NS_TYPED_ENUM;

NS_ASSUME_NONNULL_BEGIN

@interface OCBookmark : NSObject <NSSecureCoding, NSCopying>

@property(readonly) OCBookmarkUUID uuid; //!< UUID uniquely identifying the bookmark

@property(strong,nullable) NSString *name; //!< Name of the server
@property(strong,nullable) NSURL *url; //!< URL to use to connect to the server

@property(strong,nullable) NSURL *originURL; //!< URL originally provided by the user, which then redirected to .url. In case .url becomes invalid, the originURL can be used to find the new server. If originURL is set, UI should present it prominently - while also displaying .url near it.

@property(strong,nullable) NSString *serverLocationUserName; //!< User name to use for server location

@property(strong,nullable,nonatomic) id<OCViewProvider> avatar; //!< Object that can provide a view to display the avatar of the user

@property(readonly,nullable) NSString *userName; //!< Convenience method for accessing the userName stored in the authenticationData. Use .user.userName instead if possible.
@property(strong,nullable) NSString *userDisplayName; //!< Display name of a user. Please use .user.userDisplayName instead.
@property(strong,nullable) OCUser *user; //!< User object of the bookmark's account owner. Available / kept up-to-date after every login.

@property(strong,nullable) OCCertificateStore *certificateStore; //!< Certificate store
@property(readonly,nullable) OCCertificate *primaryCertificate; //!< Primary certificate for the bookmark (usually the certificate for url.host - or the only certificate in the store)

@property(strong,nullable) OCAuthenticationMethodIdentifier authenticationMethodIdentifier; //!< Identifies the authentication method to use
@property(strong,nonatomic,nullable) NSData *authenticationData; //!< OCAuthenticationMethod's data (opaque) needed to log into the server. Backed by keychain or memory depending on .authenticationDataStorage.
@property(readonly,nonatomic,nullable) OCAuthenticationDataID authenticationDataID; //!< Unique ID of the currently set authentication data. Backed by .authenticationData.
@property(assign,nonatomic) OCBookmarkAuthenticationDataStorage authenticationDataStorage; //! Determines where to store authenticationData. Keychain by default. Changing the storage copies the data from the old to the new storage.
@property(strong,nullable) NSDate *authenticationValidationDate; //!< The date that the authenticationData was last known to be in valid state (typically changed when editing/creating bookmarks, used to f.ex. automatically handle sync issues predating that date).

@property(assign) OCDatabaseVersion databaseVersion; //!< The version of the database after the last update. A 0 value indicates a pre-11.6 bookmark.

@property(strong,nonatomic) NSMutableDictionary<OCBookmarkUserInfoKey, id<NSObject,NSSecureCoding>> *userInfo; //!< Dictionary for storing app-specific / custom properties alongside the bookmark

#pragma mark - Creation
+ (instancetype)bookmarkForURL:(NSURL *)url; //!< Creates a bookmark for the OpenCloud server with the specified URL.

#pragma mark - Persist / Restore
+ (instancetype)bookmarkFromBookmarkData:(NSData *)bookmarkData; //!< Creates a bookmark from BookmarkData.
- (nullable NSData *)bookmarkData; //!< Returns the BookmarkData for the bookmark, suitable for saving to disk.

#pragma mark - Data replacement
- (void)setValuesFrom:(OCBookmark *)sourceBookmark; //!< Replaces all values in the receiving bookmark with those in the source bookmark.
- (void)setLastUserName:(nullable NSString *)userName; //!< Replaces the internally stored fallback user name returned by .userName for when no authentication data is available.

#pragma mark - Capabilities
@property(strong,nullable,nonatomic) NSSet<OCBookmarkCapability> *capabilities;
- (void)addCapability:(OCBookmarkCapability)capability;
- (void)removeCapability:(OCBookmarkCapability)capability;
- (BOOL)hasCapability:(OCBookmarkCapability)capability;

#pragma mark - Metadata storage
@property(strong,nullable) NSURL *metaDataStorageURL; //!< URL to store bookmark data in (f.ex. certificates, avatar images, ..)

- (nullable NSError *)storeMetadata;

#pragma mark - Certificate approval
- (NSNotificationName)certificateUserApprovalUpdateNotificationName; //!< Notification that gets sent if the bookmark's certificate user-approved status changed
- (void)postCertificateUserApprovalUpdateNotification; //!< Posts a .certificateUserApprovalUpdateNotificationName notification

@end

extern OCBookmarkUserInfoKey OCBookmarkUserInfoKeyStatusInfo; //!<  .userInfo key with a NSDictionary holding the info from "status.php".
extern OCBookmarkUserInfoKey OCBookmarkUserInfoKeyAllowHTTPConnection; //!< .userInfo key with a NSDate value. To be set to the date that the user was informed and allowed the usage of HTTP. To be removed otherwise.
extern OCBookmarkUserInfoKey OCBookmarkUserInfoKeyBookmarkCreation; //!<  .userInfo key with a NSDictionary holding information on the creation of the bookmark.

extern OCBookmarkCapability OCBookmarkCapabilityDrives; //!< This bookmark is drive-based.
extern OCBookmarkCapability OCBookmarkCapabilityFavorites; //!< This bookmark supports favorites.

extern NSNotificationName OCBookmarkAuthenticationDataChangedNotification; //!< Name of notification that is sent whenever a bookmark's authenticationData is changed. The object of the notification is the bookmark. Sent only if .authenticationDataStorage is OCBookmarkAuthenticationDataStorageKeychain.

extern NSNotificationName OCBookmarkUpdatedNotification; //!< Name of notification that can be sent by third parties after completing an update to a bookmark.

NS_ASSUME_NONNULL_END
