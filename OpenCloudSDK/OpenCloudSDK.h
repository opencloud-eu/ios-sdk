//
//  OpenCloudSDK.h
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

#import <Foundation/Foundation.h>

//! Project version number for OpenCloudSDK.
FOUNDATION_EXPORT double OpenCloudSDKVersionNumber;

//! Project version string for OpenCloudSDK.
FOUNDATION_EXPORT const unsigned char OpenCloudSDKVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <OpenCloudSDK/PublicHeader.h>

#import <OpenCloudSDK/OCPlatform.h>

#import <OpenCloudSDK/OCTypes.h>
#import <OpenCloudSDK/OCMacros.h>
#import <OpenCloudSDK/OCFeatureAvailability.h>

#import <OpenCloudSDK/OCViewProvider.h>
#import <OpenCloudSDK/OCViewProviderContext.h>

#import <OpenCloudSDK/OCLocale.h>
#import <OpenCloudSDK/OCLocaleFilter.h>
#import <OpenCloudSDK/OCLocaleFilterClassSettings.h>
#import <OpenCloudSDK/OCLocaleFilterVariables.h>
#import <OpenCloudSDK/OCLocale+SystemLanguage.h>

#import <OpenCloudSDK/NSError+OCError.h>
#import <OpenCloudSDK/OCHTTPStatus.h>
#import <OpenCloudSDK/NSError+OCHTTPStatus.h>
#import <OpenCloudSDK/NSError+OCDAVError.h>
#import <OpenCloudSDK/NSError+OCNetworkFailure.h>

#import <OpenCloudSDK/OCAppIdentity.h>

#import <OpenCloudSDK/OCKeychain.h>
#import <OpenCloudSDK/OCCertificate.h>
#import <OpenCloudSDK/OCCertificateRuleChecker.h>
#import <OpenCloudSDK/OCCertificateStore.h>
#import <OpenCloudSDK/OCCertificateStoreRecord.h>

#import <OpenCloudSDK/OCClassSetting.h>
#import <OpenCloudSDK/OCClassSettings.h>
#import <OpenCloudSDK/OCClassSettings+Documentation.h>
#import <OpenCloudSDK/OCClassSettings+Metadata.h>
#import <OpenCloudSDK/OCClassSettings+Validation.h>
#import <OpenCloudSDK/NSObject+OCClassSettings.h>
#import <OpenCloudSDK/NSError+OCClassSettings.h>
#import <OpenCloudSDK/NSString+OCClassSettings.h>
#import <OpenCloudSDK/OCClassSettingsFlatSource.h>
#import <OpenCloudSDK/OCClassSettingsFlatSourceManagedConfiguration.h>
#import <OpenCloudSDK/OCClassSettingsFlatSourcePropertyList.h>
#import <OpenCloudSDK/OCClassSettingsFlatSourcePostBuild.h>
#import <OpenCloudSDK/NSDictionary+OCExpand.h>

#import <OpenCloudSDK/OCCore.h>
#import <OpenCloudSDK/OCCore+FileProvider.h>
#import <OpenCloudSDK/OCCoreItemList.h>
#import <OpenCloudSDK/OCCore+ItemList.h>
#import <OpenCloudSDK/OCCore+ItemUpdates.h>
#import <OpenCloudSDK/OCCore+DirectURL.h>
#import <OpenCloudSDK/OCCore+NameConflicts.h>
#import <OpenCloudSDK/OCCore+Search.h>
#import <OpenCloudSDK/OCSearchResult.h>
#import <OpenCloudSDK/OCScanJobActivity.h>
#import <OpenCloudSDK/NSString+NameConflicts.h>
#import <OpenCloudSDK/NSProgress+OCEvent.h>

#import <OpenCloudSDK/OCCore+ItemPolicies.h>
#import <OpenCloudSDK/OCItemPolicy.h>
#import <OpenCloudSDK/OCItemPolicy+OCDataItem.h>
#import <OpenCloudSDK/OCItemPolicyProcessor.h>
#import <OpenCloudSDK/OCItemPolicyProcessorAvailableOffline.h>
#import <OpenCloudSDK/OCItemPolicyProcessorDownloadExpiration.h>
#import <OpenCloudSDK/OCItemPolicyProcessorVacuum.h>

#import <OpenCloudSDK/OCPasswordPolicy.h>
#import <OpenCloudSDK/OCPasswordPolicy+Default.h>
#import <OpenCloudSDK/OCPasswordPolicy+Generator.h>
#import <OpenCloudSDK/OCPasswordPolicyRule.h>
#import <OpenCloudSDK/OCPasswordPolicyRuleCharacters.h>
#import <OpenCloudSDK/OCPasswordPolicyRuleByteLength.h>
#import <OpenCloudSDK/OCPasswordPolicyRule+StandardRules.h>
#import <OpenCloudSDK/OCPasswordPolicyReport.h>
#import <OpenCloudSDK/OCCapabilities+PasswordPolicy.h>

