//
//  OCTypes.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 06.02.18.
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

#ifndef OCTypes_h
#define OCTypes_h

typedef NSString* OCPath; //!< NSString representing the path relative to the server's root directory.

typedef NSString* OCDriveID; //!< Unique identifier for an OpenCloud drive / space. old server items have no drive ID.

typedef NSUInteger OCSeed; //!< Generic seed value type. Higher values mean newer objects.

typedef NSString* OCLocalID; //!< Unique local identifier of the item (persists over lifetime of file, incl. across modifications and placeholder -> item transition).

typedef NSString* OCFileID; //!< Unique identifier of the item on the server (persists over lifetime of file, incl. across modifications) (files and folders)
typedef NSString* OCFileETag; //!< Identifier unique to a specific combination of contents and metadata. Can be used to detect changes. (files and folders)

typedef NSString* OCFileIDUniquePrefix; //!< Unique fileID prefix of an item on the server. Background is that OC 10 FileIDs are composed of an 8-digit (%08ld) number and the server's ID (apparently identical across files). That number is unique for every file and also used as the number component in old server private links. By using a prefix here, it's possible to support both old server-style fileID prefixes as well as future full-length fileIDs for searching for items.

typedef NSString* OCMIMEType; //!< MIME Type (f.ex. "application/msexcel")
typedef NSString* OCTypeAlias; //!< Type Alias (f.ex. "x-office/spreadsheet" for "application/msexcel"). For MIME types where no alias exists, the alias is (OCTypeAliasMIMEPrefix + mimeType)
typedef NSString* OCFileExtension; //!< File extension string (without leading dot)

typedef NSString* OCLocalAttribute NS_TYPED_ENUM; //!< Identifier uniquely identifying a local attribute

typedef NSNumber* OCItemFavorite; //!< Favorite status of an item (boolean)
typedef NSString* OCItemPropertyName NS_TYPED_ENUM; //!< Name of an item property

typedef NSString* OCItemDownloadTriggerID NS_TYPED_ENUM; //!< Identifier of what triggered the download of an item

typedef id OCDatabaseID; //!< Object referencing the item in the database (OCDatabase-specific, OCItem's NSSecureCoding support assumes NSValue or NSValue subclass).
typedef NSNumber* OCDatabaseTimestamp; //!< ((NSUInteger)NSDate.timeIntervalSinceReferenceDate) value an entry was added to or last updated in the database.

typedef NSNumber* OCSyncAnchor; //!< Sync Anchor (running number, increasing in value with every change made)
typedef NSUUID* OCCoreRunIdentifier;

typedef void(^OCCompletionHandler)(id sender, NSError *error);

typedef void(^OCConnectionAuthenticationAvailabilityHandler)(NSError *error, BOOL authenticationIsAvailable);

typedef NSString* OCSyncActionIdentifier NS_TYPED_ENUM;
typedef NSString* OCSyncActionParameter NS_TYPED_ENUM;
typedef NSString* OCSyncActionCategory NS_TYPED_ENUM;
typedef NSNumber* OCSyncRecordID;
typedef NSNumber* OCSyncRecordRevision;

typedef NSString* OCSyncReason NS_TYPED_ENUM; //!< Reason a sync action has been started (f.ex. user, available offline, ..)

typedef NSNumber* OCSyncLaneID;
typedef NSString* OCSyncLaneTag;

typedef NSDictionary<NSString*,id<NSSecureCoding>>* OCCodableDict;
typedef NSMutableDictionary<NSString*,id<NSSecureCoding>>* OCMutableCodableDict;

typedef NSString* OCActionTrackingID; //!< Identifier used to track a triggered action's progress / state

typedef NSString *OCKQLQuery; //!< KQL query string

#endif /* OCTypes_h */
