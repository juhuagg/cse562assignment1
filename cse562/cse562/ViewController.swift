import UIKit
import CoreMotion

import DGCharts

// Quaternion struct for orientation representation remains unchanged
struct Quaternion {
    var w: Double
    var x: Double
    var y: Double
    var z: Double
    
    // Initialize identity quaternion
    init() {
        self.w = 1.0
        self.x = 0.0
        self.y = 0.0
        self.z = 0.0
    }
    
    // Initialize with components
    init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }
    
    // Multiplication operation for quaternions
    func multiply(_ q: Quaternion) -> Quaternion {
        return Quaternion(
            w: w * q.w - x * q.x - y * q.y - z * q.z,
            x: w * q.x + x * q.w + y * q.z - z * q.y,
            y: w * q.y - x * q.z + y * q.w + z * q.x,
            z: w * q.z + x * q.y - y * q.x + z * q.w
        )
    }
    
    // Conjugate of quaternion
    func conjugate() -> Quaternion {
        return Quaternion(w: w, x: -x, y: -y, z: -z)
    }
    
    // Normalize quaternion
    func normalize() -> Quaternion {
        let magnitude = sqrt(w*w + x*x + y*y + z*z)
        if magnitude > 0 {
            return Quaternion(
                w: w / magnitude,
                x: x / magnitude,
                y: y / magnitude,
                z: z / magnitude
            )
        }
        return Quaternion()
    }
    
    // Create rotation quaternion from axis and angle
    static func fromAxisAngle(axis: SIMD3<Double>, angle: Double) -> Quaternion {
        let halfAngle = angle / 2.0
        let sinHalfAngle = sin(halfAngle)
        
        return Quaternion(
            w: cos(halfAngle),
            x: axis.x * sinHalfAngle,
            y: axis.y * sinHalfAngle,
            z: axis.z * sinHalfAngle
        ).normalize()
    }
    
    // Transform a vector by this quaternion (rotate the vector)
    func rotate(vector: SIMD3<Double>) -> SIMD3<Double> {
        // Create a quaternion with the vector
        let vq = Quaternion(w: 0, x: vector.x, y: vector.y, z: vector.z)
        
        // q * v * q^-1
        let result = self.multiply(vq).multiply(self.conjugate())
        
        return SIMD3<Double>(result.x, result.y, result.z)
    }
}

// Data structure for sensor readings
struct SensorDataPoint: Codable {
    let timestamp: TimeInterval
    let accelerometer: [String: Double]
    let gyroscope: [String: Double]
    let orientation: [String: Double]
    let algorithm: String  // Added algorithm field to track which method was used
}

// Enum to track which algorithm is currently active
enum TiltAlgorithm {
    case accelerometerOnly
    case gyroscopeOnly
    case complementaryFilter
}

class ViewController: UIViewController {
    
    let motion = CMMotionManager()
    let updateInterval = 1.0 / 50.0
    
    // Current orientation quaternion
    var currentOrientation = Quaternion()
    
    // Last update timestamp
    var lastUpdateTime: TimeInterval = 0
    
    // Complementary filter gain (alpha)
    let alpha: Double = 0.02 // Adjust based on testing
    
    // Timer for data collection
    var dataCollectionTimer: Timer?
    
    // Flag to track if data collection is active
    var isCollectingData = false
    
    // Array to store collected data
    var collectedData: [SensorDataPoint] = []
    
    // Current algorithm selection
    var currentAlgorithm: TiltAlgorithm = .complementaryFilter
    
    // Stored pitch and roll values for gyroscope-only integration
    var gyroPitch: Double = 0.0
    var gyroRoll: Double = 0.0
    
    // Link the UI with the parameters in funcs
    @IBOutlet weak var accel_x_text: UILabel!
    @IBOutlet weak var accel_y_text: UILabel!
    @IBOutlet weak var accel_z_text: UILabel!
    
    @IBOutlet weak var gyro_x_text: UILabel!
    @IBOutlet weak var gyro_y_text: UILabel!
    @IBOutlet weak var gyro_z_text: UILabel!
    
    // Add tilt output labels
    @IBOutlet weak var pitch_text: UILabel!
    @IBOutlet weak var roll_text: UILabel!
    
