# Note iOS SDK

[中文](README.zh-CN.md)

Upload audio/video to Note and follow processing from Swift or Objective-C. Requires iOS 16 or later.
An API key can query recordings uploaded with that same key. View transcripts, summaries and playback in Note.
No third-party runtime dependencies.

## Install

In Xcode, choose **File → Add Package Dependencies** and enter
`https://github.com/beclab/note-ios-sdk`. Select a published version and add the `NoteSDK` product
to your app target. Swift Package Manager downloads the binary and handles linking and embedding.
Swift and Objective-C use the same package.

Check `release.json` in that version's [release](https://github.com/beclab/note-ios-sdk/releases)
for the compiler used to build the binary. Use that Xcode version or a compatible newer version.

<details>
<summary>Offline installation</summary>

If the version you need is not on SwiftPM, extract `olares-note-ios-sdk-0.2.4-spm.zip`.
In Xcode, choose **Add Package Dependencies → Add Local**, select the directory containing
`Package.swift` and add the `NoteSDK` product. You can also add `NoteSDK.xcframework` directly
and select **Embed & Sign**. Keep the complete XCFramework and add the SDK only once.

</details>

Your app needs read access to the file. For a document-picker URL, retain its security-scoped
access during upload; copy the file to your app container or save a bookmark for recovery after restart.

## Upload and query

Create an API key in **Note → Settings → API Key**. It includes the service address.
Your app supplies `apiKey` and `fileURL` below. Generate an `idempotencyKey` once per new upload
and save it with the file reference before uploading. Reuse the saved value when resuming.

### Swift

Call from an asynchronous context:

```swift
import Foundation
import NoteSDK

let client = try NoteClient(apiKey: apiKey)
let idempotencyKey = UUID().uuidString
// Save idempotencyKey with the file reference before uploading.
let recording = try await client.upload(
    fileURL: fileURL,
    options: .init(title: "Weekly meeting"),
    idempotencyKey: idempotencyKey
) { sent, total in
    // Confirmed bytes / total bytes. Dispatch UI changes to the main actor.
}
// Save recording.recordingID for later queries.
let result = try await client.waitForCompletion(recordingID: recording.recordingID) { status in
    // Show status.processing.currentStage; dispatch UI changes to the main actor.
}
```

### Objective-C

Initialize and call `NTNoteClient` on the main thread. Callbacks arrive on the main thread:

```objc
#import <Foundation/Foundation.h>
#import <NoteSDK/NoteSDK-Swift.h>

NSError *error = nil;
NTNoteClient *client = [[NTNoteClient alloc] initWithAPIKey:apiKey error:&error];
if (!client) { /* Handle the invalid key or address. */ return; }
NSString *idempotencyKey = NSUUID.UUID.UUIDString;
// Save idempotencyKey with the file reference before uploading.
NTRecordingOptions *options = [NTRecordingOptions new];
options.title = @"Weekly meeting";
NTRequest *call = [client uploadFileAtURL:fileURL fileName:nil options:options
    idempotencyKey:idempotencyKey
    progress:^(int64_t sent, int64_t total) { /* Update upload progress. */ }
    completion:^(NTRecordingStatus *recording, NSError *error) {
        if (error) { /* Handle request failure. */ return; }
        // Save recording.recordingID; use it to query processing below.
    }];
```

Upload success means Note has accepted the file; processing may still be running.
Save the returned recording ID and query it. Processing failures are returned as statuses,
including to Objective-C completions without an error; check the processing state.

## Methods

Swift network methods are `async throws` and return `RecordingStatus`. Objective-C methods
return a cancelable `NTRequest` and deliver `NTRecordingStatus` or `NSError` to their completion.

| Swift method | Parameters and result |
| --- | --- |
| `NoteClient(apiKey:attempts:)` | `apiKey`; maximum attempts per request defaults to 3, clamped to 1–5. Returns a client; the first request verifies authorization |
| `upload(fileURL:options:idempotencyKey:fileName:progress:)` | Uploads a local file in chunks and returns upload status. Only `fileURL` is required. The `data:fileName:` variant accepts `Data` and requires a file name with an extension |
| `uploadRecording(fileURL:options:idempotencyKey:fileName:)` | Same file/data inputs as `upload`. Sends one multipart request, without chunk progress or resumable chunks |
| `createUpload(fileName:totalBytes:options:idempotencyKey:)` | File name, size in bytes (`Int64`), optional recording options and idempotency key. Creates or recovers a session |
| `uploadChunk(recordingID:offset:data:)` | Recording ID, absolute byte offset (`Int64`) and chunk `Data`. Returns updated status |
| `getUpload(recordingID:)` | Returns upload state, confirmed offset and chunk size |
| `getStatus(recordingID:)` | Returns upload and processing state |
| `waitForCompletion(recordingID:interval:timeout:onStatus:)` | Polls and returns a terminal status, including failure |

