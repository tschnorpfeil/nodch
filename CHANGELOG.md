# Changelog

All notable changes to nodch are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added
- Drag files toward the notch and the island grows into a large drop target; it lights up and grows a little more
  under the files, and folds away when they go elsewhere. It never takes the keyboard from the app you drag from.
- At rest the notch keeps a small green dot beside the camera, so you can see nodch is running and connected without
  pressing ⌥ Space. Below a menu bar the resting island still stays out of the way.
- Settings › Open Nod in: Open Nod opens the Nod app for a Nod on this Mac and the browser for any other address,
  so it shows the Nod nodch talks to. Choose Nod app or Browser to always use one.
- When Nod finishes a turn that ran 5 seconds or more, the island says how long it took (m:ss).
- The prompt offers Start at login once, so nodch is back after a restart. It turns on only when you click Turn on.

### Changed
- One word for each thing: "Nod isn’t connected", "Drop files for Nod", "Open Nod", "Ask Nod".

### Fixed
- Save in Settings tries the saved connection and says whether it worked, instead of only "Saved".
- After the Mac wakes, or when the network comes back, nodch reconnects at once instead of after up to a minute.
  A file uploading at that moment still lands.
- A 403 no longer suggests localhost: it says the address must match Nod's NOD_PUBLIC_URL exactly.
- Open Nod and Open in Nod close the card, as ⌘↩ does. Without a connection the card says so instead of doing nothing.
- A click on an island that shows a failed turn opens the prompt, with the reason above the field, so you can try
  again.
- A send that fails while the prompt is hidden still says why when you open it again, until the next send.
- An approval that arrives while you type is one click away: "Show" in the prompt opens it, and its buttons wait
  out the usual moment before they take a click.
- VoiceOver says when a message or file wasn't sent, and names the shortcut that opens a waiting approval or question.
- The README's uninstall step names the real Keychain items, one per server.

## 0.2.0 — 2026-11-16

### Added
- Settings has a Prompt section: click the shortcut and press a new one, reset it or turn it off. It applies at once,
  and Settings says when macOS or another app already uses a shortcut instead of failing silently.
- The dictation language can be picked in Settings, as well as from the microphone's menu.
- ⇧⌘C, or a right-click on the answer, copies Nod's whole answer.
- When nodch gets its token from the environment (a LaunchAgent, a terminal), Settings offers **Save on this Mac**:
  one click keeps the address and token, so nodch also connects when it is opened from Finder or after a restart.

### Changed
- nodch uses about a third of the CPU while Nod works: the spinner turns without redrawing the island 60 times a
  second, and streamed answer tokens no longer wake the app.

### Fixed
- Without a token, nodch says "Nod asks for a token" instead of claiming one was rejected.
- While Nod isn't connected, the shortcut opens the card that says why, with Settings and Retry, instead of a prompt
  that cannot be sent; the microphone stays off.
- Return no longer sends a message without a file whose upload failed: it waits until you remove the red chip.
- Files dropped while a message is going out say why they were ignored instead of vanishing.
- The card says "Connecting to Nod…" while nodch connects, at launch and after Retry, and Retry keeps the last answer.
- Connection errors shown in Settings point at the fields above, not back to Settings.
- On first run, a Nod that refuses the host name opens Settings, like one that doesn't answer.

## 0.1.2 — 2026-11-14

### Fixed
- An answer that arrives while the island is closed no longer shows as one cut-off line that fades after a few
  seconds. The island says "Answer ready" until you open it, and the answer is there however late you do.
- ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z and ⇧⌘Z work in the prompt.
- Two mails with the same subject dropped from Mail both arrive; the second one failed with "no such file".
- A drop that brings nothing says so in the prompt instead of vanishing.

### Changed
- VoiceOver announces a ready answer, an approval, a question and a failed turn.

## 0.1.1 — 2026-11-14

### Fixed
- Return under a question from Nod that just appeared waits out the same short guard as a click, so keys typed for
  another app can't answer Nod.
- Mails and photos dropped from Mail or Photos are deleted from nodch's caches once uploaded, and at launch.

### Changed
- Hint text is easier to read (above WCAG's 4.5:1 contrast).
- When macOS denies the microphone, an Open Settings link takes you to the right privacy pane.
- The offline card has Retry, which connects to Nod again right away.
- README: an animated tour, corrected troubleshooting, and a social preview image.

## 0.1.0 — 2026-11-13

### Settings and keys
- Settings window for Nod's address and token (kept in the Keychain), Test connection, Start at login; opens by
  itself on first run. Right-click the island for Settings, Start at login and Quit.
- Every card works from the keyboard: ⌘Return opens the Nod app, ⌥Return approves or sends ticked choices, ⌥⌫
  declines, ⌘. stops. ⌥Space on the open prompt hides it and keeps your words.

### Island
- Shows Nod's current status in the MacBook notch, or at the top of the menu bar on displays without one.
- Appears on the display you are working on.
- Hands anything bigger to Nod's own window, and opens the installed Nod app when available.

### Quick prompt
- Opens with the global shortcut ⌥Space.
- Follow-up questions are focused and can be answered from the keyboard.

### Dictation
- Opening the quick prompt with ⌥Space starts listening; your words appear live in the field.
- Uses Apple's on-device speech model and follows your system languages; the language can be picked from the
  microphone's context menu.
- The microphone starts off the main thread, so the prompt opens at once.
- Speech is detected with on-device sound analysis. The first typed key turns the microphone off and keeps the text.

### Answers and questions
- Shows Nod's answers in full with their formatting, above the prompt for ten minutes, for follow-ups.
- Nod's questions show their choices as buttons; typing your own words answers them too.

### Approvals
- Shows what Nod asks to do, with the full action text, so you can approve or decline.

### Files
- Files dropped on the island are uploaded to Nod at once and attached to the prompt you send.
