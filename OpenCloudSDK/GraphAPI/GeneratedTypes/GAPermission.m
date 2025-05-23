//
// GAPermission.m
// Autogenerated / Managed by ocapigen
// Copyright (C) 2024 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2024, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

// occgen: includes
#import "GAPermission.h"
#import "GAIdentitySet.h"
#import "GASharePointIdentitySet.h"
#import "GASharingInvitation.h"
#import "GASharingLink.h"

// occgen: type start
@implementation GAPermission

// occgen: type serialization
+ (nullable instancetype)decodeGraphData:(GAGraphData)structure context:(nullable GAGraphContext *)context error:(NSError * _Nullable * _Nullable)outError
{
	GAPermission *instance = [self new];

	GA_MAP(identifier, "id", NSString, Nil);
	GA_SET(hasPassword, NSNumber, Nil);
	GA_SET(expirationDateTime, NSDate, Nil);
	GA_SET(createdDateTime, NSDate, Nil);
	GA_SET(grantedToV2, GASharePointIdentitySet, Nil);
	GA_SET(link, GASharingLink, Nil);
	GA_SET(roles, NSString, NSArray.class);
	GA_SET(grantedToIdentities, GAIdentitySet, NSArray.class);
	GA_MAP(libreGraphPermissionsActions, "@libre.graph.permissions.actions", NSString, NSArray.class);
	GA_SET(invitation, GASharingInvitation, Nil);

	return (instance);
}

// occgen: struct serialization
- (nullable GAGraphStruct)encodeToGraphStructWithContext:(nullable GAGraphContext *)context error:(NSError * _Nullable * _Nullable)outError
{
	GA_ENC_INIT
	GA_ENC_ADD(_identifier, "id", NO);
	GA_ENC_ADD(_hasPassword, "hasPassword", NO);
	GA_ENC_ADD(_expirationDateTime, "expirationDateTime", NO);
	GA_ENC_ADD(_createdDateTime, "createdDateTime", NO);
	GA_ENC_ADD(_grantedToV2, "grantedToV2", NO);
	GA_ENC_ADD(_link, "link", NO);
	GA_ENC_ADD(_roles, "roles", NO);
	GA_ENC_ADD(_grantedToIdentities, "grantedToIdentities", NO);
	GA_ENC_ADD(_libreGraphPermissionsActions, "@libre.graph.permissions.actions", NO);
	GA_ENC_ADD(_invitation, "invitation", NO);
	GA_ENC_RETURN
}

// occgen: type native deserialization
+ (BOOL)supportsSecureCoding
{
	return (YES);
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]) != nil)
	{
		_identifier = [decoder decodeObjectOfClass:NSString.class forKey:@"identifier"];
		_hasPassword = [decoder decodeObjectOfClass:NSNumber.class forKey:@"hasPassword"];
		_expirationDateTime = [decoder decodeObjectOfClass:NSDate.class forKey:@"expirationDateTime"];
		_createdDateTime = [decoder decodeObjectOfClass:NSDate.class forKey:@"createdDateTime"];
		_grantedToV2 = [decoder decodeObjectOfClass:GASharePointIdentitySet.class forKey:@"grantedToV2"];
		_link = [decoder decodeObjectOfClass:GASharingLink.class forKey:@"link"];
		_roles = [decoder decodeObjectOfClasses:[NSSet setWithObjects: NSString.class, NSArray.class, nil] forKey:@"roles"];
		_grantedToIdentities = [decoder decodeObjectOfClasses:[NSSet setWithObjects: GAIdentitySet.class, NSArray.class, nil] forKey:@"grantedToIdentities"];
		_libreGraphPermissionsActions = [decoder decodeObjectOfClasses:[NSSet setWithObjects: NSString.class, NSArray.class, nil] forKey:@"libreGraphPermissionsActions"];
		_invitation = [decoder decodeObjectOfClass:GASharingInvitation.class forKey:@"invitation"];
	}

	return (self);
}

// occgen: type native serialization
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_identifier forKey:@"identifier"];
	[coder encodeObject:_hasPassword forKey:@"hasPassword"];
	[coder encodeObject:_expirationDateTime forKey:@"expirationDateTime"];
	[coder encodeObject:_createdDateTime forKey:@"createdDateTime"];
	[coder encodeObject:_grantedToV2 forKey:@"grantedToV2"];
	[coder encodeObject:_link forKey:@"link"];
	[coder encodeObject:_roles forKey:@"roles"];
	[coder encodeObject:_grantedToIdentities forKey:@"grantedToIdentities"];
	[coder encodeObject:_libreGraphPermissionsActions forKey:@"libreGraphPermissionsActions"];
	[coder encodeObject:_invitation forKey:@"invitation"];
}

// occgen: type debug description
- (NSString *)description
{
	return ([NSString stringWithFormat:@"<%@: %p%@%@%@%@%@%@%@%@%@%@>", NSStringFromClass(self.class), self, ((_identifier!=nil) ? [NSString stringWithFormat:@", identifier: %@", _identifier] : @""), ((_hasPassword!=nil) ? [NSString stringWithFormat:@", hasPassword: %@", _hasPassword] : @""), ((_expirationDateTime!=nil) ? [NSString stringWithFormat:@", expirationDateTime: %@", _expirationDateTime] : @""), ((_createdDateTime!=nil) ? [NSString stringWithFormat:@", createdDateTime: %@", _createdDateTime] : @""), ((_grantedToV2!=nil) ? [NSString stringWithFormat:@", grantedToV2: %@", _grantedToV2] : @""), ((_link!=nil) ? [NSString stringWithFormat:@", link: %@", _link] : @""), ((_roles!=nil) ? [NSString stringWithFormat:@", roles: %@", _roles] : @""), ((_grantedToIdentities!=nil) ? [NSString stringWithFormat:@", grantedToIdentities: %@", _grantedToIdentities] : @""), ((_libreGraphPermissionsActions!=nil) ? [NSString stringWithFormat:@", libreGraphPermissionsActions: %@", _libreGraphPermissionsActions] : @""), ((_invitation!=nil) ? [NSString stringWithFormat:@", invitation: %@", _invitation] : @"")]);
}

// occgen: type protected {"locked":true}


// occgen: type end
@end

