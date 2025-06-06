//
//  OCCapabilities.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 15.03.19.
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

#import <Foundation/Foundation.h>
#import "OCChecksumAlgorithm.h"
#import "OCShare.h"
#import "OCTUSHeader.h"
#import "OCAppProvider.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSNumber* OCCapabilityBool;

@interface OCCapabilities : NSObject

#pragma mark - Version
@property(readonly,nullable,nonatomic) NSNumber *majorVersion;
@property(readonly,nullable,nonatomic) NSNumber *minorVersion;
@property(readonly,nullable,nonatomic) NSNumber *microVersion;

#pragma mark - Core
@property(readonly,nullable,nonatomic) NSNumber *pollInterval;
@property(readonly,nullable,nonatomic) NSString *webDAVRoot;

#pragma mark - Core : Status
@property(readonly,nullable,nonatomic) OCCapabilityBool installed;
@property(readonly,nullable,nonatomic) OCCapabilityBool maintenance;
@property(readonly,nullable,nonatomic) OCCapabilityBool needsDBUpgrade;
@property(readonly,nullable,nonatomic) NSString *version;
@property(readonly,nullable,nonatomic) NSString *versionString;
@property(readonly,nullable,nonatomic) NSString *edition;
@property(readonly,nullable,nonatomic) NSString *productName;
@property(readonly,nullable,nonatomic) NSString *hostName;

@property(readonly,nullable,nonatomic) NSString *longProductVersionString;

#pragma mark - Checksums
@property(readonly,nullable,nonatomic) NSArray<OCChecksumAlgorithmIdentifier> *supportedChecksumTypes;
@property(readonly,nullable,nonatomic) OCChecksumAlgorithmIdentifier preferredUploadChecksumType;

#pragma mark - DAV
@property(readonly,nullable,nonatomic) NSString *davChunkingVersion;
@property(readonly,nullable,nonatomic) NSArray<NSString *> *davReports;
@property(readonly,nullable,nonatomic) OCCapabilityBool davPropfindSupportsDepthInfinity;

#pragma mark - Spaces
@property(readonly,nullable,nonatomic) OCCapabilityBool spacesEnabled;
@property(readonly,nullable,nonatomic) NSString *spacesVersion;

#pragma mark - Password Policy
@property(readonly,nonatomic) BOOL passwordPolicyEnabled;
@property(readonly,nullable,nonatomic) NSNumber *passwordPolicyMinCharacters;
@property(readonly,nullable,nonatomic) NSNumber *passwordPolicyMaxCharacters;
@property(readonly,nullable,nonatomic) NSNumber *passwordPolicyMinLowerCaseCharacters;
@property(readonly,nullable,nonatomic) NSNumber *passwordPolicyMinUpperCaseCharacters;
@property(readonly,nullable,nonatomic) NSNumber *passwordPolicyMinDigits;
@property(readonly,nullable,nonatomic) NSNumber *passwordPolicyMinSpecialCharacters;
@property(readonly,nullable,nonatomic) NSString *passwordPolicySpecialCharacters;

#pragma mark - App Providers
@property(readonly,nullable,nonatomic) NSArray<OCAppProvider *> *appProviders;
@property(readonly,nullable,nonatomic) OCAppProvider *latestSupportedAppProvider; //!< Convenience method to return the latest supported and available app provider

#pragma mark - TUS
@property(readonly,nonatomic) BOOL tusSupported;
@property(readonly,nullable,nonatomic) OCTUSCapabilities tusCapabilities;
@property(readonly,nullable,nonatomic) NSArray<OCTUSVersion> *tusVersions;
@property(readonly,nullable,nonatomic) OCTUSVersion tusResumable;
@property(readonly,nullable,nonatomic) NSArray<OCTUSExtension> *tusExtensions;
@property(readonly,nullable,nonatomic) NSNumber *tusMaxChunkSize;
@property(readonly,nullable,nonatomic) OCHTTPMethod tusHTTPMethodOverride;

@property(readonly,nullable,nonatomic) OCTUSHeader *tusCapabilitiesHeader; //!< .tusCapabilities translated into an OCTUSHeader

#pragma mark - Files
@property(readonly,nullable,nonatomic) OCCapabilityBool supportsPrivateLinks;
@property(readonly,nullable,nonatomic) OCCapabilityBool supportsBigFileChunking;
@property(readonly,nullable,nonatomic) NSArray<NSString *> *blacklistedFiles;
@property(readonly,nullable,nonatomic) OCCapabilityBool supportsUndelete;
@property(readonly,nullable,nonatomic) OCCapabilityBool supportsVersioning;
@property(readonly,nullable,nonatomic) OCCapabilityBool supportsFavorites;

