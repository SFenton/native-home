# Live Activity problem card: the failure notice

> **What:** where a problem card shows the one-update failure notice after a button press fails. **Read when:** you touch `ProblemCardView`, the `notice` content key, or the problem card's mockup.

## Rules

1. `notice` takes the place of the card's content line while it stands: the job card's value, the problem card's instruction.
2. The device line, the problem line and the buttons stay where they are.
3. The problem card's notice is subheadline, semibold, white (`ActivityStyle.primaryText`), never `ActivityStyle.noticeText`, which is the warning severity's problem-line colour.
4. It takes two lines at ordinary sizes and has no limit at accessibility sizes.
5. It is its own static text, `liveactivity.notice`, read after the problem phrase (`liveactivity.problem`) and before the buttons. The phrase still speaks the instruction.
6. The words come with the content; the app writes only "Couldn't reach Home".
7. The Lock Screen, banner and StandBy draw it, one fluid layout on iPhone, iPhone Duo and iPad. The Dynamic Island and the small family do not.
8. The card stays within the 160 pt Lock Screen limit at the default text size.

Source: HIG, Live Activities (important information at a glance, readable text, height that fits the information, 84 to 160 pt).

Mockups: [live-activity-problem-card](mockups/components/live-activity/live-activity-problem-card/live-activity-problem-card.html) (state `notice`); the options as proposed, [live-activity-problem-notice](mockups/proposals/live-activity-problem-notice/live-activity-problem-notice.html).