    // Button to start/stop data collection
    @IBOutlet weak var recordButton: UIButton!
    
    // Algorithm selection buttons
    @IBOutlet weak var accelButton: UIButton!
    @IBOutlet weak var gyroButton: UIButton!
    @IBOutlet weak var complementaryButton: UIButton!
    
    // Algorithm label to display current method
    @IBOutlet weak var algorithmLabel: UILabel!
    
    //Add Linechart
    @IBOutlet weak var chartView: LineChartView!
    // Chart view and data properties
    private var pitchDataEntries: [ChartDataEntry] = []
    private var rollDataEntries: [ChartDataEntry] = []
    private let maxDataPoints = 100 // Maximum points to display
    
    //function to setup the chartView
    func setupChartView() {
        // Configure chart appearance
        chartView.rightAxis.enabled = false
        chartView.xAxis.labelPosition = .bottom
        chartView.xAxis.drawLabelsEnabled = false
        
        // Set axis limits for degrees (-90° to 90°)
        chartView.leftAxis.axisMinimum = -90
        chartView.leftAxis.axisMaximum = 90
        chartView.leftAxis.labelCount = 7
        
        // Create initial empty datasets
        let pitchSet = LineChartDataSet(entries: pitchDataEntries, label: "Pitch")
        pitchSet.setColor(.systemBlue)
        pitchSet.drawCirclesEnabled = false
        pitchSet.lineWidth = 2
        pitchSet.drawValuesEnabled = false
        pitchSet.mode = .cubicBezier
        
        let rollSet = LineChartDataSet(entries: rollDataEntries, label: "Roll")
        rollSet.setColor(.systemRed)
        rollSet.drawCirclesEnabled = false
        rollSet.lineWidth = 2
        rollSet.drawValuesEnabled = false
        rollSet.mode = .cubicBezier
        
        // Add datasets to chart
        let data = LineChartData(dataSets: [pitchSet, rollSet])
        chartView.data = data
        
        // Disable interactions for real-time data
        chartView.pinchZoomEnabled = false
        chartView.doubleTapToZoomEnabled = false
    }
    
    //function to update the chartView
    func updateChart(pitch: Double, roll: Double) {
        // Convert to degrees for better visualization
        let pitchDegrees = pitch * 180.0 / .pi
        let rollDegrees = roll * 180.0 / .pi
        
        // Get current x value (time index)
        let xValue = Double(pitchDataEntries.count)
        
        // Add new data points
        pitchDataEntries.append(ChartDataEntry(x: xValue, y: pitchDegrees))
        rollDataEntries.append(ChartDataEntry(x: xValue, y: rollDegrees))
        
        // Maintain fixed window of data points
        if pitchDataEntries.count > maxDataPoints {
            pitchDataEntries.removeFirst()
            rollDataEntries.removeFirst()
            
            // Shift x values left
            for i in 0..<pitchDataEntries.count {
                pitchDataEntries[i].x = Double(i)
                rollDataEntries[i].x = Double(i)
            }
        }
        
        // Update chart data
        if let chartData = chartView.data {
            // Update existing datasets
            if let pitchSet = chartData.dataSets[0] as? LineChartDataSet,
               let rollSet = chartData.dataSets[1] as? LineChartDataSet {
                pitchSet.replaceEntries(pitchDataEntries)
                rollSet.replaceEntries(rollDataEntries)
                
                chartData.notifyDataChanged()
                chartView.notifyDataSetChanged()
                
                // Auto-scroll to show latest data
                chartView.moveViewToX(Double(pitchDataEntries.count - 1))
            }
        }
    }
    
