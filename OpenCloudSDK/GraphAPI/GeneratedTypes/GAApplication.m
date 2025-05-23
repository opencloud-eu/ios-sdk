//
// GAApplication.m
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
#import "GAApplication.h"
#import "GAAppRole.h"

// occgen: type start
@implementation GAApplication

// occgen: type serialization
+ (nullable instancetype)decodeGraphData:(GAGraphData)structure context:(nullable GAGraphContext *)context error:(NSError * _Nullable * _Nullable)outError
{
	GAApplication *instance = [self new];

	GA_MAP_REQ(identifier, "id", NSString, Nil);
	GA_SET(appRoles, GAAppRole, NSArray.class);
	GA_SET(displayName, NSString, Nil);

	return (instance);
}

// occgen: struct serialization
- (nullable GAGraphStruct)encodeToGraphStructWithContext:(nullable GAGraphContext *)context error:(NSError * _Nullable * _Nullable)outError
{
	GA_ENC_INIT
	GA_ENC_ADD(_identifier, "id", YES);
	GA_ENC_ADD(_appRoles, "appRoles", NO);
	GA_ENC_ADD(_displayName, "displayName", NO);
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
		_appRoles = [decoder decodeObjectOfClasses:[NSSet setWithObjects: GAAppRole.class, NSArray.class, nil] forKey:@"appRoles"];
		_displayName = [decoder decodeObjectOfClass:NSString.class forKey:@"displayName"];
	}

	return (self);
}

// occgen: type native serialization
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_identifier forKey:@"identifier"];
	[coder encodeObject:_appRoles forKey:@"appRoles"];
	[coder encodeObject:_displayName forKey:@"displayName"];
}

// occgen: type debug description
- (NSString *)description
{
	return ([NSString stringWithFormat:@"<%@: %p%@%@%@>", NSStringFromClass(self.class), self, ((_identifier!=nil) ? [NSString stringWithFormat:@", identifier: %@", _identifier] : @""), ((_appRoles!=nil) ? [NSString stringWithFormat:@", appRoles: %@", _appRoles] : @""), ((_displayName!=nil) ? [NSString stringWithFormat:@", displayName: %@", _displayName] : @"")]);
}

// occgen: type protected {"locked":true}


// occgen: type end
@end

