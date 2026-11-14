# Changelog

All notable changes to nodch are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
