//
// GAPhoto.m
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
#import "GAPhoto.h"

// occgen: type start
@implementation GAPhoto

// occgen: type serialization
+ (nullable instancetype)decodeGraphData:(GAGraphData)structure context:(nullable GAGraphContext *)context error:(NSError * _Nullable * _Nullable)outError
{
	GAPhoto *instance = [self new];

	GA_SET(cameraMake, NSString, Nil);
	GA_SET(cameraModel, NSString, Nil);
	GA_SET(exposureDenominator, NSNumber, Nil);
	GA_SET(exposureNumerator, NSNumber, Nil);
	GA_SET(fNumber, NSNumber, Nil);
	GA_SET(focalLength, NSNumber, Nil);
	GA_SET(iso, NSNumber, Nil);
	GA_SET(orientation, NSNumber, Nil);
	GA_SET(takenDateTime, NSDate, Nil);

	return (instance);
}

// occgen: struct serialization
- (nullable GAGraphStruct)encodeToGraphStructWithContext:(nullable GAGraphContext *)context error:(NSError * _Nullable * _Nullable)outError
{
	GA_ENC_INIT
	GA_ENC_ADD(_cameraMake, "cameraMake", NO);
	GA_ENC_ADD(_cameraModel, "cameraModel", NO);
	GA_ENC_ADD(_exposureDenominator, "exposureDenominator", NO);
	GA_ENC_ADD(_exposureNumerator, "exposureNumerator", NO);
	GA_ENC_ADD(_fNumber, "fNumber", NO);
	GA_ENC_ADD(_focalLength, "focalLength", NO);
	GA_ENC_ADD(_iso, "iso", NO);
	GA_ENC_ADD(_orientation, "orientation", NO);
	GA_ENC_ADD(_takenDateTime, "takenDateTime", NO);
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
		_cameraMake = [decoder decodeObjectOfClass:NSString.class forKey:@"cameraMake"];
		_cameraModel = [decoder decodeObjectOfClass:NSString.class forKey:@"cameraModel"];
		_exposureDenominator = [decoder decodeObjectOfClass:NSNumber.class forKey:@"exposureDenominator"];
		_exposureNumerator = [decoder decodeObjectOfClass:NSNumber.class forKey:@"exposureNumerator"];
		_fNumber = [decoder decodeObjectOfClass:NSNumber.class forKey:@"fNumber"];
		_focalLength = [decoder decodeObjectOfClass:NSNumber.class forKey:@"focalLength"];
		_iso = [decoder decodeObjectOfClass:NSNumber.class forKey:@"iso"];
		_orientation = [decoder decodeObjectOfClass:NSNumber.class forKey:@"orientation"];
		_takenDateTime = [decoder decodeObjectOfClass:NSDate.class forKey:@"takenDateTime"];
	}

	return (self);
}

// occgen: type native serialization
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_cameraMake forKey:@"cameraMake"];
	[coder encodeObject:_cameraModel forKey:@"cameraModel"];
	[coder encodeObject:_exposureDenominator forKey:@"exposureDenominator"];
	[coder encodeObject:_exposureNumerator forKey:@"exposureNumerator"];
	[coder encodeObject:_fNumber forKey:@"fNumber"];
	[coder encodeObject:_focalLength forKey:@"focalLength"];
	[coder encodeObject:_iso forKey:@"iso"];
	[coder encodeObject:_orientation forKey:@"orientation"];
	[coder encodeObject:_takenDateTime forKey:@"takenDateTime"];
}

// occgen: type debug description
- (NSString *)description
{
	return ([NSString stringWithFormat:@"<%@: %p%@%@%@%@%@%@%@%@%@>", NSStringFromClass(self.class), self, ((_cameraMake!=nil) ? [NSString stringWithFormat:@", cameraMake: %@", _cameraMake] : @""), ((_cameraModel!=nil) ? [NSString stringWithFormat:@", cameraModel: %@", _cameraModel] : @""), ((_exposureDenominator!=nil) ? [NSString stringWithFormat:@", exposureDenominator: %@", _exposureDenominator] : @""), ((_exposureNumerator!=nil) ? [NSString stringWithFormat:@", exposureNumerator: %@", _exposureNumerator] : @""), ((_fNumber!=nil) ? [NSString stringWithFormat:@", fNumber: %@", _fNumber] : @""), ((_focalLength!=nil) ? [NSString stringWithFormat:@", focalLength: %@", _focalLength] : @""), ((_iso!=nil) ? [NSString stringWithFormat:@", iso: %@", _iso] : @""), ((_orientation!=nil) ? [NSString stringWithFormat:@", orientation: %@", _orientation] : @""), ((_takenDateTime!=nil) ? [NSString stringWithFormat:@", takenDateTime: %@", _takenDateTime] : @"")]);
}

// occgen: type protected {"locked":true}


// occgen: type end
@end

