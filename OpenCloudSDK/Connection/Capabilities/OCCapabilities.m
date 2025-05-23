//
//  OCCapabilities.m
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

#import "OCCapabilities.h"
#import "OCMacros.h"
#import "OCConnection.h"
#import "NSObject+OCClassSettings.h"

#define WithDefault(val,def) (((val)==nil)?(def):(val))

static NSInteger _defaultSharingSearchMinLength = 2;

@interface OCCapabilities()
{
	NSDictionary<NSString *, id> *_capabilities;

	OCTUSHeader *_tusCapabilitiesHeader;
	NSArray<OCTUSVersion> *_tusVersions;
	NSArray<OCTUSExtension> *_tusExtensions;

	NSArray<OCAppProvider *> *_appProviders;
	OCAppProvider *_latestSupportedAppProvider;
}

@end

@implementation OCCapabilities

#pragma mark - Version
@dynamic majorVersion;
@dynamic minorVersion;
@dynamic microVersion;

#pragma mark - Core
@dynamic pollInterval;
@dynamic webDAVRoot;

#pragma mark - Core : Status
@dynamic installed;
@dynamic maintenance;
@dynamic needsDBUpgrade;
@dynamic version;
@dynamic versionString;
@dynamic edition;
@dynamic productName;
@dynamic hostName;
@dynamic supportedChecksumTypes;
@dynamic preferredUploadChecksumType;
@dynamic longProductVersionString;

#pragma mark - DAV
@dynamic davChunkingVersion;
@dynamic davReports;
@dynamic davPropfindSupportsDepthInfinity;

#pragma mark - TUS
@dynamic tusSupported;
@dynamic tusCapabilities;
@dynamic tusVersions;
@dynamic tusResumable;
@dynamic tusExtensions;
@dynamic tusMaxChunkSize;
@dynamic tusHTTPMethodOverride;

@dynamic tusCapabilitiesHeader;

#pragma mark - Files
@dynamic supportsPrivateLinks;
@dynamic supportsBigFileChunking;
@dynamic blacklistedFiles;
@dynamic supportsUndelete;
@dynamic supportsVersioning;

#pragma mark - Sharing
@dynamic sharingAPIEnabled;
@dynamic sharingResharing;
@dynamic sharingGroupSharing;
@dynamic sharingAutoAcceptShare;
@dynamic sharingWithGroupMembersOnly;
@dynamic sharingWithMembershipGroupsOnly;
@dynamic sharingAllowed;
@dynamic sharingDefaultPermissions;
@dynamic sharingSearchMinLength;

#pragma mark - Sharing : Public
@dynamic publicSharingEnabled;
@dynamic publicSharingPasswordEnforced;
@dynamic publicSharingPasswordEnforcedForReadOnly;
@dynamic publicSharingPasswordEnforcedForReadWrite;
@dynamic publicSharingPasswordEnforcedForReadWriteDelete;
@dynamic publicSharingPasswordEnforcedForUploadOnly;
@dynamic publicSharingPasswordBlockRemovalForReadOnly;
@dynamic publicSharingPasswordBlockRemovalForReadWrite;
@dynamic publicSharingPasswordBlockRemovalForReadWriteDelete;
@dynamic publicSharingPasswordBlockRemovalForUploadOnly;

@dynamic publicSharingExpireDateAddDefaultDate;
@dynamic publicSharingExpireDateEnforceDateAndDaysDeterminesLastAllowedDate;
@dynamic publicSharingDefaultExpireDateDays;
@dynamic publicSharingSendMail;
@dynamic publicSharingSocialShare;
@dynamic publicSharingUpload;
@dynamic publicSharingMultiple;
@dynamic publicSharingSupportsUploadOnly;
@dynamic publicSharingDefaultLinkName;

#pragma mark - Sharing : User
@dynamic userSharingSendMail;

