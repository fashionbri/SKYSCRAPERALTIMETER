import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var networkManager: NetworkManager

    @State private var serverURL: String = ""
    @State private var ingestToken: String = ""
    @State private var sendInterval: Double = 5

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server")) {
                    TextField("http://192.168.1.100:8787", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    SecureField("Ingest Token", text: $ingestToken)
                }

                Section(header: Text("Send Interval")) {
                    Stepper(value: $sendInterval, in: 3...10, step: 1) {
                        Text("\(Int(sendInterval)) seconds")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        networkManager.configure(
                            serverURL: serverURL,
                            token: ingestToken,
                            interval: sendInterval
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
                ingestToken = UserDefaults.standard.string(forKey: "ingestToken") ?? ""
                sendInterval = UserDefaults.standard.object(forKey: "sendInterval") as? Double ?? 5
            }
        }
    }
}
