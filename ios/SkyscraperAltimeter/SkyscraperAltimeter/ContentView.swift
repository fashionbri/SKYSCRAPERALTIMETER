import SwiftUI

struct ContentView: View {
    @StateObject private var altimeterManager = AltimeterManager()
    @StateObject private var networkManager = NetworkManager()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Skyscraper Altimeter")
                    .font(.title)
                    .bold()

                Spacer()

                statusBadge
            }

            if altimeterManager.isActive {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: "%.2f m", altimeterManager.relativeAltitudeM))
                        .font(.system(size: 48, weight: .bold))
                    Text(String(format: "Net Change: %.2f m", altimeterManager.netChangeM))
                    Text(String(format: "Vertical Gain: %.2f m", altimeterManager.verticalGainM))
                    Text(String(format: "Pressure: %.2f kPa", altimeterManager.pressureKPa))
                    Text("Sequence: \(altimeterManager.sequenceNumber)")
                    Text("Last Sent: \(lastSentText)")
                    Text("Queued: \(networkManager.queuedPayloads)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Altimeter is stopped")
                    .foregroundColor(.secondary)
            }
            
            if let error = altimeterManager.lastError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            HStack(spacing: 16) {
                if altimeterManager.isActive {
                    Button("Stop") {
                        altimeterManager.stop()
                        networkManager.stopSending()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button("Start") {
                        altimeterManager.start()
                        networkManager.startSending()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(networkManager: networkManager)
        }
        .onAppear {
            altimeterManager.onUpdate = { reading in
                networkManager.enqueuePayload(
                    relativeAltitudeM: reading.relativeAltitudeM,
                    pressureKPa: reading.pressureKPa,
                    verticalGainM: reading.verticalGainM,
                    netChangeM: reading.netChangeM,
                    seq: reading.seq,
                    battery: nil,
                    isCharging: nil
                )
            }
        }
    }

    private var statusBadge: some View {
        let color: Color
        switch networkManager.connectionStatus {
        case "connected":
            color = .green
        case "connecting":
            color = .yellow
        default:
            color = .red
        }

        return Text(networkManager.connectionStatus)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }

    private var lastSentText: String {
        guard let lastSent = networkManager.lastSentTime else {
            return "never"
        }
        let interval = Int(Date().timeIntervalSince(lastSent))
        return "\(interval)s ago"
    }
}
