//
//  OCCoreItemList.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 02.04.18.
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

#import "OCCoreItemList.h"
#import "NSString+OCPath.h"
#import "OCDrive.h"

@implementation OCCoreItemList

@synthesize state = _state;

@synthesize items = _items;
@synthesize itemsByPath = _itemsByPath;
@synthesize itemPathsSet = _itemPathsSet;

@synthesize itemsByFileID = _itemsByFileID;
@synthesize itemFileIDsSet = _itemFileIDsSet;

@synthesize itemsByParentPaths = _itemsByParentPaths;
@synthesize itemParentPaths = _itemParentPaths;

@synthesize error = _error;

+ (instancetype)itemListWithItems:(NSArray <OCItem *> *)items
{
	OCCoreItemList *itemList;

	itemList = [self new];
	itemList.items = items;

	return (itemList);
}

- (void)updateWithError:(NSError *)error items:(NSArray <OCItem *> *)items
{
	self.error = error;

	if (error != nil)
	{
		self.state = OCCoreItemListStateFailed;
	}
	else
	{
		self.state = OCCoreItemListStateSuccess;
		self.items = items;
	}
}

- (void)setItems:(NSArray<OCItem *> *)items
{
	_itemsByPath = nil;
	_itemPathsSet = nil;
	_itemsByFileID = nil;
	_itemFileIDsSet = nil;
	_itemsByLocalID = nil;
	_itemLocalIDsSet = nil;
	_itemsByParentPaths = nil;
	_itemParentPaths = nil;
	_itemListsByDriveID = nil;

	_items = items;
}

- (NSMutableDictionary<OCPath,OCItem *> *)itemsByPath
{
	if (_itemsByPath == nil)
	{
		_itemsByPath = [NSMutableDictionary new];

		for (OCItem *item in self.items)
		{
			if (item.path != nil)
			{
				_itemsByPath[item.path] = item;
			}
		}
	}

	return (_itemsByPath);
}

- (NSSet<OCPath> *)itemPathsSet
{
	if (_itemPathsSet == nil)
	{
		NSArray<OCPath> *itemPaths;

		if ((itemPaths = [self.itemsByPath allKeys]) != nil)
		{
			_itemPathsSet = [[NSSet alloc] initWithArray:itemPaths];
		}
		else
		{
			_itemPathsSet = [NSSet new];
		}
	}

	return (_itemPathsSet);
}

- (NSMutableDictionary<OCFileID,OCItem *> *)itemsByFileID
{
	if (_itemsByFileID == nil)
	{
		_itemsByFileID = [NSMutableDictionary new];

		for (OCItem *item in self.items)
		{
			if (item.fileID != nil)
			{
				_itemsByFileID[item.fileID] = item;
			}
		}
	}

	return (_itemsByFileID);
}

- (NSSet<OCFileID> *)itemFileIDsSet
{
	if (_itemFileIDsSet == nil)
	{
		NSArray<OCPath> *itemFileIDs;

		if ((itemFileIDs = [self.itemsByFileID allKeys]) != nil)
		{
			_itemFileIDsSet = [[NSSet alloc] initWithArray:itemFileIDs];
		}
		else
		{
			_itemFileIDsSet = [NSSet new];
		}
	}

	return (_itemFileIDsSet);
}

- (NSMutableDictionary<OCLocalID,OCItem *> *)itemsByLocalID
{
	if (_itemsByLocalID == nil)
	{
		_itemsByLocalID = [NSMutableDictionary new];

		for (OCItem *item in self.items)
		{
			if (item.localID != nil)
			{
				_itemsByLocalID[item.localID] = item;
			}
		}
	}

	return (_itemsByLocalID);
}

- (NSSet<OCLocalID> *)itemLocalIDsSet
{
	if (_itemLocalIDsSet == nil)
	{
		NSArray<OCPath> *itemLocalIDs;

		if ((itemLocalIDs = [self.itemsByLocalID allKeys]) != nil)
		{
			_itemLocalIDsSet = [[NSSet alloc] initWithArray:itemLocalIDs];
		}
		else
		{
			_itemLocalIDsSet = [NSSet new];
		}
	}

	return (_itemLocalIDsSet);
}

- (NSMutableDictionary<OCPath,NSMutableArray<OCItem *> *> *)itemsByParentPaths
{
	if (_itemsByParentPaths == nil)
	{
		_itemsByParentPaths = [NSMutableDictionary new];

		for (OCItem *item in self.items)
		{
			OCPath parentPath;

			if ((parentPath = [item.path parentPath]) != nil)
			{
				NSMutableArray <OCItem *> *items;

				if ((items = _itemsByParentPaths[parentPath]) == nil)
				{
					_itemsByParentPaths[parentPath] = items = [NSMutableArray new];
				}

				[items addObject:item];
			}
		}
	}

	return (_itemsByParentPaths);
}

- (NSSet<OCPath> *)itemParentPaths
{
	if (_itemParentPaths == nil)
	{
		NSArray<OCPath> *itemParentPaths;

		if ((itemParentPaths = [self.itemsByParentPaths allKeys]) != nil)
		{
			_itemParentPaths = [[NSSet alloc] initWithArray:itemParentPaths];
		}
		else
		{
			_itemParentPaths = [NSSet new];
		}
	}

	return (_itemParentPaths);
}

- (NSMutableDictionary<OCDriveID,NSMutableArray<OCItem *> *> *)_itemsByDriveID
{
	NSMutableDictionary<OCDriveID, NSMutableArray<OCItem *> *> *itemsByDriveID = [NSMutableDictionary new];
	OCDriveID nilID = OCDriveIDNil;

	for (OCItem *item in self.items)
	{
		OCDriveID driveID = (item.driveID == nil) ? nilID : item.driveID;
		NSMutableArray<OCItem *> *items;

		if ((items = itemsByDriveID[driveID]) == nil)
		{
			items = [NSMutableArray new];
			itemsByDriveID[driveID] = items;
		}

		[items addObject:item];
	}

	return(itemsByDriveID);
}

- (NSMutableDictionary<OCDriveID,OCCoreItemList *> *)itemListsByDriveID
{
	if (_itemListsByDriveID == nil)
	{
		NSMutableDictionary<OCDriveID, NSMutableArray<OCItem *> *> *itemsByDriveID = [self _itemsByDriveID];
		NSMutableDictionary<OCDriveID, OCCoreItemList *> *itemListsByDriveID = [NSMutableDictionary new];

		[itemsByDriveID enumerateKeysAndObjectsUsingBlock:^(OCDriveID  _Nonnull driveID, NSMutableArray<OCItem *> * _Nonnull driveItems, BOOL * _Nonnull stop) {
			itemListsByDriveID[driveID] = [OCCoreItemList itemListWithItems:driveItems];
		}];

		_itemListsByDriveID = itemListsByDriveID;
	}

	return(_itemListsByDriveID);
}

@end
