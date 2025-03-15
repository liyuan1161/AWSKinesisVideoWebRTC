import AWSCore
import AWSCognitoIdentityProvider
import AWSKinesisVideo
import AWSKinesisVideoSignaling
import AWSMobileClient
import Foundation
import WebRTC

/// 频道配置视图控制器 - 负责管理WebRTC连接的配置和建立
class ChannelConfigurationViewController: UIViewController, UITextFieldDelegate {
    
    // MARK: - Cognito认证相关属性
    var user: AWSCognitoIdentityUser?                    // Cognito用户对象
    var pool: AWSCognitoIdentityUserPool?                // Cognito用户池
    var userDetailsResponse: AWSCognitoIdentityUserGetDetailsResponse?    // 用户详情响应
    var userSessionResponse: AWSCognitoIdentityUserSession?              // 用户会话响应

    // MARK: - UI控制变量
    var sendAudioEnabled: Bool = true    // 是否启用音频发送
    var isMaster: Bool = false          // 是否为主播角色
    var signalingConnected: Bool = false // 信令服务器连接状态

    // MARK: - WebRTC连接客户端
    var signalingClient: SignalingClient?    // WebRTC信令客户端
    var webRTCClient: WebRTCClient?          // WebRTC客户端

    // MARK: - 发送者ID
    var remoteSenderClientId: String?        // 远程发送者客户端ID
    lazy var localSenderId: String = {       // 本地发送者ID
        return connectAsViewClientId
    }()

    // MARK: - UI输入控件
    @IBOutlet var connectedLabel: UILabel!   // 连接状态标签
    @IBOutlet var channelName: UITextField!  // 频道名称输入框
    @IBOutlet var clientID: UITextField!     // 客户端ID输入框
    @IBOutlet var regionName: UITextField!   // 区域名称输入框
    @IBOutlet var isAudioEnabled: UISwitch!  // 音频开关

    // MARK: - 连接按钮
    @IBOutlet weak var connectAsMasterButton: UIButton!  // 以主播身份连接按钮
    @IBOutlet weak var connectAsViewerButton: UIButton!  // 以观众身份连接按钮
    
    var vc: VideoViewController?             // 视频视图控制器
    var peerConnection: RTCPeerConnection?   // WebRTC点对点连接

    // MARK: - 视图生命周期方法
    
