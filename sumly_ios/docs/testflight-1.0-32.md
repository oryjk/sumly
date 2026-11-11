# TestFlight 1.0 (32)

Date: 2026-11-11 (Asia/Shanghai)

- Source branch: `codex/app-store-1-0`.
- Source commit: `8f27df562b4279b930bab97a1da2a6873d0e3eec`.
- Bundle ID: `com.oryjk.sumly`; version 1.0; build 32.
- Change: remove the persistent provider reauthentication button from 我的. Normal sign-in and account-deletion-triggered reauthentication remain available. Includes the settings-page relocation from build 31.
- Validation: unchanged application code already passed simulator compilation, the signed-in account rendering test and two deletion-reauthentication regression tests before the version bump. The signed-in account screenshot was inspected. Logs: `build/account-without-reverify-20261111.log` and `build/account-reauth-regression-20261111.log`. The unchanged uploader's 12 offline tests passed during build 31 preparation.
- Standing workflow: future completed iOS code/UI changes automatically receive a new internal TestFlight build after validation and source push. Documentation-only updates do not create additional builds.
- Distribution target: internal 测试 group only, per the user's current instruction. Do not change external tester distribution or the App Store review build.
- Signing/upload: existing Apple Distribution certificate/profile; local signed IPA plus existing JWT API uploader. Archive: `build/Sumly-1.0-b32.xcarchive`; IPA/recovery: `build/ipa-b32`.
- Current stage: prepared; push source and this provenance record before archive/upload. Initial check found no build 32 or existing local build-32 archive/IPA directory.
