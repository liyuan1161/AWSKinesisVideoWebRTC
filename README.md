# AWS Kinesis Video WebRTC iOS 视频直播指南

本文档详细介绍如何在 iOS 应用中使用 AWS Kinesis Video Streams with WebRTC 建立实时视频直播。

## 目录

- [前提条件](#前提条件)
- [步骤 1：创建 AWS 凭证提供者](#步骤-1创建-aws-凭证提供者)
- [步骤 2：配置 AWS 服务](#步骤-2配置-aws-服务)
- [步骤 3：注册 AWSKinesisVideo 客户端](#步骤-3注册-awskinesisvideo-客户端)
- [步骤 4：创建视频流并启动直播](#步骤-4创建视频流并启动直播)
- [步骤 5：创建和配置信令通道（可选）](#步骤-5创建和配置信令通道可选)
- [总结](#总结)

## 前提条件

- 有效的 AWS 账户，并已创建 IAM 用户并赋予必要权限。
- 已安装并配置 [AWS CLI](https://aws.amazon.com/cli/)。
- 已在你的 iOS 项目中集成 AWS Kinesis Video 和 WebRTC SDK。

## 步骤 1：创建 AWS 凭证提供者

使用临时 AWS 会话凭证创建凭证提供者：

```swift
let credentialsProvider = AWSBasicSessionCredentialsProvider(
    accessKey: AWSConstants.ACCESS_KEY,
    secretKey: AWSConstants.SECRET_KEY,
    sessionToken: AWSConstants.SESSION_TOKEN
)
```

## 步骤 2：配置 AWS 服务

使用提供的凭证配置 AWS 服务：

```swift
guard let configuration = AWSServiceConfiguration(
    region: awsRegionType,  // 示例：AWSRegionType.USEast1
    credentialsProvider: credentialsProvider
) else {
    print("Failed to create AWSServiceConfiguration")
    return
}
```

## 步骤 3：注册 AWSKinesisVideo 客户端

将配置注册到 AWSKinesisVideo 客户端，后续可通过 key 获取客户端实例：

```swift
AWSKinesisVideo.register(with: configuration, forKey: awsKinesisVideoKey)
```

## 步骤 4：创建视频流并启动直播

创建视频流，并进行视频采集、编码和上传数据：

```swift
guard let kinesisVideoClient = AWSKinesisVideo(forKey: awsKinesisVideoKey) else {
    print("Failed to get AWSKinesisVideo client")
    return
}

let streamName = "MyLiveStream"
let mediaType = "video/h264"

kinesisVideoClient.createStream(withStreamName: streamName, mediaType: mediaType) { (streamARN, error) in
    if let error = error {
        print("Stream creation error: \(error)")
        return
    }
    print("Stream created successfully with ARN: \(streamARN)")

    // setupVideoCapture()
    // startUploadingVideoData()
}
```

## 步骤 5：创建和配置信令通道（可选）

如需低延迟实时通信，创建 WebRTC 信令通道：

```swift
let createChannelInput = AWSKinesisVideoCreateSignalingChannelInput()
createChannelInput.channelName = "YourChannelName"
createChannelInput.channelType = .singleMaster

AWSKinesisVideo.default().createSignalingChannel(createChannelInput).continueWith { task in
    if let error = task.error {
        print("Error creating signaling channel: \(error)")
    } else {
        print("Signaling channel created successfully.")
    }
    return nil
}
```

配置 WebRTC 参数：

```swift
let signalingClient = AWSKinesisVideoSignalingClient(forChannelARN: "YourChannelARN")
signalingClient.configure(role: .master, region: awsRegionType)

let iceServer = RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
let config = RTCConfiguration()
config.iceServers = [iceServer]
```

处理信令通道事件：

```swift
signalingClient.onSignalingClientStateChange = { state in
    switch state {
    case .connected:
        print("Connected.")
    case .disconnected:
        print("Disconnected.")
    default:
        break
    }
}

signalingClient.onSignalingClientError = { error in
    print("Error: \(error)")
}
```

## 总结

按照以上步骤，您可以快速搭建基于 AWS Kinesis Video WebRTC 的 iOS 实时视频直播应用。根据实际需求进行扩展和优化即可满足不同场景的需求。