#import <OpenCloudSDK/OCCore+Claims.h>
#import <OpenCloudSDK/OCClaim.h>

#import <OpenCloudSDK/OCKeyValueStore.h>

#import <OpenCloudSDK/OCCoreConnectionStatusSignalProvider.h>

#import <OpenCloudSDK/OCBookmark.h>
#import <OpenCloudSDK/OCBookmark+Diagnostics.h>

#import <OpenCloudSDK/OCAuthenticationMethod.h>
#import <OpenCloudSDK/OCAuthenticationMethodBasicAuth.h>
#import <OpenCloudSDK/OCAuthenticationMethodOAuth2.h>
#import <OpenCloudSDK/OCAuthenticationMethodOpenIDConnect.h>
#import <OpenCloudSDK/OCAuthenticationMethod+OCTools.h>

#import <OpenCloudSDK/OCAuthenticationBrowserSession.h>
#import <OpenCloudSDK/OCAuthenticationBrowserSessionCustomScheme.h>

#import <OpenCloudSDK/OCConnection.h>
#import <OpenCloudSDK/OCCapabilities.h>

#import <OpenCloudSDK/OCServerInstance.h>
#import <OpenCloudSDK/OCBookmark+ServerInstance.h>

#import <OpenCloudSDK/OCLockManager.h>
#import <OpenCloudSDK/OCLockRequest.h>
#import <OpenCloudSDK/OCLock.h>

#import <OpenCloudSDK/OCHTTPRequest.h>
#import <OpenCloudSDK/OCHTTPRequest+JSON.h>
#import <OpenCloudSDK/OCHTTPResponse.h>
#import <OpenCloudSDK/OCHTTPDAVRequest.h>

#import <OpenCloudSDK/OCHTTPCookieStorage.h>
#import <OpenCloudSDK/NSHTTPCookie+OCCookies.h>

#import <OpenCloudSDK/OCHTTPPipelineManager.h>
#import <OpenCloudSDK/OCHTTPPipeline.h>
#import <OpenCloudSDK/OCHTTPPipelineTask.h>
#import <OpenCloudSDK/OCHTTPPipelineTaskMetrics.h>
#import <OpenCloudSDK/OCHTTPPipelineBackend.h>
#import <OpenCloudSDK/OCHTTPPipelineTaskCache.h>

#import <OpenCloudSDK/OCHTTPPolicyManager.h>
#import <OpenCloudSDK/OCHTTPPolicy.h>

#import <OpenCloudSDK/OCHTTPDAVMultistatusResponse.h>

#import <OpenCloudSDK/OCHostSimulator.h>
#import <OpenCloudSDK/OCHostSimulatorResponse.h>
#import <OpenCloudSDK/OCHostSimulatorManager.h>
#import <OpenCloudSDK/OCHostSimulator+BuiltIn.h>
#import <OpenCloudSDK/OCExtension+HostSimulation.h>

#import <OpenCloudSDK/OCWaitCondition.h>

#import <OpenCloudSDK/OCEvent.h>
#import <OpenCloudSDK/OCEventTarget.h>

#import <OpenCloudSDK/OCVault.h>
#import <OpenCloudSDK/OCVaultLocation.h>
#import <OpenCloudSDK/OCDatabase.h>
#import <OpenCloudSDK/OCDatabase+Versions.h>
#import <OpenCloudSDK/OCDatabaseConsistentOperation.h>
#import <OpenCloudSDK/OCSQLiteDB.h>
#import <OpenCloudSDK/OCSQLiteQuery.h>
#import <OpenCloudSDK/OCSQLiteQueryCondition.h>
#import <OpenCloudSDK/OCSQLiteTransaction.h>
#import <OpenCloudSDK/OCSQLiteResultSet.h>
#import <OpenCloudSDK/OCSQLiteCollation.h>
#import <OpenCloudSDK/OCSQLiteCollationLocalized.h>

#import <OpenCloudSDK/OCBookmark+Prepopulation.h>
#import <OpenCloudSDK/OCVault+Prepopulation.h>
#import <OpenCloudSDK/OCDAVRawResponse.h>

