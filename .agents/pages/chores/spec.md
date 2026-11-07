# Chores, Groceries and To-Do: spec

> **What:** platform-neutral behavior of the Chores tab, its five sub-pages and the admin To-Do. **Read when:** changing any todo page or sheet.

Web source `ha-sfenton-react-dash@9ac2a46`: `src/pages/DashboardViewPage.tsx` (`TodoPageContent`, `TodoSection`, `todoListVisible`, `ChoresIntro`, `ChoreQuickLink`), `src/constants/portedDashboard.ts` (`TODO_PAGES`, `CHORE_QUICK_LINKS`), `choreQuickLinkCounts.ts`, `householdResidents.ts`, `dashboardAccess.ts`, `src/components/hass/TodoListPanel.tsx`, `useDonetickTaskForm.ts`, `donetickTaskForm.ts`, `DonetickTaskFormPage.tsx`, `CreateGroceryItemSheet.tsx`, `CreateTodoItemSheet.tsx`, `EditTodoItemSheet.tsx`, `src/hooks/useTodoOptimisticStatuses.ts`, `src/components/shell/DashboardFloatingAction.tsx`.

## Pages (config: `HassCore/Config/ChoresConfig.swift`)

| Route | Title | Lists | Add | Rows edit |
|---|---|---|---|---|
| `chores` (tab) | Chores | the viewer's time-of-day lists (`*_with_unassigned`, only lists whose users include the viewer and whose entity count > 0) | Add Task (Anyone) | Choreapp form |
| `groceries` | Groceries | `todo.demo_todo_2` | Add Groceries | no |
| `<resident>-chores` (one per resident; the route raw values are code-bound), `unassigned-chores`, `home-improvement-chores` | per config | Past Due, Due Today, Upcoming, No Due Date | Add Task (assignee 1, 2, Anyone, 3) | Choreapp form |
| `to-do` (Settings; hidden from non-admin residents) | To-Do | `todo.demo_todo_1`, no header; checking off runs `script.demo_script_1` | Add Task (admin, images) | rename |

- The Chores tab starts with Quick Links (Groceries, each resident's chores, Unassigned, Home Tasks) whose subtitles summarize the page's list entity counts ("2 overdue tasks · 1 task listed", "3 items"); the viewer's own link reads "Your Chores", the other resident's "{Name}'s Chores".
- A list's entity state is its open-item count: 0 hides the list before any fetch. Loaded lists with no open items hide too. When every visible list is settled and hidden, the empty state shows ("No Chores Due" / "…Nice job!", "You have no chores due. Nice job!" on the viewer's own page, "Enjoy vacation!" on chore pages while `input_boolean.demo_mode_3` is on).
- Items load over the websocket (`todo/item/list`), sort by due (undated last), and reload when the list entity changes or a sheet saves. Completed items are hidden.
- Checking off is optimistic: the row disappears at once and returns if the call fails or nothing confirms within 15 s.
- **Resident pages include unassigned tasks** (found and decided 2026-10-16, owner: a resident's page did not show the unassigned maintenance chores). Choreapp exposes two views per resident: `todo.demo_todo_<n>` (tasks assigned to the resident) and its `_with_unassigned` twin (those plus tasks with no assignee). Maintenance chores with `assigned_to: null` and `assign_strategy: no_assignee` appear in the `_with_unassigned` views and in none of the assigned-only lists. The Chores tab and the Profile summary already read the `_with_unassigned` views and showed them; the resident Chores pages (and the quick-link counts) read the assigned-only lists, as the web does (`portedDashboard.ts:468`), and did not. Departure from the web: the resident chores pages now read the `_with_unassigned` lists too, so the Chores tab, the resident's page, the Profile summary and the Chores tab badge (the Past Due list's open count, `OverdueChoresBadge`) all agree. Unassigned Tasks still lists the unassigned chores on their own.
- Row: checkbox, title (battery maintenance tasks append "· 18%"), relative due ("Due in 3 days", "2 hours overdue"; overdue under a day vs longer are distinct tones), optional "Edit {title}" button. Choreapp rows are editable only when the uid starts with a task id (`42--…`).

## Native additions (owner, 2026-10-16)

- **Swipe actions** (not on the web): swiping a row from the leading edge completes it (full swipe performs it); from the trailing edge it offers Delete (outermost, destructive, asks "Delete {title}?" first) and Edit. Delete exists on Choreapp pages and Groceries (`todo.remove_item`), not the admin To-Do (GitHub-synced); Edit only where the row has an editor. The same actions are in the row's context menu and VoiceOver actions (`TodoRowActions`). See [ios.md](ios.md).
- **Completion animates**: a checked-off row leaves the list with the list's row animation and comes back, with the error, if the call fails or nothing confirms in 15 s.
- **Quick-link tiles** are filled in colours used nowhere else (see [ios.md](ios.md)).
- **Add Task**: Task Name and Description are separate sections, each with a header and a footer saying what goes in it; the sheet has no "Choreapp" subtitle.

## Sheets

- **Create / Edit Task** (Choreapp): name, assignee (Anyone, You/<resident name>, You/<other resident name>, Home Improvement), Hide While On Vacation, description, due date and time, priority (None, P1–P4), recurrence (Custom Interval adds Repeat Every 1–365 + unit; Specific Days of Week adds weekdays; editing adds Adaptive). Create → `donetick.create_task_form`; edit loads `donetick.get_task` (`return_response`, `config_entry_id` = list entity, `task_id`), saves `donetick.update_task_form` (`assignees` only when changed), deletes with `todo.remove_item` after "Delete {name}?".
- **Add Grocery Item**: `todo.add_item` on `todo.demo_todo_2`.
- **Add Task (admin)**: public-repo disclosure; no images → `todo.add_item`; up to four PNG/JPEG/WebP images ≤ 10 MB → multipart POST `/api/sfenton_admin_todo` with the bearer token.
- **Edit Task (admin)**: rename with `todo.update_item` `rename`; Reset restores the original.
