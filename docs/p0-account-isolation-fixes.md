# P0 Account Isolation Fixes

Scope: account isolation and user-state data closure.

- Added account-scope checks before async favorite, follow, and unread-notification backfills write into app state.
- Scoped compose and publish drafts as `userId::key`; guest drafts use `guest::key`.
- Scoped the today-topic dismissed flag as `userId::key`.
- Connected project likes to backend `creative` reactions with local rollback on sync failure.
- Updated LocalStore tests to seed scoped keys.

## Code Locations

- `frontend/lib/providers/app_state_provider.dart`: added scope guards for favorite, follow, and unread-notification async backfills; added backend project-like sync and rollback.
- `frontend/lib/data/api/interactions_api.dart`: added `setProjectReaction(...)` for project reaction persistence.
- `frontend/lib/features/publish/compose_screen.dart`: scoped compose draft storage key with `currentUser.id` or `guest`.
- `frontend/lib/features/publish/publish_screen.dart`: scoped publish draft storage key with `currentUser.id` or `guest`.
- `frontend/lib/features/discover/discover_screen.dart`: scoped today's topic dismiss key with `currentUser.id` or `guest`.
- `frontend/test/core/storage/local_store_test.dart`: updated draft test seeds to use scoped guest keys.

## My Page Closure Fixes

- `backend/app/api/v1/me.py`: `/me/favorites` and `/me/try` now attach each user's link action time as `linked_at`.
- `backend/app/schemas/project.py`: `ProjectCard` now allows optional `linked_at` for personal linked lists.
- `backend/app/services/projects.py`: `list_linked_projects(...)` keeps the link row with the project so callers can use the real action time.
- `frontend/lib/data/api/interactions_api.dart`: `listTryItems()` returns `TryProjectItem(project, triedAtMs)` instead of dropping the user's action time.
- `frontend/lib/providers/remote_project_provider.dart`: `remoteTryItemsProvider` now exposes `List<TryProjectItem>`.
- `frontend/lib/features/library/library_screen.dart`: material tab separates visit actions and saved-material actions; visit actions sort by `/me/try.linked_at`, while local saved materials sort by `SavedTakeaway.savedAtMs`; favorites keep backend action-time order.
- `frontend/lib/features/detail/detail_screen.dart`: local saved material IDs use `material-{projectId}` so they do not collide with visit-action IDs.
- `frontend/lib/features/profile/profile_screen.dart`: other users' Favorites tab no longer shows authored projects as fake saved items.
- `frontend/lib/features/me/me_screen.dart`, `frontend/lib/features/publish/compose_screen.dart`, and `frontend/lib/providers/app_state_provider.dart`: recent viewed wording is scoped to recent viewed projects.

## Publish Closure Fixes

- `frontend/lib/features/publish/compose_screen.dart`: post publishing now has a publishing lock/state, autosaves text drafts with debounce, blocks silent media loss, keeps content on failure, and routes successful posts to `/discover?tab=following`.
- `frontend/lib/features/publish/publish_screen.dart`: project publishing now has a publishing lock/state, autosaves drafts with debounce, asks save/discard/continue on exit, blocks silent media loss, keeps content on failure, and routes successful projects to `/kankan?tab=latest`.
- `frontend/lib/features/discover/discover_screen.dart`: accepts an initial tab index so publish success can open the Following feed.
- `frontend/lib/features/kankan/kankan_screen.dart`: accepts an initial tab index and changes the former Hot tab to Latest.
- `frontend/lib/router/app_router.dart`: maps `/discover?tab=following` and `/kankan?tab=latest` to the intended initial tabs.

## Comment Interaction Order Fixes