#pragma mark - Sharing
@property(readonly,nullable,nonatomic) OCCapabilityBool sharingAPIEnabled;
@property(readonly,nullable,nonatomic) OCCapabilityBool sharingResharing;
@property(readonly,nullable,nonatomic) OCCapabilityBool sharingGroupSharing;
@property(readonly,nullable,nonatomic) OCCapabilityBool sharingAutoAcceptShare;
@property(readonly,nullable,nonatomic) OCCapabilityBool sharingWithGroupMembersOnly;
@property(readonly,nullable,nonatomic) OCCapabilityBool sharingWithMembershipGroupsOnly;
@property(readonly,nullable,nonatomic) OCCapabilityBool sharingAllowed;
@property(readonly,nonatomic) OCSharePermissionsMask sharingDefaultPermissions;
@property(readonly,nullable,nonatomic) NSNumber *sharingSearchMinLength;
@property(readonly,class,nonatomic) NSInteger defaultSharingSearchMinLength;

#pragma mark - Sharing : Public
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingEnabled;
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingPasswordEnforced; //!< Controls whether a password is required for links (catch-all)
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingPasswordEnforcedForReadOnly; //!< Controls whether a password is required for read-only links
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingPasswordEnforcedForReadWrite; //!< Controls whether a password is required for read-write links
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingPasswordEnforcedForReadWriteDelete; //!< Controls whether a password is required for read-write-delete links
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingPasswordEnforcedForUploadOnly; //!< Controls whether a password is required for upload-only links
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingPasswordBlockRemovalForReadOnly; //!< Controls whether the removal of a password is blocked for read-only links
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingPasswordBlockRemovalForReadWrite; //!< Controls whether the removal of a password is blocked for read-write links
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingPasswordBlockRemovalForReadWriteDelete; //!< Controls whether the removal of a password is blocked for read-write-delete links
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingPasswordBlockRemovalForUploadOnly; //!< Controls whether the removal of a password is blocked for upload-only links

@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingExpireDateAddDefaultDate; //!< Controls whether a *default* expiration date should be set
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingExpireDateEnforceDateAndDaysDeterminesLastAllowedDate; //!< Controls whether .publicSharingDefaultExpireDateDays is enforced as maximum expiration date. Also, when set, an expiration date is REQUIRED.
@property(readonly,nullable,nonatomic) NSNumber *publicSharingDefaultExpireDateDays;
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingSendMail;
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingSocialShare;
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingUpload;
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingMultiple;
@property(readonly,nullable,nonatomic) OCCapabilityBool publicSharingSupportsUploadOnly;
@property(readonly,nullable,nonatomic) NSString *publicSharingDefaultLinkName;

#pragma mark - Sharing : User
@property(readonly,nullable,nonatomic) OCCapabilityBool userSharingSendMail;

#pragma mark - Sharing : User Enumeration
@property(readonly,nullable,nonatomic) OCCapabilityBool userEnumerationEnabled;
@property(readonly,nullable,nonatomic) OCCapabilityBool userEnumerationGroupMembersOnly;

#pragma mark - Sharing : Federation
@property(readonly,nullable,nonatomic) OCCapabilityBool federatedSharingIncoming;
@property(readonly,nullable,nonatomic) OCCapabilityBool federatedSharingOutgoing;

@property(readonly,nonatomic) BOOL federatedSharingSupported;

#pragma mark - Search
@property(readonly,nonatomic) BOOL serverSideSearchSupported; //!< Indicates if opencloud-style KQL-based server-side search is available
@property(readonly,nullable,nonatomic) NSArray<NSString *> *enabledServerSideSearchProperties; //!< Returns a list of enabled/supported server-side search properties (f.ex. "name", "mtime", "size", "mediatype", "type", "tag", "tags", "content", "scope")
- (nullable NSArray<NSString *> *)supportedKeywordsForServerSideSearchProperty:(NSString *)searchPropertyName; //!< Returns the server-provided list of supported keywords for that property (f.ex. "document", "spreadsheet", … for "mediatype")

#pragma mark - Notifications
@property(readonly,nullable,nonatomic) NSArray<NSString *> *notificationEndpoints;

#pragma mark - Raw JSON
@property(readonly,strong) NSDictionary<NSString *, id> *rawJSON;

- (instancetype)initWithRawJSON:(NSDictionary<NSString *, id> *)rawJSON;

@end

NS_ASSUME_NONNULL_END