#pragma mark - Sharing : User Enumeration
@dynamic userEnumerationEnabled;
@dynamic userEnumerationGroupMembersOnly;

#pragma mark - Sharing : Federation
@dynamic federatedSharingIncoming;
@dynamic federatedSharingOutgoing;

#pragma mark - Search
@dynamic serverSideSearchSupported;

#pragma mark - Notifications
@dynamic notificationEndpoints;

- (instancetype)initWithRawJSON:(NSDictionary<NSString *,id> *)rawJSON
{
	if ((self = [super init]) != nil)
	{
		_rawJSON = rawJSON;
		_capabilities = _rawJSON[@"ocs"][@"data"][@"capabilities"];
	}

	return (self);
}

#pragma mark - Helpers
- (NSNumber *)_castOrConvertToNumber:(id)value
{
	if ([value isKindOfClass:[NSString class]])
	{
		value = @([((NSString *)value) longLongValue]);
	}

	return (OCTypedCast(value, NSNumber));
}

#pragma mark - Version
- (NSNumber *)majorVersion
{
	return (OCTypedCast(_rawJSON[@"ocs"][@"data"][@"version"][@"major"], NSNumber));
}

- (NSNumber *)minorVersion
{
	return (OCTypedCast(_rawJSON[@"ocs"][@"data"][@"version"][@"minor"], NSNumber));
}

- (NSNumber *)microVersion
{
	return (OCTypedCast(_rawJSON[@"ocs"][@"data"][@"version"][@"micro"], NSNumber));
}

#pragma mark - Core
- (NSNumber *)pollInterval
{
	return (OCTypedCast(_capabilities[@"core"][@"pollinterval"], NSNumber));
}

- (NSString *)webDAVRoot
{
	return (OCTypedCast(_capabilities[@"core"][@"webdav-root"], NSString));
}

#pragma mark - Core : Status
- (OCCapabilityBool)installed
{
	return (OCTypedCast(_capabilities[@"core"][@"status"][@"installed"], NSNumber));
}

- (OCCapabilityBool)maintenance
{
	return (OCTypedCast(_capabilities[@"core"][@"status"][@"maintenance"], NSNumber));
}

- (OCCapabilityBool)needsDBUpgrade
{
	return (OCTypedCast(_capabilities[@"core"][@"status"][@"needsDbUpgrade"], NSNumber));
}

- (NSString *)version
{
	return (OCTypedCast(_capabilities[@"core"][@"status"][@"version"], NSString));
}

- (NSString *)versionString
{
	return (OCTypedCast(_capabilities[@"core"][@"status"][@"versionstring"], NSString));
}

- (NSString *)edition
{
	return (OCTypedCast(_capabilities[@"core"][@"status"][@"edition"], NSString));
}

- (NSString *)productName
{
	return (OCTypedCast(_capabilities[@"core"][@"status"][@"productname"], NSString));
}

- (NSString *)hostName
{
	return (OCTypedCast(_capabilities[@"core"][@"status"][@"hostname"], NSString));
}

- (NSString *)longProductVersionString
{
	NSDictionary *statusDict;

	if ((statusDict = OCTypedCast(_capabilities[@"core"][@"status"], NSDictionary)) != nil)
	{
		return ([OCConnection serverLongProductVersionStringFromServerStatus:statusDict]);
	}

	return (nil);
}

#pragma mark - Checksums
- (NSArray<OCChecksumAlgorithmIdentifier> *)supportedChecksumTypes
{
	return (OCTypedCast(_capabilities[@"checksums"][@"supportedTypes"], NSArray));
}

- (OCChecksumAlgorithmIdentifier)preferredUploadChecksumType
{
	return (OCTypedCast(_capabilities[@"checksums"][@"preferredUploadType"], NSString));
}

#pragma mark - DAV
- (NSString *)davChunkingVersion
{
	return (OCTypedCast(_capabilities[@"dav"][@"chunking"], NSString));
}

