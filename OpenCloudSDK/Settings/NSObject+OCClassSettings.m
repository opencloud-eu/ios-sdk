//
//  NSObject+OCClassSettings.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 25.02.18.
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

#import "NSObject+OCClassSettings.h"

@implementation NSObject (OCClassSettings)

+ (void)registerOCClassSettingsDefaults:(NSDictionary<OCClassSettingsKey, id> *)additionalDefaults metadata:(nullable OCClassSettingsMetadataCollection)metaData
{
	if (additionalDefaults==nil) { return; }

	[OCClassSettings.sharedSettings registerDefaults:additionalDefaults metadata:metaData forClass:self];
}

+ (nullable id)classSettingForOCClassSettingsKey:(OCClassSettingsKey)key
{
	if (key==nil) { return(nil); }

	return ([[OCClassSettings.sharedSettings settingsForClass:self.class] objectForKey:key]);
}

- (nullable id)classSettingForOCClassSettingsKey:(OCClassSettingsKey)key
{
	if (key==nil) { return(nil); }

	return ([[OCClassSettings.sharedSettings settingsForClass:self.class] objectForKey:key]);
}

@end
