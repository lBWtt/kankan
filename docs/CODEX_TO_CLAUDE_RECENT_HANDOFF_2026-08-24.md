# Codex -> Claude Recent Handoff

Date: 2026-08-24
Workspace: `F:\kankan`
Production host: `ubuntu@118.89.112.187`

## What Codex Recently Did

This note summarizes the recent Codex-side work so Claude can pick up without guessing. It is a handoff note, not a new product strategy.

## Android Beta Readiness

- Prepared the Android app for controlled beta distribution under the current package `com.kankan.kankan_flutter`.
- Current release artifact published at `https://lovluu.com/downloads/kankan-android.apk`.
- Built version: `0.2.3+4`.
- APK SHA-256: `35525BEEB7E2B5AC38D6DFD8DD326C2FBB9BE87DD207EFCF2CF0B0D73F2A4F69`.
- Release signing certificate SHA-256 stayed unchanged:
  `23:10:D3:2B:28:4A:88:C4:F2:3B:45:4F:69:EE:DA:33:64:F7:00:C2:18:AA:DF:0F:A4:84:19:1C:69:E1:8B:2E`.
- Added a release-build guard so release APK builds fail unless `USE_REMOTE=true` and `API_BASE_URL=https://lovluu.com/api/v1`.

Primary docs:

- `docs/THOUSAND_BETA_READINESS_2026-08-16.md`
- `docs/ANDROID_RELEASE_SIGNING.md`
- `docs/CODEX_OPERATION_LOG.md`

## App/Frontend Changes

- Added first-run privacy/analytics consent before normal app routing.
- Moved mobile token persistence to secure storage while keeping web SharedPreferences behavior for browser login.
- Added account deletion UI and optional analytics withdrawal controls in Settings.
- Fixed the onboarding/root navigator issue found during emulator validation.
- Updated app version display to read from package metadata.
- Updated launcher/web icons to the temporary green `K` icon supplied by the user.
- Kept the Android app and existing project feed behavior intact during beta readiness work.

Important changed areas:

- `frontend/lib/app.dart`
- `frontend/lib/core/prefs.dart`
- `frontend/lib/data/token_store.dart`
- `frontend/lib/providers/analytics_provider.dart`
- `frontend/lib/providers/auth_provider.dart`
- `frontend/lib/features/legal/privacy_consent_screen.dart`
- `frontend/lib/features/settings/settings_screen.dart`
- `frontend/android/app/build.gradle.kts`
- `frontend/pubspec.yaml`

## Backend/Production Changes

- Added `DELETE /me` account deletion support with Redis refresh-token revocation.
- Added production database and media backup scripts plus systemd timers.
- Added Docker log rotation settings for backend, nginx, postgres, and redis containers.
- Deployed backend changes to the Tencent Cloud production host.
- Verified production health and a low-risk public read load test.

Important changed areas:

- `backend/app/api/v1/me.py`
- `backend/app/core/security.py`
- `backend/deploy/backup_production.sh`
- `backend/deploy/systemd/`
- `backend/docker-compose.prod.yml`

## Validation Already Run

- Flutter tests: `300/300` passed.
- Backend unittest discovery: `37/37` passed.
- `flutter analyze --no-fatal-infos`: no errors; only pre-existing non-null assertion warnings in `frontend/lib/features/shared/project_card.dart`.
- Release APK built with remote production API defines.
- APK signature verified.
- Production health checked after deployment.
- Production account deletion was tested with a disposable account and cleaned up.

## Things Codex Did Not Do

- Did not change the content constitution strategy during beta readiness.
- Did not modify the DeepSeek/scoring/collector pipeline in the beta-readiness pass.
- Did not change creator attribution or persona ownership rules.
- Did not commit the dirty worktree. The workspace already had many user/Claude changes, so Codex left changes uncommitted to avoid mixing unrelated work.

## Known Product/Admin Caveat

Approved candidates become published projects. The main candidate review list in the Flutter admin surface defaults to `pending_review`, so already-published content may not appear there. The backend has project-management APIs:

- `GET /api/v1/admin/projects`
- `PATCH /api/v1/admin/projects/{project_id}`

For example, the app card titled `300个中国城市，帮你选出最适合旅居养老的那一个` is:

- Project ID: `426931ff-555f-42dc-811d-685a7ceec928`
- Candidate ID: `fad1359c-49f8-4d24-811e-8f7bc8a926a4`
- Project status: `published`
- Candidate status: `approved`
- Current try URL: `https://yiju.city`
- Source URL: `https://web.okjike.com/originalPost/6878d4a04e1325bfbc617373`

If the user wants to edit links after publishing, prefer exposing/fixing the published-project edit flow instead of searching only the candidate queue.

Follow-up on 2026-08-24: Codex added a title search box to `backend/admin_web/index.html` and deployed that static page to production. In `https://lovluu.com/admin-web/`, choose status `已通过`, then search by title text such as `旅居` or `城市` to find the approved candidate and use `保存修改（改线上项目）` to update the published project's `try_url`. A later fix moved the title search box before the platform filter because the original order was misleading, and added automatic loading when the left queue scrolls near the bottom.

## Production Safety Reminder

Use only the Tencent Cloud production host:

- `ubuntu@118.89.112.187`
- Key: `~/.ssh/kankan_tc`

Never connect to `47.109.198.37`; that was the old stopped Aliyun host and may now belong to someone else.