- (NSArray<NSString *> *)davReports
{
	return (OCTypedCast(_capabilities[@"dav"][@"reports"], NSArray));
}

- (OCCapabilityBool)davPropfindSupportsDepthInfinity
{
	return (OCTypedCast(_capabilities[@"dav"][@"propfind"][@"depth_infinity"], NSNumber));
}

#pragma mark - Spaces
- (OCCapabilityBool)spacesEnabled
{
	return (OCTypedCast(_capabilities[@"spaces"][@"enabled"], NSNumber));
}

- (NSString *)spacesVersion
{
	return (OCTypedCast(_capabilities[@"spaces"][@"version"], NSString));
}

#pragma mark - Password Policy
- (NSDictionary<NSString *, id> *)_passwordPolicy
{
	return (OCTypedCast(_capabilities[@"password_policy"], NSDictionary));
}

- (NSDictionary<NSString *, id> *)_passwordRequirements
{
	return (OCTypedCast(self._passwordPolicy[@"password_requirements"],NSDictionary));
}

- (BOOL)passwordPolicyEnabled
{
	if (self._passwordRequirements != nil) {
		return (self.passwordPolicyMinCharacters.integerValue > 0);
	}

	return (self._passwordPolicy != nil);
}

- (NSNumber *)passwordPolicyMinCharacters
{
	NSNumber *minimumCharacters = nil;

	if (self._passwordRequirements != nil) {
		// old server-style password policy
		minimumCharacters = OCTypedCast(self._passwordRequirements[@"minimum_characters"], NSNumber);
	} else {
		// OpenCloud-style password policy
		minimumCharacters = OCTypedCast(self._passwordPolicy[@"min_characters"], NSNumber);
	}

	if (minimumCharacters == nil)
	{
		NSUInteger minimumFromSum =
			self.passwordPolicyMinLowerCaseCharacters.integerValue +
			self.passwordPolicyMinUpperCaseCharacters.integerValue +
			self.passwordPolicyMinDigits.integerValue +
			self.passwordPolicyMinSpecialCharacters.integerValue;

		if (minimumFromSum > 0) {
			return (@(minimumFromSum));
		}
	}

	return (minimumCharacters);
}

- (NSNumber *)passwordPolicyMaxCharacters
{
	// OpenCloud-style password policy
	return (OCTypedCast(self._passwordPolicy[@"max_characters"], NSNumber));
}

- (NSNumber *)passwordPolicyMinLowerCaseCharacters
{
	if (self._passwordRequirements != nil) {
		// old server-style password policy
		return (OCTypedCast(OCTypedCast(OCTypedCast(self._passwordRequirements[@"configuration"], NSDictionary)[@"lower_case"], NSDictionary)[@"minimum"], NSNumber));
	}

	// OpenCloud-style password policy
	return (OCTypedCast(self._passwordPolicy[@"min_lowercase_characters"], NSNumber));
}

- (NSNumber *)passwordPolicyMinUpperCaseCharacters
{
	if (self._passwordRequirements != nil) {
		// old server-style password policy
		return (OCTypedCast(OCTypedCast(OCTypedCast(self._passwordRequirements[@"configuration"], NSDictionary)[@"upper_case"], NSDictionary)[@"minimum"], NSNumber));
	}

	// OpenCloud-style password policy
	return (OCTypedCast(self._passwordPolicy[@"min_uppercase_characters"], NSNumber));
}

- (NSNumber *)passwordPolicyMinDigits
{
	if (self._passwordRequirements != nil) {
		// old server-style password policy
		return (OCTypedCast(OCTypedCast(OCTypedCast(self._passwordRequirements[@"configuration"], NSDictionary)[@"numbers"], NSDictionary)[@"minimum"], NSNumber));
	}

	// OpenCloud-style password policy
	return (OCTypedCast(self._passwordPolicy[@"min_digits"], NSNumber));
}

