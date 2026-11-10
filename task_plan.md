# App Store launch — 2026-11-10

Goal: prepare and submit 记金 for App Store distribution using existing credentials and the existing signed IPA / JWT API workflow. User authorized release on 2026-11-10.

## Phases
- [x] Audit live App Store metadata, distribution regions, privacy, review access and backend health.
- [x] Make necessary iOS release fixes and align version with the App Store version.
- [x] Run meaningful tests, simulator verification and local Release signing.
- [x] Complete store materials, upload one release build, and submit for review when all required facts are available.
- [ ] Report actual Apple state and any specific external blockers.

## Constraints
- Never expose credentials or commit private material.
- Preserve existing store pricing, regions and business information unless the user supplies a change.
- Do not invent filing numbers, legal declarations or review accounts.
- Follow sumly_ios/AGENTS.md; no alternative upload route.
- No duplicate upload, no redundant post-success checks.

## Known state
- Initial source was 0.1.1 (29); the release source is now 1.0 (30).
- Local signing and API authentication have been verified.
- Version 1.0 (30) is VALID / IN_BETA_TESTING in the internal 测试 group, and is selected for App Store version 1.0.
- User selected all territories outside mainland China; 174 enabled, China disabled, free price verified.
- User confirmed Apple's privacy-publication attestation; the seven-type privacy disclosure is now published and was verified in the browser.
- User explicitly confirmed the necessary rights or lawful basis for displayed derived outputs. Saved USES_THIRD_PARTY_CONTENT; added version 1.0 to review submission and submitted it. Actual state is WAITING_FOR_REVIEW, with release AFTER_APPROVAL.
- Separate mainland filing assistance requested; technical material prepared. Verified the JD Cloud server and selected one new authorization code for APP / 记金. The user subsequently chose personal operation, selected 个人 and completed subject information. Service information and iOS public certificate details are saved. The user explicitly accepted the personal undertaking; advanced to 电子核验. Awaiting the user's ID attachments and video material directly on JD Cloud; no filing application submitted.
