//
//  OCShare.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 05.02.18.
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

#import "OCShare.h"
#import "OCMacros.h"

@implementation OCShare

@dynamic canRead;
@dynamic canUpdate;
@dynamic canCreate;
@dynamic canDelete;
@dynamic canShare;

@synthesize protectedByPassword = _protectedByPassword;

- (instancetype)init
{
	if ((self = [super init]) != nil)
	{
		_type = OCShareTypeUnknown;
	}

	return (self);
}

#pragma mark - Convenience constructors
+ (instancetype)shareWithRecipient:(OCIdentity *)recipient location:(OCLocation *)location permissions:(OCSharePermissionsMask)permissions expiration:(NSDate *)expirationDate
{
	OCShare *share = [OCShare new];

	if (recipient.type == OCRecipientTypeGroup)
	{
		share.type = OCShareTypeGroupShare;
	}
	else if (recipient.type == OCRecipientTypeUser)
	{
		if (recipient.user.isRemote)
		{
			share.type = OCShareTypeRemote;
		}
		else
		{
			share.type = OCShareTypeUserShare;
		}
	}

	share.category = OCShareCategoryByMe;

	share.recipient = recipient;

	share.itemLocation = location;

	share.permissions = permissions;
	share.expirationDate = expirationDate;

	return (share);
}

+ (instancetype)shareWithPublicLinkToLocation:(OCLocation *)location linkName:(NSString *)name permissions:(OCSharePermissionsMask)permissions password:(NSString *)password expiration:(NSDate *)expirationDate
{
	OCShare *share = [OCShare new];

	share.type = OCShareTypeLink;
	share.category = OCShareCategoryByMe;

	share.name = name;

	share.itemLocation = location;

	share.password = password;

	share.permissions = permissions;
	share.expirationDate = expirationDate;

	return (share);
}

#pragma mark - Permission convenience
#define BIT_ACCESSOR(getMethodName,setMethodName,flag) \
- (BOOL)getMethodName \
{ \
	return ((_permissions & flag) == flag); \
} \
\
- (void)setMethodName:(BOOL)flagValue \
{ \
	_permissions = (_permissions & ~flag) | (flagValue ? flag : 0); \
}

BIT_ACCESSOR(canRead,	setCanRead,	OCSharePermissionsMaskRead);
BIT_ACCESSOR(canUpdate,	setCanUpdate,	OCSharePermissionsMaskUpdate);
BIT_ACCESSOR(canCreate,	setCanCreate,	OCSharePermissionsMaskCreate);
BIT_ACCESSOR(canDelete,	setCanDelete,	OCSharePermissionsMaskDelete);
BIT_ACCESSOR(canShare,	setCanShare,	OCSharePermissionsMaskShare);

- (BOOL)protectedByPassword
{
	if ((_password != nil) && ![_password isEqual:@""])
	{
		_protectedByPassword = YES;
	}

	return (_protectedByPassword);
}

- (void)setProtectedByPassword:(BOOL)protectedByPassword
{
	if (!protectedByPassword)
	{
		self.password = nil;
	}

	_protectedByPassword = protectedByPassword;
}

#pragma mark - Conversions
+ (OCShareTypesMask)maskForType:(OCShareType)type
{
	switch (type)
	{
		case OCShareTypeUnknown:		return (OCShareTypesMaskNone);
		case OCShareTypeUserShare:		return (OCShareTypesMaskUserShare);
		case OCShareTypeGroupShare:		return (OCShareTypesMaskGroupShare);
		case OCShareTypeLink:			return (OCShareTypesMaskLink);
		case OCShareTypeGuest:			return (OCShareTypesMaskGuest);
		case OCShareTypeRemote:			return (OCShareTypesMaskRemote);
	}

	return (OCShareTypesMaskNone);
}

+ (OCShareType)typeForMask:(OCShareTypesMask)mask
{
	switch (mask)
	{
		case OCShareTypesMaskNone:		return (OCShareTypeUnknown);
		case OCShareTypesMaskUserShare:		return (OCShareTypeUserShare);
		case OCShareTypesMaskGroupShare:	return (OCShareTypeGroupShare);
		case OCShareTypesMaskLink:		return (OCShareTypeLink);
		case OCShareTypesMaskGuest:		return (OCShareTypeGuest);
		case OCShareTypesMaskRemote:		return (OCShareTypeRemote);
	}

	return (OCShareTypeUnknown);
}

#pragma mark - Comparison
- (NSUInteger)hash
{
	return (_identifier.hash ^ _token.hash ^ _itemLocation.hash ^ _owner.hash ^ _recipient.hash ^ _itemOwner.hash ^ _type);
}