- (NSNumber *)passwordPolicyMinSpecialCharacters
{
	if (self._passwordRequirements != nil) {
		// old server-style password policy
		return (OCTypedCast(OCTypedCast(OCTypedCast(self._passwordRequirements[@"configuration"], NSDictionary)[@"special_characters"], NSDictionary)[@"minimum"], NSNumber));
	}

	// OpenCloud-style password policy
	return (OCTypedCast(self._passwordPolicy[@"min_special_characters"], NSNumber));
}

- (NSString *)passwordPolicySpecialCharacters
{
	if (self.spacesEnabled.boolValue)
	{
		// OpenCloud special characters, as per:
		// - https://doc.opencloud.eu/opencloud/next/deployment/services/s-list/frontend.html (general idea)
		// - https://github.com/owncloud/ocis/pull/7195 (implementation description)
		// - https://github.com/opencloud-eu/opencloud/blob/main/vendor/github.com/cs3org/reva/v2/pkg/password/password_policies.go#L12 (actual implementation) <= mirrored here
		// - minus space, because that can lead to issues, especially if it is at the end
		return (@"!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~");
	}
	else
	{
	    // FIXME: delete this.
		// old server special characters
		if (self._passwordRequirements != nil)
		{
			// old server-style password policy
			NSDictionary<NSString *, id> *specialCharactersGenerateFromDict;

			if ((specialCharactersGenerateFromDict = OCTypedCast(OCTypedCast(OCTypedCast(self._passwordRequirements[@"configuration"], NSDictionary)[@"special_characters"], NSDictionary)[@"generate_from"], NSDictionary)) != nil)
			{
				if (OCTypedCast(specialCharactersGenerateFromDict[@"characters"],NSString).length > 0)
				{
					return(specialCharactersGenerateFromDict[@"characters"]);
				}

				if ([OCTypedCast(specialCharactersGenerateFromDict[@"any"],NSNumber) isEqual:@(YES)])
				{
					// Return same special chars as for OpenCloud
					return (@"!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~");
				}
			}
		}

		return (@"#!");
	}
}

#pragma mark - App Providers
- (NSArray<OCAppProvider *> *)appProviders
{
	if (_appProviders == nil)
	{
		NSArray<NSDictionary<NSString*,id> *> *jsonAppProviders;
		NSMutableArray<OCAppProvider *> *appProviders = [NSMutableArray new];

		if ((jsonAppProviders = OCTypedCast(_capabilities[@"files"][@"app_providers"], NSArray)) != nil)
		{
			for (id jsonAppProviderEntry in jsonAppProviders)
			{
				NSDictionary<NSString*,id> *jsonAppProviderDict;

				if ((jsonAppProviderDict = OCTypedCast(jsonAppProviderEntry, NSDictionary)) != nil)
				{
					NSNumber *enabledNumber = OCTypedCast(jsonAppProviderDict[@"enabled"], NSNumber);
					NSString *versionString = OCTypedCast(jsonAppProviderDict[@"version"], NSString);
					NSString *appsURLString = OCTypedCast(jsonAppProviderDict[@"apps_url"], NSString);
					NSString *openURLString = OCTypedCast(jsonAppProviderDict[@"open_url"], NSString);
					NSString *openWebURLString = OCTypedCast(jsonAppProviderDict[@"open_web_url"], NSString);
					NSString *newURLString = OCTypedCast(jsonAppProviderDict[@"new_url"], NSString);

					if ((enabledNumber != nil) && (versionString != nil))
					{
						OCAppProvider *appProvider = [OCAppProvider new];

						appProvider.enabled = enabledNumber.boolValue;
						appProvider.version = versionString;
						appProvider.appsURLPath = appsURLString;
						appProvider.openURLPath = openURLString;
						appProvider.openWebURLPath = openWebURLString;
						appProvider.createURLPath = newURLString;

						[appProviders addObject:appProvider];
					}
				}
			}
		}

		if (appProviders.count > 0)
		{
			_appProviders = appProviders;
		}
	}

	return (_appProviders);
}

