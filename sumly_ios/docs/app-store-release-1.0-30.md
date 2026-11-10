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

## Pending
- Apple completed processing: build 1.0 (30) is VALID / IN_BETA_TESTING and belongs to the internal 测试 group. The build is selected for App Store version 1.0. Preserve build/ipa-b30/Sumly.asc-upload-state.json; do not upload it twice.
- All three iPad screenshots are COMPLETE; the iPhone screenshot is UPLOAD_COMPLETE with no asset error at the final check.
- Privacy questionnaire has seven types prepared (functionality only, linked, no tracking), but publication attestation awaits the user's confirmation.
- The contentRightsDeclaration field is unset. The app accesses third-party market data; the owner must establish authorization or other permitted use before making this declaration.
- Formal review and public availability have not yet been achieved.

## Mainland China follow-up
The user separately requested app-filing assistance. Public technical materials are prepared outside Git at ~/.config/sumly/mainland-filing-20261110. Cloud provider, existing filing platform and legal subject still require input. No filing application has been submitted.
