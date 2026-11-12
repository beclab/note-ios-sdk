# Note iOS SDK Objective-C 接入

[English](OBJECTIVE_C.md)

动态库 `NoteSDK.xcframework` 已包含 `NTNoteClient` 和 Foundation 数据对象，最低 iOS 16，
无需添加 Swift 源码或宿主桥接层。添加 Framework 后设为 **Embed & Sign**，开启 Modules，
并保持 **Always Embed Swift Standard Libraries** 为 `YES`。

## 上传与查询

在主线程创建并调用客户端，completion、进度和状态回调也在主线程异步执行。
调用前设置选项，客户端会复制这些选项。

```objc
#import <Foundation/Foundation.h>
#import <NoteSDK/NoteSDK-Swift.h>

NSError *error = nil;
NTNoteClient *client = [[NTNoteClient alloc] initWithAPIKey:apiKey error:&error];
if (!client) { /* 处理无效的 Key 或地址 */ return; }
NSString *idempotencyKey = NSUUID.UUID.UUIDString;
// 上传前与文件引用一起保存，续传时复用。
NTRecordingOptions *options = [NTRecordingOptions new];
options.title = @"周会";
NTRequest *call = [client uploadFileAtURL:fileURL fileName:nil options:options
    idempotencyKey:idempotencyKey progress:nil
    completion:^(NTRecordingStatus *recording, NSError *error) {
        if (error) { /* 处理请求失败 */ return; }
        // 保存 recording.recordingID，后续用它查询处理状态。
    }];
```

`apiKey`、`fileURL` 由 App 提供。旧 Key 不含地址时，用 `initWithAPIKey:endpoint:error:`
创建 `NTConfiguration`，再调用 `initWithConfiguration:`。地址只能是 HTTPS origin，首次请求才验证授权。

## 方法

网络操作均返回 `NTRequest`，可在任意线程调用其 `cancel`。
忽略或释放句柄不会取消操作。

| 方法名 | 行为 |
| --- | --- |
| `uploadFileAtURL:fileName:options:idempotencyKey:progress:completion:` | 自动分块上传，同一文件和幂等键可续传；文件名默认取 URL 最后一个路径分量 |
| `uploadData:fileName:options:idempotencyKey:progress:completion:` | 上传 `NSData`，必须传带扩展名的文件名 |
| `uploadRecordingFileAtURL:fileName:options:idempotencyKey:completion:` | 单次 multipart 请求，不提供分块进度和续传 |
| `uploadRecordingData:fileName:options:idempotencyKey:completion:` | 接收 `NSData` 的 multipart 版本 |
| `createUploadWithFileName:totalBytes:options:idempotencyKey:completion:` | 创建或恢复会话，大小为 `int64_t` 字节 |
| `uploadChunkWithRecordingID:offset:data:completion:` | 按 `int64_t` 绝对字节偏移发送一块数据 |
| `getUploadWithRecordingID:completion:` | 查询上传状态、`uploadedBytes` 和 `chunkSize` |
| `getStatusWithRecordingID:completion:` | 查询上传与处理状态 |
| `waitForCompletionWithRecordingID:interval:statusHandler:completion:` | 轮询到终态，`statusHandler` 接收每次查询结果 |
| `waitForCompletionWithRecordingID:interval:timeout:statusHandler:completion:` | 带本地等待上限的轮询 |

间隔和上限单位为秒，取值 0 到 365 天。上限为 0 时仍会查询一次；超时在请求间检查。
不带 `timeout:` 的重载无限等待。处理失败以状态返回 completion，不是 `NSError`。

## 参数、返回值与错误

`NTRecordingOptions` 接收录音设置，可空布尔值和说话人数使用 `NSNumber`。
`nil` 表示未指定，`@NO`、`@0` 则发送明确值。
`title` 为录音标题，`language` / `targetLanguage` 为录音和输出语言，`speakerHint` 为 0–50（0 表示未知）；
`translateEnabled` / `summarizeEnabled` 为翻译和纪要开关，`summaryTemplateID` 为纪要模板，
`sourceClient` / `sourceDevice` 为来源应用及版本、设备标签。

`NTRecordingStatus` 包含 `recordingID`、`title`、`statusURL`、`uploadState`、`uploadedBytes`、
`chunkSize`、`totalBytes`、`uploadError`、`processingState`、`currentStage`、`outcome`、
`processingErrorCode`、`processingError`、`waiting` 和 `isTerminal`。
`waiting` 包含模型等待原因和时间，`outcome = no_speech` 表示未检测到语音。

请求错误 domain 为 `com.olares.note.sdk`，数值 code 为 HTTP 状态码，本地错误为 1。
业务判断读取 `userInfo`：

| 字段 | 含义 |
| --- | --- |
| `code` | 字符串业务码，如 `file_unreadable`、`idempotency_mismatch` |
| `httpStatus`、`retryable` | `NSNumber` 类型的 HTTP 状态码（本地错误为 0）和重试标志 |
| `requestID` | 服务端提供时存在的请求 ID |
| `NSLocalizedDescriptionKey` | 错误描述 |

取消返回 `NSURLErrorDomain / NSURLErrorCancelled`，只停止本地操作。
保存文件和幂等键用于续传。SDK 不管理本地记录、队列、密钥，也不申请后台执行时间。
文件选择器授权在上传期间需保持有效；需要重启后恢复时，将文件复制到 App 容器或保存书签。

## Demo

纯 Objective-C Demo 直接调用该二进制接口，包含离线上传与恢复、按连接隔离的记录和 Keychain 存储。
在 Demo ZIP 中打开 `ObjectiveCDemo/` 工程。
