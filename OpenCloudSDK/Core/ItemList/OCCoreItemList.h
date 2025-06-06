//
//  OCCoreItemList.h
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

#import <Foundation/Foundation.h>
#import "OCItem.h"

typedef NS_ENUM(NSUInteger, OCCoreItemListState)
{
	OCCoreItemListStateNew,
	OCCoreItemListStateStarted,
	OCCoreItemListStateSuccess,
	OCCoreItemListStateFailed
};

@interface OCCoreItemList : NSObject
{
	OCCoreItemListState _state;

	NSArray <OCItem *> *_items;
	NSMutableDictionary <OCPath, OCItem *> *_itemsByPath;
	NSSet <OCPath> *_itemPathsSet;

	NSMutableDictionary <OCFileID, OCItem *> *_itemsByFileID;
	NSSet <OCFileID> *_itemFileIDsSet;

	NSMutableDictionary <OCLocalID, OCItem *> *_itemsByLocalID;
	NSSet <OCLocalID> *_itemLocalIDsSet;

	NSMutableDictionary <OCPath, NSMutableArray<OCItem *> *> *_itemsByParentPaths;
	NSSet <OCPath> *_itemParentPaths;

	NSMutableDictionary<OCDriveID, OCCoreItemList *> *_itemListsByDriveID;

	NSError *_error;
}

@property(assign) OCCoreItemListState state;

@property(strong,nonatomic) NSArray <OCItem *> *items;

@property(readonly,strong,nonatomic) NSMutableDictionary <OCPath, OCItem *> *itemsByPath;
@property(readonly,strong,nonatomic) NSSet <OCPath> *itemPathsSet;

@property(readonly,strong,nonatomic) NSMutableDictionary <OCFileID, OCItem *> *itemsByFileID;
@property(readonly,strong,nonatomic) NSSet <OCFileID> *itemFileIDsSet;

@property(readonly,strong,nonatomic) NSMutableDictionary <OCLocalID, OCItem *> *itemsByLocalID;
@property(readonly,strong,nonatomic) NSSet <OCLocalID> *itemLocalIDsSet;

@property(readonly,strong,nonatomic) NSMutableDictionary <OCPath, NSMutableArray<OCItem *> *> *itemsByParentPaths;
@property(readonly,strong,nonatomic) NSSet <OCPath> *itemParentPaths;

@property(readonly,strong,nonatomic) NSMutableDictionary<OCDriveID, OCCoreItemList *> *itemListsByDriveID;

@property(strong) NSError *error;

+ (instancetype)itemListWithItems:(NSArray <OCItem *> *)items;

- (void)updateWithError:(NSError *)error items:(NSArray <OCItem *> *)items;

@end