    func startAccelAndGyro(){
        if (self.motion.isAccelerometerAvailable && self.motion.isGyroAvailable){
            self.motion.startAccelerometerUpdates()
            self.motion.startGyroUpdates()
            self.motion.accelerometerUpdateInterval = updateInterval
            self.motion.gyroUpdateInterval = updateInterval
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        startAccelAndGyro()
        lastUpdateTime = CACurrentMediaTime()
        
        // Configure record button
        recordButton.setTitle("Start Recording", for: .normal)
        recordButton.backgroundColor = UIColor.systemGreen
        recordButton.layer.cornerRadius = 8
        recordButton.addTarget(self, action: #selector(toggleDataCollection), for: .touchUpInside)
        
        // Configure algorithm selection buttons
        setupAlgorithmButtons()
        
        // Update the algorithm label
        updateAlgorithmLabel()
        
        // Start the sensor update loop (for display only)
        Timer.scheduledTimer(timeInterval: updateInterval, target: self, selector: #selector(updateSensorDisplay), userInfo: nil, repeats: true)
        
        setupChartView()
    }
    
    // Setup algorithm selection buttons
    func setupAlgorithmButtons() {
        // Accelerometer only button
        accelButton.setTitle("Accel Only", for: .normal)
        accelButton.backgroundColor = UIColor.systemBlue
        accelButton.layer.cornerRadius = 8
        accelButton.addTarget(self, action: #selector(selectAccelerometerOnly), for: .touchUpInside)
        
        // Gyroscope only button
        gyroButton.setTitle("Gyro Only", for: .normal)
        gyroButton.backgroundColor = UIColor.systemBlue
        gyroButton.layer.cornerRadius = 8
        gyroButton.addTarget(self, action: #selector(selectGyroscopeOnly), for: .touchUpInside)
        
        // Complementary filter button
        complementaryButton.setTitle("Complementary", for: .normal)
        complementaryButton.backgroundColor = UIColor.systemPurple  // Highlight as default
        complementaryButton.layer.cornerRadius = 8
        complementaryButton.addTarget(self, action: #selector(selectComplementaryFilter), for: .touchUpInside)
    }
    
    // Update algorithm selection label
    func updateAlgorithmLabel() {
        switch currentAlgorithm {
        case .accelerometerOnly:
            algorithmLabel.text = "Accelerometer Only"
            highlightActiveButton(accelButton)
        case .gyroscopeOnly:
            algorithmLabel.text = "Gyroscope Only"
            highlightActiveButton(gyroButton)
        case .complementaryFilter:
            algorithmLabel.text = "Complementary Filter"
            highlightActiveButton(complementaryButton)
        }
    }
    
    // Highlight the active button and reset the others
    func highlightActiveButton(_ activeButton: UIButton) {
        accelButton.backgroundColor = UIColor.systemBlue
        gyroButton.backgroundColor = UIColor.systemBlue
        complementaryButton.backgroundColor = UIColor.systemBlue
        
        activeButton.backgroundColor = UIColor.systemPurple
    }
    
    // Algorithm selection handlers
    @objc func selectAccelerometerOnly() {
        currentAlgorithm = .accelerometerOnly
        updateAlgorithmLabel()
        
        // Reset orientation for clean start
        currentOrientation = Quaternion()
        gyroPitch = 0.0
        gyroRoll = 0.0
    }
    
    @objc func selectGyroscopeOnly() {
        currentAlgorithm = .gyroscopeOnly
        updateAlgorithmLabel()
        
        // Reset orientation for clean start
        currentOrientation = Quaternion()
        gyroPitch = 0.0
        gyroRoll = 0.0
    }
    
    @objc func selectComplementaryFilter() {
        currentAlgorithm = .complementaryFilter
        updateAlgorithmLabel()
        
        // Reset orientation for clean start
        currentOrientation = Quaternion()
        gyroPitch = 0.0
        gyroRoll = 0.0
    }
    
    // Toggle data collection on/off
    @objc func toggleDataCollection() {
        if isCollectingData {
            stopDataCollection()
        } else {
            startDataCollection()
        }
    }
    
    // Start collecting sensor data
    func startDataCollection() {
        collectedData.removeAll()
        isCollectingData = true
        recordButton.setTitle("Stop Recording", for: .normal)
        recordButton.backgroundColor = UIColor.systemRed
        
        // Start timer for data collection
        dataCollectionTimer = Timer.scheduledTimer(timeInterval: updateInterval, target: self, selector: #selector(collectDataPoint), userInfo: nil, repeats: true)
    }
    
    // Stop collecting sensor data and save to file
    func stopDataCollection() {
        // Invalidate timer
        dataCollectionTimer?.invalidate()
        dataCollectionTimer = nil
        
        isCollectingData = false
        recordButton.setTitle("Start Recording", for: .normal)
        recordButton.backgroundColor = UIColor.systemGreen
        
        // Save collected data to JSON file
        saveDataToJSON()
    }
    
    // Collect a single data point
    @objc func collectDataPoint() {
        if let accelData = self.motion.accelerometerData,
           let gyroData = self.motion.gyroData {
            
            // Calculate time delta
            let currentTime = CACurrentMediaTime()
            let deltaTime = currentTime - lastUpdateTime
            lastUpdateTime = currentTime
            
            // Get sensor data
            let accel = SIMD3<Double>(
                accelData.acceleration.x,
                accelData.acceleration.y,
                accelData.acceleration.z
            )
            
            let gyro = SIMD3<Double>(
                gyroData.rotationRate.x,
                gyroData.rotationRate.y,
                gyroData.rotationRate.z
            )
            
            // Get pitch and roll based on current algorithm
            var pitch: Double = 0.0
            var roll: Double = 0.0
            
            switch currentAlgorithm {
            case .accelerometerOnly:
                (pitch, roll) = calculateAccelerometerTilt(accel: accel)
            case .gyroscopeOnly:
                (pitch, roll) = updateGyroscopeTilt(gyro: gyro, deltaTime: deltaTime)
            case .complementaryFilter:
                // Step 1: Update orientation using gyroscope data (dead reckoning)
                updateOrientationFromGyro(gyro: gyro, deltaTime: deltaTime)
                
                // Step 2: Apply tilt correction from accelerometer data
                correctTiltFromAccel(accel: accel)
                
                // Step 3: Extract pitch and roll from the orientation quaternion
                (pitch, roll) = extractPitchAndRoll()
            }
            
            // Create data point with algorithm information
            let algorithmName: String
            switch currentAlgorithm {
            case .accelerometerOnly:
                algorithmName = "accelerometer_only"
            case .gyroscopeOnly:
                algorithmName = "gyroscope_only"
            case .complementaryFilter:
                algorithmName = "complementary_filter"
            }
            
            let dataPoint = SensorDataPoint(
                timestamp: currentTime,
                accelerometer: [
                    "x": accelData.acceleration.x,
                    "y": accelData.acceleration.y,
                    "z": accelData.acceleration.z
                ],
                gyroscope: [
                    "x": gyroData.rotationRate.x,
                    "y": gyroData.rotationRate.y,
                    "z": gyroData.rotationRate.z
                ],
                orientation: [
                    "pitch": pitch,
                    "roll": roll
                ],
                algorithm: algorithmName
            )
            
            // Add to collected data
            collectedData.append(dataPoint)
            
            // Also update the display
            updateDisplay(accel: accelData.acceleration, gyro: gyroData.rotationRate, pitch: pitch, roll: roll)
        }
    }
    
    // BASELINE 1: Calculate tilt using only accelerometer data
    func calculateAccelerometerTilt(accel: SIMD3<Double>) -> (Double, Double) {
        // Normalize accelerometer reading (assuming it's measuring gravity)
        let accelMagnitude = sqrt(accel.x*accel.x + accel.y*accel.y + accel.z*accel.z)
        
        if accelMagnitude < 0.1 {
            // Avoid division by near-zero
            return (0.0, 0.0)
        }
        
        let ax = accel.x / accelMagnitude
        let ay = accel.y / accelMagnitude
        let az = accel.z / accelMagnitude
        
        // Calculate pitch (rotation around x-axis)
        // arcsin of negative y component of normalized acceleration
        let pitch = asin(-ay)
        
        // Calculate roll (rotation around z-axis)
        // arctan2 of x and z components of normalized acceleration
        let roll = atan2(ax, -az)
        
        return (pitch, roll)
    }
    
    // BASELINE 2: Calculate tilt using only gyroscope integration
    func updateGyroscopeTilt(gyro: SIMD3<Double>, deltaTime: TimeInterval) -> (Double, Double) {
        // Simple integration of angular rates
        // Note: This will drift over time without correction
        gyroPitch += gyro.x * deltaTime
        gyroRoll += gyro.y * deltaTime
        
        // Normalize angles to stay within -π to π range
        if gyroPitch > .pi {
            gyroPitch -= 2 * .pi
        } else if gyroPitch < -.pi {
            gyroPitch += 2 * .pi
        }
        
        if gyroRoll > .pi {
            gyroRoll -= 2 * .pi
        } else if gyroRoll < -.pi {
            gyroRoll += 2 * .pi
        }
        
        return (gyroPitch, gyroRoll)
    }
    
    // Save collected data to JSON file
    func saveDataToJSON() {
        guard !collectedData.isEmpty else {
            showAlert(title: "No Data", message: "No sensor data collected.")
            return
        }
        
        do {
            // Create JSON encoder
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            // Encode data to JSON
            let jsonData = try encoder.encode(collectedData)
            
            // Create a timestamp for the filename
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            
            // Get the document directory path
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                showAlert(title: "Error", message: "Could not access document directory.")
                return
            }
            
            // Create the file URL
            let fileURL = documentsDirectory.appendingPathComponent("sensor_data_\(timestamp)_\(currentAlgorithm).json")
            
            // Write JSON data to file
            try jsonData.write(to: fileURL)
            
            showAlert(title: "Data Saved", message: "Sensor data saved to: \(fileURL.lastPathComponent)")
            
            // Log file path
            NSLog("Data saved to: %@", fileURL.path)
            
        } catch {
            showAlert(title: "Error", message: "Failed to save data: \(error.localizedDescription)")
        }
    }
    
    // Show alert message
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // Update display only (no data collection)
    @objc func updateSensorDisplay() {
        if !isCollectingData, let accelData = self.motion.accelerometerData, let gyroData = self.motion.gyroData {
            // Calculate time delta
            let currentTime = CACurrentMediaTime()
            let deltaTime = currentTime - lastUpdateTime
            lastUpdateTime = currentTime
            
            // Get sensor data
            let accel = SIMD3<Double>(
                accelData.acceleration.x,
                accelData.acceleration.y,
                accelData.acceleration.z
            )
            
            let gyro = SIMD3<Double>(
                gyroData.rotationRate.x,
                gyroData.rotationRate.y,
                gyroData.rotationRate.z
            )
            
            // Get pitch and roll based on current algorithm
            var pitch: Double = 0.0
            var roll: Double = 0.0
            
            switch currentAlgorithm {
            case .accelerometerOnly:
                (pitch, roll) = calculateAccelerometerTilt(accel: accel)
            case .gyroscopeOnly:
                (pitch, roll) = updateGyroscopeTilt(gyro: gyro, deltaTime: deltaTime)
            case .complementaryFilter:
                // Update orientation
                updateOrientationFromGyro(gyro: gyro, deltaTime: deltaTime)
                correctTiltFromAccel(accel: accel)
                (pitch, roll) = extractPitchAndRoll()
            }
            
            // Update UI
            updateDisplay(accel: accelData.acceleration, gyro: gyroData.rotationRate, pitch: pitch, roll: roll)
        }
    }
    
    // Update UI display with sensor data
    func updateDisplay(accel: CMAcceleration, gyro: CMRotationRate, pitch: Double, roll: Double) {
        accel_x_text.text = String(format: "%2.3f", accel.x)
        accel_y_text.text = String(format: "%2.3f", accel.y)
        accel_z_text.text = String(format: "%2.3f", accel.z)
        gyro_x_text.text = String(format: "%2.3f", gyro.x)
        gyro_y_text.text = String(format: "%2.3f", gyro.y)
        gyro_z_text.text = String(format: "%2.3f", gyro.z)
        
        // Display calculated tilt (pitch and roll in degrees)
        pitch_text.text = String(format: "Pitch: %2.1f°", pitch * 180.0 / .pi)
        roll_text.text = String(format: "Roll: %2.1f°", roll * 180.0 / .pi)
        
        // Update the chartView
        updateChart(pitch: pitch, roll: roll)
    }
    
    // Old runloop function replaced by updateSensorDisplay and collectDataPoint
    @objc func runloop(){
        // This function is kept for backward compatibility
        // but functionality has been moved to updateSensorDisplay
        updateSensorDisplay()
    }
    
    // Step 1: Update orientation using gyroscope integration
    func updateOrientationFromGyro(gyro: SIMD3<Double>, deltaTime: TimeInterval) {
        // Calculate magnitude of angular velocity
        let gyroMagnitude = sqrt(gyro.x*gyro.x + gyro.y*gyro.y + gyro.z*gyro.z)
        
        // If rotation rate is negligible, skip update
        if gyroMagnitude < 0.001 {
            return
        }
        
        // Calculate rotation axis (normalized)
        let rotationAxis = SIMD3<Double>(
            gyro.x / gyroMagnitude,
            gyro.y / gyroMagnitude,
            gyro.z / gyroMagnitude
        )
        
        // Calculate rotation angle
        let rotationAngle = gyroMagnitude * deltaTime
        
        // Create rotation quaternion
        let rotationQuat = Quaternion.fromAxisAngle(axis: rotationAxis, angle: rotationAngle)
        
        // Update orientation: q[k+1] = q[k] * q(v, θ)
        currentOrientation = currentOrientation.multiply(rotationQuat).normalize()
    }
    
    // Step 2: Apply tilt correction from accelerometer data
    func correctTiltFromAccel(accel: SIMD3<Double>) {
        // Skip correction if acceleration is not close to gravity (during movement)
        let accelMagnitude = sqrt(accel.x*accel.x + accel.y*accel.y + accel.z*accel.z)
        if abs(accelMagnitude - 1.0) > 0.1 { // Check if magnitude is close to 1g
            return
        }
        
        // Normalize accelerometer reading
        let normalizedAccel = SIMD3<Double>(
            accel.x / accelMagnitude,
            accel.y / accelMagnitude,
            accel.z / accelMagnitude
        )
        
        // Transform accelerometer vector to global frame
        let globalAccel = currentOrientation.rotate(vector: normalizedAccel)
        
        // Reference "up" vector in global frame （opposite to gravity）
        let upVector = SIMD3<Double>(0, 0, -1)
        
        // Project globalAccel into XZ plane
        let accelXZ = SIMD3<Double>(globalAccel.x, 0, globalAccel.z)
        
        // Calculate tilt axis: t = (âz, 0, -âx)
        let tiltAxis = SIMD3<Double>(globalAccel.y, -globalAccel.x, 0)
        let tiltAxisMagnitude = sqrt(tiltAxis.x*tiltAxis.x + tiltAxis.y*tiltAxis.y + tiltAxis.z*tiltAxis.z)
        
        if tiltAxisMagnitude < 0.001 {
            return  // No significant tilt axis
        }
        
        // Normalize tilt axis
        let normalizedTiltAxis = SIMD3<Double>(
            tiltAxis.x / tiltAxisMagnitude,
            tiltAxis.y / tiltAxisMagnitude,
            tiltAxis.z / tiltAxisMagnitude
        )
        
        // Calculate tilt error angle φ (angle between globalAccel and upVector)
        let dotProduct = globalAccel.x * upVector.x + globalAccel.y * upVector.y + globalAccel.z * upVector.z
        let tiltErrorAngle = acos(max(-1.0, min(1.0, dotProduct)))
        
        // Create correction quaternion: q(t, -αφ)
        let correctionQuat = Quaternion.fromAxisAngle(
            axis: normalizedTiltAxis,
            angle: -alpha * tiltErrorAngle
        )
        
        // Apply correction: q'[k] = q(t, -αφ) * q[k]
        currentOrientation = correctionQuat.multiply(currentOrientation).normalize()
    }
    
    // Extract pitch and roll angles from quaternion - CORRECTLY FIXED VERSION
    func extractPitchAndRoll() -> (Double, Double) {
        // Reference vectors in sensor frame
        let forwardVector = SIMD3<Double>(0, 0, 1)  // Initially pointing along z-axis
        
        // Transform forward vector using current orientation
        let rotatedForward = currentOrientation.rotate(vector: forwardVector)
        
        // Calculate pitch (rotation around x-axis)
        let pitch = asin(-rotatedForward.y)
        
        // For roll calculation, we need to consider the projection of rotated forward vector
        // onto the xz-plane and its angle with the z-axis
        let roll = atan2(rotatedForward.x, rotatedForward.z)
        
        return (pitch, roll)
    }
}
