import Foundation

class NetworkManager: ObservableObject {
    @Published var connectionStatus: String = "disconnected"
    @Published var lastSentTime: Date?
    @Published var queuedPayloads: Int = 0

    private let deviceId: String
    private var serverURL: String
    private var ingestToken: String
    private var sendInterval: TimeInterval = 5
    private var payloadQueue: [[String: Any]] = []
    private var timer: Timer?
    private var retryCount: Int = 0
    private var isSending: Bool = false

    init() {
        let defaults = UserDefaults.standard
        if let storedDeviceId = defaults.string(forKey: "deviceId") {
            deviceId = storedDeviceId
        } else {
            let newId = UUID().uuidString
            defaults.set(newId, forKey: "deviceId")
            deviceId = newId
        }

        serverURL = KeychainHelper.load(key: "serverURL") ?? defaults.string(forKey: "serverURL") ?? ""
        ingestToken = KeychainHelper.load(key: "ingestToken") ?? defaults.string(forKey: "ingestToken") ?? ""
        if let storedInterval = defaults.object(forKey: "sendInterval") as? Double {
            sendInterval = storedInterval
        }
        connectionStatus = "disconnected"
    }

    func configure(serverURL: String, token: String, interval: TimeInterval) {
        self.serverURL = serverURL
        ingestToken = token
        sendInterval = interval

        _ = KeychainHelper.save(key: "serverURL", value: serverURL)
        _ = KeychainHelper.save(key: "ingestToken", value: token)
        UserDefaults.standard.set(serverURL, forKey: "serverURL")
        UserDefaults.standard.set(token, forKey: "ingestToken")
        UserDefaults.standard.set(interval, forKey: "sendInterval")
        UserDefaults.standard.set(deviceId, forKey: "deviceId")
    }

    func startSending() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: sendInterval, repeats: true) { [weak self] _ in
            self?.sendNextPayload()
        }
    }

    func stopSending() {
        timer?.invalidate()
        timer = nil
    }

    func enqueuePayload(
        relativeAltitudeM: Double,
        pressureKPa: Double,
        verticalGainM: Double,
        netChangeM: Double,
        seq: Int,
        battery: Double?,
        isCharging: Bool?
    ) {
        var payload: [String: Any] = [
            "device_id": deviceId,
            "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000),
            "relative_altitude_m": relativeAltitudeM,
            "pressure_kpa": pressureKPa,
            "vertical_gain_m": verticalGainM,
            "net_change_m": netChangeM,
            "seq": seq,
            "app_version": "1.0.0"
        ]

        if let battery {
            payload["battery_level"] = battery
        }
        if let isCharging {
            payload["is_charging"] = isCharging
        }

        payloadQueue.append(payload)
        if payloadQueue.count > 50 {
            payloadQueue.removeFirst()
        }
        queuedPayloads = payloadQueue.count
    }

    private func sendNextPayload() {
        guard !isSending else { return }
        guard !payloadQueue.isEmpty else {
            connectionStatus = "connected"
            return
        }
        guard !serverURL.isEmpty, !ingestToken.isEmpty else {
            connectionStatus = "error"
            return
        }
        guard let url = URL(string: "\(serverURL)/ingest") else {
            connectionStatus = "error"
            return
        }

        isSending = true
        connectionStatus = "connecting"

        let payload = payloadQueue[0]
        let bodyData = try? JSONSerialization.data(withJSONObject: payload, options: [])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(ingestToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSending = false

                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode),
                   error == nil {
                    self.payloadQueue.removeFirst()
                    self.queuedPayloads = self.payloadQueue.count
                    self.lastSentTime = Date()
                    self.connectionStatus = "connected"
                    self.retryCount = 0
                } else {
                    self.retryCount += 1
                    self.connectionStatus = "error"
                    let delay = min(pow(2.0, Double(self.retryCount)), 60)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.sendNextPayload()
                    }
                }
            }
        }.resume()
    }
}
