# App Store launch — 2026-11-10

Goal: prepare and submit 记金 for App Store distribution using existing credentials and the existing signed IPA / JWT API workflow. User authorized release on 2026-11-10.

## Phases
- [x] Audit live App Store metadata, distribution regions, privacy, review access and backend health.
- [x] Make necessary iOS release fixes and align version with the App Store version.
- [x] Run meaningful tests, simulator verification and local Release signing.
- [ ] Complete store materials, upload one release build, and submit for review when all required facts are available.
- [ ] Report actual Apple state and any specific external blockers.

## Constraints
- Never expose credentials or commit private material.
- Preserve existing store pricing, regions and business information unless the user supplies a change.
- Do not invent filing numbers, legal declarations or review accounts.
- Follow sumly_ios/AGENTS.md; no alternative upload route.
- No duplicate upload, no redundant post-success checks.

## Known state
- Local source 0.1.1 (29); store version 1.0 is PREPARE_FOR_SUBMISSION.
- Existing build 29 is VALID; local signing and API authentication have been verified.
- Version 1.0 (30) is VALID / IN_BETA_TESTING in the internal 测试 group, and is selected for App Store version 1.0.
- User selected all territories outside mainland China; 174 enabled, China disabled, free price verified.
- User confirmation is pending for Apple's privacy-publication attestation; third-party content rights facts are also pending. Do not submit an unsupported declaration.
- Separate mainland filing assistance requested; technical material prepared, awaiting cloud provider / subject details.
