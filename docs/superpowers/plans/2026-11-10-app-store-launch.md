# App Store 1.0 release plan

Goal: ship the existing 记金 iOS app through App Store review, as authorized by the user.

Architecture: preserve the existing SwiftUI, SwiftData and account/cloud architecture. Reuse implemented calendar functionality for the empty accounting navigation slot. Use the existing signed IPA / JWT upload path.

## Release changes
- [ ] Set project.yml to 1.0 (30), regenerate the Xcode project and Info.plist.
- [ ] Replace the unimplemented accounting tab with the existing calendar sheet, preserving the active account's SwiftData context, selected book, amount-visibility preference and market basis.
- [ ] Remove the unimplemented gold subscription control and its alert/binding from HomeView and MarketHomeChartContent.
- [ ] Add easily accessible privacy-policy and support links to AccountView; policy URL https://oryjk.cn/sumly/privacy is verified reachable.
- [ ] Add truthful Chinese store copy and English reviewer instructions; reuse existing Beta reviewer contact information without exposing it in repository files.

## Verification and distribution
- [ ] Run iOS simulator tests, inspect phone and tablet UI, and generate screenshots from actual implemented screens.
- [ ] Review the complete diff before archiving; check Release metadata, entitlements and privacy manifest.
- [ ] Archive and export locally, upload once via existing JWT API workflow, preserve upload recovery state.
- [ ] Populate category, age rating, privacy policy URL, description, screenshots and reviewer details.
- [ ] Wait for the user's distribution-region answer; do not fabricate a mainland-China app filing number.
- [ ] Submit only after Apple-required fields and privacy declarations are complete. Preserve automatic release AFTER_APPROVAL.

## Review focus
- Calendar must use the current workspace and must respect hidden amounts.
- New links must be reachable and no placeholder feature may remain exposed.
- Screenshots and metadata must describe the actual app; production login currently offers Apple only.
- Store privacy answers must reflect account holdings cloud storage and server access logs.
- Do not confuse an uploaded build or a TestFlight success with formal review/public release.
