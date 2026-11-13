# Security

## Report a vulnerability

Please report privately: open the repository's **Security** tab and choose **Report a vulnerability**. Do not open a
public issue for it. This is a one-person prototype, so there is no response-time promise.

## In scope

- The approval path: anything that approves, declines, retries or sends without an explicit user action.
- Handling of the Nod auth token or access key: leaks, logging, sending it to a host other than the configured one.
- The local HTTP and SSE connection to Nod.

Problems in Nod itself belong to [Nod](https://github.com/n8n-io/nod).

## What nodch stores and sends

Only what the code shows:

- **Credential.** `NOD_AUTH_TOKEN` is sent as a bearer token. If it is unset, nodch reads Nod's `access-key` file in
  `NOD_DATA_ROOT` (default `.local`) and sends it as a cookie. It is read per request and not written anywhere by nodch.
- **Network.** Requests go only to the `NOD_URL` origin (default `http://127.0.0.1:4310`) over an ephemeral URL session,
  without cookie storage. Redirects are not followed. The code adds no telemetry or other endpoints.
- **Speech.** Dictation uses Apple's on-device `SpeechAnalyzer`; no audio leaves the Mac through nodch. The microphone
  is used while the quick prompt is open.
- **On disk.** The chosen speech language is kept in user defaults. Dropped files that arrive as promises are copied to
  `~/Library/Caches/nodch/Drops/`.
- **Dropped files.** A file is uploaded to your Nod as soon as you drop it, before you press Return. Removing it from
  the prompt or pressing Esc keeps it out of the message, but does not delete the upload from Nod.
