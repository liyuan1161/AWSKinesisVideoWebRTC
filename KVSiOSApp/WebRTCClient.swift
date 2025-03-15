import Foundation
import WebRTC

/// WebRTC客户端代理协议 - 用于处理WebRTC事件回调
protocol WebRTCClientDelegate: class {
    /// 生成新的ICE候选者时调用
    func webRTCClient(_ client: WebRTCClient, didGenerate candidate: RTCIceCandidate)
    /// 连接状态改变时调用
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState)
    /// 收到数据通道数据时调用
    func webRTCClient(_ client: WebRTCClient, didReceiveData data: Data)
}

/// WebRTC客户端类 - 负责管理WebRTC连接、音视频流和数据通道
final class WebRTCClient: NSObject {
    // MARK: - 静态属性
    
    /// WebRTC连接工厂，用于创建各种WebRTC对象
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        // 支持所有编解码格式
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(),
                                      decoderFactory: RTCDefaultVideoDecoderFactory())
    }()

    // MARK: - 属性
    weak var delegate: WebRTCClientDelegate?
    private let peerConnection: RTCPeerConnection        // 对等连接对象

    // 接收远程端的音视频流
    private let streamId = "KvsLocalMediaStream"        // 本地媒体流ID
    private let mediaConstrains = [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                                 kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue]
    
    // 媒体相关属性
    private var videoCapturer: RTCVideoCapturer?        // 视频捕获器
    private var localVideoTrack: RTCVideoTrack?         // 本地视频轨道
    private var localAudioTrack: RTCAudioTrack?         // 本地音频轨道
    private var remoteVideoTrack: RTCVideoTrack?        // 远程视频轨道
    private var remoteDataChannel: RTCDataChannel?      // 远程数据通道
    private var constructedIceServers: [RTCIceServer]?  // ICE服务器列表

    // 连接管理
    private var peerConnectionFoundMap = [String: RTCPeerConnection]()       // 已建立的对等连接映射
    private var pendingIceCandidatesMap = [String: Set<RTCIceCandidate>]()  // 待处理的ICE候选者映射

    /// 初始化WebRTC客户端
    /// - Parameters:
    ///   - iceServers: ICE服务器配置列表
    ///   - isAudioOn: 是否启用音频
    required init(iceServers: [RTCIceServer], isAudioOn: Bool) {
        // 配置WebRTC连接
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan               // 使用统一计划模式
        config.continualGatheringPolicy = .gatherContinually  // 持续收集ICE候选者
        config.bundlePolicy = .maxBundle                 // 最大化媒体流捆绑
        config.keyType = .ECDSA                         // 使用ECDSA加密
        config.rtcpMuxPolicy = .require                 // 要求RTCP多路复用
        config.tcpCandidatePolicy = .enabled            // 启用TCP候选者

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection = WebRTCClient.factory.peerConnection(with: config, constraints: constraints, delegate: nil)

        super.init()
        configureAudioSession()    // 配置音频会话

        if (isAudioOn) {
            createLocalAudioStream()   // 创建本地音频流
        }
        createLocalVideoStream()       // 创建本地视频流
        peerConnection.delegate = self
    }

    /// 配置音频会话
    func configureAudioSession() {
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.isAudioEnabled = true
        do {
            try? audioSession.lockForConfiguration()
            // 设置音频会话类别和选项
            try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, with:.defaultToSpeaker)
            try audioSession.setMode(AVAudioSessionModeDefault)
            // 强制使用扬声器输出
            try audioSession.overrideOutputAudioPort(.speaker)
            // 设置音频会话为活动状态，并在停用时通知其他音频会话
            try? AVAudioSession.sharedInstance().setActive(true, with: .notifyOthersOnDeactivation)
            audioSession.unlockForConfiguration()
        } catch {
            print("音频会话配置失败")
            print(error.localizedDescription)
            audioSession.unlockForConfiguration()
        }
    }

    /// 关闭WebRTC连接
    func shutdown() {
        peerConnection.close()

        // 清理媒体流
        if let stream = peerConnection.localStreams.first {
            localAudioTrack = nil
            localVideoTrack = nil
            remoteVideoTrack = nil
            peerConnection.remove(stream)
        }
        // 清理连接映射
        peerConnectionFoundMap.removeAll()
        pendingIceCandidatesMap.removeAll()
    }

    func offer(completion: @escaping (_ sdp: RTCSessionDescription) -> Void) {
        let constrains = RTCMediaConstraints(mandatoryConstraints: mediaConstrains,
                                             optionalConstraints: nil)
        peerConnection.offer(for: constrains) { sdp, _ in
            guard let sdp = sdp else {
                return
            }

            self.peerConnection.setLocalDescription(sdp, completionHandler: { _ in
                completion(sdp)
            })
        }
    }

    func answer(completion: @escaping (_ sdp: RTCSessionDescription) -> Void) {
        let constrains = RTCMediaConstraints(mandatoryConstraints: mediaConstrains,
                                             optionalConstraints: nil)
        peerConnection.answer(for: constrains) { sdp, _ in
            guard let sdp = sdp else {
                return
            }

            self.peerConnection.setLocalDescription(sdp, completionHandler: { _ in
                completion(sdp)
            })
        }
    }

    func updatePeerConnectionAndHandleIceCandidates(clientId: String) {
        peerConnectionFoundMap[clientId] = peerConnection;
        handlePendingIceCandidates(clientId: clientId);
    }

    func handlePendingIceCandidates(clientId: String) {
        // Add any pending ICE candidates from the queue for the client ID
        if pendingIceCandidatesMap.index(forKey: clientId) != nil {
            var pendingIceCandidateListByClientId: Set<RTCIceCandidate> = pendingIceCandidatesMap[clientId]!;
            while !pendingIceCandidateListByClientId.isEmpty {
                let iceCandidate: RTCIceCandidate = pendingIceCandidateListByClientId.popFirst()!
                let peerConnectionCurrent : RTCPeerConnection = peerConnectionFoundMap[clientId]!
                peerConnectionCurrent.add(iceCandidate)
                print("Added ice candidate after SDP exchange \(iceCandidate.sdp)");
            }
            // After sending pending ICE candidates, the client ID's peer connection need not be tracked
            pendingIceCandidatesMap.removeValue(forKey: clientId)
        }
    }

    func set(remoteSdp: RTCSessionDescription, clientId: String, completion: @escaping (Error?) -> Void) {
        peerConnection.setRemoteDescription(remoteSdp, completionHandler: completion)
        if remoteSdp.type == RTCSdpType.answer {
            print("Received answer for client ID: \(clientId)")
            updatePeerConnectionAndHandleIceCandidates(clientId: clientId)
        }
    }

    func checkAndAddIceCandidate(remoteCandidate: RTCIceCandidate, clientId: String) {
        // if answer/offer is not received, it means peer connection is not found. Hold the received ICE candidates in the map.
        if peerConnectionFoundMap.index(forKey: clientId) == nil {
            print("SDP exchange not completed yet. Adding candidate: \(remoteCandidate.sdp) to pending queue")

            // If the entry for the client ID already exists (in case of subsequent ICE candidates), update the queue
            if pendingIceCandidatesMap.index(forKey: clientId) != nil {
                var pendingIceCandidateListByClientId: Set<RTCIceCandidate> = pendingIceCandidatesMap[clientId]!
                pendingIceCandidateListByClientId.insert(remoteCandidate)
                pendingIceCandidatesMap[clientId] = pendingIceCandidateListByClientId
            }
            // If the first ICE candidate before peer connection is received, add entry to map and ICE candidate to a queue
            else {
                var pendingIceCandidateListByClientId = Set<RTCIceCandidate>()
                pendingIceCandidateListByClientId.insert(remoteCandidate)
                pendingIceCandidatesMap[clientId] = pendingIceCandidateListByClientId
            }
        }
        // This is the case where peer connection is established and ICE candidates are received for the established connection
        else {
            print("Peer connection found already")
            // Remote sent us ICE candidates, add to local peer connection
            let peerConnectionCurrent : RTCPeerConnection = peerConnectionFoundMap[clientId]!
            peerConnectionCurrent.add(remoteCandidate);
            print("Added ice candidate \(remoteCandidate.sdp)");
        }
    }

    func set(remoteCandidate: RTCIceCandidate, clientId: String) {
        checkAndAddIceCandidate(remoteCandidate: remoteCandidate, clientId: clientId)
    }

    func startCaptureLocalVideo(renderer: RTCVideoRenderer) {
        guard let capturer = self.videoCapturer as? RTCCameraVideoCapturer else {
            return
        }

        guard
            let frontCamera = (RTCCameraVideoCapturer.captureDevices().first { $0.position == .front }),

            let format = RTCCameraVideoCapturer.supportedFormats(for: frontCamera).last,

            let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate else {
                debugPrint("Error setting fps.")
                return
            }

        capturer.startCapture(with: frontCamera,
                              format: format,
                              fps: Int(fps.magnitude))

        localVideoTrack?.add(renderer)
    }

    func renderRemoteVideo(to renderer: RTCVideoRenderer) {
        remoteVideoTrack?.add(renderer)
    }

    private func createLocalVideoStream() {
        localVideoTrack = createVideoTrack()

        if let localVideoTrack = localVideoTrack {
            peerConnection.add(localVideoTrack, streamIds: [streamId])
            remoteVideoTrack = peerConnection.transceivers.first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
        }

    }

    private func createLocalAudioStream() {
        localAudioTrack = createAudioTrack()
        if let localAudioTrack  = localAudioTrack {
            peerConnection.add(localAudioTrack, streamIds: [streamId])
            let audioTracks = peerConnection.transceivers.compactMap { $0.sender.track as? RTCAudioTrack }
            audioTracks.forEach { $0.isEnabled = true }
        }
    }

    private func createVideoTrack() -> RTCVideoTrack {
        let videoSource = WebRTCClient.factory.videoSource()
        videoSource.adaptOutputFormat(toWidth: 1280, height: 720, fps: 30)
        videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        return WebRTCClient.factory.videoTrack(with: videoSource, trackId: "KvsVideoTrack")
    }

    private func createAudioTrack() -> RTCAudioTrack {
        let mediaConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = WebRTCClient.factory.audioSource(with: mediaConstraints)
        return WebRTCClient.factory.audioTrack(with: audioSource, trackId: "KvsAudioTrack")
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        debugPrint("peerConnection stateChanged: \(stateChanged)")
    }

    func peerConnection(_: RTCPeerConnection, didAdd _: RTCMediaStream) {
        debugPrint("peerConnection did add stream")
    }

    func peerConnection(_: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        debugPrint("peerConnection didRemove stream:\(stream)")
    }

    func peerConnectionShouldNegotiate(_: RTCPeerConnection) {
        debugPrint("peerConnectionShouldNegotiate")
    }

    func peerConnection(_: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        debugPrint("peerConnection RTCIceGatheringState:\(newState)")
    }

    func peerConnection(_: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        debugPrint("peerConnection RTCIceConnectionState: \(newState)")
        delegate?.webRTCClient(self, didChangeConnectionState: newState)
    }

    func peerConnection(_: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        debugPrint("peerConnection didGenerate: \(candidate)")
        delegate?.webRTCClient(self, didGenerate: candidate)
    }

    func peerConnection(_: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        debugPrint("peerConnection didRemove \(candidates)")
    }

    func peerConnection(_: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        debugPrint("peerConnection didOpen \(dataChannel)")
        remoteDataChannel = dataChannel
    }
}

extension WebRTCClient: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        debugPrint("dataChannel didChangeState: \(dataChannel.readyState)")
    }

    func dataChannel(_: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        delegate?.webRTCClient(self, didReceiveData: buffer.data)
    }
}
