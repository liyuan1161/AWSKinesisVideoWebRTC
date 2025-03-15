import Foundation
import Starscream
import WebKit
import WebRTC

/// 远程连接事件的代理协议
protocol SignalClientDelegate: class {
    /// 信令客户端连接成功时调用
    func signalClientDidConnect(_ signalClient: SignalingClient)
    
    /// 信令客户端断开连接时调用
    func signalClientDidDisconnect(_ signalClient: SignalingClient)
    
    /// 收到远程SDP描述时调用
    /// - Parameters:
    ///   - signalClient: 信令客户端
    ///   - senderClientId: 发送者客户端ID
    ///   - sdp: WebRTC会话描述
    func signalClient(_ signalClient: SignalingClient, senderClientId: String, didReceiveRemoteSdp sdp: RTCSessionDescription)
    
    /// 收到ICE候选者时调用
    /// - Parameters:
    ///   - signalClient: 信令客户端
    ///   - senderClientId: 发送者客户端ID
    ///   - candidate: ICE候选者
    func signalClient(_ signalClient: SignalingClient, senderClientId: String, didReceiveCandidate candidate: RTCIceCandidate)
}

/// 信令客户端类 - 负责WebRTC信令服务器的通信
final class SignalingClient {
    // MARK: - 属性
    private let socket: WebSocket          // WebSocket连接对象
    private let encoder = JSONEncoder()    // JSON编码器
    weak var delegate: SignalClientDelegate?   // 代理对象

    /// 初始化方法
    /// - Parameter serverUrl: 信令服务器URL
    init(serverUrl: URL) {
        var request: URLRequest = URLRequest(url: serverUrl)

        // 设置User-Agent
        let webView = WKWebView()
        webView.configuration.preferences.javaScriptEnabled = false

        let UA = webView.value(forKey: "userAgent") as? String?
        if let agent = UA {
            request.setValue(appName + "/" + appVersion + " " + agent!, forHTTPHeaderField: userAgentHeader)
        } else {
            request.setValue(appName + "/" + appVersion, forHTTPHeaderField: userAgentHeader)
        }
        
        socket = WebSocket(request: request)
    }

    /// 连接到信令服务器
    func connect() {
        socket.delegate = self
        socket.connect()
    }

    /// 断开与信令服务器的连接
    func disconnect() {
        socket.disconnect()
    }

    /// 发送SDP提议
    /// - Parameters:
    ///   - rtcSdp: WebRTC会话描述
    ///   - senderClientid: 发送者客户端ID
    func sendOffer(rtcSdp: RTCSessionDescription, senderClientid: String) {
        do {
            debugPrint("正在发送SDP提议 \(rtcSdp)")
            let message: Message = Message.createOfferMessage(sdp: rtcSdp.sdp, senderClientId: senderClientid)
            let data = try encoder.encode(message)
            let msg = String(data: data, encoding: .utf8)!
            socket.write(string: msg)
            print("已发送SDP提议消息到信令服务器:", msg)
        } catch {
            print(error)
        }
    }

    /// 发送SDP应答
    /// - Parameters:
    ///   - rtcSdp: WebRTC会话描述
    ///   - recipientClientId: 接收者客户端ID
    func sendAnswer(rtcSdp: RTCSessionDescription, recipientClientId: String) {
        do {
            debugPrint("正在发送SDP应答 \(rtcSdp)")
            let message: Message = Message.createAnswerMessage(sdp: rtcSdp.sdp, recipientClientId)
            let data = try encoder.encode(message)
            let msg = String(data: data, encoding: .utf8)!
            socket.write(string: msg)
            print("已发送SDP应答消息到信令服务器:", msg)
        } catch {
            print(error)
        }
    }

