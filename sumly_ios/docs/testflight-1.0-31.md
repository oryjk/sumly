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
- Current stage: source prepared; commit/push required before archive/upload. No build 31 existed in App Store Connect at the initial check.
- This TestFlight update does not replace the build selected for the existing App Store review.
