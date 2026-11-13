# Changelog

All notable changes to nodch are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 0.1.0 — Unreleased

### Island
- Shows Nod's current status in the MacBook notch, or at the top of the menu bar on displays without one.
- Appears on the display you are working on.
- Hands anything bigger to Nod's own window, and opens the installed Nod app when available.

### Quick prompt
- Opens with the global shortcut ⌥Space.
- Follow-up questions are focused and can be answered from the keyboard.

### Dictation
- The quick prompt starts listening on open; your words appear live in the field.
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
- Files dropped on the island are sent to Nod with your prompt.
