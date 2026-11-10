# App Store launch — 2026-11-10

Goal: prepare and submit 记金 for App Store distribution using existing credentials and the existing signed IPA / JWT API workflow. User authorized release on 2026-11-10.

## Phases
- [x] Audit live App Store metadata, distribution regions, privacy, review access and backend health.
- [x] Make necessary iOS release fixes and align version with the App Store version.
- [x] Run meaningful tests, simulator verification and local Release signing.
- [x] Complete store materials, upload one release build, and submit for review when all required facts are available.
- [x] Report actual Apple state and any specific external blockers.

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
- Mainland filing application is submitted. After the user's explicit acceptance of both final agreements and authorization, the user supplied the submission-success screenshot; the live JD Cloud audit page confirmed 您的资料已提交等待审核 / 京东云初审, estimated 1–3 working days. Preserve the existing order; do not resubmit. Approval, later SMS verification and filing completion remain external follow-up steps. Mainland App Store availability remains disabled until a valid APP filing number is obtained and configured.
