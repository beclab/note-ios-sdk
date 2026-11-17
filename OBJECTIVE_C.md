# Note iOS SDK for Objective-C

[中文](OBJECTIVE_C.zh-CN.md)

The dynamic `NoteSDK.xcframework` includes `NTNoteClient` and Foundation models. Requires iOS 16+;
no Swift source or host bridge is needed. Add the framework with **Embed & Sign**, enable modules,
and keep **Always Embed Swift Standard Libraries** set to `YES`.

## Upload and query

Initialize and call the client on the main thread. Completions, progress and status callbacks
are asynchronous on the main thread. Set options before calling; the client copies them.

```objc
#import <Foundation/Foundation.h>
#import <NoteSDK/NoteSDK-Swift.h>

NSError *error = nil;
NTNoteClient *client = [[NTNoteClient alloc] initWithAPIKey:apiKey error:&error];
if (!client) { /* Handle the invalid key or address. */ return; }
NSString *idempotencyKey = NSUUID.UUID.UUIDString;
// Save this key with the file reference before uploading. Reuse it to resume.
NTRecordingOptions *options = [NTRecordingOptions new];
options.title = @"Weekly meeting";
NTRequest *call = [client uploadFileAtURL:fileURL fileName:nil options:options
    idempotencyKey:idempotencyKey progress:nil
    completion:^(NTRecordingStatus *recording, NSError *error) {
        if (error) { /* Handle request failure. */ return; }
        // Save recording.recordingID and query processing with it.
    }];
```

`apiKey` and `fileURL` come from your app. For an old key without an address, create
`NTConfiguration` with `initWithAPIKey:endpoint:error:`, then call `initWithConfiguration:`.
Addresses must be HTTPS origins. The first request verifies authorization.

## Methods

All operations return `NTRequest`; use its `cancel` method from any thread.
Ignoring or releasing the handle does not cancel the operation.

| Selector | Behavior |
| --- | --- |
| `uploadFileAtURL:fileName:options:idempotencyKey:progress:completion:` | Automatic chunk upload; same file/key resumes. File name defaults to the URL's last component |
| `uploadData:fileName:options:idempotencyKey:progress:completion:` | Upload `NSData`; file name with an extension is required |
| `uploadRecordingFileAtURL:fileName:options:idempotencyKey:completion:` | Single multipart request, without chunk progress or resume |
| `uploadRecordingData:fileName:options:idempotencyKey:completion:` | Multipart variant for `NSData` |
| `createUploadWithFileName:totalBytes:options:idempotencyKey:completion:` | Create or recover a session; size is `int64_t` bytes |
| `uploadChunkWithRecordingID:offset:data:completion:` | Send one chunk at an absolute `int64_t` byte offset |
| `getUploadWithRecordingID:completion:` | Read upload state, `uploadedBytes` and `chunkSize` |
| `getStatusWithRecordingID:completion:` | Read upload and processing state |
| `getStatusesWithRecordingIDs:completion:` (0.2.5+) | Query 1–50 IDs; completion returns an array with per-record errors |
| `waitForCompletionWithRecordingID:interval:statusHandler:completion:` | Poll until a terminal status; receives each status through `statusHandler` |
| `waitForCompletionWithRecordingID:interval:timeout:statusHandler:completion:` | Same with a local wait limit |

Interval and timeout use seconds, from 0 to 365 days. A zero timeout still queries once.
The timeout is checked between requests. The overload without `timeout:` waits indefinitely.
A terminal processing failure reaches completion as a status, not an `NSError`.

## Options, results and errors

Use `NTRecordingOptions` for recording settings; nullable booleans and speaker count use
`NSNumber`. `nil` leaves a setting unspecified; `@NO` and `@0` send explicit values.
`title` is the recording title; `language` / `targetLanguage` are the spoken/output languages.
`speakerHint` is 0–50 (0 means unknown). `translateEnabled` / `summarizeEnabled` control translation
and summaries; `summaryTemplateID` selects a summary template. `sourceClient` / `sourceDevice`
identify the source app/version and device.

`NTRecordingStatus` exposes `recordingID`, `title`, `statusURL`, `uploadState`, `uploadedBytes`,
`chunkSize`, `totalBytes`, `uploadError`, `processingState`, `currentStage`, `outcome`,
`processingErrorCode`, `processingError`, `waiting` and `isTerminal`.
`waiting` carries a model wait's reason and timestamps; `outcome = no_speech` means no speech was detected.

Request errors use domain `com.olares.note.sdk`. The numeric `NSError.code` equals the SDK status when nonzero, or 1 when status is 0. Use these `userInfo` fields:

| Field | Meaning |
| --- | --- |
| `code` | Business error string, such as `file_unreadable` or `idempotency_mismatch` |
| `httpStatus`, `retryable` | `NSNumber` SDK status and retry flag; usually the HTTP status, but local errors can use 0, 409, 422 or 500 |
| `requestID` | Server request ID, when provided |
| `NSLocalizedDescriptionKey` | Error description |

See the [integration guide](README.md#sdk-error-codes) for error codes and actions.

Cancellation uses `NSURLErrorDomain / NSURLErrorCancelled` and stops local work only.
Save the file and idempotency key to resume. The SDK owns no history, queue, credential store
or background execution time. Document-picker access must remain valid during upload;
copy files into your app container or save bookmarks for recovery after restart.

## Batch status lookup

`getStatusesWithRecordingIDs:completion:` accepts 1–50 IDs and returns a cancelable NTRequest.
**Available since SDK 0.2.5.** Requires a Note server with the batch status endpoint.
The completion's results array contains NTRecordingStatusResult values in input order.
Each item has either recording or error; read code and httpStatus from result.error.userInfo.
The completion's error indicates a whole-request failure. An item 404 neither fails the request nor triggers another upload.
Invalid response fields, counts or IDs fail with invalid_response (httpStatus 0 in userInfo), retaining requestID when available.

```objective-c
NSArray<NSString *> *recordingIDs = @[
    @"11111111-1111-4111-8111-111111111111",
    @"22222222-2222-4222-8222-222222222222"
];
[client getStatusesWithRecordingIDs:recordingIDs completion:^(NSArray<NTRecordingStatusResult *> *results, NSError *error) {
    if (error != nil) { NSLog(@"%@", error); return; }
    for (NTRecordingStatusResult *result in results) {
        if (result.recording != nil) NSLog(@"%@: %@", result.recordingID, result.recording.processingState);
        else NSLog(@"%@: %@", result.recordingID, result.error.userInfo[@"code"]);
    }
}];
```

## Demo

The pure Objective-C Demo uses this binary interface. It includes offline upload/recovery,
connection-specific history and Keychain storage. Open `ObjectiveCDemo/` in the Demo ZIP.
