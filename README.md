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

If the version you need is not on SwiftPM, extract `olares-note-ios-sdk-0.2.5-spm.zip`.
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

Swift network methods are `async throws`; result types are listed below. Objective-C methods
return a cancelable `NTRequest` and deliver results or an `NSError` to their completion.

| Swift method | Parameters and result |
| --- | --- |
| `NoteClient(apiKey:attempts:)` | `apiKey`; maximum attempts per request defaults to 3, clamped to 1–5. Returns a client; the first request verifies authorization |
| `upload(fileURL:options:idempotencyKey:fileName:progress:)` | Uploads a local file in chunks and returns upload status. Only `fileURL` is required. The `data:fileName:` variant accepts `Data` and requires a file name with an extension |
| `uploadRecording(fileURL:options:idempotencyKey:fileName:)` | Same file/data inputs as `upload`. Sends one multipart request, without chunk progress or resumable chunks |
| `createUpload(fileName:totalBytes:options:idempotencyKey:)` | File name, size in bytes (`Int64`), optional recording options and idempotency key. Creates or recovers a session |
| `uploadChunk(recordingID:offset:data:)` | Recording ID, absolute byte offset (`Int64`) and chunk `Data`. Returns updated status |
| `getUpload(recordingID:)` | Returns upload state, confirmed offset and chunk size |
| `getStatus(recordingID:)` | Returns upload and processing state |
| `getStatuses(recordingIDs:)` (0.2.5+) | `recordingIDs: [String]` → `[RecordingStatusResult]` |
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

### Batch status lookup

**Available since SDK 0.2.5.** Requires a Note server with the batch status endpoint.
Query 1–50 known recording IDs in one request. This creates no upload session and returns no history list. Results follow input order, including duplicates.

Exactly one of `recording` or `error` is present in each result:

| Field | Meaning |
| --- | --- |
| `recordingID` | Requested recording ID |
| `recording` | The same RecordingStatus returned by getStatus |
| `error.code`, `error.status`, `error.message` | Per-record error code, status and description |

| Case | Result | Action |
| --- | --- | --- |
| Accessible recording | Item has recording | Read its upload and processing state |
| Missing, trashed or owned by another key | Item error: 404 / not_found | Mark the cloud recording unavailable; do not automatically upload again |
| Invalid individual ID | Item error: 400 / invalid_id | Correct that ID; other results remain usable |
| Individual service failure | Item error: 500 / internal, 503 / database_unavailable, or another server code | Retry that item later |
| Empty list / more than 50 IDs | Whole call fails: 400 / invalid_request or field_too_long | Supply IDs or split the batch |
| Invalid response fields, result count or ID correspondence | Whole call fails: invalid_response (status 0) | Retain the request ID; do not reconcile local records |
| Invalid API key or whole-request failure | Whole call throws / invokes the failure callback | Handle as a request error |

`error.status` describes an individual failure, not the HTTP response status of the batch. HTTP 200 means the batch request completed, not that every item succeeded. Missing recordings do not fail the SDK call; check each item's error. The SDK does not automatically retry item errors; query those IDs again when needed.
`not_found` does not distinguish deletion, a nonexistent ID or lack of access. An old ID also returns not_found after permanent deletion.

```swift
let recordingIDs = [
    "11111111-1111-4111-8111-111111111111",
    "22222222-2222-4222-8222-222222222222",
]
let results = try await client.getStatuses(recordingIDs: recordingIDs)
for result in results {
    if let recording = result.recording {
        print(result.recordingID, recording.processing.status)
    } else if let error = result.error {
        print(result.recordingID, error.code, error.status)
    }
}
```

## Recovery, cancellation and errors

- Resume with the same file, API key and saved idempotency key. Keep the file unchanged and readable.
  After upload returns, save `recordingID` and query directly.
- Your app owns upload records, key storage and task queues. The SDK does not save them or schedule work after restart.
  It uses foreground `URLSession` requests, without background execution time. Resume explicitly if iOS suspends the app.
- Cancel the calling `Task`, or use Objective-C's `[call cancel]`. This stops local work;
  it does not delete recordings or stop processing in Note.
- Request failures throw `NoteError`. Client creation can also fail on an invalid key or address.
  Handle `code`; use `status` (see the error codes below), `requestID` and `isRetryable` for diagnostics
  and retry decisions. Never log API keys. Objective-C uses `NSError`; business fields are in `userInfo`.
