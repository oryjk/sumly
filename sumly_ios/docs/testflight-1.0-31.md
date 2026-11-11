# TestFlight 1.0 (31)

Date: 2026-11-11 (Asia/Shanghai)

- Source branch: `codex/app-store-1-0`.
- Source commit: `1d2d10f214969dcecdee14cc4f77b7aef682b5af`.
- Bundle ID: `com.oryjk.sumly`; version 1.0; build 31.
- Change: 我的 has a top-right settings gear. Account synchronization, guest import/conflict controls and market-cache clearing now live on the settings page.
- Validation: the unchanged feature code passed simulator compilation and three targeted rendering/cache tests in `build/SettingsNavigation-20261111-verified.xcresult`. Guest account and signed-in settings images were inspected. The upload script's 12 offline tests passed before this upload. Manual navigation remains unverified because the home Mac is locked; the user requested a TestFlight build for device testing.
- Signing/upload: existing Apple Distribution certificate/profile; local signed IPA plus the existing JWT API uploader. Credentials and upload recovery state remain outside Git.
- Expected archive: `build/Sumly-1.0-b31.xcarchive`; IPA/recovery directory: `build/ipa-b31`.
- Distribution target: internal 测试 group; configure external 外部测试 when Apple permits the corresponding Beta review submission.
- Source and release records were pushed to `origin/codex/app-store-1-0` and the remote commit was verified before archive/upload; the build tree was clean.
- Archive and local export succeeded. Strict archive signature and exported IPA bundle/version/build were verified. IPA SHA-256: `d642ecc3ed4238830c87a763eb8b46e50b39456a0861bf04221ffa43885ccf1c`.
- Apple build ID: `ae7d1886-35bf-4a75-86eb-8c26b0a9527c`; final `processingState=VALID`, `internalBuildState=IN_BETA_TESTING`, confirmed in internal 测试 group. Build 31 is ready for internal testing. Preserve `build/ipa-b31/Sumly.asc-upload-state.json`; do not upload again.
- Chinese testing notes are saved and automatic notification is enabled. Build 31 also belongs to the existing 外部测试 group.
- External review submission was rejected with `ENTITY_UNPROCESSABLE.ANOTHER_BUILD_IN_REVIEW`: build 30 in the same version train is still under Beta review. Build 31 is `READY_FOR_BETA_SUBMISSION`, not available to external testers yet. Submit its external Beta review after the existing review is completed; no review was canceled or App Store build changed.
- This TestFlight update does not replace the build selected for the existing App Store review.
