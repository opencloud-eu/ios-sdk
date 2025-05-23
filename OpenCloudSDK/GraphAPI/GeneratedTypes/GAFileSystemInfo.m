//
// GAFileSystemInfo.m
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
#import "GAFileSystemInfo.h"

// occgen: type start
@implementation GAFileSystemInfo

// occgen: type serialization
+ (nullable instancetype)decodeGraphData:(GAGraphData)structure context:(nullable GAGraphContext *)context error:(NSError * _Nullable * _Nullable)outError
{
	GAFileSystemInfo *instance = [self new];

	GA_SET(createdDateTime, NSDate, Nil);
	GA_SET(lastAccessedDateTime, NSDate, Nil);
	GA_SET(lastModifiedDateTime, NSDate, Nil);

	return (instance);
}

// occgen: struct serialization
- (nullable GAGraphStruct)encodeToGraphStructWithContext:(nullable GAGraphContext *)context error:(NSError * _Nullable * _Nullable)outError
{
	GA_ENC_INIT
	GA_ENC_ADD(_createdDateTime, "createdDateTime", NO);
	GA_ENC_ADD(_lastAccessedDateTime, "lastAccessedDateTime", NO);
	GA_ENC_ADD(_lastModifiedDateTime, "lastModifiedDateTime", NO);
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
		_createdDateTime = [decoder decodeObjectOfClass:NSDate.class forKey:@"createdDateTime"];
		_lastAccessedDateTime = [decoder decodeObjectOfClass:NSDate.class forKey:@"lastAccessedDateTime"];
		_lastModifiedDateTime = [decoder decodeObjectOfClass:NSDate.class forKey:@"lastModifiedDateTime"];
	}

	return (self);
}

// occgen: type native serialization
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_createdDateTime forKey:@"createdDateTime"];
	[coder encodeObject:_lastAccessedDateTime forKey:@"lastAccessedDateTime"];
	[coder encodeObject:_lastModifiedDateTime forKey:@"lastModifiedDateTime"];
}

// occgen: type debug description
- (NSString *)description
{
	return ([NSString stringWithFormat:@"<%@: %p%@%@%@>", NSStringFromClass(self.class), self, ((_createdDateTime!=nil) ? [NSString stringWithFormat:@", createdDateTime: %@", _createdDateTime] : @""), ((_lastAccessedDateTime!=nil) ? [NSString stringWithFormat:@", lastAccessedDateTime: %@", _lastAccessedDateTime] : @""), ((_lastModifiedDateTime!=nil) ? [NSString stringWithFormat:@", lastModifiedDateTime: %@", _lastModifiedDateTime] : @"")]);
}

// occgen: type protected {"locked":true}


// occgen: type end
@end