    /// 视图出现时调用
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        self.signalingConnected = false
        updateConnectionLabel()
    }
    
    /// 视图加载完成时调用
    override func viewDidLoad() {
        super.viewDidLoad()
        self.signalingConnected = false
        updateConnectionLabel()

        // 设置文本框代理
        channelName.delegate = self
        clientID.delegate = self
        regionName.delegate = self
        channelName.text = "qiren"
        clientID.text = "liyuan"
        regionName.text =  "cn-north-1"
    }

    // MARK: - UI交互方法

    /// 处理文本框返回事件
    func textFieldShouldReturn(_: UITextField) -> Bool {
        view.endEditing(true)
        return false
    }

    /// 视图即将消失时调用
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(false, animated: true)
    }

    /// 视图即将出现时调用
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: true)
    }

    /// 音频状态改变事件处理
    @IBAction func audioStateChanged(sender: UISwitch!) {
        self.sendAudioEnabled = sender.isOn
    }

    /// 以观众身份连接按钮点击事件
    @IBAction func connectAsViewer(_sender _: AnyObject) {
        self.isMaster = false
        connectAsRole()
    }

    /// 以主播身份连接按钮点击事件
    @IBAction func connectAsMaster(_: AnyObject) {
        self.isMaster = true
        connectAsRole()
    }

    /// 退出登录按钮点击事件
    @IBAction func signOut(_ sender: AnyObject) {
        AWSMobileClient.default().signOut()
        let mainStoryBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
        self.present((mainStoryBoard.instantiateViewController(withIdentifier: "signinController") as? UINavigationController)!, animated: true, completion: nil)
    }

    /// 显示错误弹窗
    func popUpError(title: String, message: String) {
        let alertController = UIAlertController(title: title,
                                                message: message,
                                                preferredStyle: .alert)
        let okAction = UIAlertAction(title: "Ok", style: .default, handler: nil)
        alertController.addAction(okAction)
        present(alertController, animated: true, completion: nil)
    }

    // MARK: - WebRTC连接建立流程
    
    /// 建立WebRTC连接的主要方法
    /// 流程：
    /// 1. 获取Channel ARN（如果不存在则创建新的Channel）
    /// 2. 检查是否需要使用媒体服务器存储流（仅适用于主播且必须启用音视频）
    /// 3. 获取信令通道的端点
    /// 4. 收集ICE候选者信息
    /// 5. 连接到Channel ARN关联的信令客户端
    /// 完成后切换到视频视图
    func connectAsRole() {
        // Attempt to gather User Inputs
        guard let channelNameValue = self.channelName.text?.trim(), !channelNameValue.isEmpty else {
            popUpError(title: "Missing Required Fields", message: "Channel name is required for WebRTC connection")
            return
        }
        guard let awsRegionValue = self.regionName.text?.trim(), !awsRegionValue.isEmpty else {
            popUpError(title: "Missing Required Fields", message: "Region name is required for WebRTC connection")
            return
        }

        let awsRegionType = awsRegionValue.aws_regionTypeValue()
        if (awsRegionType == .Unknown) {
            popUpError(title: "Invalid Region Field", message: "Enter a valid AWS region name")
            return
        }
        // If ClientID is not provided generate one
        if (self.clientID.text!.isEmpty) {
            self.localSenderId = NSUUID().uuidString.lowercased()
            print("Generated clientID is \(self.localSenderId)")
        }
        
        // 创建会话凭证提供者
        let credentialsProvider = AWSBasicSessionCredentialsProvider(
            accessKey: AWSConstants.ACCESS_KEY,
            secretKey: AWSConstants.SECRET_KEY,
            sessionToken: AWSConstants.SESSION_TOKEN
        )
        // 配置 Kinesis Video Client
        guard let configuration = AWSServiceConfiguration(
            region: awsRegionType,
            credentialsProvider: credentialsProvider
        ) else {
            return
        }
            
        AWSKinesisVideo.register(with: configuration, forKey: awsKinesisVideoKey)

        // Attempt to retrieve signalling channel.  If it does not exist create the channel
        var channelARN = retrieveChannelARN(channelName: channelNameValue)
        if channelARN == nil {
            channelARN = createChannel(channelName: channelNameValue)
            if (channelARN == nil) {
                popUpError(title: "Unable to create channel", message: "Please validate all the input fields")
                return
            }
        }
        // check whether signalling channel will save its recording to a stream
        // only applies for master
        var usingMediaServer : Bool = false
        if self.isMaster {
            usingMediaServer = isUsingMediaServer(channelARN: channelARN!, channelName: channelNameValue)
            // Make sure that audio is enabled if ingesting webrtc connection
            if(usingMediaServer && !self.sendAudioEnabled) {
                popUpError(title: "Invalid Configuration", message: "Audio must be enabled to use MediaServer")
                return
            }
        }
        // get signalling channel endpoints
        let endpoints = getSignallingEndpoints(channelARN: channelARN!, region: awsRegionValue, isMaster: self.isMaster, useMediaServer: usingMediaServer)
        let wssURL = createSignedWSSUrl(channelARN: channelARN!, region: awsRegionValue, wssEndpoint: endpoints["WSS"]!, isMaster: self.isMaster)
        print("WSS URL :", wssURL?.absoluteString as Any)
        // get ice candidates using https endpoint
        let httpsEndpoint =
            AWSEndpoint(region: awsRegionType,
                        service: .KinesisVideo,
                        url: URL(string: endpoints["HTTPS"]!!))
        let RTCIceServersList = getIceCandidates(channelARN: channelARN!, endpoint: httpsEndpoint!, regionType: awsRegionType, clientId: localSenderId)
        webRTCClient = WebRTCClient(iceServers: RTCIceServersList, isAudioOn: sendAudioEnabled)
        webRTCClient!.delegate = self

        // Connect to signalling channel with wss endpoint
        print("Connecting to web socket from channel config")
        signalingClient = SignalingClient(serverUrl: wssURL!)
        signalingClient!.delegate = self
        signalingClient!.connect()

        // Create the video view
        let seconds = 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            self.updateConnectionLabel()
            self.vc = VideoViewController(webRTCClient: self.webRTCClient!, signalingClient: self.signalingClient!, localSenderClientID: self.localSenderId, isMaster: self.isMaster, mediaServerEndPoint: endpoints["WEBRTC"] ?? nil)
            self.present(self.vc!, animated: true, completion: nil)
        }
    }

    /// 更新连接状态标签的显示
    func updateConnectionLabel() {
        if signalingConnected {
            connectedLabel!.text = "Connected"
            connectedLabel!.textColor = .green
        } else {
            connectedLabel!.text = "Not Connected"
            connectedLabel!.textColor = .red
        }
    }

    /// 创建信令通道
    /// - Parameter channelName: 通道名称
    /// - Returns: 成功返回通道ARN，失败返回nil
    /// 对应AWS CLI命令:
    /// aws kinesisvideo create-signaling-channel --channel-name channelName --region cognitoIdentityUserPoolRegion
    func createChannel(channelName: String) -> String? {
        var channelARN : String?
        let kvsClient = AWSKinesisVideo(forKey: awsKinesisVideoKey)
        let createSigalingChannelInput = AWSKinesisVideoCreateSignalingChannelInput.init()
        createSigalingChannelInput?.channelName = channelName
        kvsClient.createSignalingChannel(createSigalingChannelInput!).continueWith(block: { (task) -> Void in
            if let error = task.error {
                print("Error creating channel \(error)")
            } else {
                print("Channel ARN : ", task.result?.channelARN)
                channelARN = task.result?.channelARN
            }
        }).waitUntilFinished()
        return channelARN
    }

    /// 尝试获取已存在的信令通道ARN
    /// - Parameter channelName: 通道名称
    /// - Returns: 通道存在时返回ARN，不存在返回nil
    /// - Note: 如果返回nil，需要检查是由于通道不存在还是凭证无效导致
    func retrieveChannelARN(channelName: String) -> String? {
        var channelARN : String?
        /*
            equivalent AWS CLI command:
            aws kinesisvideo describe-signaling-channel --channelName channelName --region cognitoIdentityUserPoolRegion
        */
        let describeInput = AWSKinesisVideoDescribeSignalingChannelInput()
        describeInput?.channelName = channelName
        let kvsClient = AWSKinesisVideo(forKey: awsKinesisVideoKey)
        kvsClient.describeSignalingChannel(describeInput!).continueWith(block: { (task) -> Void in
            if let error = task.error {
                print("Error describing channel: \(error)")
            } else {
                print("Channel ARN : ", task.result!.channelInfo!.channelARN ?? "Channel ARN empty.")
                channelARN = task.result?.channelInfo?.channelARN
            }
        }).waitUntilFinished()
        return channelARN
    }
    
    /// 检查信令通道是否启用了媒体服务器
    /// - Parameters:
    ///   - channelARN: 通道ARN
    ///   - channelName: 通道名称
    /// - Returns: 是否启用了媒体服务器
    func isUsingMediaServer(channelARN: String, channelName: String) -> Bool {
        var usingMediaServer : Bool = false
        /*
            equivalent AWS CLI command:
            aws kinesisvideo describe-media-storage-configuration --channel-name channelARN --region cognitoIdentityUserPoolRegion
        */        
        let mediaStorageInput = AWSKinesisVideoDescribeMediaStorageConfigurationInput()
        mediaStorageInput?.channelARN = channelARN
        let kvsClient = AWSKinesisVideo(forKey: awsKinesisVideoKey)
        kvsClient.describeMediaStorageConfiguration(mediaStorageInput!).continueWith(block: { (task) -> Void in
            if let error = task.error {
                print("Error retriving Media Storage Configuration: \(error)")
            } else {
                usingMediaServer = task.result?.mediaStorageConfiguration!.status == AWSKinesisVideoMediaStorageConfigurationStatus.enabled
                // the app doesn't use the streamARN but could be useful information for the user
                if (usingMediaServer) {
                    print("Stream ARN : ", task.result?.mediaStorageConfiguration!.streamARN ?? "No Stream ARN.")
                }
            }
        }).waitUntilFinished()
        return usingMediaServer
    }
    
    /// 获取ICE服务器配置列表
    /// - Parameters:
    ///   - channelARN: 通道ARN
    ///   - endpoint: AWS端点
    ///   - regionType: AWS区域类型
    ///   - clientId: 客户端ID
    /// - Returns: ICE服务器配置列表
    func getIceCandidates(channelARN: String, endpoint: AWSEndpoint, regionType: AWSRegionType, clientId: String) -> [RTCIceServer] {
        var RTCIceServersList = [RTCIceServer]()
        // TODO: don't use the self.regionName.text!
        let kvsStunUrlStrings = ["stun:stun.kinesisvideo." + self.regionName.text! + ".amazonaws.com:443"]
        /*
            equivalent AWS CLI command:
            aws kinesis-video-signaling get-ice-server-config --channel-arn channelARN --client-id clientId --region cognitoIdentityUserPoolRegion
        */
        let configuration =
            AWSServiceConfiguration(region: regionType,
                                    endpoint: endpoint,
                                    credentialsProvider: AWSMobileClient.default())
        AWSKinesisVideoSignaling.register(with: configuration!, forKey: awsKinesisVideoKey)
        let kvsSignalingClient = AWSKinesisVideoSignaling(forKey: awsKinesisVideoKey)

        let iceServerConfigRequest = AWSKinesisVideoSignalingGetIceServerConfigRequest.init()

        iceServerConfigRequest?.channelARN = channelARN
        iceServerConfigRequest?.clientId = clientId
        kvsSignalingClient.getIceServerConfig(iceServerConfigRequest!).continueWith(block: { (task) -> Void in
            if let error = task.error {
                print("Error to get ice server config: \(error)")
            } else {
                print("ICE Server List : ", task.result!.iceServerList!)

                for iceServers in task.result!.iceServerList! {
                    RTCIceServersList.append(RTCIceServer.init(urlStrings: iceServers.uris!, username: iceServers.username, credential: iceServers.password))
                }

                RTCIceServersList.append(RTCIceServer.init(urlStrings: kvsStunUrlStrings))
            }
        }).waitUntilFinished()
        return RTCIceServersList
    }
   
    /// 获取信令通道的端点信息
    /// - Parameters:
    ///   - channelARN: 通道ARN
    ///   - region: AWS区域
    ///   - isMaster: 是否为主播角色
    ///   - useMediaServer: 是否使用媒体服务器
    /// - Returns: 包含不同协议端点的字典
    func getSignallingEndpoints(channelARN: String, region: String, isMaster: Bool, useMediaServer: Bool) -> Dictionary<String, String?> {
        
        var endpoints = Dictionary <String, String?>()
        /*
            equivalent AWS CLI command:
            aws kinesisvideo get-signaling-channel-endpoint --channel-arn channelARN --single-master-channel-endpoint-configuration Protocols=WSS,HTTPS[,WEBRTC],Role=MASTER|VIEWER --region cognitoIdentityUserPoolRegion
            Note: only include WEBRTC in Protocols if you need a media-server endpoint
        */
        let singleMasterChannelEndpointConfiguration = AWSKinesisVideoSingleMasterChannelEndpointConfiguration()
        singleMasterChannelEndpointConfiguration?.protocols = videoProtocols
        singleMasterChannelEndpointConfiguration?.role = getSingleMasterChannelEndpointRole(isMaster: isMaster)
        
        if(useMediaServer){
            singleMasterChannelEndpointConfiguration?.protocols?.append("WEBRTC")
        }
 
        let kvsClient = AWSKinesisVideo(forKey: awsKinesisVideoKey)

        let signalingEndpointInput = AWSKinesisVideoGetSignalingChannelEndpointInput()
        signalingEndpointInput?.channelARN = channelARN
        signalingEndpointInput?.singleMasterChannelEndpointConfiguration = singleMasterChannelEndpointConfiguration

        kvsClient.getSignalingChannelEndpoint(signalingEndpointInput!).continueWith(block: { (task) -> Void in
            if let error = task.error {
               print("Error to get channel endpoint: \(error)")
            } else {
                print("Resource Endpoint List : ", task.result!.resourceEndpointList!)
            }
            //TODO: Test this popup
            guard (task.result?.resourceEndpointList) != nil else {
                self.popUpError(title: "Invalid Region Field", message: "No endpoints found")
                return
            }
            for endpoint in task.result!.resourceEndpointList! {
                switch endpoint.protocols {
                case .https:
                    endpoints["HTTPS"] = endpoint.resourceEndpoint
                case .wss:
                    endpoints["WSS"] = endpoint.resourceEndpoint
                case .webrtc:
                    endpoints["WEBRTC"] = endpoint.resourceEndpoint
                case .unknown:
                    print("Error: Unknown endpoint protocol ", endpoint.protocols, "for endpoint" + endpoint.description())
                }
            }
        }).waitUntilFinished()
        return endpoints
    }
    
    /// 创建带签名的WSS URL
    /// - Parameters:
    ///   - channelARN: 通道ARN
    ///   - region: AWS区域
    ///   - wssEndpoint: WSS端点
    ///   - isMaster: 是否为主播角色
    /// - Returns: 签名后的WSS URL
    func createSignedWSSUrl(channelARN: String, region: String, wssEndpoint: String?, isMaster: Bool) -> URL? {
        var httpURlString = wssEndpoint! + "?X-Amz-ChannelARN=" + channelARN
        if !isMaster {
            httpURlString += "&X-Amz-ClientId=" + self.localSenderId
        }
        
        let httpRequestURL = URL(string: httpURlString)
        let wssRequestURL = URL(string: wssEndpoint!)
        let wssURL = KVSSigner.sign(
            signRequest: httpRequestURL!,
            secretKey: AWSConstants.SECRET_KEY,
            accessKey: AWSConstants.ACCESS_KEY,
            sessionToken: AWSConstants.SESSION_TOKEN,
            wssRequest: wssRequestURL!,
            region: region
        )
        return wssURL
    }
    
    /// 获取适当的Kinesis Video通道角色
    /// - Parameter isMaster: 是否为主播角色
    /// - Returns: 对应的通道角色
    func getSingleMasterChannelEndpointRole(isMaster: Bool) -> AWSKinesisVideoChannelRole {
        if isMaster {
            return .master
        }
        return .viewer
    }
}


