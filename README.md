flowchart TB
    %% ---------------- Producer 端 ----------------
    subgraph Producer [Producer 端]
        KinesisVideoClient[KinesisVideoClient<br/>管理视频流创建/配置]
        KinesisVideoProducer[KinesisVideoProducer<br/>采集/编码/上传数据]
        KinesisVideoStream[KinesisVideoStream<br/>具体视频流对象]
        StreamCallbacks[StreamCallbacks<br/>事件回调处理]
        KinesisVideoClient --> KinesisVideoStream
        KinesisVideoProducer --> KinesisVideoStream
        KinesisVideoStream --> StreamCallbacks
    end

    %% --------------- Consumer APIs ----------------
    subgraph Consumer [Consumer APIs]
        GetMediaAPI[GetMedia API<br/>实时获取视频数据]
        GetMediaForFragmentListAPI[GetMediaForFragmentList API<br/>按片段获取视频]
        HLSDASHAPIs[HLS & DASH APIs<br/>流媒体播放]
        KinesisVideoStream --> GetMediaAPI
        KinesisVideoStream --> GetMediaForFragmentListAPI
        KinesisVideoStream --> HLSDASHAPIs
    end

    %% --------------- Support 组件 ----------------
    subgraph Support [Support Components]
        Metrics[Metrics<br/>监控指标]
        Persistence[Persistence<br/>数据缓存/断网保护]
        Auth[Auth<br/>身份认证]
        KinesisVideoClient --> Metrics
        KinesisVideoClient --> Persistence
        KinesisVideoClient --> Auth
    end

    %% ---------- WebRTC 信令 & 传输 -----------
    subgraph WebRTC [WebRTC 信令 & 传输]
        KinesisVideoSignalingClient[KinesisVideoSignalingClient<br/>管理信令交互]
        
        %% 创建信令通道部分
        CreateInput[AWSKinesisVideoCreateSignalingChannelInput<br/>输入参数:<br/>- ChannelName<br/>- ChannelType (SINGLE_MASTER)<br/>- SingleMasterConfiguration<br/>- Tags (Optional)]
        SignalingChannel[SignalingChannel<br/>实际信令通道]
        CreateOutput[AWSKinesisVideoCreateSignalingChannelOutput<br/>输出参数:<br/>- ChannelARN]
        
        %% WebRTC P2P 传输
        WebRTCMaster[WebRTC Master<br/>P2P 推流端]
        WebRTCViewer[WebRTC Viewer<br/>P2P 拉流端]
        ICECandidateExchange[ICE Candidate Exchange<br/>NAT 穿透]
        
        KinesisVideoStream --> KinesisVideoSignalingClient
        KinesisVideoSignalingClient --> CreateInput
        CreateInput --> SignalingChannel
        SignalingChannel --> CreateOutput
        CreateOutput --> WebRTCMaster
        CreateOutput --> WebRTCViewer
        WebRTCMaster --> ICECandidateExchange
        WebRTCViewer --> ICECandidateExchange
    end
