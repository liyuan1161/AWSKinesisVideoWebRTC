# AWS Kinesis Video SDK - 建立视频直播过程

本教程演示如何使用 AWS Kinesis Video SDK 在 iOS 应用中建立实时视频直播，清晰地分为以下四个关键步骤：

## 步骤一：创建会话凭证提供者

首先创建 AWS 会话凭证提供者，用于管理临时安全凭证：

```swift
// 创建会话凭证提供者
let credentialsProvider = AWSBasicSessionCredentialsProvider(
    accessKey: AWSConstants.ACCESS_KEY,
    secretKey: AWSConstants.SECRET_KEY,
    sessionToken: AWSConstants.SESSION_TOKEN
)
```

- `ACCESS_KEY`、`SECRET_KEY` 和 `SESSION_TOKEN` 应替换为你的 AWS 凭证。

## 步骤二：配置 Kinesis Video Client

使用提供的凭证和区域设置配置 AWS 服务：

```swift
// 配置 Kinesis Video Client
guard let configuration = AWSServiceConfiguration(
    region: awsRegionType,
    credentialsProvider: credentialsProvider
) else {
    print("配置 AWSServiceConfiguration 失败")
    return
}
```

- `awsRegionType` 替换为你实际的 AWS 服务区域。

## Step 3: 注册 AWSKinesisVideo 客户端

使用上述配置注册 AWS Kinesis Video 客户端：

```swift
// 注册 AWSKinesisVideo 客户端
AWSKinesisVideo.register(with: configuration, forKey: awsKinesisVideoKey)
```

- 注册后可随时通过该 key 获取客户端实例。

## Step 4: 建立视频直播过程

创建视频流，并初始化视频采集、上传数据：

```swift
// 获取 AWS Kinesis Video 客户端实例
guard let kinesisVideoClient = AWSKinesisVideo(forKey: awsKinesisVideoKey) else {
    print("获取 AWSKinesisVideo 客户端失败")
    return
}

// 定义视频流参数
let streamName = "MyLiveStream"
let mediaType = "video/h264" // 根据实际编码格式选择

// 创建视频流并启动直播
kinesisVideoClient.createStream(withStreamName: streamName, mediaType: mediaType) { (streamARN, error) in
    if let error = error {
        print("视频流创建失败: \(error)")
        return
    }
    print("视频流创建成功，ARN 为：\(streamARN)")

    // 初始化视频采集设备和编码器
    // setupVideoCapture()

    // 开始上传视频数据
    // startUploadingVideoData()
}
```

## 可选扩展：WebRTC 信令通道配置

如需实现低延迟点对点传输，可配置 WebRTC 信令通道：

- 使用 `AWSKinesisVideoCreateSignalingChannelInput` 设置通道创建的参数。
- 信令通道创建成功后返回 `AWSKinesisVideoCreateSignalingChannelOutput`，包含 `ChannelARN`。

```swift
// 示例配置 AWSKinesisVideoCreateSignalingChannelInput
let signalingChannelInput = AWSKinesisVideoCreateSignalingChannelInput()
signalingChannelInput.channelName = "MySignalingChannel"
signalingChannelInput.channelType = .singleMaster

// 创建信令通道
kinesisVideoClient.createSignalingChannel(signalingChannelInput) { (output, error) in
    if let error = error {
        print("信令通道创建失败: \(error)")
        return
    }

    if let channelARN = output?.channelARN {
        print("创建成功，通道ARN为：\(channelARN)")
        // 后续使用ChannelARN进行WebRTC通信
    }
}
```

---

以上步骤涵盖了使用 AWS Kinesis Video SDK 在 iOS 应用中快速实现视频直播的完整流程。