- `backend/app/schemas/comment.py`: added `CommentOut.is_deleted` so clients can distinguish a soft-deleted comment from normal content.
- `backend/app/services/comments.py`: comment lists now include soft-deleted top-level comments and replies, and `_to_out` returns the placeholder text `content deleted` (`内容已删除` in code) with no author/likes for deleted comments.
- `frontend/lib/domain/models/comment.dart` and `frontend/lib/domain/models/comment.freezed.dart`: added `Comment.isDeleted` for deleted-comment rendering and local mock updates.
- `frontend/lib/data/api/comments_api.dart`: maps backend `is_deleted` to `Comment.isDeleted`, forces deleted content to `content deleted` (`内容已删除` in code), and zeroes deleted-comment likes.
- `frontend/lib/features/shared/comment_thread.dart`: deleted comments no longer open profile, like, reply, or long-press actions; own-comment detection also accepts local mock `me`; self-report is not offered for own comments; delete refreshes remote comments instead of removing the row, and local mock delete now becomes a placeholder.
- `frontend/lib/features/post_detail/post_detail_screen.dart`: after posting/deleting comments, dynamic detail and feed providers are invalidated so visible comment counts refresh immediately.

## List Loading Empty Error State Fixes

- `frontend/lib/features/shared/list_state_views.dart`: added reusable list loading states with card skeletons and a slow-network hint.
- `frontend/lib/features/kankan/kankan_screen.dart`: project lists and featured projects now use project skeleton loading instead of a bare spinner.
- `frontend/lib/features/discover/discover_screen.dart`: recommended and following dynamic feeds now use post skeleton loading; following feed also surfaces project-stream errors with retry instead of swallowing them.
- `frontend/lib/features/profile/profile_screen.dart`: profile posts/projects/favorites now use skeleton loading and the favorites tab surfaces backend favorite errors with retry.
- `frontend/lib/features/library/library_screen.dart`: favorites and material tabs now expose remote loading/error/retry states instead of converting failed or pending calls into empty lists.
- `frontend/lib/features/me/me_screen.dart`: "My published" now shows loading/error/retry states for remote projects/posts instead of falling through to empty content.

### Current Code Line References

- `frontend/lib/features/shared/list_state_views.dart`: `ListLoadingState` starts at line 7; `ProjectListSkeleton` starts at line 62; `PostListSkeleton` starts at line 91; `CompactListSkeleton` starts at line 113.
- `frontend/lib/features/kankan/kankan_screen.dart`: project list loading uses `ProjectListSkeleton` around line 291; featured loading uses `ProjectListSkeleton` around line 383.
- `frontend/lib/features/discover/discover_screen.dart`: recommended feed loading uses `PostListSkeleton` around line 234; following feed loading/error handling is around lines 547-557.
- `frontend/lib/features/profile/profile_screen.dart`: profile posts loading is around line 457; profile projects loading is around line 503; profile favorites remote error handling is around line 573.
- `frontend/lib/features/library/library_screen.dart`: favorites tab state wiring starts around line 98; `_SavedTab` loading/error handling starts around line 198; material tab remote loading/error handling is around line 299.
- `frontend/lib/features/me/me_screen.dart`: "My published" remote loading/error handling starts around line 498.
- `backend/app/schemas/comment.py`: `CommentOut.is_deleted` is around line 46; `backend/app/services/comments.py`: deleted comment placeholder mapping starts around line 64; `frontend/lib/features/shared/comment_thread.dart`: deleted-comment action guard starts around line 307 and delete-to-placeholder handling starts around line 424.

## Deleted And Taken-Down Content Boundary Fixes

- `backend/app/schemas/project.py`: `ProjectCard.status` is returned to the frontend, so linked lists can distinguish `published`, `taken_down`, and `deleted`.
- `backend/app/api/v1/me.py`: `/me/favorites` and `/me/try` use `list_linked_projects(...)`, preserving linked project rows and their status for the user's own saved lists.
- `backend/app/services/projects.py`: `card_from_project(...)` copies `p.status` into `ProjectCard`; `list_linked_projects(...)` is the linked-list source for favorites and try items.
- `frontend/lib/features/shared/project_card.dart`: project cards now render `deleted` as `该作品已被作者删除` and `taken_down` as `内容已下架`; both keep the saved record visible without opening details.
- `frontend/lib/features/library/library_screen.dart`: remote try/material rows from unavailable projects keep the saved row and mark the label as `去看看 · 来源不可访问`; tapping shows `来源作品已不可访问` instead of navigating to a dead detail page.
- `frontend/lib/features/detail/detail_screen.dart`: direct detail loads that return null now show `内容不可访问`.

