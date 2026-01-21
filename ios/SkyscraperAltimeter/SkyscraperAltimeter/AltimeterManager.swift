import CoreMotion
import Foundation

struct AltimeterReading {
    let relativeAltitudeM: Double
    let pressureKPa: Double
    let verticalGainM: Double
    let netChangeM: Double
    let seq: Int
}

class AltimeterManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var relativeAltitudeM: Double = 0.0
    @Published var pressureKPa: Double = 0.0
    @Published var verticalGainM: Double = 0.0
    @Published var netChangeM: Double = 0.0
    @Published var lastError: String?
    @Published var sequenceNumber: Int = 0

    private let altimeter = CMAltimeter()
    private var startAltitude: Double?
    private var previousAltitude: Double?

    var onUpdate: ((AltimeterReading) -> Void)?

    func start() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            lastError = "Relative altitude is not available on this device."
            return
        }

        startAltitude = nil
        previousAltitude = nil
        verticalGainM = 0.0
        netChangeM = 0.0
        sequenceNumber = 0
        lastError = nil

        altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { [weak self] data, error in
            guard let self else { return }
            if let error = error {
                self.lastError = error.localizedDescription
                return
            }
            guard let data = data else { return }

            let currentAltitude = data.relativeAltitude.doubleValue
            let pressureKPa = data.pressure.doubleValue * 10.0

            if self.startAltitude == nil {
                self.startAltitude = currentAltitude
            }

            if let previous = self.previousAltitude {
                let delta = currentAltitude - previous
                if delta > 0 {
                    self.verticalGainM += delta
                }
            }

            let baseline = self.startAltitude ?? currentAltitude
            self.netChangeM = currentAltitude - baseline

            self.relativeAltitudeM = currentAltitude
            self.pressureKPa = pressureKPa
            self.sequenceNumber += 1
            self.previousAltitude = currentAltitude

            let reading = AltimeterReading(
                relativeAltitudeM: currentAltitude,
                pressureKPa: pressureKPa,
                verticalGainM: self.verticalGainM,
                netChangeM: self.netChangeM,
                seq: self.sequenceNumber
            )
            self.onUpdate?(reading)
        }

        isActive = true
    }

    func stop() {
        altimeter.stopRelativeAltitudeUpdates()
        isActive = false
    }
}
