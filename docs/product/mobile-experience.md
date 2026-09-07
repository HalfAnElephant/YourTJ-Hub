# Mobile experience

> Doc type: product spec
>
> Status: Active
>
> Owner: Platform maintainers
>
> Last verified: 2026-09-07

The Flutter app combines the forum, course catalog, scheduler and Wiki. Ordinary browsing and
writing use native pages. Management uses the same first-party workspaces and permission checks as
Web inside an authenticated in-app browser. The navigation and management boundary are recorded in
[0011](../decisions/0011-mobile-navigation-and-management.md).

## Navigation and reading

- `Current`: four persistent destinations — Home, Campus, Messages and Profile — use icon-only
  navigation with accessible labels. Search is a pushed page, reachable from Home. Campus links to
  the native course catalog, scheduler and Wiki; returning preserves the selected destination.
  About links to native friend links, sponsors, terms and privacy pages using the site’s published
  configuration; disabled policies remain hidden.
- `Current`: Home cards retain both images for two-image topics. A portrait single image sits beside
  the text; a landscape image appears below the text with aspect-preserving fit. Portrait galleries
  show up to three columns; two landscape images share a row; larger landscape galleries overlap
  up to three previews with a total count. Tapping opens the full gallery with zoom.
- `Current`: simple-content topics show an uncropped, swipeable image gallery above the body. The
  same gallery is used in the publishing preview.
- `Current`: contextual floating actions settle after scrolling stops. Home offers compose or
  refresh-and-return-to-top. Topic pages offer reply, return to the first post, refresh, or a jump
  to discussion when the first post extends well beyond the viewport. Reduced-motion preferences
  suppress the scroll animation. Actions run only on a tap.
- `Current`: the floor slider loads the selected server window on release. Earliest/latest
  shortcuts, reply links, and earlier/later pagination navigate the actual reply stream. Returning
  to the first post from a middle window reloads that window before offering refresh; stale
  pagination responses are discarded after a floor or session change.

- `Current`: topic and reply authors open their public profiles. Owners can edit/delete their
  content; replies support likes, bookmarks, sharing and paginated revision history. Moderation
  actions follow server capabilities. Removed content has an explicit placeholder; posting
  restrictions suppress reply controls, while anonymous users can proceed to login.
- `Current`: reply edits preserve unsaved text on failed saves and confirm before discarding.
  Server-required reply captchas can be refreshed without losing the draft. Session changes
  invalidate pending edits and destructive confirmations; share failures remain visible in-app.

## Publishing

- `Current`: the type selector keeps Web's moment/question/article values. Moments and questions
  use a simple gallery plus text; articles use an inline rich editor backed by Markdown. Article
  formatting tools are folded by default. Existing topics retain their type when edited.
- `Current`: simple galleries support up to nine uploaded images, reordering and removal. Images
  survive switching to the article editor. Switching back extracts images into the gallery and
  plain text into the body; conversion is rejected when more than nine images would be lost.
- `Current`: Next opens the preview/classification step. Up to three existing categories can be
  selected below the rendered image/title/body preview. Publish writes only after this step; saving a draft retains the server's title,
  body and classification requirements. Moments can derive their title from the first text line.
- `Current`: publishing limits, captcha requests and other API failures use the Web error catalog
  in the selected language, including server-provided parameters.
- `Current`: unsaved changes prompt before leaving. A server-required captcha is shown in the
  composer and can be refreshed without discarding content.
- `Planned`: text-to-image cards and offline draft autosave. No UI claims these features exist.

## Profile and privacy

- `Current`: avatar and cover uploads open a native drag/pinch crop preview with an accessible
  zoom slider and reset action. Avatars export at 300×300; covers at 1600×320 with the central
  mobile area marked. Camera orientation is normalized before cropping. Failed uploads retain
  the selection for retry; covers can also be removed with confirmation.
- `Current`: OAuth connections show native account identity and provider availability. Binding
  opens the existing site settings in the system browser, where the user signs into the matching
  account; returning refreshes the native binding list. Unbinding remains native, including an
  existing Google connection when new Google sign-in is disabled. This browser flow does not
  transfer the native session and may require a separate Web login.
- `Current`: account settings support username changes and the twelve built-in avatars. Server
  validation remains visible in the username form so rejected names can be corrected and retried.
- `Current`: profile editing includes nickname, bio, signature, website name/URL, profile language
  and the six Web social providers. Saving preserves unedited fields and unknown social providers;
  website/social destinations accept HTTP(S), and social usernames expand to provider URLs.
  Public profiles display website/social links and open them in the system browser. Returning
  from settings refreshes profile identity and media immediately.

- `Current`: the overflow menu contains drafts, content management, recycle bin, account settings,
  and permission-gated administration/moderation. Account controls are outside the public profile.
- `Current`: only the active profile tab displays its label; all tabs retain accessible names.
  Activity, topics, likes, own bookmarks, follows/followers and badges fetch their corresponding
  server streams. Cursor pagination uses the server's next URL within the same user's profile.
- `Current`: content management and recycle bin provide topic/reply filters, cursor loading,
  multi-selection, restore and deletion. Restore/permanent-delete affordances follow the server's
  capabilities; confirmation/password requirements and partial batch failures remain authoritative.
- `Current`: privacy settings link to content management and account closure. Closure offers
  anonymized-history and best-effort content-deletion modes, requires the current password and
  clears the native session on success. Retention and authorization rules match Web.

## Management workspaces

- `Partial`: the complete Web admin console and moderation workspace are reachable in the App.
  The native wrapper and authenticated handoff pass local iOS and Android login/draft/console
  journeys; all 27 administrative modules fit both viewports, including the link editor.
  The journey creates and deletes a friend link through the real administrative form.
  Both independent course workspaces also pass authenticated handoff and viewport checks on iOS
  and Android.
  Android export sharing and a JSON file selected through the system picker also pass a local
  device journey; the import is not submitted by that test. On iOS the export reaches the native
  share sheet, but dismissal/file selection has not completed under the available simulator UI
  automation. Remaining administrative forms and that iOS file round-trip still need device
  validation before claiming complete mobile parity.
- `Current`: course management and course-review moderation have separate entries in Profile and
  the course catalog. Only CourseManager or Admin can discover and enter them; forum moderator
  status alone does not grant access.
- The embedded browser accepts only the configured first-party origin. Production requires HTTPS;
  cleartext is permitted only for local development hosts. Outside links open in the system browser
  without the native Bearer header. No bearer is placed in a URL or injected into JavaScript.
- The handoff accepts an explicit Bearer credential, verifies the existing session and workspace
  permission, sets an HttpOnly SameSite=Lax cookie, then redirects to an allowlisted workspace.
  Cookie-only requests cannot establish a browser session. All responses are `no-store`; existing
  revocation, role, writable-account and CSRF checks remain active.
- Android file inputs use the system file selector; iOS uses WebKit's picker. Export navigation is
  restricted to the exact same-origin admin export endpoint. Native downloads do not follow
  redirects, require an attachment response, and share the actual JSON/CSV filename. Temporary
  files are removed after sharing. The browser's cookies/storage/cache are cleared on exit.

## Verification boundaries

The source, contract and focused Flutter/Go tests define the implemented behavior. Figma is the
editable visual counterpart, not an alternative API or permission model. Native device behavior,
Linux-rendered goldens, distribution and additional locales have independent verification gates;
local widget tests do not imply those gates passed.
