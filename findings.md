# Launch findings

- iOS uses SwiftUI / Swift 6 / SwiftData; iPhone and iPad targets, iOS 17+.
- App Store Connect is accessible using restored existing API credentials.
- Current App Store draft is version 1.0; source project is 0.1.1 (29).
- Unimplemented accounting tab and subscription button remain visible in source.
- Privacy policy exists at docs/privacy.html, but account UI has no privacy link.
- Credentials live outside the repository; private Python environment is ~/.config/sumly/publish-venv.
- This run must distinguish submission, approval, and actual public availability.
- Live App Store draft has no build selected, screenshots, description, keywords, support URL, copyright, category, age-rating answers or privacy-policy URL. Release type is AFTER_APPROVAL.
- Existing Beta reviewer contact fields are present and can be reused; no test login credentials are stored there.
- Production authentication capabilities: Apple enabled, phone/email disabled. Guests can use the app locally.
- https://oryjk.cn/sumly/privacy returns HTTP 200; /privacy.html is not a valid deployment path.
- Production AU9999 quote endpoint returned HTTP 200 and a current quote.
- Browser control initialization timed out; API access works. Public App Store privacy questionnaire may require a working logged-in browser.
- Asked user asynchronously for launch territories and, if mainland China is included, the app ICP filing number.
- User answered: launch outside mainland China first.
- Official Apple OpenAPI 4.6 contains no privacy-questionnaire API; browser access now works through native Edge accessibility and will be used only for those unsupported fields.
- Tests were terminated by a test fixture with fixed 2026-09-28 data outside today's rolling month, followed by points[0] access. Replacing rolling-range fixture dates with five days ago and using optional first element assertions preserves test meaning without changing production market logic.
