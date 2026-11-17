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

需要的版本尚未发布到 SwiftPM 时，解压 `olares-note-ios-sdk-0.2.5-spm.zip`。
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

Swift 网络方法为 `async throws`，返回类型见下表。
Objective-C 方法返回可取消的 `NTRequest`，通过 completion 返回结果或 `NSError`。

| Swift 方法 | 参数与返回值 |
| --- | --- |
| `NoteClient(apiKey:attempts:)` | 接收 `apiKey`；单请求最大尝试次数默认 3，限定为 1–5。返回客户端，首次请求才验证 Key 是否有效 |
| `upload(fileURL:options:idempotencyKey:fileName:progress:)` | 自动分块上传本地文件，返回上传状态，仅 `fileURL` 必填。`data:fileName:` 版本接收 `Data`，文件名必填且需带扩展名 |
| `uploadRecording(fileURL:options:idempotencyKey:fileName:)` | 文件和字节参数与 `upload` 相同。单次 multipart 上传，不提供分块进度和分块续传 |
| `createUpload(fileName:totalBytes:options:idempotencyKey:)` | 文件名、字节大小（`Int64`）、可选录音设置和幂等键。创建或恢复会话 |
| `uploadChunk(recordingID:offset:data:)` | 录音 ID、绝对字节偏移（`Int64`）、分块 `Data`。返回更新后的状态 |
| `getUpload(recordingID:)` | 返回上传状态、已确认偏移和分块大小 |
| `getStatus(recordingID:)` | 返回上传与处理状态 |
| `getStatuses(recordingIDs:)`（0.2.5+） | `recordingIDs: [String]` → `[RecordingStatusResult]` |
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

### 批量查询状态

**SDK 0.2.5 起支持。** Note 服务端也需支持批量查询接口。
一次查询 1–50 个已有录音 ID，不创建上传会话，也不返回历史列表。结果按输入顺序返回，重复 ID 也各返回一项。

每项结果中，`recording` 和 `error` 恰好有一个有值：

| 字段 | 含义 |
| --- | --- |
| `recordingID` | 本项请求的录音 ID |
| `recording` | 与 getStatus 返回的 RecordingStatus 相同 |
| `error.code`、`error.status`、`error.message` | 本项失败的错误码、对应状态码和描述 |

| 情况 | 返回方式 | 接入方处理 |
| --- | --- | --- |
| 录音可查询 | 本项 recording 有值 | 读取上传和处理状态 |
| 录音不存在、在回收站中，或不属于当前 Key | 本项 error：404 / not_found | 核对 Key 和录音 ID；不要自动重传 |
| 单个 ID 格式无效 | 本项 error：400 / invalid_id | 修正该 ID，其他结果仍可使用 |
| 单条查询发生服务故障 | 本项 error：500 / internal 或 503 / database_unavailable 等 | 稍后重试该项 |
| ID 列表为空／超过 50 个 | 整次调用失败：400 / invalid_request 或 field_too_long | 分别修正为空的列表或拆分批次 |
| 响应格式错误、字段缺失、结果数量或 ID 对应不符 | 整次调用失败：invalid_response（status 为 0） | 保留请求 ID 排查；不更新本地记录 |
| API Key 无效，或整个请求失败 | 整次调用抛错／进入失败回调 | 按请求错误处理 |

`error.status` 表示该条错误对应的状态码，不是批量请求的 HTTP 响应码。服务端 HTTP 200 表示批量请求已完成，不代表每条录音都查询成功。缺失记录不会让整次 SDK 调用失败；逐项检查 error。SDK 不自动重试结果数组里的单条错误，需要重试时再次查询对应 ID。
`not_found` 不区分删除、从未存在和无访问权限。旧录音彻底删除后，旧 ID 仍返回 not_found。

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

## 续传、取消和错误

- 用同一文件、API Key 和保存的幂等键再次上传即可续传。源文件需保持可读且内容不变。
  上传返回后保存 `recordingID`，后续直接查询。
- App 负责保存上传记录、密钥和任务队列，SDK 不保存这些数据，也不在重启后自动调度。
  SDK 使用前台 `URLSession`，不申请后台执行时间。App 被系统挂起后，需要主动续传。
- Swift 取消调用方 `Task`，Objective-C 使用 `[call cancel]`；只停止本地操作，
  不删除录音，也不停止 Note 处理。
- 请求失败抛出 `NoteError`，创建客户端时也可能因 Key 或地址无效而失败。
  业务按 `code` 判断；`status` 的含义见下方错误码说明；`requestID` 用于排查，
  `isRetryable` 表示稍后重试可能成功。不要记录 API Key。Objective-C 使用 `NSError`，业务字段在 `userInfo`。
- 每个请求默认最多尝试 3 次，退避从 500 毫秒开始。POST 只有带幂等键时才重试。
  Objective-C 取消操作返回 `NSURLErrorDomain / NSURLErrorCancelled`。

### SDK 错误码

