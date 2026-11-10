# Launch progress

## 2026-11-10
- User authorized proceeding with App Store launch and necessary preparation.
- Read iOS release instructions and restored credentials in the preceding task.
- Beginning live metadata audit and release preparation.
- Created codex/app-store-1-0 branch for release changes.
- Updated version to 1.0 (30), linked existing calendar, removed unfinished subscription UI, added privacy/support links.
- First test build found two rendering fixtures still passing the removed showingNotice argument; updated both call sites before rerunning.
- Corrected rolling-date fixtures and replaced brittle fixed sleep assertions with bounded state waits. Realtime failure/retry test now gates recovery until the failed state has been observed.
- Full simulator suite passed: 195 tests (ReleaseReadiness-1.0-30-stable.xcresult).
- Saved Chinese store copy, category, copyright, age-rating answers, privacy URL and review contacts through Apple's API.
- User authorized launch outside mainland China first; separately requested assistance applying for mainland app filing. Requested provider and legal-subject details.
- Independent release review found incorrect legacy sign-in copy claiming holdings remain local / no cloud sync. Corrected those disclosures and hid unavailable provider controls; retained failure/retry behavior.
- Phone and iPad simulator home screens visually verified. Created a 10 g / CNY 800-per-gram local guest sample on the dedicated iPad simulator for actual UI/screenshot checks; no production account or cloud data was changed.
- Privacy questionnaire prepared with seven collected types, functionality-only, linked to user, no tracking. Apple's publication attestation awaits explicit user confirmation.
- Final simulator validation passed again: 195 tests; plist checks and independent code review completed.
- Distribution is configured for all 174 territories outside mainland China. Free price schedule saved.
- Four screenshots uploaded successfully: iPhone market; iPad market, holdings and calendar.
- First archive compiled but automatic signing selected an existing development key and waited for keychain authorization. Stopped that signing step; Release now explicitly uses the restored distribution certificate/profile, leaving Debug signing unchanged.
- Mainland filing technical bundle prepared under ~/.config/sumly/mainland-filing-20261110; contains public certificate/key, MD5, Bundle ID and icon, no private keys.
- Manual distribution archive/export succeeded. Strict archive signature verified; exported IPA metadata and privacy manifest checked. Apple accepted the IPA and is processing it.
- Live pricing verified free; live availability verified 174 enabled / mainland China disabled. Four screenshot uploads accepted, no asset errors reported.
- Content rights declaration is unset; requested the owner's authorization/permitted-use basis for the third-party market data. No content-rights assertion or formal submission was made.
