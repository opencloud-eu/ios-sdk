//
//  OCDatabase+Schemas.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 02.05.18.
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

#import "OCDatabase.h"

@interface OCDatabase (Schemas)

#pragma mark - Schemas
- (void)addSchemas;

@end

extern OCDatabaseTableName OCDatabaseTableNameMetaData;
extern OCDatabaseTableName OCDatabaseTableNameSyncJournal;
extern OCDatabaseTableName OCDatabaseTableNameSyncLanes;
extern OCDatabaseTableName OCDatabaseTableNameUpdateJobs;
extern OCDatabaseTableName OCDatabaseTableNameThumbnails;
extern OCDatabaseTableName OCDatabaseTableNameResources;
extern OCDatabaseTableName OCDatabaseTableNameCounters;
extern OCDatabaseTableName OCDatabaseTableNameEvents;
extern OCDatabaseTableName OCDatabaseTableNameItemPolicies;