以下为 SDK 自行产生的错误，分为本地校验和上传过程错误。服务端返回的 `error.code` 也会传给调用方；错误码是字符串，不是封闭枚举。
`status` 在 HTTP 失败时保留响应状态码；SDK 自行报错通常为 `0`，也会设置 `409`、`422`、`500`，因此不能只靠它判断错误来源。

`upload()` 自动分块上传按以下顺序执行：

1. **请求前准备文件**：准备文件来源，确定文件名并获取本地文件字节数。Key 格式在创建客户端时检查。
2. **请求创建或恢复会话**：调用 `POST /v1/uploads`，获取会话的总字节数和上传状态。
3. **SDK 比较文件大小**：返回的会话总字节数非 0 时，与本地文件大小比较；不一致就抛出 `idempotency_mismatch`（SDK status 为 409），停止本次上传，不发送分块。此项检查在判断上传是否完成之前执行。
4. **按上传状态继续**：校验通过后，`ready` 返回已有录音状态，`pending` / `active` 继续上传分块，`failed` 抛出 `upload_failed`。

恢复已完成会话时，接口返回 HTTP 200 后仍执行第 3 步；校验失败的 409 由 SDK 设置，不是接口响应状态码。大小比较使用准确字节数，不比较显示时长或文件内容哈希。

本地校验和文件准备：

| code | status | 触发条件 | 接入方处理 |
| --- | --- | --- | --- |
| `invalid_api_key_format` | `0` | API Key 格式或内嵌信息无效 | 从 Note 重新复制完整 Key |
| `api_key_too_new` | `0` | Key 使用了当前 SDK 不支持的版本 | 升级 SDK |
| `api_key_without_endpoint` | `0` | Key 未携带服务地址，且未指定地址 | 创建新 Key，或显式指定服务地址 |
| `missing_file_name` | `0` | 未提供且无法推断文件名 | 传入带扩展名的 fileName |
| `file_unreadable` | `0` | 文件无法读取，或上传期间发生变化 | 检查访问权限；蓝牙同步完成并停止写入后再上传 |
| `idempotency_mismatch` | `409` | upload() 创建或恢复的会话总字节数非 0，且与本地文件大小不同；已完成会话也会检查 | 恢复与会话一致的原文件；文件确已变化时，用新幂等键创建新录音 |
| `invalid_endpoint` | `0` | 服务地址不符合 HTTP(S) URL 要求 | 检查协议、主机；移除账号信息、查询参数和片段 |
| `invalid_upload` | `0` | 显式传入的幂等键为空白或超过 200 个 UTF-8 字节 | 修正幂等键，最长 200 个 UTF-8 字节 |
| `invalid_recording_id` | `0` | 录音 ID 不是 UUID | 使用 SDK 返回的录音 ID |
| `invalid_chunk` | `0` | 手动传块时偏移量为负或数据为空 | 修正偏移量和分块数据 |
| `invalid_timeout` | `0` | 轮询时间参数无效 | 使用有效的非负时间参数 |
| `local_storage_error` | `0` | 无法准备或访问本地上传数据 | 检查 App 存储和文件访问权限 |

上传和请求过程：

| code | status | 触发条件 | 接入方处理 |
| --- | --- | --- | --- |
| `network_error` | `0` | 请求未能完成 | 检查网络和服务；续传保留原文件和幂等键 |
| `timeout` | `0` | 网络请求超时，或等待处理达到本地时限 | 按已有录音 ID 继续查询，不因此创建新录音 |
| `upload_failed` | `422` | upload() 检测到 upload.state 为 failed | 读取错误描述，检查文件及 Note 服务 |
| `upload_stalled` | `500` | 上传偏移量未推进，或会话分块状态异常 | 先查询状态；需要续传时使用原文件和幂等键 |
| `invalid_response` | `0` | 服务响应无法解析为 SDK 支持的状态数据 | 检查服务版本并保留请求 ID（如有）供排查 |
| `tls_error` | `0` | HTTPS 安全连接或证书校验失败 | 检查服务端证书及 HTTPS 配置 |

服务端错误保留原始 `code` 和 HTTP `status`，例如 `invalid_api_key`（401，重新配置 Key）、`quota_exceeded`（507，清理空间）。
没有 `error.code` 的 HTTP 失败使用 `http_<状态码>`，如 `http_503`。未知错误使用通用提示，并保留错误码和可选请求 ID；不要按错误描述分支，也不要记录 API Key。

Objective-C 读取 `NSError.userInfo["code"]` 和 `userInfo["httpStatus"]`；`NSError.code` 是数值，不是业务错误码。取消不作为上传失败处理。

## Demo

`olares-note-ios-demo-0.2.5-source.zip` 中的 SwiftUI 和 Objective-C Demo
包含文件选择、按连接隔离的本地记录和重启后手动续传。离线模式不需要 Note 服务或 API Key，可模拟上传与处理。
选择文件只新增记录，在详情页点「开始上传」后才发送。

[AGPL-3.0-only](LICENSE)