    /// 发送ICE候选者
    /// - Parameters:
    ///   - rtcIceCandidate: ICE候选者
    ///   - master: 是否为主播
    ///   - recipientClientId: 接收者客户端ID
    ///   - senderClientId: 发送者客户端ID
    func sendIceCandidate(rtcIceCandidate: RTCIceCandidate, master: Bool,
                          recipientClientId: String,
                          senderClientId: String) {
        do {
            debugPrint("正在发送ICE候选者 \(rtcIceCandidate)")
            let message: Message = Message.createIceCandidateMessage(candidate: rtcIceCandidate,
                                                                     master,
                                                                     recipientClientId: recipientClientId,
                                                                     senderClientId: senderClientId)
            let data = try encoder.encode(message)
            let msg = String(data: data, encoding: .utf8)!
            socket.write(string: msg)
            print("已发送ICE候选者消息到信令服务器:", msg)
        } catch {
            print(error)
        }
    }
}

// MARK: - WebSocket代理
extension SignalingClient: WebSocketDelegate {
    /// WebSocket连接成功
    func websocketDidConnect(socket _: WebSocketClient) {
        delegate?.signalClientDidConnect(self)
        debugPrint("信令服务器连接成功")
    }

    /// WebSocket断开连接
    func websocketDidDisconnect(socket _: WebSocketClient, error: Error?) {
        delegate?.signalClientDidDisconnect(self)
        debugPrint("信令服务器断开连接 \(error != nil ? error!.localizedDescription : "")")
    }

    /// 收到WebSocket二进制数据
    func websocketDidReceiveData(socket _: WebSocketClient, data: Data) {
        debugPrint("收到额外的信令数据(不支持) \(data)")
    }

    /// 收到WebSocket文本消息
    func websocketDidReceiveMessage(socket _: WebSocketClient, text: String) {
        debugPrint("收到信令消息 \(text)")
        var parsedMessage: Message?

        parsedMessage = Event.parseEvent(event: text)

        if parsedMessage != nil {
            let messagePayload = parsedMessage?.getMessagePayload()
            let messageType = parsedMessage?.getAction()
            let senderClientId = parsedMessage?.getSenderClientId()
            
            // 解码Base64消息内容
            let message: String = String(messagePayload!.base64Decoded()!)

            do {
                let jsonObject = try message.trim().convertToDictionary()
                if jsonObject.count != 0 {
                    // 处理不同类型的消息
                    if messageType == "SDP_OFFER" {
                        guard let sdp = jsonObject["sdp"] as? String else {
                            return
                        }
                        let rcSessionDescription: RTCSessionDescription = RTCSessionDescription(type: .offer, sdp: sdp)
                        delegate?.signalClient(self, senderClientId: senderClientId!, didReceiveRemoteSdp: rcSessionDescription)
                        debugPrint("收到SDP提议 \(sdp)")
                    } else if messageType == "SDP_ANSWER" {
                        guard let sdp = jsonObject["sdp"] as? String else {
                            return
                        }
                        let rcSessionDescription: RTCSessionDescription = RTCSessionDescription(type: .answer, sdp: sdp)
                        delegate?.signalClient(self, senderClientId: "", didReceiveRemoteSdp: rcSessionDescription)
                        debugPrint("收到SDP应答 \(sdp)")
                    } else if messageType == "ICE_CANDIDATE" {
                        guard let iceCandidate = jsonObject["candidate"] as? String else {
                            return
                        }
                        guard let sdpMid = jsonObject["sdpMid"] as? String else {
                            return
                        }
                        guard let sdpMLineIndex = jsonObject["sdpMLineIndex"] as? Int32 else {
                            return
                        }
                        let rtcIceCandidate: RTCIceCandidate = RTCIceCandidate(sdp: iceCandidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
                        delegate?.signalClient(self, senderClientId: senderClientId!, didReceiveCandidate: rtcIceCandidate)
                        debugPrint("收到ICE候选者 \(iceCandidate)")
                    }
                } else {
                    dump(jsonObject)
                }
            } catch {
                print("消息负载解析错误 \(error)")
            }
        }
    }
}

// MARK: - 字符串扩展
extension String {
    /// 将字符串转换为字典
    func convertToDictionary() throws -> [String: Any] {
        let data = Data(utf8)

        if let anyResult = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            return anyResult
        } else {
            return [:]
        }
    }
}
