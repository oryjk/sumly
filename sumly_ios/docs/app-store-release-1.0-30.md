# App Store 1.0 (30) preparation

Date: 2026-11-10 (Asia/Shanghai)

## Product and signing
- Version 1.0 / build 30; bundle com.oryjk.sumly; iOS 17+, iPhone and iPad.
- Calendar navigation replaces the unfinished accounting entry and reuses the active workspace, selected book and amount visibility.
- Removed the unfinished market subscription entry.
- Account page includes the live privacy policy and support email.
- Sign-in disclosures now accurately describe account cloud storage and separate guest records; unavailable phone/email controls are hidden.
- Release explicitly uses the existing distribution certificate and profile. Debug remains automatically signed.
- Privacy manifest additionally covers purchase history and technical diagnostic logs. Production phone/email sign-in are disabled; revisit store disclosures before enabling additional data collection.

## Validation
- Full simulator suite: 195 tests passed, result bundle build/ReleaseReadiness-1.0-30-complete.xcresult.
- Corrected stale rolling-month test fixtures, safe assertions and scheduling-dependent test waits.
- Corrected the chart's zero formatting argument to retain Double type.
- Independent source review completed; misleading legacy sign-in copy identified and corrected.
- iPhone/iPad market screens inspected; iPad local guest save, holdings summary and calendar exercised without changing production account data.
- Archive signature passed codesign --verify --deep --strict.
- Exported IPA reports 1.0 (30), iOS 26.5 SDK, no non-exempt encryption, no tracking and packaged privacy manifest.

## Store preparation
- Chinese metadata: app-store-metadata-zh-Hans.json.
- Category Finance; age rating questionnaire answered based on actual features.
- Existing Beta reviewer contact reused for formal review.
- Free pricing; 174 territories enabled, mainland China disabled, per the user's instruction.
- Four actual simulator screenshots uploaded: iPhone market; iPad market, holdings and calendar.
- Existing automatic release-after-approval setting preserved.

## App Store review
- Apple completed processing: build 1.0 (30) is VALID / IN_BETA_TESTING and belongs to the internal 测试 group. The build is selected for App Store version 1.0. Preserve build/ipa-b30/Sumly.asc-upload-state.json; do not upload it twice.
- All four screenshots are now COMPLETE.
- Privacy questionnaire has seven types published (functionality only, linked, no tracking), after explicit user confirmation. Browser publication status verified.
- The owner explicitly confirmed the necessary rights or lawful basis for the app's distributed fusion/processed outputs. Saved USES_THIRD_PARTY_CONTENT based on that confirmation. No-IDFA declaration is saved.
- Added version 1.0 / build 30 to the App Review submission and submitted it. Verified actual App Store state WAITING_FOR_REVIEW and release type AFTER_APPROVAL.
- App Store formal submission is complete. Public availability awaits Apple's review and release processing; it is not yet live.

## Mainland China follow-up
The user separately requested app-filing assistance with JD Cloud at https://record-console.jdcloud.com/. Technical materials remain outside Git at ~/.config/sumly/mainland-filing-20261110. The production lightweight server was verified; one new authorization code was generated and selected, preserving the older code already in progress. After correcting the region, the user chose personal operation for 记金 instead of reusing the individual-business website subject, confirmed selecting 个人 and completed subject information directly. Service information is saved: iOS, Bundle ID, certificate public key and SHA-1 fingerprint, actual backend domain, JPG app icon, 工具 classification and the actual feature description. The draft has advanced to 上传资料. The generated personal undertaking was opened for reading; explicit acceptance is pending because 下一步 constitutes agreement. No filing application has been submitted.