- (BOOL)isEqual:(id)object
{
	OCShare *otherShare = OCTypedCast(object, OCShare);

	if (otherShare != nil)
	{
		#define compareVar(var) ((otherShare->var == var) || [otherShare->var isEqual:var])

		return (compareVar(_identifier) &&

			(otherShare->_type == _type) &&
			(otherShare->_category == _category) &&

			compareVar(_itemLocation) &&
			(otherShare->_itemType == _itemType) &&
			compareVar(_itemOwner) &&
			compareVar(_itemMIMEType) &&

			compareVar(_name) &&
			compareVar(_token) &&
			compareVar(_url) &&

			(otherShare->_permissions == _permissions) &&

			(otherShare.protectedByPassword == self.protectedByPassword) &&

			compareVar(_creationDate) &&
			compareVar(_expirationDate) &&

			compareVar(_owner) &&
			compareVar(_recipient) &&

			compareVar(_mountPoint) &&
			compareVar(_accepted) &&
			compareVar(_state)
		);
	}

	return (NO);
}

#pragma mark - Secure Coding
+ (BOOL)supportsSecureCoding
{
	return (YES);
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]) != nil)
	{
		_identifier = [decoder decodeObjectOfClass:[NSString class] forKey:@"identifier"];

		_type = [decoder decodeIntegerForKey:@"type"];
		_category = [decoder decodeIntegerForKey:@"category"];

		_itemLocation = [decoder decodeObjectOfClass:OCLocation.class forKey:@"itemLocation"];
		if (_itemLocation == nil)
		{
			NSString *itemPath;

			if ((itemPath = [decoder decodeObjectOfClass:[NSString class] forKey:@"itemPath"]) != nil)
			{
				_itemLocation = [OCLocation legacyRootPath:itemPath];
			}
		}

		OCItemType legacyType = [decoder decodeIntegerForKey:@"itemType"];
		_itemType = (legacyType == OCItemTypeFile) ? OCLocationTypeFile : OCLocationTypeFolder;
		OCLocationType itemType = [decoder decodeIntegerForKey:@"itemLType"];
		if (itemType != OCLocationTypeUnknown)
		{
			_itemType = itemType;
		}

		_itemOwner = [decoder decodeObjectOfClass:[OCUser class] forKey:@"itemOwner"];
		_itemMIMEType = [decoder decodeObjectOfClass:[NSString class] forKey:@"itemMIMEType"];

		_name = [decoder decodeObjectOfClass:[NSString class] forKey:@"name"];
		_token = [decoder decodeObjectOfClass:[NSString class] forKey:@"token"];
		_url = [decoder decodeObjectOfClass:[NSURL class] forKey:@"url"];

		_permissions = [decoder decodeIntegerForKey:@"permissions"];

		_protectedByPassword = [decoder decodeBoolForKey:@"protectedByPassword"];

		_creationDate = [decoder decodeObjectOfClass:[NSDate class] forKey:@"creationDate"];
		_expirationDate = [decoder decodeObjectOfClass:[NSDate class] forKey:@"expirationDate"];

		_owner = [decoder decodeObjectOfClass:[OCUser class] forKey:@"owner"];
		_recipient = [decoder decodeObjectOfClass:[OCIdentity class] forKey:@"recipient"];

		_mountPoint = [decoder decodeObjectOfClass:[NSString class] forKey:@"mountPoint"];
		_accepted = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"accepted"];
		_state = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"state"];
	}
	
	return (self);
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_identifier forKey:@"identifier"];

	[coder encodeInteger:_type forKey:@"type"];
	[coder encodeInteger:_category forKey:@"category"];

	[coder encodeObject:_itemLocation forKey:@"itemLocation"];
	[coder encodeInteger:_itemType forKey:@"itemLType"];
	[coder encodeObject:_itemOwner forKey:@"itemOwner"];
	[coder encodeObject:_itemMIMEType forKey:@"itemMIMEType"];

	[coder encodeObject:_name forKey:@"name"];
	[coder encodeObject:_token forKey:@"token"];
	[coder encodeObject:_url forKey:@"url"];

	[coder encodeInteger:_permissions forKey:@"permissions"];

	[coder encodeBool:self.protectedByPassword forKey:@"protectedByPassword"];

	[coder encodeObject:_creationDate forKey:@"creationDate"];
	[coder encodeObject:_expirationDate forKey:@"expirationDate"];

	[coder encodeObject:_owner forKey:@"owner"];
	[coder encodeObject:_recipient forKey:@"recipient"];

	[coder encodeObject:_mountPoint forKey:@"mountPoint"];
	[coder encodeObject:_accepted forKey:@"accepted"];
	[coder encodeObject:_state forKey:@"state"];
}

