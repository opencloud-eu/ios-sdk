//
//  OCFile.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 21.06.18.
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

#import "OCFile.h"

@implementation OCFile

#pragma mark - Secure Coding
+ (BOOL)supportsSecureCoding
{
	return (YES);
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]) != nil)
	{
		_fileID = [decoder decodeObjectOfClass:[NSString class] forKey:@"fileID"];
		_eTag = [decoder decodeObjectOfClass:[NSString class] forKey:@"eTag"];

		_item = [decoder decodeObjectOfClass:[OCItem class] forKey:@"item"];
		_checksum = [decoder decodeObjectOfClass:[OCChecksum class] forKey:@"checksum"];
		_url = [decoder decodeObjectOfClass:[NSURL class] forKey:@"url"];

		_claim = [decoder decodeObjectOfClass:[OCClaim class] forKey:@"claim"];
	}

	return (self);
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_fileID forKey:@"fileID"];
	[coder encodeObject:_eTag forKey:@"eTag"];

	[coder encodeObject:_item forKey:@"item"];
	[coder encodeObject:_checksum forKey:@"checksum"];
	[coder encodeObject:_url forKey:@"url"];

	[coder encodeObject:_claim forKey:@"claim"];
}

@end