- (OCAppProvider *)latestSupportedAppProvider
{
	if (_latestSupportedAppProvider == nil)
	{
		OCAppProvider *latestSupportedAppProvider = nil;

		for (OCAppProvider *appProvider in self.appProviders)
		{
			if (appProvider.isSupported)
			{
				// Assume that versions are returned in ascending order (simple first implementation)
				latestSupportedAppProvider = appProvider;
			}
		}

		_latestSupportedAppProvider = latestSupportedAppProvider;
	}

	return (_latestSupportedAppProvider);
}

#pragma mark - TUS
- (BOOL)tusSupported
{
	return (self.tusResumable.length > 0);
}

- (OCTUSCapabilities)tusCapabilities
{
	return (OCTypedCast(_capabilities[@"files"][@"tus_support"], NSDictionary));
}

- (NSArray<OCTUSVersion> *)tusVersions
{
	if (_tusVersions)
	{
		_tusVersions = [OCTypedCast(self.tusCapabilities[@"version"], NSString) componentsSeparatedByString:@","];
	}

	return (_tusVersions);
}

- (OCTUSVersion)tusResumable
{
	return(OCTypedCast(self.tusCapabilities[@"resumable"], NSString));
}

- (NSArray<OCTUSExtension> *)tusExtensions
{
	if (_tusExtensions == nil)
	{
		NSString *tusExtensionsString = OCTypedCast(self.tusCapabilities[@"extension"], NSString);

		_tusExtensions = [tusExtensionsString componentsSeparatedByString:@","];
	}

	return (_tusExtensions);
}

- (NSNumber *)tusMaxChunkSize
{
	return(OCTypedCast(self.tusCapabilities[@"max_chunk_size"], NSNumber));
}

- (OCHTTPMethod)tusHTTPMethodOverride
{
	NSString *httpMethodOverride = OCTypedCast(self.tusCapabilities[@"http_method_override"], NSString);

	if (httpMethodOverride.length == 0)
	{
		return (nil);
	}

	return(httpMethodOverride);
}

- (OCTUSHeader *)tusCapabilitiesHeader
{
	if ((_tusCapabilitiesHeader == nil) && self.tusSupported)
	{
		OCTUSHeader *header = [[OCTUSHeader alloc] init];

		header.extensions = self.tusExtensions;
		header.version = self.tusResumable;
		header.versions = self.tusVersions;

		header.maximumChunkSize = self.tusMaxChunkSize;

		_tusCapabilitiesHeader = header;
	}

	return (_tusCapabilitiesHeader);
}

#pragma mark - Files
- (OCCapabilityBool)supportsPrivateLinks
{
	return (OCTypedCast(_capabilities[@"files"][@"privateLinks"], NSNumber));
}

- (OCCapabilityBool)supportsBigFileChunking
{
	return (OCTypedCast(_capabilities[@"files"][@"bigfilechunking"], NSNumber));
}

- (NSArray <NSString *> *)blacklistedFiles
{
	return (OCTypedCast(_capabilities[@"files"][@"blacklisted_files"], NSArray));
}

- (OCCapabilityBool)supportsUndelete
{
	return (OCTypedCast(_capabilities[@"files"][@"undelete"], NSNumber));
}

- (OCCapabilityBool)supportsVersioning
{
	return (OCTypedCast(_capabilities[@"files"][@"versioning"], NSNumber));
}

- (OCCapabilityBool)supportsFavorites
{
	return (OCTypedCast(_capabilities[@"files"][@"favorites"], NSNumber));
}

#pragma mark - Sharing
- (OCCapabilityBool)sharingAPIEnabled
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"api_enabled"], NSNumber));
}

- (OCCapabilityBool)sharingResharing
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"resharing"], NSNumber));
}

