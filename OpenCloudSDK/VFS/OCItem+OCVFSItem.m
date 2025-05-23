//
//  OCItem+OCVFSItem.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 20.05.22.
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

#import "OCItem+OCVFSItem.h"

@implementation OCItem (VFSItem)

#pragma mark - OCVFSItem
- (OCVFSItemID)vfsItemID
{
	if (self.isRoot)
	{
		return ([OCVFSNode rootFolderItemIDForBookmarkUUID:self.bookmarkUUID driveID:self.driveID]);
	}

	return ([OCVFSCore composeVFSItemIDForOCItemWithBookmarkUUID:self.bookmarkUUID driveID:self.driveID localID:self.localID]);
}

- (OCVFSItemID)vfsParentItemID
{
	if (self.path.parentPath.isRootPath)
	{
		return ([OCVFSNode rootFolderItemIDForBookmarkUUID:self.bookmarkUUID driveID:self.driveID]);
	}

	return ([OCVFSCore composeVFSItemIDForOCItemWithBookmarkUUID:self.bookmarkUUID driveID:self.driveID localID:self.parentLocalID]);
}

- (NSString *)vfsItemName
{
	return (self.name);
}

@end