### Deleted Boundary Line References

- `frontend/lib/features/shared/project_card.dart`: unavailable status guard is around lines 58-59; `_UnavailableProjectCard` starts around line 298; deleted/taken-down copy is around lines 309-310.
- `frontend/lib/features/library/library_screen.dart`: unavailable material label is around line 268; tile unavailable detection is around line 372.
- `frontend/lib/features/detail/detail_screen.dart`: null detail fallback copy is around line 116.
- `backend/app/api/v1/me.py`: favorites endpoint starts around line 161 and try endpoint starts around line 177.
- `backend/app/services/projects.py`: `list_linked_projects(...)` starts around line 159; `card_from_project(...)` copies `status` around line 48.

## Feedback Entry And Context Fixes

- Kept the existing Settings feedback entry as the main manual entry; no duplicate top-level entry was added.
- `frontend/lib/features/shared/remote_error.dart`: unified remote loading failures now show a `Feedback Bug` action; submitting from this state carries the current route and normalized error code into feedback.
- `frontend/lib/features/publish/compose_screen.dart`: dynamic publish failure snackbars now include a feedback action that opens the feedback sheet with `/compose` and the publish error code.
- `frontend/lib/features/publish/publish_screen.dart`: project publish failure snackbars now include a feedback action that opens the feedback sheet with `/publish` and the publish error code.
- `frontend/lib/features/feedback/feedback_sheet.dart` and `frontend/lib/data/api/feedback_api.dart`: feedback submission now accepts and sends `source_page` and `error_code`, alongside the existing app version/platform/device metadata.
- `backend/app/models/feedback.py`, `backend/app/schemas/feedback.py`, and `backend/app/api/v1/feedback.py`: feedback records now store `source_page` and `error_code`.
- `backend/app/api/v1/admin.py`: admin feedback list returns `source_page` and `error_code`; existing `status=new/handled` filtering remains the backend handling queue.
- `backend/alembic/versions/0022_feedback_context.py`: adds nullable `feedbacks.source_page` and `feedbacks.error_code` columns.

### Feedback Line References

- `frontend/lib/features/shared/remote_error.dart`: feedback sheet opening is around line 84; route/error context is around lines 86-87; visible feedback action is around line 181.
- `frontend/lib/features/publish/compose_screen.dart`: snackbar feedback action is around lines 345-350.
- `frontend/lib/features/publish/publish_screen.dart`: snackbar feedback action is around lines 1097-1102.
- `frontend/lib/features/feedback/feedback_sheet.dart`: `showFeedbackSheet(...)` context parameters start around line 18; submit passes context around lines 86-87.
- `frontend/lib/data/api/feedback_api.dart`: request payload writes `source_page` and `error_code` around lines 35-38.
- `backend/app/models/feedback.py`: new columns are around lines 33-34.
- `backend/app/schemas/feedback.py`: create/admin fields are around lines 27-28 and 44-45.
- `backend/app/api/v1/feedback.py`: submit stores context around lines 34-35.
- `backend/app/api/v1/admin.py`: admin feedback status filter starts around line 663; context fields are returned around line 692.
- `backend/alembic/versions/0022_feedback_context.py`: migration adds the two columns around lines 16-17.

## First-Run Onboarding Fixes