- (OCCapabilityBool)sharingGroupSharing
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"group_sharing"], NSNumber));
}

- (OCCapabilityBool)sharingAutoAcceptShare
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"auto_accept_share"], NSNumber));
}

- (OCCapabilityBool)sharingWithGroupMembersOnly
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"share_with_group_members_only"], NSNumber));
}

- (OCCapabilityBool)sharingWithMembershipGroupsOnly
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"share_with_membership_groups_only"], NSNumber));
}

- (OCCapabilityBool)sharingAllowed
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"can_share"], NSNumber));
}

- (OCSharePermissionsMask)sharingDefaultPermissions
{
	return ((OCTypedCast(_capabilities[@"files_sharing"][@"default_permissions"], NSNumber)).integerValue);
}

- (NSNumber *)sharingSearchMinLength
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"search_min_length"], NSNumber));
}

+ (NSInteger)defaultSharingSearchMinLength
{
	return _defaultSharingSearchMinLength;
}

#pragma mark - Sharing : Public
- (OCCapabilityBool)publicSharingEnabled
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"enabled"], NSNumber));
}

- (OCCapabilityBool)publicSharingPasswordEnforced
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"password"][@"enforced"], NSNumber));
}

- (OCCapabilityBool)publicSharingPasswordEnforcedForReadOnly
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"password"][@"enforced_for"][@"read_only"], NSNumber));
}

- (OCCapabilityBool)publicSharingPasswordEnforcedForReadWrite
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"password"][@"enforced_for"][@"read_write"], NSNumber));
}

- (OCCapabilityBool)publicSharingPasswordEnforcedForReadWriteDelete
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"password"][@"enforced_for"][@"read_write_delete"], NSNumber));
}

- (OCCapabilityBool)publicSharingPasswordEnforcedForUploadOnly
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"password"][@"enforced_for"][@"upload_only"], NSNumber));
}

- (OCCapabilityBool)_blockPasswordRemovalDefault
{
	return ([OCConnection classSettingForOCClassSettingsKey:OCConnectionBlockPasswordRemovalDefault]);
}

- (OCCapabilityBool)publicSharingPasswordBlockRemovalForReadOnly
{
	return (WithDefault(OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"password"][@"block_password_removal"][@"read_only"], NSNumber), self._blockPasswordRemovalDefault));
}

- (OCCapabilityBool)publicSharingPasswordBlockRemovalForReadWrite
{
	return (WithDefault(OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"password"][@"block_password_removal"][@"read_write"], NSNumber), self._blockPasswordRemovalDefault));
}

- (OCCapabilityBool)publicSharingPasswordBlockRemovalForReadWriteDelete
{
	return (WithDefault(OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"password"][@"block_password_removal"][@"read_write_delete"], NSNumber), self._blockPasswordRemovalDefault));
}

- (OCCapabilityBool)publicSharingPasswordBlockRemovalForUploadOnly
{
	return (WithDefault(OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"password"][@"block_password_removal"][@"upload_only"], NSNumber), self._blockPasswordRemovalDefault));
}

- (OCCapabilityBool)publicSharingExpireDateAddDefaultDate
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"expire_date"][@"enabled"], NSNumber));
}

- (OCCapabilityBool)publicSharingExpireDateEnforceDateAndDaysDeterminesLastAllowedDate
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"expire_date"][@"enforced"], NSNumber));
}

- (NSNumber *)publicSharingDefaultExpireDateDays
{
	return ([self _castOrConvertToNumber:_capabilities[@"files_sharing"][@"public"][@"expire_date"][@"days"]]);
}

- (OCCapabilityBool)publicSharingSendMail
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"send_mail"], NSNumber));
}

- (OCCapabilityBool)publicSharingSocialShare
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"social_share"], NSNumber));
}

- (OCCapabilityBool)publicSharingUpload
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"upload"], NSNumber));
}

- (OCCapabilityBool)publicSharingMultiple
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"multiple"], NSNumber));
}

