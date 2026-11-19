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

## 2026-11-11 — Account settings follow-up
- [x] Move synchronization, guest import/conflicts and market-cache clearing into a dedicated settings page.
- [x] Add an accessible gear at the top right of 我的, navigating to settings.
- [x] Compile and run targeted rendering/cache checks; inspect actual generated screenshots.
- [ ] Verify gear navigation and return manually on the office computer; the home Mac is locked and the user is taking over this check.
- [x] Commit and push the related code and verification record (code: 55ef770, origin/codex/app-store-1-0).

## 2026-11-11 — TestFlight build 31
- [x] Confirm build 31 is not already uploaded; increment build number and run offline upload checks.
- [x] Commit/push source and provenance record; verify the remote commit before upload.
- [x] Archive, export and upload one signed IPA using the established JWT API route.
- [x] Configure internal/external test distribution and report the actual usable/review state: internal ready; external Beta submission blocked by build 30's existing review.
- External follow-up: submit build 31 for Beta review after Apple's existing same-version review is completed. Do not upload the IPA again or replace the App Store build for this testing task.

## 2026-11-11 — Internal TestFlight build 32
- [x] Record automatic internal-test release workflow; prepare build 32 with existing passing feature validation.
- [x] Push source/provenance and verify the remote commit before upload.
- [x] Archive/export/upload one signed IPA using the established JWT API workflow.
- [x] Save testing notes, configure internal 测试 group and verify final TestFlight readiness once: 1.0 (32), VALID / IN_BETA_TESTING, internal group confirmed. External testing remains paused; App Store review unchanged.

## 2026-11-18 — 1.0.1 中国大陆上架

- [x] 设置页显示 App 备案号及工信部查询链接，验证游客和登录态。
- [x] 推送 1.0.1（33）源码和版本记录，核对远端提交。
- [x] 在 Apple 后台保存备案号及两项中国大陆合规声明。
- [x] 确认 Apple 构建处理完成，分发至内部「测试」并提交正式审核。
- [x] 1.0.1 审核通过后开放中国大陆店面。
- [ ] 核对中国大陆店面的公开产品页和可下载状态。

## 2026-11-19 — 禅观 WebView 本地联调

- [x] 禅观在 local233 校验服务端请求，创建 60 秒一次性凭证并兑换 HttpOnly Cookie。跟踪数据按 `sumly:<user_id>` 隔离。
- [x] 记金 Go 后端复用实时原生会话校验，向禅观签发接口申请凭证。未配置时关闭该接入。
- [x] 记金 iOS 复用当前登录态，在独立 WKWebView 会话中兑换并打开禅观，验证切换账户、失效及重试。
- [x] 通过隔离的 local233 测试实例验证后端与模拟器。公开转发与发布留到生产 HTTPS 地址配置后。

## 2026-11-19 — 禅观公网免登测试

- [x] 通过 local109 和 local233 增加独立 HTTPS 测试路由，保护服务端签发接口，复查 Android。
- [x] 用 iPhone 模拟器在公网 HTTPS 上验证内部构建。
- [ ] 推送源码，上传 1.0.2（34），确认内部「测试」可安装。