- `frontend/lib/app.dart`: the app root checks the local first-run flag after the first frame and opens a lightweight onboarding sheet only once, so the trigger is not tied to revisiting the Kankan tab.
- `frontend/lib/features/kankan/kankan_onboarding_sheet.dart`: added a three-card onboarding sheet explaining that Kankan is for discovering AI-made small products, collecting projects/materials and following domains, publishing work, and reporting bugs.
- `frontend/lib/core/prefs.dart`: added `PrefsKeys.kvKankanOnboardingSeen` so the onboarding prompt is not repeated after the user has seen it.
- The onboarding sheet includes a Bug feedback icon that opens the existing feedback form with `sourcePage=/kankan/onboarding`.

### Onboarding Line References

- `frontend/lib/app.dart`: first-frame trigger is around line 58; one-time flag check and sheet opening are around lines 98-113.
- `frontend/lib/features/kankan/kankan_onboarding_sheet.dart`: sheet entry starts around line 8; the three cards start around lines 55, 64, and 73; feedback entry is around lines 101-108.
- `frontend/lib/core/prefs.dart`: onboarding seen key is around line 110.

## Current Turn: Regression Correction And Baseline Record

This section records the changes made in the current turn and the version evidence used. The working tree was already dirty and contained many uncommitted changes; the installed APK was built from the current `F:\kankan` workspace on branch `feat/media-transfer`, commit `80216e8`, with package `com.kankan.kankan_flutter` version `0.2.1`. That package version is not proof that the source matches Claude's latest branch. Claude's separate record is `CHANGES_CLAUDE.md`; its relevant historical commits include `2713e48` (real "My published" data) and `a333339` (interest settings/backend contract).

- `frontend/lib/features/library/library_screen.dart` around lines 139, 175-176, 212, 249, 296, and 538: repaired user-visible mojibake back to `收藏`, `素材`, `全部`, and readable loading/error labels. The underlying favorites/material separation and action-time sorting were preserved.
- `frontend/lib/features/shared/comment_thread.dart` around lines 206, 214, 396, 562, and 576: changed comment UI labels from the legacy `心得` wording to `评论`, including the header, empty state, delete confirmation, edit placeholder, and new-comment placeholder.
- `frontend/lib/features/detail/detail_screen.dart` around line 547: changed the fixed project-detail comment entry from `心得 N` to `评论 N`. The project detail currently has one `CommentThread` around lines 164-181; the fixed bottom entry around lines 527-549 only scrolls to it and does not create a second comment list.
- `frontend/lib/features/shared/project_card.dart` around line 277: repaired the compact project-card footer from mojibake to the readable `赞 · 评论` format.
- `frontend/lib/features/comments/comments_screen.dart` already uses `评论` for its title and empty state; no duplicate comment implementation was added in this turn.
- `frontend/lib/features/me/me_screen.dart`: wrapped the My page in its own `Scaffold` with a visible error fallback around lines 58-125, and removed the stale `PageStorageKey` values from the guest/logged-in lists. If a synchronous provider/widget error occurs, the page now shows `我的`, `页面加载失败`, the error text, and a retry action instead of a blank body. The logged-in branch starts around line 205 and the guest branch around line 189 after this wrapper.
- Verification: `flutter analyze --no-fatal-infos` passed for the four affected frontend files; `flutter build apk --debug --dart-define=USE_REMOTE=true --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1` succeeded; the backend process was not restarted or modified by the install/verification commands.

### Version And Ownership Notes

- The current workspace contains both Claude-recorded work and later uncommitted work. Do not treat `0.2.1`, `app-debug.apk`, or branch `feat/media-transfer` as "Claude latest" without a commit/patch comparison.
- The legacy word `心得` remains in domain comments and content-description documentation where it describes a project's narrative text, but it has been removed from comment controls and comment counts. Any future change that renames content concepts must keep project narrative, posts, and comments separate.
- The known unresolved item from this verification is the physical-device rendering of the My page. It requires a foreground/unlocked device check or a reproducible Flutter frame/log; no backend restart is needed.
