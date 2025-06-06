//
//  OCVFSNode.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 28.04.22.
//  Copyright © 2022 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2022, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import <Foundation/Foundation.h>
#import "OCVFSTypes.h"
#import "OCItem.h"

@class OCVFSCore;

NS_ASSUME_NONNULL_BEGIN

@interface OCVFSNode : NSObject <OCVFSItem>

@property(weak,nullable,nonatomic) OCVFSCore *vfsCore;
@property(weak,nullable,readonly,nonatomic) OCVFSNode *parentNode;

@property(strong,nonatomic) OCVFSNodeID identifier; //!< Internal ID of virtual nodes.
@property(assign) OCVFSNodeType type; //!< The type of VFS node.
@property(assign) BOOL autogeneratedFillNode; //!< YES if this node has been autogenerated to fill a gap in the tree, i.e. if /some/folder is added and /some doesn't exist, the VFS core autogenerates a /some "fill node". Needed primarily for internal housekeeping.

@property(strong,readonly,nonatomic) OCVFSItemID itemID; //!< Computed item ID
//@property(strong,nullable) OCVFSItemID aliasItemID; //!< Alias item ID. When set, is used to locate the VFSNode for a "real" item.

@property(strong,nonatomic) NSString *name; //!< The name of the VFS node.
@property(strong,nonatomic) OCPath path; //!< The virtual path of the VFS node.

@property(strong, nullable) OCLocation *location; //!< The real location of a folder on a server
@property(strong, nullable, nonatomic) OCItem *locationItem; //!< The item at the location

@property(readonly,nonatomic) BOOL isRootNode; //!< Returns YES if this node is at the root of the VFS

+ (OCVFSNode *)virtualFolderAtPath:(OCPath)path location:(nullable OCLocation *)location;

+ (OCVFSNode *)virtualFolderInPath:(OCPath)path withName:(NSString *)name location:(nullable OCLocation *)location;

+ (OCVFSItemID)rootFolderItemIDForBookmarkUUID:(OCBookmarkUUIDString)bookmarkUUIDString driveID:(nullable OCDriveID)driveID;

@end

NS_ASSUME_NONNULL_END