extension ChannelConfigurationViewController: SignalClientDelegate {
    /// 信令客户端连接成功
    func signalClientDidConnect(_: SignalingClient) {
        signalingConnected = true
    }

    /// 信令客户端断开连接
    func signalClientDidDisconnect(_: SignalingClient) {
        signalingConnected = false
    }

    /// 设置远程发送者客户端ID
    func setRemoteSenderClientId() {
        if self.remoteSenderClientId == nil {
            remoteSenderClientId = connectAsViewClientId
        }
    }
    
    /// 收到远程SDP描述时的处理
    func signalClient(_: SignalingClient, senderClientId: String, didReceiveRemoteSdp sdp: RTCSessionDescription) {
        print("Received remote sdp from [\(senderClientId)]")
        if !senderClientId.isEmpty {
            remoteSenderClientId = senderClientId
        }
        setRemoteSenderClientId()
        webRTCClient!.set(remoteSdp: sdp, clientId: senderClientId) { _ in
            print("Setting remote sdp and sending answer.")
            self.vc!.sendAnswer(recipientClientID: self.remoteSenderClientId!)

        }
    }

    /// 收到远程ICE候选者时的处理
    func signalClient(_: SignalingClient, senderClientId: String, didReceiveCandidate candidate: RTCIceCandidate) {
        print("Received remote candidate from [\(senderClientId)]")
        if !senderClientId.isEmpty {
            remoteSenderClientId = senderClientId
        }
        setRemoteSenderClientId()
        webRTCClient!.set(remoteCandidate: candidate, clientId: senderClientId)
    }
}