- Each request has at most 3 attempts by default, with backoff starting at 500 ms.
  POST requests retry only with an idempotency key. Objective-C cancellation reports
  `NSURLErrorDomain / NSURLErrorCancelled`.

### SDK error codes

These errors are generated by the SDK during validation or upload. Server `error.code` values are also passed through; codes are strings, not a closed enum.
For HTTP failures, `status` preserves the response status. SDK-generated errors usually use `0`, but also use `409`, `422` and `500`; status alone does not identify the source.

Automatic chunked `upload()` runs in this order:

1. **Prepare the file before the request**: prepare the file source, determine its name and obtain its byte count. API key format is checked when creating the client.
2. **Create or resume the session**: call `POST /v1/uploads` to obtain the session's total byte count and upload state.
3. **Compare sizes in the SDK**: when the returned session total is nonzero, compare it with the local size. A mismatch throws `idempotency_mismatch` (SDK status 409) and stops the upload without sending chunks. This check runs before testing whether the upload is complete.
4. **Continue according to upload state**: after validation, `ready` returns the existing recording status, `pending` / `active` uploads chunks, and `failed` throws `upload_failed`.

When resuming a completed session, step 3 still runs after HTTP 200. Its 409 is assigned by the SDK, not returned by the endpoint. The comparison uses exact byte counts, not duration or content hashes.

Local validation and file preparation:

| code | status | Trigger | Action |
| --- | --- | --- | --- |
| `invalid_api_key_format` | `0` | Invalid API key format or metadata | Copy the complete key from Note |
| `api_key_too_new` | `0` | Key version is newer than this SDK supports | Update the SDK |
| `api_key_without_endpoint` | `0` | Neither the key nor configuration provides an endpoint | Create a new key or supply an endpoint |
| `missing_file_name` | `0` | File name is missing and cannot be inferred | Provide fileName with an extension |
| `file_unreadable` | `0` | File cannot be read or changes during upload | Check access; finish Bluetooth sync and stop writing before upload |
| `idempotency_mismatch` | `409` | upload() receives a nonzero session total that differs from the local file size, including completed uploads | Restore the original file; use a new key to create a recording for a changed file |
| `invalid_endpoint` | `0` | Endpoint is not a supported HTTP(S) URL | Check scheme and host; remove credentials, query and fragment |
| `invalid_upload` | `0` | Explicit idempotency key is blank or exceeds 200 UTF-8 bytes | Use a nonblank key of at most 200 UTF-8 bytes |
| `invalid_recording_id` | `0` | Recording ID is not a UUID | Use the recording ID returned by the SDK |
| `invalid_chunk` | `0` | Manual chunk offset is negative or data is empty | Fix the offset and chunk data |
| `invalid_timeout` | `0` | Invalid polling time parameters | Use valid nonnegative time values |
| `local_storage_error` | `0` | Cannot prepare or access local upload data | Check app storage and file access |

Upload and request errors:

| code | status | Trigger | Action |
| --- | --- | --- | --- |
| `network_error` | `0` | Request could not complete | Check connection and service; retain the file and key for resume |
| `timeout` | `0` | Network request or local processing wait timed out | Query the existing recording ID; do not create another recording |
| `upload_failed` | `422` | upload() observes upload.state = failed | Read the description; check the file and Note service |
| `upload_stalled` | `500` | Upload offset does not advance or chunk/session state is invalid | Query status first; resume with the same file and key |
| `invalid_response` | `0` | Response cannot be decoded as supported status data | Check the service version; retain the request ID when available |
| `tls_error` | `0` | TLS connection or certificate validation failed | Check the server certificate and HTTPS configuration |

Server errors retain their original `code` and HTTP `status`, for example `invalid_api_key` (401: configure a valid key) and `quota_exceeded` (507: free storage).
An HTTP failure without `error.code` uses `http_<status>`, such as `http_503`. Handle unknown codes with a generic message and retain the code and optional request ID. Never branch on descriptions or log API keys.

Objective-C reads `NSError.userInfo["code"]` and `userInfo["httpStatus"]`; the numeric `NSError.code` is not the business error code. Cancellation is not an upload failure.

## Demo

The SwiftUI and Objective-C demos in `olares-note-ios-demo-0.2.5-source.zip`
have file selection, local history separated by connection and manual recovery after restart.
Their offline mode simulates upload and processing without a Note service or API key.
Selecting a file adds a record; open its details and tap **Start upload** to send it.

[AGPL-3.0-only](LICENSE)
