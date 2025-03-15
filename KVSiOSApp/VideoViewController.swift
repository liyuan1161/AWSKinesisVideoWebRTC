import UIKit
import AWSKinesisVideo
import WebRTC

/// 视频视图控制器 - 负责管理视频通话界面和WebRTC视频流的显示
class VideoViewController: UIViewController {
    // MARK: - UI组件
    @IBOutlet var localVideoView: UIView?          // 本地视频预览视图
    @IBOutlet var joinStorageButton: UIButton?     // 加入存储会话按钮
    
    // MARK: - 私有属性
    private let webRTCClient: WebRTCClient         // WebRTC客户端
    private let signalingClient: SignalingClient    // 信令客户端
    private let localSenderClientID: String        // 本地发送者客户端ID
    private let isMaster: Bool                     // 是否为主播角色

    /// 初始化方法
    /// - Parameters:
    ///   - webRTCClient: WebRTC客户端实例
    ///   - signalingClient: 信令客户端实例
    ///   - localSenderClientID: 本地发送者客户端ID
    ///   - isMaster: 是否为主播角色
    ///   - mediaServerEndPoint: 媒体服务器端点
    init(webRTCClient: WebRTCClient, signalingClient: SignalingClient, localSenderClientID: String, isMaster: Bool, mediaServerEndPoint: String?) {
        self.webRTCClient = webRTCClient
        self.signalingClient = signalingClient
        self.localSenderClientID = localSenderClientID
        self.isMaster = isMaster
        super.init(nibName: String(describing: VideoViewController.self), bundle: Bundle.main)
        
        if !isMaster {
            // 在观众模式下，连接建立后发送提议
            webRTCClient.offer { sdp in
                self.signalingClient.sendOffer(rtcSdp: sdp, senderClientid: self.localSenderClientID)
            }
        }
        if mediaServerEndPoint == nil {
            self.joinStorageButton?.isHidden = true
        }
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 视图即将出现时调用
    override func viewWillAppear(_ animated: Bool) {
        // 锁定屏幕方向为竖屏
        AppDelegate.AppUtility.lockOrientation(UIInterfaceOrientationMask.portrait, andRotateTo: UIInterfaceOrientation.portrait)
    }

    /// 视图加载完成时调用
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 根据设备架构选择不同的视频渲染器
        #if arch(arm64)
        // 在arm64设备上使用Metal渲染
        let localRenderer = RTCMTLVideoView(frame: localVideoView?.frame ?? CGRect.zero)
        let remoteRenderer = RTCMTLVideoView(frame: view.frame)
        localRenderer.videoContentMode = .scaleAspectFill
        remoteRenderer.videoContentMode = .scaleAspectFill
        #else
        // 其他设备使用OpenGLES渲染
        let localRenderer = RTCEAGLVideoView(frame: localVideoView?.frame ?? CGRect.zero)
        let remoteRenderer = RTCEAGLVideoView(frame: view.frame)
        #endif

        // 启动本地视频捕获和远程视频渲染
        webRTCClient.startCaptureLocalVideo(renderer: localRenderer)
        webRTCClient.renderRemoteVideo(to: remoteRenderer)

        // 将渲染器嵌入视图层次结构
        if let localVideoView = self.localVideoView {
            embedView(localRenderer, into: localVideoView)
        }
        embedView(remoteRenderer, into: view)
        view.sendSubview(toBack: remoteRenderer)
    }

    /// 将视图嵌入容器视图中
    /// - Parameters:
    ///   - view: 要嵌入的视图
    ///   - containerView: 容器视图
    private func embedView(_ view: UIView, into containerView: UIView) {
        containerView.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        // 设置水平约束
        containerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[view]|",
                                                                    options: [],
                                                                    metrics: nil,
                                                                    views: ["view": view]))
        // 设置垂直约束
        containerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[view]|",
                                                                    options: [],
                                                                    metrics: nil,
                                                                    views: ["view": view]))
        containerView.layoutIfNeeded()
    }

    /// 返回按钮点击事件处理
    @IBAction func backDidTap(_: Any) {
        webRTCClient.shutdown()        // 关闭WebRTC连接
        signalingClient.disconnect()   // 断开信令连接
        dismiss(animated: true)        // 关闭视图控制器
    }
    
    /// 加入存储会话按钮点击事件处理
    @IBAction func joinStorageSession(_: Any) {
        print("按钮已点击")
        joinStorageButton?.isHidden = true
    }

    /// 发送SDP应答
    /// - Parameter recipientClientID: 接收者客户端ID
    func sendAnswer(recipientClientID: String) {
        webRTCClient.answer { localSdp in
            self.signalingClient.sendAnswer(rtcSdp: localSdp, recipientClientId: recipientClientID)
            print("已发送应答。更新对等连接映射并处理待处理的ICE候选者")
            self.webRTCClient.updatePeerConnectionAndHandleIceCandidates(clientId: recipientClientID)
        }
    }
}