extension ChannelConfigurationViewController: WebRTCClientDelegate {
    /// 生成本地ICE候选者时的处理
    func webRTCClient(_: WebRTCClient, didGenerate candidate: RTCIceCandidate) {
        print("Generated local candidate")
        setRemoteSenderClientId()
        signalingClient?.sendIceCandidate(rtcIceCandidate: candidate, master: isMaster,
                                          recipientClientId: remoteSenderClientId!,
                                          senderClientId: localSenderId)
    }

    /// WebRTC连接状态改变时的处理
    func webRTCClient(_: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
        switch state {
        case .connected, .completed:
            print("WebRTC connected/completed state")
        case .disconnected:
            print("WebRTC disconnected state")
        case .new:
            print("WebRTC new state")
        case .checking:
            print("WebRTC checking state")
        case .failed:
            print("WebRTC failed state")
        case .closed:
            print("WebRTC closed state")
        case .count:
            print("WebRTC count state")
        @unknown default:
            print("WebRTC unknown state")
        }
    }

    /// 收到本地数据时的处理
    func webRTCClient(_: WebRTCClient, didReceiveData _: Data) {
        print("收到本地数据")
    }
}

extension String {
    /// 去除字符串两端的空白字符
    func trim() -> String {
        return trimmingCharacters(in: NSCharacterSet.whitespaces)
    }
}