#import <OpenCloudSDK/OCResourceTypes.h>
#import <OpenCloudSDK/OCResourceManager.h>
#import <OpenCloudSDK/OCResourceManagerJob.h>
#import <OpenCloudSDK/OCResourceSource.h>
#import <OpenCloudSDK/OCResourceSourceURL.h>
#import <OpenCloudSDK/OCResourceSourceStorage.h>
#import <OpenCloudSDK/OCResourceRequest.h>
#import <OpenCloudSDK/OCResourceRequestImage.h>
#import <OpenCloudSDK/OCResource.h>
#import <OpenCloudSDK/OCResourceImage.h>
#import <OpenCloudSDK/OCResourceTextPlaceholder.h>
#import <OpenCloudSDK/OCResourceText.h>
#import <OpenCloudSDK/OCResourceSourceAvatarPlaceholders.h>
#import <OpenCloudSDK/OCResourceSourceAvatars.h>
#import <OpenCloudSDK/OCResourceRequestAvatar.h>
#import <OpenCloudSDK/OCResourceSourceItemThumbnails.h>
#import <OpenCloudSDK/OCResourceSourceItemLocalThumbnails.h>
#import <OpenCloudSDK/OCResourceRequestItemThumbnail.h>
#import <OpenCloudSDK/OCResourceSourceURLItems.h>
#import <OpenCloudSDK/OCResourceRequestURLItem.h>

#import <OpenCloudSDK/OCAvatar.h>

#import <OpenCloudSDK/GAGraph.h>
#import <OpenCloudSDK/GAGraphObject.h>
#import <OpenCloudSDK/GAGraphContext.h>
#import <OpenCloudSDK/GAQuota.h>
#import <OpenCloudSDK/OCConnection+GraphAPI.h>

#import <OpenCloudSDK/OCLocation.h>
#import <OpenCloudSDK/OCDrive.h>
#import <OpenCloudSDK/OCQuota.h>

#import <OpenCloudSDK/OCDataTypes.h>
#import <OpenCloudSDK/OCDataSource.h>
#import <OpenCloudSDK/OCDataSourceArray.h>
#import <OpenCloudSDK/OCDataSourceComposition.h>
#import <OpenCloudSDK/OCDataSourceKVO.h>
#import <OpenCloudSDK/OCDataSourceMapped.h>
#import <OpenCloudSDK/OCDataSourceSubscription.h>
#import <OpenCloudSDK/OCDataSourceSnapshot.h>
#import <OpenCloudSDK/OCDataItemRecord.h>
#import <OpenCloudSDK/OCDataConverter.h>
#import <OpenCloudSDK/OCDataConverterPipeline.h>
#import <OpenCloudSDK/OCDataItemPresentable.h>
#import <OpenCloudSDK/OCDataRenderer.h>

#import <OpenCloudSDK/OCCore+DataSources.h>

#import <OpenCloudSDK/OCQuery.h>
#import <OpenCloudSDK/OCQueryFilter.h>
#import <OpenCloudSDK/OCQueryCondition.h>
#import <OpenCloudSDK/OCQueryCondition+Item.h>
#import <OpenCloudSDK/OCQueryCondition+KQLBuilder.h>
#import <OpenCloudSDK/OCQueryChangeSet.h>

#import <OpenCloudSDK/OCItem.h>
#import <OpenCloudSDK/OCItem+OCDataItem.h>
#import <OpenCloudSDK/OCItem+OCTypeAlias.h>
#import <OpenCloudSDK/OCItemVersionIdentifier.h>

#import <OpenCloudSDK/OCShare.h>
#import <OpenCloudSDK/OCShare+OCDataItem.h>
#import <OpenCloudSDK/OCShareRole.h>
#import <OpenCloudSDK/OCShareRole+OCDataItem.h>
#import <OpenCloudSDK/OCUser.h>
#import <OpenCloudSDK/OCGroup.h>
#import <OpenCloudSDK/OCIdentity.h>
#import <OpenCloudSDK/OCIdentity+DataItem.h>

#import <OpenCloudSDK/OCRecipientSearchController.h>
#import <OpenCloudSDK/OCShareQuery.h>

#import <OpenCloudSDK/OCActivity.h>
#import <OpenCloudSDK/OCActivityManager.h>
#import <OpenCloudSDK/OCActivityUpdate.h>

#import <OpenCloudSDK/OCSyncRecord.h>
#import <OpenCloudSDK/OCSyncRecordActivity.h>

#import <OpenCloudSDK/OCSyncIssue.h>
#import <OpenCloudSDK/OCSyncIssueChoice.h>
#import <OpenCloudSDK/OCMessageTemplate.h>
#import <OpenCloudSDK/OCIssue+SyncIssue.h>

#import <OpenCloudSDK/OCMessageQueue.h>
#import <OpenCloudSDK/OCMessage.h>
#import <OpenCloudSDK/OCMessageChoice.h>
#import <OpenCloudSDK/OCMessagePresenter.h>

