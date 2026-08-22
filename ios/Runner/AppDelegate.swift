import AVFoundation
import Flutter
import MediaPlayer
import PushKit
import UIKit
import VBotPhoneSDK

enum ChannelName {
    static let VBOT_CHANNEL = "com.vpmedia.vbot-sdk/vbot_phone"
    static let CALL_STATE_CHANNEL = "com.vpmedia.vbot-sdk/call"
}

enum Methods: String {
    case ISUSERCONNECTED = "isUserConnected"
    case USERDISPLAYNAME = "userDisplayName"
    case CONNECT = "connect"
    case DISCONNECT = "disconnect"
    case STARTCALL = "startCall"
    case GETHOTLINE = "getHotlines"
    case HANGUP = "hangup"
    case MUTE = "mute"
    case SPEAKER = "speaker"
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var voipRegistry: PKPushRegistry?
    let client = VBotPhone.sharedInstance
    private var lastCallState: VBotCallState = .null
    private var lastCallName: String = ""

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
      
        let config = VBotConfig(
            iconTemplateImageData: UIImage(named: "callkit-icon")?.pngData(),
            environment: .staging
        )
        
        VBotPhone.sharedInstance.setup(with: config)
        VBotPhone.sharedInstance.addDelegate(self)
        
        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        
        let vbotChannel = FlutterMethodChannel(name: ChannelName.VBOT_CHANNEL, binaryMessenger: controller.binaryMessenger)
        vbotChannel.setMethodCallHandler(self.methodCall)
        
        let chargingChannel = FlutterEventChannel(name: ChannelName.CALL_STATE_CHANNEL,
                                                  binaryMessenger: controller.binaryMessenger)
        chargingChannel.setStreamHandler(self)

        self.setupPushKit()
        self.checkMicrophonePermission()
      
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func setupPushKit() {
        self.voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
        self.voipRegistry?.delegate = self
        self.voipRegistry?.desiredPushTypes = [.voIP]
    }

    private func checkMicrophonePermission() {
        let status = AVAudioSession.sharedInstance().recordPermission
        if status == .undetermined {
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        }
    }
    
