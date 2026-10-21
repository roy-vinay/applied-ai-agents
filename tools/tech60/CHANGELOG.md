# Changelog


## Unreleased

- The dot is now a tiny Tech60 app icon, with a round orange badge when new stories arrive.
- Fixed: clicking the dot didn't restore the card or ticker. The dot now owns its whole click area.
- Keep card above other windows now also keeps the card over full-screen apps and on every Space, and is remembered after quitting.
- The dot is larger and always orange with a white ring, and the first time it appears where the card (or ticker) was.
- The ticker scrolls continuously, right to left, and pauses while the pointer is over it. Speed is Slow, Normal, or Fast in the ticker's menu; Reduce Motion shows one headline at a time instead.
- Fixed spinning-wheel stalls when collapsing, dragging, or hovering the ticker and dot: their headlines are now worked out once when stories change, not on every redraw.
- Ticker and dot: collapse the card into a one-line ticker (⌘⇧T) or a small dot (⌘⇧.); click to restore the card's previous size, position, and tab. The dot glows when new stories arrive and returns to whatever it came from.
- The ticker docks to the bottom edge at first, snaps to the top or bottom edge, or floats anywhere (⌥ skips snapping). Its position, and the dot's, are remembered per display and never restored off screen.
- The ticker and dot stay above other windows, including full-screen apps, and appear on every Space; both are options.
- Tech60 windows are excluded from screen sharing and recordings by default (Hide from screen sharing).

- Top has no filler: only stories with real signal (two or more outlets, a Techmeme pick, an official post, or 400+ Hacker News points). On quiet days it's shorter and says so.
- Encyclopedia, fan wiki, and similar reference pages are never treated as news.
- The on-device editor's prompt now defines news as recent and rates reference pages, history, fiction, and evergreen essays as not news.
- Summaries are cleaned of Markdown and stray headings.

- Better news: Techmeme anchors the feed; TechCrunch, MIT Technology Review, and Platformer added; GitHub Changelog and Apple Developer news off by default.
- Noise filter: deals, reviews, buying guides, how-tos, gaming, Hacker News posts under 150 points (Show/Ask HN under 400).
- Hotness re-weighted: coverage and Techmeme picks count most; Hacker News points are capped.
- On-device editor rates each headline 1 to 5; stories rated 2 or lower leave Top (still in Latest).
- Right-click a story for More like this or Less like this; reset in Settings, Topics.

- Summaries are ready sooner: the top ten stories on the card are summarized in the background (any source), resting the pointer on a story starts its summary, and the model is loaded at launch. An opened story shows the feed's text at once while its summary finishes.

- App icon (a small front page with the Tech60 ring) and a matching menu bar icon whose corner opens into the ring.

- New "Edition" design: serif masthead with date and edition, section tabs, lead story with picture, thumbnails, heat rings without numbers, "first reported" times, and a story page with summary and coverage. Follows macOS light and dark.
- Pictures come from the feed (media:content, enclosures, inline images) or the page's link preview.

- Hot view (default): stories ranked by coverage, Hacker News points and comments, and Techmeme picks; quiet stories hidden. Latest view keeps newest first.
- Hacker News points show on each row, and carry over when HN links to a story Tech60 already has.
- Show HN and Ask HN posts now keep the author's text for summaries.

- Same news from several sources is grouped into one row.
- Follow topics (built-in or your own words); matching stories go first and the rest are dimmed.
- Daily brief notification at a time you pick, with the top five stories since the last one.
- Refresh button on the card; tap any story for an on-demand checked summary.
- Redesigned card: serif headlines, source colors, translucent panel.

## 0.1.0

- First build: a floating news card and a menu-bar item.
- Sources: six official feeds (summarized) and four publisher sources including Hacker News (headline and link only). Add your own RSS or Atom feeds.
- New since you looked: dots on new stories and a count in the header and the menu bar.
- Summaries of up to 60 words from Apple's on-device model on macOS 26, each checked against the source before it's shown, with a **Why?** view of the evidence.