#import <OpenCloudSDK/OCAppProvider.h>
#import <OpenCloudSDK/OCAppProviderApp.h>
#import <OpenCloudSDK/OCAppProviderFileType.h>

#import <OpenCloudSDK/OCTUSHeader.h>
#import <OpenCloudSDK/OCTUSJob.h>
#import <OpenCloudSDK/NSString+TUSMetadata.h>

#import <OpenCloudSDK/NSURL+OCURLNormalization.h>
#import <OpenCloudSDK/NSURL+OCURLQueryParameterExtensions.h>
#import <OpenCloudSDK/NSString+OCVersionCompare.h>
#import <OpenCloudSDK/NSString+OCPath.h>
#import <OpenCloudSDK/NSString+OCFormatting.h>
#import <OpenCloudSDK/NSProgress+OCExtensions.h>
#import <OpenCloudSDK/NSArray+ObjCRuntime.h>
#import <OpenCloudSDK/NSArray+OCFiltering.h>
#import <OpenCloudSDK/NSArray+OCMapping.h>
#import <OpenCloudSDK/NSDate+OCDateParser.h>

#import <OpenCloudSDK/UIImage+OCTools.h>

#import <OpenCloudSDK/OCXMLNode.h>
#import <OpenCloudSDK/OCXMLParser.h>
#import <OpenCloudSDK/OCXMLParserNode.h>

#import <OpenCloudSDK/OCCache.h>

#import <OpenCloudSDK/OCCoreManager.h>
#import <OpenCloudSDK/OCCoreManager+ItemResolution.h>
#import <OpenCloudSDK/OCBookmarkManager.h>
#import <OpenCloudSDK/OCBookmarkManager+ItemResolution.h>

#import <OpenCloudSDK/OCChecksum.h>
#import <OpenCloudSDK/OCChecksumAlgorithm.h>
#import <OpenCloudSDK/OCChecksumAlgorithmSHA1.h>

#import <OpenCloudSDK/OCFile.h>

#import <OpenCloudSDK/OCProgress.h>

#import <OpenCloudSDK/OCLogger.h>
#import <OpenCloudSDK/OCLogComponent.h>
#import <OpenCloudSDK/OCLogToggle.h>
#import <OpenCloudSDK/OCLogFileRecord.h>
#import <OpenCloudSDK/OCLogWriter.h>
#import <OpenCloudSDK/OCLogFileWriter.h>
#import <OpenCloudSDK/OCLogTag.h>

#import <OpenCloudSDK/OCExtensionTypes.h>
#import <OpenCloudSDK/OCExtensionManager.h>
#import <OpenCloudSDK/OCExtensionContext.h>
#import <OpenCloudSDK/OCExtensionLocation.h>
#import <OpenCloudSDK/OCExtensionMatch.h>
#import <OpenCloudSDK/OCExtension.h>
#import <OpenCloudSDK/OCExtension+License.h>

#import <OpenCloudSDK/OCIPNotificationCenter.h>

#import <OpenCloudSDK/OCBackgroundTask.h>

#import <OpenCloudSDK/OCProcessManager.h>
#import <OpenCloudSDK/OCProcessSession.h>

#import <OpenCloudSDK/OCCellularManager.h>
#import <OpenCloudSDK/OCCellularSwitch.h>

#import <OpenCloudSDK/OCNetworkMonitor.h>

#import <OpenCloudSDK/OCDiagnosticSource.h>
#import <OpenCloudSDK/OCDiagnosticNode.h>
#import <OpenCloudSDK/OCDatabase+Diagnostic.h>
#import <OpenCloudSDK/OCSyncRecord+Diagnostic.h>
#import <OpenCloudSDK/OCHTTPPipeline+Diagnostic.h>

#import <OpenCloudSDK/OCAsyncSequentialQueue.h>
#import <OpenCloudSDK/OCRateLimiter.h>
#import <OpenCloudSDK/OCDeallocAction.h>
#import <OpenCloudSDK/OCCancelAction.h>
#import <OpenCloudSDK/OCMeasurement.h>
#import <OpenCloudSDK/OCMeasurementEvent.h>

#import <OpenCloudSDK/OCServerLocator.h>

#import <OpenCloudSDK/OCVFSTypes.h>
#import <OpenCloudSDK/OCVFSCore.h>
#import <OpenCloudSDK/OCVFSNode.h>
#import <OpenCloudSDK/OCVFSContent.h>
#import <OpenCloudSDK/OCItem+OCVFSItem.h>

#import <OpenCloudSDK/OCAction.h>
#import <OpenCloudSDK/OCSymbol.h>
#import <OpenCloudSDK/OCStatistic.h>

#import <OpenCloudSDK/OCSignal.h>