Old keys without an address need `NoteConfiguration(apiKey:endpoint:)`, then
`NoteClient(configuration:)`. Endpoints must be HTTPS origins, without a path, query or fragment.
For manual chunks, use the server's `upload.offset` and `upload.chunkSize`; the last chunk may be smaller.

Objective-C has the same operations: `uploadFileAtURL:` / `uploadData:`,
`uploadRecordingFileAtURL:` / `uploadRecordingData:`, `createUploadWithFileName:`,
`uploadChunkWithRecordingID:`, `getUploadWithRecordingID:`, `getStatusWithRecordingID:`
and `waitForCompletionWithRecordingID:`. See [Objective-C integration](OBJECTIVE_C.md) for full selectors.

Use the `recordingID` your app saved from the upload response:

```swift
let status = try await client.getStatus(recordingID: recordingID)
let result = try await client.waitForCompletion(
    recordingID: recordingID, timeout: .seconds(60)
)
```

```objc
NTRequest *call = [client waitForCompletionWithRecordingID:recordingID interval:5 timeout:60
    statusHandler:^(NTRecordingStatus *status) { /* Update processing status. */ }
    completion:^(NTRecordingStatus *result, NSError *error) { /* Check error and result. */ }];
```

## Options and return values

`RecordingOptions` / `NTRecordingOptions` accept the optional recording settings below.
Omitted settings use Note defaults. Pass the idempotency key, file name and progress callback
as separate upload arguments.

| Field | Meaning |
| --- | --- |
| `title` | Recording title |
| `language` / `targetLanguage` | Spoken language / output language for translations and summaries. Omit `language` for detection |
| `speakerHint` | Expected speakers, 0–50; 0 means unknown |
| `translateEnabled` / `summarizeEnabled` | Enable translation / summaries |
| `summaryTemplateID` | Summary template ID |
| `sourceClient` / `sourceDevice` | Source app name/version / device label |

Objective-C uses `NSNumber` for nullable booleans and speaker count: `nil` leaves the setting
unspecified, while `@NO` and `@0` send explicit values. If supplied, an idempotency key must
be nonblank and at most 200 UTF-8 bytes.

`waitForCompletion` defaults to `interval: .seconds(5)` and `timeout: nil` (unlimited).
Swift uses nonnegative `Duration` values. Objective-C uses seconds in the range 0 to 365 days;
the overload without `timeout:` waits indefinitely. The timeout is checked between requests
and does not interrupt one in flight. Cancel the operation for a hard limit.
A zero timeout still permits the first query. `onStatus` / `statusHandler` receives each queried status.

Swift's `RecordingStatus` contains:

| Field | Meaning |
| --- | --- |
| `recordingID`, `title`, `statusURL` | Recording ID, title and status address |
| `upload` | `state`, `offset`, `chunkSize`, `totalBytes`, optional `error` |
| `processing` | `status`, optional `currentStage`, `outcome`, `errorCode`, `error`, `waiting` |

`recording.isTerminal` checks for a terminal outcome. Read `upload.error` when upload state
is `failed`. Processing ends at `completed`, `failed` or `canceled`; `outcome = no_speech` means
no speech was detected.

`processing.waiting` describes a model wait. Its `reason` is `model_unavailable`, `model_warming`,
`model_busy` or `model_stalled`; use a generic message for unknown values. It also carries
`capability`, RFC 3339 timestamps `since` / `nextProbeAt`, and optional `message`.
Keep querying: model recovery can continue processing without another upload.

Objective-C flattens these fields into `NTRecordingStatus`: `uploadState`, `uploadedBytes`,
`chunkSize`, `totalBytes`, `uploadError`, `processingState`, `currentStage`, `outcome`,
`processingErrorCode`, `processingError`, `waiting` and `isTerminal`.

## Recovery, cancellation and errors

- Resume with the same file, API key and saved idempotency key. Keep the file unchanged and readable.
  After upload returns, save `recordingID` and query directly.
- Your app owns upload records, key storage and task queues. The SDK does not save them or schedule work after restart.
  It uses foreground `URLSession` requests, without background execution time. Resume explicitly if iOS suspends the app.
- Cancel the calling `Task`, or use Objective-C's `[call cancel]`. This stops local work;
  it does not delete recordings or stop processing in Note.
- Request failures throw `NoteError`. Client creation can also fail on an invalid key or address.
  Handle `code`; use `status` (HTTP status, or 0 locally), `requestID` and `isRetryable` for diagnostics
  and retry decisions. Never log API keys. Objective-C uses `NSError`; business fields are in `userInfo`.
- Each request has at most 3 attempts by default, with backoff starting at 500 ms.
  POST requests retry only with an idempotency key. Objective-C cancellation reports
  `NSURLErrorDomain / NSURLErrorCancelled`.

## Demo

The SwiftUI and Objective-C demos in `olares-note-ios-demo-0.2.4-source.zip`
have file selection, local history separated by connection and manual recovery after restart.
Their offline mode simulates upload and processing without a Note service or API key.
Selecting a file adds a record; open its details and tap **Start upload** to send it.

[AGPL-3.0-only](LICENSE)