#pragma mark - Description
- (NSString *)description
{
	NSString *typeAsString = nil, *permissionsString = @"", *itemTypeString = nil, *categoryAsString = nil;

	switch (_type)
	{
		case OCShareTypeUserShare:
			typeAsString = @"user";
		break;

		case OCShareTypeGroupShare:
			typeAsString = @"group";
		break;

		case OCShareTypeLink:
			typeAsString = @"link";
		break;

		case OCShareTypeGuest:
			typeAsString = @"guest";
		break;

		case OCShareTypeRemote:
			typeAsString = @"remote";
		break;

		case OCShareTypeUnknown:
			typeAsString = @"unknown";
		break;
	}

	switch (_category)
	{
		case OCShareCategoryUnknown:
			categoryAsString = @"unknown";
		break;
		case OCShareCategoryByMe:
			categoryAsString = @"by me";
		break;
		case OCShareCategoryWithMe:
			categoryAsString = @"with me";
		break;
	}

	if (self.canRead) { permissionsString = [permissionsString stringByAppendingString:@"read, "]; }
	if (self.canUpdate) { permissionsString = [permissionsString stringByAppendingString:@"update, "]; }
	if (self.canCreate) { permissionsString = [permissionsString stringByAppendingString:@"create, "]; }
	if (self.canDelete) { permissionsString = [permissionsString stringByAppendingString:@"delete, "]; }
	if (self.canShare) { permissionsString = [permissionsString stringByAppendingString:@"share, "]; }

	if (permissionsString.length > 3)
	{
		permissionsString = [permissionsString substringWithRange:NSMakeRange(0, permissionsString.length-2)];
	}
	else
	{
		permissionsString = @"none";
	}

	switch (_itemType)
	{
		case OCLocationTypeUnknown:
			itemTypeString = @"unknown";
		break;
		case OCLocationTypeFile:
			itemTypeString = @"file";
		break;
		case OCLocationTypeFolder:
			itemTypeString = @"folder";
		break;
		case OCLocationTypeDrive:
			itemTypeString = @"drive";
		break;
		case OCLocationTypeAccount:
			itemTypeString = @"account";
		break;
	}

	return ([NSString stringWithFormat:@"<%@: %p, identifier: %@, type: %@, category: %@, name: %@, itemLocation: %@, itemType: %@, itemMIMEType: %@, itemOwner: %@, creationDate: %@, expirationDate: %@, permissions: %@%@%@%@%@%@%@%@>", NSStringFromClass(self.class), self, _identifier, typeAsString, categoryAsString, _name, _itemLocation, itemTypeString, _itemMIMEType, _itemOwner, _creationDate, _expirationDate, permissionsString, ((_password!=nil) ? @", password: [redacted]" : (_protectedByPassword ? @", protectedByPassword" : @"")), ((_token!=nil)?[NSString stringWithFormat:@", token: %@", _token] : @""), ((_url!=nil)?[NSString stringWithFormat:@", url: %@", _url] : @""), ((_owner!=nil) ? [NSString stringWithFormat:@", owner: %@", _owner] : @""), ((_recipient!=nil) ? [NSString stringWithFormat:@", recipient: %@", _recipient] : @""), ((_accepted!=nil) ? [NSString stringWithFormat:@", accepted: %@", _accepted] : @""), ((_state!=nil) ? ([_state isEqual:OCShareStateAccepted] ? @", state: accepted" : ([_state isEqual:OCShareStateDeclined] ? @", state: declined" : [_state isEqual:OCShareStatePending] ? @", state: pending" : @", state: ?!")) : @"")]);
}

- (OCShareState)effectiveState
{
	if (_type == OCShareTypeRemote)
	{
		if (self.accepted.boolValue)
		{
			return (OCShareStateAccepted);
		}

		return (OCShareStatePending);
	}

	return (_state);
}

#pragma mark - Copying
- (id)copyWithZone:(NSZone *)zone
{
	OCShare *copiedShare = [self.class new];

	copiedShare->_identifier = _identifier;
	copiedShare->_type = _type;
	copiedShare->_category = _category;

	copiedShare->_itemLocation = _itemLocation;
	copiedShare->_itemType = _itemType;
	copiedShare->_itemOwner = _itemOwner;
	copiedShare->_itemMIMEType = _itemMIMEType;

	copiedShare->_name = _name;
	copiedShare->_token = _token;
	copiedShare->_url = _url;

	copiedShare->_permissions = _permissions;

	copiedShare->_creationDate = _creationDate;
	copiedShare->_expirationDate = _expirationDate;

	copiedShare->_password = _password;
	copiedShare->_protectedByPassword = _protectedByPassword;

	copiedShare->_owner = _owner;
	copiedShare->_recipient = _recipient;

	copiedShare->_mountPoint = _mountPoint;
	copiedShare->_accepted = _accepted;

	copiedShare->_state = _state;

	return (copiedShare);
}

@end

OCShareState OCShareStateAccepted = @"0";
OCShareState OCShareStatePending  = @"1";
OCShareState OCShareStateDeclined = @"2";