- (OCCapabilityBool)publicSharingSupportsUploadOnly
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"supports_upload_only"], NSNumber));
}

- (NSString *)publicSharingDefaultLinkName
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"public"][@"defaultPublicLinkShareName"], NSString));
}

#pragma mark - Sharing : User
- (OCCapabilityBool)userSharingSendMail
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"user"][@"send_mail"], NSNumber));
}

#pragma mark - Sharing : User Enumeration
- (OCCapabilityBool)userEnumerationEnabled
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"user_enumeration"][@"enabled"], NSNumber));
}

- (OCCapabilityBool)userEnumerationGroupMembersOnly
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"user_enumeration"][@"group_members_only"], NSNumber));
}

#pragma mark - Sharing : Federation
- (OCCapabilityBool)federatedSharingIncoming
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"federation"][@"incoming"], NSNumber));
}

- (OCCapabilityBool)federatedSharingOutgoing
{
	return (OCTypedCast(_capabilities[@"files_sharing"][@"federation"][@"outgoing"], NSNumber));
}

- (BOOL)federatedSharingSupported
{
	if (self.spacesEnabled.boolValue)
	{
		// OpenCloud bug: can't depend on federatedSharingIncoming and federatedSharingOutgoing: https://github.com/owncloud/ocis/issues/4788
		return (NO);
	}

	return (self.federatedSharingIncoming.boolValue || self.federatedSharingOutgoing.boolValue);
}

#pragma mark - Search
- (BOOL)serverSideSearchSupported
{
	return (OCTypedCast(_capabilities[@"search"], NSDictionary) != nil);
}

- (NSArray<NSString *> *)enabledServerSideSearchProperties
{
	NSDictionary<NSString *, NSDictionary *> *searchCapabilityDict = OCTypedCast(_capabilities[@"search"], NSDictionary);
	NSMutableArray<NSString *> *enabledProperties = nil;
	if (searchCapabilityDict != nil)
	{
		NSDictionary<NSString *, NSDictionary *> *propertyListDict = OCTypedCast(searchCapabilityDict[@"property"], NSDictionary);
		if (propertyListDict != nil)
		{
			for (NSString *property in propertyListDict)
			{
				NSDictionary<NSString *, id> *propertyDict = OCTypedCast(propertyListDict[property], NSDictionary);

				if (propertyDict != nil)
				{
					if ([propertyDict[@"enabled"] isKindOfClass:NSNumber.class] && (((NSNumber *)propertyDict[@"enabled"]).boolValue))
					{
						if (enabledProperties == nil) { enabledProperties = [NSMutableArray new]; }
						[enabledProperties addObject:property];
					}
				}
			}
		}
	}

	return (enabledProperties);
}

- (nullable NSArray<NSString *> *)supportedKeywordsForServerSideSearchProperty:(NSString *)searchPropertyName
{
	NSDictionary<NSString *, NSDictionary *> *searchCapabilityDict = OCTypedCast(_capabilities[@"search"], NSDictionary);
	NSMutableArray<NSString *> *enabledProperties = nil;
	if (searchCapabilityDict != nil)
	{
		NSDictionary<NSString *, NSDictionary *> *propertyListDict = OCTypedCast(searchCapabilityDict[@"property"], NSDictionary);
		if (propertyListDict != nil)
		{
			NSDictionary<NSString *, id> *propertyDict = OCTypedCast(propertyListDict[searchPropertyName], NSDictionary);
			if ((propertyDict != nil) && [propertyDict[@"keywords"] isKindOfClass:NSArray.class])
			{
				return (propertyDict[@"keywords"]);
			}
		}
	}
	return (nil);
}

#pragma mark - Notifications
- (NSArray<NSString *> *)notificationEndpoints
{
	return (OCTypedCast(_capabilities[@"notifications"][@"ocs-endpoints"], NSArray));
}

@end
