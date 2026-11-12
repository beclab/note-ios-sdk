# Note iOS SDK

[English](README.md)

在 iOS App 中上传音视频到 Note，并查询处理状态。支持 Swift、Objective-C，最低 iOS 16。
API Key 可查询同一 Key 上传的录音。文字稿、纪要和播放请在 Note 中查看。无第三方运行时依赖。

## 安装

在 Xcode 选择 **File → Add Package Dependencies**，输入
`https://github.com/beclab/note-ios-sdk`，选择已发布的版本，将 `NoteSDK` 产品加入 App Target。
Swift Package Manager 会下载二进制库并处理链接和嵌入，Swift 和 Objective-C 使用同一个包。

在该版本的[发布页](https://github.com/beclab/note-ios-sdk/releases)查看 `release.json`，
核对构建二进制使用的编译器，使用相同版本或兼容的新版本 Xcode。

<details>
<summary>离线安装</summary>

需要的版本尚未发布到 SwiftPM 时，解压 `olares-note-ios-sdk-0.2.2-spm.zip`。
在 Xcode 选择 **Add Package Dependencies → Add Local**，选中包含 `Package.swift` 的目录，
将 `NoteSDK` 产品加入 App Target。也可直接添加 `NoteSDK.xcframework`，设为 **Embed & Sign**。
保留完整 XCFramework，SDK 只添加一次。

</details>

App 需有权读取文件。文件选择器返回的 URL 在上传期间需保留 security-scoped 访问授权；
需要重启后续传时，先复制到 App 容器或保存书签。

## 上传与查询

在 **Note → 设置 → API Key** 创建 Key，Key 已包含服务地址。
下例的 `apiKey` 和 `fileURL` 由 App 提供。每个新上传只生成一次 `idempotencyKey`（幂等键），
上传前与文件引用一起保存，续传时读取保存的值。

### Swift

在异步上下文中调用：

```swift
import Foundation
import NoteSDK

let client = try NoteClient(apiKey: apiKey)
let idempotencyKey = UUID().uuidString
// 先保存 idempotencyKey 和文件引用，再开始上传。
let recording = try await client.upload(
    fileURL: fileURL,
    options: .init(title: "周会"),
    idempotencyKey: idempotencyKey
) { sent, total in
    // 已确认字节数 / 总字节数；更新界面时切回主 actor。
}
// 保存 recording.recordingID，后续可直接查询。
let result = try await client.waitForCompletion(recordingID: recording.recordingID) { status in
    // 展示 status.processing.currentStage；更新界面时切回主 actor。
}
```

### Objective-C

在主线程创建并调用 `NTNoteClient`，回调也在主线程：

```objc
#import <Foundation/Foundation.h>
#import <NoteSDK/NoteSDK-Swift.h>

NSError *error = nil;
NTNoteClient *client = [[NTNoteClient alloc] initWithAPIKey:apiKey error:&error];
if (!client) { /* 处理无效的 Key 或地址 */ return; }
NSString *idempotencyKey = NSUUID.UUID.UUIDString;
// 先保存 idempotencyKey 和文件引用，再开始上传。
NTRecordingOptions *options = [NTRecordingOptions new];
options.title = @"周会";
NTRequest *call = [client uploadFileAtURL:fileURL fileName:nil options:options
    idempotencyKey:idempotencyKey
    progress:^(int64_t sent, int64_t total) { /* 更新上传进度 */ }
    completion:^(NTRecordingStatus *recording, NSError *error) {
        if (error) { /* 处理请求失败 */ return; }
        // 保存 recording.recordingID，使用下方方法查询处理状态。
    }];
```

上传成功表示 Note 已接收文件，处理可能仍在继续。保存返回的录音 ID，后续用它查询。
处理失败也会返回状态，Objective-C completion 此时没有请求错误，需检查处理状态。

## 方法

Swift 网络方法是 `async throws`，返回 `RecordingStatus`。
Objective-C 方法返回可取消的 `NTRequest`，通过 completion 返回 `NTRecordingStatus` 或 `NSError`。

| Swift 方法 | 参数与返回值 |
| --- | --- |
| `NoteClient(apiKey:attempts:)` | 接收 `apiKey`；单请求最大尝试次数默认 3，限定为 1–5。返回客户端，首次请求才验证 Key 是否有效 |
| `upload(fileURL:options:idempotencyKey:fileName:progress:)` | 自动分块上传本地文件，返回上传状态，仅 `fileURL` 必填。`data:fileName:` 版本接收 `Data`，文件名必填且需带扩展名 |
| `uploadRecording(fileURL:options:idempotencyKey:fileName:)` | 文件和字节参数与 `upload` 相同。单次 multipart 上传，不提供分块进度和分块续传 |
| `createUpload(fileName:totalBytes:options:idempotencyKey:)` | 文件名、字节大小（`Int64`）、可选录音设置和幂等键。创建或恢复会话 |
| `uploadChunk(recordingID:offset:data:)` | 录音 ID、绝对字节偏移（`Int64`）、分块 `Data`。返回更新后的状态 |
| `getUpload(recordingID:)` | 返回上传状态、已确认偏移和分块大小 |
| `getStatus(recordingID:)` | 返回上传与处理状态 |
| `waitForCompletion(recordingID:interval:timeout:onStatus:)` | 轮询到终态并返回，终态包含失败 |

旧 Key 不含地址时，使用 `NoteConfiguration(apiKey:endpoint:)`，再创建 `NoteClient(configuration:)`。
服务地址只能是 HTTPS origin，不能带路径、查询参数或片段。
自行分块时，按服务端的 `upload.offset` 和 `upload.chunkSize` 读取下一块，最后一块可更小。

Objective-C 提供同一组操作：`uploadFileAtURL:` / `uploadData:`、
`uploadRecordingFileAtURL:` / `uploadRecordingData:`、`createUploadWithFileName:`、
`uploadChunkWithRecordingID:`、`getUploadWithRecordingID:`、`getStatusWithRecordingID:`
和 `waitForCompletionWithRecordingID:`。完整方法名见 [Objective-C 接入](OBJECTIVE_C.zh-CN.md)。

使用 App 从上传响应中保存的 `recordingID`：

```swift
let status = try await client.getStatus(recordingID: recordingID)
let result = try await client.waitForCompletion(
    recordingID: recordingID, timeout: .seconds(60)
)
```

```objc
NTRequest *call = [client waitForCompletionWithRecordingID:recordingID interval:5 timeout:60
    statusHandler:^(NTRecordingStatus *status) { /* 更新处理状态 */ }
    completion:^(NTRecordingStatus *result, NSError *error) { /* 检查错误和结果 */ }];
```

## 参数与返回值

`RecordingOptions` / `NTRecordingOptions` 可设置下列录音参数，均为可选；省略时使用 Note 默认值。
幂等键、文件名和进度回调通过上传方法的独立参数传入。

| 字段 | 含义 |
| --- | --- |
| `title` | 录音标题 |
| `language` / `targetLanguage` | 录音语言 / 译文和纪要的目标语言；省略 `language` 时自动检测 |
| `speakerHint` | 预计说话人数，0–50，0 表示未知 |
| `translateEnabled` / `summarizeEnabled` | 翻译 / 纪要开关 |
| `summaryTemplateID` | 纪要模板 ID |
| `sourceClient` / `sourceDevice` | 来源应用名称及版本 / 设备标签 |

Objective-C 的可空布尔值和说话人数使用 `NSNumber`；`nil` 表示未指定，`@NO`、`@0` 则发送明确值。
传入幂等键时，需为非空白字符串，且最多 200 个 UTF-8 字节。

`waitForCompletion` 默认 `interval: .seconds(5)`、`timeout: nil`（无限等待）。
Swift 使用非负 `Duration`；Objective-C 使用秒，范围为 0 到 365 天，不带 `timeout:` 的重载无限等待。
超时在两次请求间检查，不中断进行中的请求；需要严格总时限时取消操作。
上限为 0 时仍会查询一次。`onStatus` / `statusHandler` 接收每次查询后的状态。

Swift 的 `RecordingStatus` 包含：

| 字段 | 含义 |
| --- | --- |
| `recordingID`、`title`、`statusURL` | 录音 ID、标题、状态查询地址 |
| `upload` | `state`、`offset`、`chunkSize`、`totalBytes` 和可选 `error` |
| `processing` | `status`，以及可选 `currentStage`、`outcome`、`errorCode`、`error`、`waiting` |

`recording.isTerminal` 判断是否到达终态。上传状态为 `failed` 时读取 `upload.error`。
处理状态为 `completed`、`failed`、`canceled` 时结束；`outcome = no_speech` 表示未检测到语音。

`processing.waiting` 表示等待模型，`reason` 为 `model_unavailable`、`model_warming`、
`model_busy` 或 `model_stalled`，未知值使用通用提示。还包含 `capability`、
RFC 3339 时间 `since` / `nextProbeAt` 和可选 `message`。继续查询即可，模型恢复后无需重新上传。

Objective-C 将状态展开到 `NTRecordingStatus`：`uploadState`、`uploadedBytes`、`chunkSize`、
`totalBytes`、`uploadError`、`processingState`、`currentStage`、`outcome`、`processingErrorCode`、
`processingError`、`waiting` 和 `isTerminal`。

## 续传、取消和错误

- 用同一文件、API Key 和保存的幂等键再次上传即可续传。源文件需保持可读且内容不变。
  上传返回后保存 `recordingID`，后续直接查询。
- App 负责保存上传记录、密钥和任务队列，SDK 不保存这些数据，也不在重启后自动调度。
  SDK 使用前台 `URLSession`，不申请后台执行时间。App 被系统挂起后，需要主动续传。
- Swift 取消调用方 `Task`，Objective-C 使用 `[call cancel]`；只停止本地操作，
  不删除录音，也不停止 Note 处理。
- 请求失败抛出 `NoteError`，创建客户端时也可能因 Key 或地址无效而失败。
  业务按 `code` 判断；`status` 为 HTTP 状态码，本地错误为 0；`requestID` 用于排查，
  `isRetryable` 表示稍后重试可能成功。不要记录 API Key。Objective-C 使用 `NSError`，业务字段在 `userInfo`。
- 每个请求默认最多尝试 3 次，退避从 500 毫秒开始。POST 只有带幂等键时才重试。
  Objective-C 取消操作返回 `NSURLErrorDomain / NSURLErrorCancelled`。

## Demo

`olares-note-ios-demo-0.2.2-source.zip` 中的 SwiftUI 和 Objective-C Demo
包含文件选择、按连接隔离的本地记录和重启后手动续传。离线模式不需要 Note 服务或 API Key，可模拟上传与处理。
选择文件只新增记录，在详情页点「开始上传」后才发送。

[AGPL-3.0-only](LICENSE)
