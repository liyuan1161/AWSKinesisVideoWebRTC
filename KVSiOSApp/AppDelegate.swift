import UIKit
import AWSCognitoIdentityProvider
import AWSMobileClient
import AWSCore
// @UIApplicationMain 标记此类为应用程序的入口点
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    // MARK: - 属性
    var window: UIWindow?                    // 应用程序主窗口
    var signInViewController: SignInViewController?                // 登录视图控制器
    var channelConfigViewController: ChannelConfigurationViewController?    // 频道配置视图控制器
    var navigationController: UINavigationController?             // 导航控制器
    var storyboard: UIStoryboard?                                // 故事板引用
    var rememberDeviceCompletionSource: AWSTaskCompletionSource<NSNumber>? // AWS记住设备完成回调

    // MARK: - 应用程序生命周期方法
    
    /// 应用程序启动完成时调用
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // 设置AWS日志级别
        AWSDDLog.sharedInstance.logLevel = .verbose

        // 创建会话凭证提供者
        let credentialsProvider = AWSBasicSessionCredentialsProvider(
            accessKey: AWSConstants.ACCESS_KEY,
            secretKey: AWSConstants.SECRET_KEY,
            sessionToken: AWSConstants.SESSION_TOKEN
        )
        
        // 配置AWS服务
        let serviceConfiguration = AWSServiceConfiguration(
            region: .CNNorth1, // 设置你需要的区域
            credentialsProvider: credentialsProvider
        )
        
        // 注册默认服务配置
        AWSServiceManager.default().defaultServiceConfiguration = serviceConfiguration
        
        // 直接进入主界面，不需要登录
        self.storyboard = UIStoryboard(name: "Main", bundle: nil)
        self.navigationController = self.storyboard?.instantiateViewController(withIdentifier: "channelConfig") as? UINavigationController
        self.channelConfigViewController = self.navigationController?.viewControllers[0] as? ChannelConfigurationViewController
        
        DispatchQueue.main.async {
            self.window?.rootViewController = self.navigationController
        }
        
        return true
    }

    // MARK: - 屏幕方向控制
    
    /// 控制屏幕方向的锁定状态
    var orientationLock = UIInterfaceOrientationMask.all

    /// 返回支持的屏幕方向
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return self.orientationLock
    }
    
    /// 屏幕方向工具结构体
    struct AppUtility {
        /// 锁定屏幕方向
        static func lockOrientation(_ orientation: UIInterfaceOrientationMask) {
            if let delegate = UIApplication.shared.delegate as? AppDelegate {
                delegate.orientationLock = orientation
            }
        }

        /// 锁定屏幕方向并旋转到指定方向
        static func lockOrientation(_ orientation: UIInterfaceOrientationMask, andRotateTo rotateOrientation: UIInterfaceOrientation) {
            self.lockOrientation(orientation)
            // iOS 16适配代码已注释
            UIDevice.current.setValue(rotateOrientation.rawValue, forKey: "orientation")
        }
    }

    // MARK: - 应用程序状态变化方法
    
    /// 应用程序即将进入非活动状态
    func applicationWillResignActive(_ application: UIApplication) {
        // 当应用程序从活动状态切换到非活动状态时调用
        // 例如接收到电话或短信时，或用户切出应用程序时
        // 用于暂停正在进行的任务，禁用计时器，降低OpenGL ES帧率等
    }

    /// 应用程序进入后台
    func applicationDidEnterBackground(_ application: UIApplication) {
        // 用于释放共享资源，保存用户数据，使计时器失效
        // 存储足够的应用程序状态信息以便后续恢复
    }

    /// 应用程序即将进入前台
    func applicationWillEnterForeground(_ application: UIApplication) {
        // 从后台转到非活动状态时调用，可以撤销进入后台时所做的更改
    }

    /// 应用程序变为活动状态
    func applicationDidBecomeActive(_ application: UIApplication) {
        // 重启之前暂停的任务，如果应用程序之前在后台，可以选择刷新用户界面
    }

    /// 应用程序即将终止
    func applicationWillTerminate(_ application: UIApplication) {
        // 应用程序即将终止时调用，可以在此保存数据
    }
}
