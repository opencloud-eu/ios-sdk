//
// GADriveItemInvite.m
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
#import "GADriveItemInvite.h"
#import "GADriveRecipient.h"

// occgen: type start
@implementation GADriveItemInvite

// occgen: type serialization
+ (nullable instancetype)decodeGraphData:(GAGraphData)structure context:(nullable GAGraphContext *)context error:(NSError * _Nullable * _Nullable)outError
{
	GADriveItemInvite *instance = [self new];

	GA_SET(recipients, GADriveRecipient, NSArray.class);
	GA_SET(roles, NSString, NSArray.class);
	GA_MAP(libreGraphPermissionsActions, "@libre.graph.permissions.actions", NSString, NSArray.class);
	GA_SET(expirationDateTime, NSDate, Nil);

	return (instance);
}

// occgen: struct serialization
- (nullable GAGraphStruct)encodeToGraphStructWithContext:(nullable GAGraphContext *)context error:(NSError * _Nullable * _Nullable)outError
{
	GA_ENC_INIT
	GA_ENC_ADD(_recipients, "recipients", NO);
	GA_ENC_ADD(_roles, "roles", NO);
	GA_ENC_ADD(_libreGraphPermissionsActions, "@libre.graph.permissions.actions", NO);
	GA_ENC_ADD(_expirationDateTime, "expirationDateTime", NO);
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
		_recipients = [decoder decodeObjectOfClasses:[NSSet setWithObjects: GADriveRecipient.class, NSArray.class, nil] forKey:@"recipients"];
		_roles = [decoder decodeObjectOfClasses:[NSSet setWithObjects: NSString.class, NSArray.class, nil] forKey:@"roles"];
		_libreGraphPermissionsActions = [decoder decodeObjectOfClasses:[NSSet setWithObjects: NSString.class, NSArray.class, nil] forKey:@"libreGraphPermissionsActions"];
		_expirationDateTime = [decoder decodeObjectOfClass:NSDate.class forKey:@"expirationDateTime"];
	}

	return (self);
}

// occgen: type native serialization
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_recipients forKey:@"recipients"];
	[coder encodeObject:_roles forKey:@"roles"];
	[coder encodeObject:_libreGraphPermissionsActions forKey:@"libreGraphPermissionsActions"];
	[coder encodeObject:_expirationDateTime forKey:@"expirationDateTime"];
}

// occgen: type debug description
- (NSString *)description
{
	return ([NSString stringWithFormat:@"<%@: %p%@%@%@%@>", NSStringFromClass(self.class), self, ((_recipients!=nil) ? [NSString stringWithFormat:@", recipients: %@", _recipients] : @""), ((_roles!=nil) ? [NSString stringWithFormat:@", roles: %@", _roles] : @""), ((_libreGraphPermissionsActions!=nil) ? [NSString stringWithFormat:@", libreGraphPermissionsActions: %@", _libreGraphPermissionsActions] : @""), ((_expirationDateTime!=nil) ? [NSString stringWithFormat:@", expirationDateTime: %@", _expirationDateTime] : @"")]);
}

// occgen: type protected {"locked":true}


// occgen: type end
@end