    func methodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let mode = Methods(rawValue: call.method)
        switch mode {
        case .ISUSERCONNECTED:
            self.isUserConnected(call, result)
        case .USERDISPLAYNAME:
            self.userDisplayName(call, result)
        case .CONNECT:
            self.connect(call, result)
        case .DISCONNECT:
            self.disconnect(call, result)
        case .STARTCALL:
            self.startCall(call, result)
        case .GETHOTLINE:
            self.getHotlines(call, result)
        case .HANGUP:
            self.hangup(call, result)
        case .MUTE:
            self.mute(call, result)
        case .SPEAKER:
            self.speaker(call, result)
        default:
            result(FlutterMethodNotImplemented)
            return
        }
    }

    func isUserConnected(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let isUserConnected = self.client.isUserConnected()
        result(["isUserConnected": isUserConnected])
    }
    
    func userDisplayName(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let userDisplayName = self.client.userDisplayName()
        result(["userDisplayName": userDisplayName])
    }
    
    func connect(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let token = (args?["token"] as? String ?? "")
        let envStr = (args?["environment"] as? String)
        let baseUrl = (args?["baseUrl"] as? String)

        let customUrl = (baseUrl?.isEmpty == false) ? baseUrl : nil

        if envStr != nil || customUrl != nil {
            var env: VBotEnvironment = .staging
            switch envStr?.uppercased() {
            case "PRODUCTION": env = .production
            case "SANDBOX": env = .sandbox
            case "STAGING": env = .staging
            default: env = .staging
            }
            let config = VBotConfig(environment: env, customBaseUrl: customUrl)
            VBotPhone.sharedInstance.setConfig(config: config)
        }

        let pushkitToken = self.client.pushKitToken ?? ""
        self.client.connect(token: token, pushkitToken: pushkitToken) { displayName, error in
            if let error = error as NSError? {
                result(FlutterError(code: "\(error.code)", message: error.localizedDescription, details: nil))
                return
            }
            
            result(["displayName": displayName])
        }
    }
    
    func disconnect(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        self.client.disconnect { error in
            if let error = error as NSError? {
                result(FlutterError(code: "\(error.code)", message: error.localizedDescription, details: nil))
                return
            }
            
            result(["disconnect": true])
        }
    }
    
    func startCall(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let name = ((call.arguments as? [String: Any])?["name"] as? String ?? "")
        let phoneNumber = ((call.arguments as? [String: Any])?["phoneNumber"] as? String ?? "")
        let hotline = ((call.arguments as? [String: Any])?["hotline"] as? String ?? "")
        
        self.lastCallName = name.isEmpty ? phoneNumber : name
        
        self.client.startOutgoingCall(displayName: name, number: phoneNumber, hotline: hotline) { success, error in
            if let error = error {
                result(FlutterError(code: "\(error.code)", message: error.localizedDescription, details: nil))
                return
            }
            result(["phoneNumber": phoneNumber])
        }
    }
    
    func getHotlines(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        self.client.getHotlines { hotlines, error in
            if let error = error as NSError? {
                result(FlutterError(code: "\(error.code)", message: error.localizedDescription, details: nil))
                return
            }
            let hotlinesMap = hotlines?.map { hotline in
                ["name": hotline.name, "phoneNumber": hotline.phoneNumber]
            }
            result(hotlinesMap)
        }
    }
    
    func hangup(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        self.client.endCall { error in
            if let error = error as NSError? {
                result(FlutterError(code: "\(error.code)", message: error.localizedDescription, details: nil))
                return
            }
            result(nil)
        }
    }
    
    func mute(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        self.client.muteCall()
        result(nil)
    }
    
    func speaker(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        self.client.onOffSpeaker()
        result(nil)
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

extension AppDelegate: VBotPhoneDelegate {
    func callStateChanged(state: VBotCallState) {
        self.lastCallState = state
        guard let eventSink = eventSink else {
            return
        }
        eventSink(CallSink(state, name: self.lastCallName, isMute: self.client.isCallMute(), onHold: self.client.isCallHold()).toMap)
    }
    
    func callMuteStateDidChange(muted: Bool) {
        guard let eventSink = eventSink else {
            return
        }
        eventSink(CallSink(self.lastCallState, name: self.lastCallName, isMute: muted, onHold: self.client.isCallHold()).toMap)
    }
    
    func callEnded(reason: VBotEndCallReason, endedBy: VBotCallEndParty) {
        print("callEnded reason: \(reason.rawValue), endedBy: \(endedBy)")
    }
    
    func callEnded(reason: VBotEndCallReason) {
        print("callEnded reason: \(reason.rawValue)")
    }
}

extension AppDelegate: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        self.client.pushKitToken = token
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        self.client.startIncomingCall(payload: payload) {
            completion()
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        self.client.pushKitToken = nil
    }
}

extension Encodable {
    /// Converting object to postable JSON
    func toJSON(_ encoder: JSONEncoder = JSONEncoder()) throws -> NSString {
        let data = try encoder.encode(self)
        let result = String(decoding: data, as: UTF8.self)
        return NSString(string: result)
    }
}

struct CallSink {
    let name: String
    let state: String
    let isIncoming: Bool
    let isMute: Bool
    let onHold: Bool
    
    init(_ callState: VBotCallState, name: String, isMute: Bool = false, onHold: Bool = false) {
        self.name = name
        self.state = CallSink.getCallState(callState)
        self.isIncoming = (callState == .incoming)
        self.isMute = isMute
        self.onHold = onHold
    }
    
    public static func getCallState(_ state: VBotCallState) -> String {
        switch state {
        case .calling, .early:
            return "calling"
        case .incoming:
            return "incoming"
        case .connecting:
            return "connecting"
        case .confirmed:
            return "confirmed"
        default:
            return "disconnected"
        }
    }
                      
    private static var dateComponentsFormatter: DateComponentsFormatter = {
        let dateComponentsFormatter = DateComponentsFormatter()
        dateComponentsFormatter.zeroFormattingBehavior = .pad
        dateComponentsFormatter.allowedUnits = [.minute, .second]
        return dateComponentsFormatter
    }()
    
    var toMap: [String: Any] {
        return [
            "name": self.name,
            "state": self.state,
            "isIncoming": self.isIncoming,
            "isMute": self.isMute,
            "onHold": self.onHold
        ]
    }
}
