//
// GAAudio.m
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
#import "GAAudio.h"

// occgen: type start
@implementation GAAudio

// occgen: type serialization
+ (nullable instancetype)decodeGraphData:(GAGraphData)structure context:(nullable GAGraphContext *)context error:(NSError * _Nullable * _Nullable)outError
{
	GAAudio *instance = [self new];

	GA_SET(album, NSString, Nil);
	GA_SET(albumArtist, NSString, Nil);
	GA_SET(artist, NSString, Nil);
	GA_SET(bitrate, NSNumber, Nil);
	GA_SET(composers, NSString, Nil);
	GA_SET(copyright, NSString, Nil);
	GA_SET(disc, NSNumber, Nil);
	GA_SET(discCount, NSNumber, Nil);
	GA_SET(duration, NSNumber, Nil);
	GA_SET(genre, NSString, Nil);
	GA_SET(hasDrm, NSNumber, Nil);
	GA_SET(isVariableBitrate, NSNumber, Nil);
	GA_SET(title, NSString, Nil);
	GA_SET(track, NSNumber, Nil);
	GA_SET(trackCount, NSNumber, Nil);
	GA_SET(year, NSNumber, Nil);

	return (instance);
}

// occgen: struct serialization
- (nullable GAGraphStruct)encodeToGraphStructWithContext:(nullable GAGraphContext *)context error:(NSError * _Nullable * _Nullable)outError
{
	GA_ENC_INIT
	GA_ENC_ADD(_album, "album", NO);
	GA_ENC_ADD(_albumArtist, "albumArtist", NO);
	GA_ENC_ADD(_artist, "artist", NO);
	GA_ENC_ADD(_bitrate, "bitrate", NO);
	GA_ENC_ADD(_composers, "composers", NO);
	GA_ENC_ADD(_copyright, "copyright", NO);
	GA_ENC_ADD(_disc, "disc", NO);
	GA_ENC_ADD(_discCount, "discCount", NO);
	GA_ENC_ADD(_duration, "duration", NO);
	GA_ENC_ADD(_genre, "genre", NO);
	GA_ENC_ADD(_hasDrm, "hasDrm", NO);
	GA_ENC_ADD(_isVariableBitrate, "isVariableBitrate", NO);
	GA_ENC_ADD(_title, "title", NO);
	GA_ENC_ADD(_track, "track", NO);
	GA_ENC_ADD(_trackCount, "trackCount", NO);
	GA_ENC_ADD(_year, "year", NO);
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
		_album = [decoder decodeObjectOfClass:NSString.class forKey:@"album"];
		_albumArtist = [decoder decodeObjectOfClass:NSString.class forKey:@"albumArtist"];
		_artist = [decoder decodeObjectOfClass:NSString.class forKey:@"artist"];
		_bitrate = [decoder decodeObjectOfClass:NSNumber.class forKey:@"bitrate"];
		_composers = [decoder decodeObjectOfClass:NSString.class forKey:@"composers"];
		_copyright = [decoder decodeObjectOfClass:NSString.class forKey:@"copyright"];
		_disc = [decoder decodeObjectOfClass:NSNumber.class forKey:@"disc"];
		_discCount = [decoder decodeObjectOfClass:NSNumber.class forKey:@"discCount"];
		_duration = [decoder decodeObjectOfClass:NSNumber.class forKey:@"duration"];
		_genre = [decoder decodeObjectOfClass:NSString.class forKey:@"genre"];
		_hasDrm = [decoder decodeObjectOfClass:NSNumber.class forKey:@"hasDrm"];
		_isVariableBitrate = [decoder decodeObjectOfClass:NSNumber.class forKey:@"isVariableBitrate"];
		_title = [decoder decodeObjectOfClass:NSString.class forKey:@"title"];
		_track = [decoder decodeObjectOfClass:NSNumber.class forKey:@"track"];
		_trackCount = [decoder decodeObjectOfClass:NSNumber.class forKey:@"trackCount"];
		_year = [decoder decodeObjectOfClass:NSNumber.class forKey:@"year"];
	}

	return (self);
}

// occgen: type native serialization
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_album forKey:@"album"];
	[coder encodeObject:_albumArtist forKey:@"albumArtist"];
	[coder encodeObject:_artist forKey:@"artist"];
	[coder encodeObject:_bitrate forKey:@"bitrate"];
	[coder encodeObject:_composers forKey:@"composers"];
	[coder encodeObject:_copyright forKey:@"copyright"];
	[coder encodeObject:_disc forKey:@"disc"];
	[coder encodeObject:_discCount forKey:@"discCount"];
	[coder encodeObject:_duration forKey:@"duration"];
	[coder encodeObject:_genre forKey:@"genre"];
	[coder encodeObject:_hasDrm forKey:@"hasDrm"];
	[coder encodeObject:_isVariableBitrate forKey:@"isVariableBitrate"];
	[coder encodeObject:_title forKey:@"title"];
	[coder encodeObject:_track forKey:@"track"];
	[coder encodeObject:_trackCount forKey:@"trackCount"];
	[coder encodeObject:_year forKey:@"year"];
}

// occgen: type debug description
- (NSString *)description
{
	return ([NSString stringWithFormat:@"<%@: %p%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@>", NSStringFromClass(self.class), self, ((_album!=nil) ? [NSString stringWithFormat:@", album: %@", _album] : @""), ((_albumArtist!=nil) ? [NSString stringWithFormat:@", albumArtist: %@", _albumArtist] : @""), ((_artist!=nil) ? [NSString stringWithFormat:@", artist: %@", _artist] : @""), ((_bitrate!=nil) ? [NSString stringWithFormat:@", bitrate: %@", _bitrate] : @""), ((_composers!=nil) ? [NSString stringWithFormat:@", composers: %@", _composers] : @""), ((_copyright!=nil) ? [NSString stringWithFormat:@", copyright: %@", _copyright] : @""), ((_disc!=nil) ? [NSString stringWithFormat:@", disc: %@", _disc] : @""), ((_discCount!=nil) ? [NSString stringWithFormat:@", discCount: %@", _discCount] : @""), ((_duration!=nil) ? [NSString stringWithFormat:@", duration: %@", _duration] : @""), ((_genre!=nil) ? [NSString stringWithFormat:@", genre: %@", _genre] : @""), ((_hasDrm!=nil) ? [NSString stringWithFormat:@", hasDrm: %@", _hasDrm] : @""), ((_isVariableBitrate!=nil) ? [NSString stringWithFormat:@", isVariableBitrate: %@", _isVariableBitrate] : @""), ((_title!=nil) ? [NSString stringWithFormat:@", title: %@", _title] : @""), ((_track!=nil) ? [NSString stringWithFormat:@", track: %@", _track] : @""), ((_trackCount!=nil) ? [NSString stringWithFormat:@", trackCount: %@", _trackCount] : @""), ((_year!=nil) ? [NSString stringWithFormat:@", year: %@", _year] : @"")]);
}

// occgen: type protected {"locked":true}


// occgen: type end
@end

