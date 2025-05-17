# MAX3000x Configuration with `MAX3000xProgrammer.swift`

This document outlines the capabilities of the `MAX3000xProgrammer.swift` module for configuring the MAX3000x series analog front-end (AFE) on ECG-capable Movesense sensors. It provides guidance on how to use this module to adjust sensor settings for specific bio-potential measurements, with a primary focus on achieving an Electroencephalography (EEG)-friendly state. The principles can be adapted for other measurements like surface Electromyography (sEMG).

## I. `MAX3000xProgrammer.swift` Capabilities

The `MAX3000xProgrammer.swift` module provides a high-level Swift interface to directly write to MAX3000x registers, read from them, and send commands to the AFE. This allows for fine-grained control and verification of the sensor's analog and digital signal processing chain from an iOS application.

**Core Functionality:**

*   **`writeRegister(device: MovesenseDevice, address: UInt8, value: UInt32, completion: @escaping (Result<Void, MAX3000xError>) -> Void)`:**
    *   Allows writing a 32-bit `value` to a specific 8-bit register `address` on the MAX3000x chip of the connected `device`.
    *   Used for setting configuration registers like `CNFG_GEN`, `CNFG_ECG`, `CNFG_EMUX`.
*   **`readRegister(device: MovesenseDevice, address: UInt8, completion: @escaping (Result<UInt32, MAX3000xError>) -> Void)`:**
    *   Allows reading a 32-bit value from a specific 8-bit register `address` on the MAX3000x chip.
    *   Useful for verifying that register writes were successful.
*   **`sendCommand(device: MovesenseDevice, command: UInt8, completion: @escaping (Result<Void, MAX3000xError>) -> Void)`:**
    *   Allows sending an 8-bit `command` (e.g., `SYNCH`, `FIFO_RST`) to the MAX3000x chip.
*   **`configureForEEG(device: MovesenseDevice, completion: @escaping (Result<Void, MAX3000xError>) -> Void)`:**
    *   A pre-defined convenience method that executes the specific sequence for an EEG-friendly setup (detailed below).

**Underlying Mechanism:**
The module uses direct calls to `MDSWrapper.sharedInstance().doPut(...)`, passing parameters as an unnamed JSON array in the `contract` argument. This aligns with the Movesense iOS SDK's method for handling positional parameters for these generic component paths.

## II. Configuring MAX3000x for EEG Measurements

The following recipe configures the Movesense sensor with MAX30003 AFE into an EEG-friendly state. This typically involves setting appropriate gain, sample rate, and filter cutoffs.

### 1. EEG Configuration Register Values

| Register        | Address | Value      | Key Settings & Rationale for EEG                                                                                                     |
| :-------------- | :------ | :--------- | :----------------------------------------------------------------------------------------------------------------------------------- |
| `CNFG_GEN`      | `0x10`  | `0x081007` | Enables ECG channel (`EN_ECG=1`), sets master clock frequency (`FMSTR=01` for ~500kHz, allowing 256 sps decimation).                      |
| `CNFG_EMUX`     | `0x14`  | `0x0B0000` | Connects `ECGP`/`ECGN` to AFE inputs, disconnects internal self-test calibration voltages to ensure clean signal path.                   |
| `CNFG_ECG`      | `0x15`  | `0x90DC00` | Sets GAIN=12×, RATE=256 sps, DHPF=1 (HPF ≈0.25 Hz to remove DC drift), DLPF=1 (analog LPF ≈40 Hz to reduce EMG/mains noise). |
| `SYNCH` Command | N/A     | `0x00`     | Synchronizes internal timing of the MAX3000x AFE to apply new settings cleanly.                                               |
| `FIFO_RST` Cmd  | N/A     | `0x0A`     | Resets the AFE's data FIFO, ensuring data stream starts fresh post-configuration.                                                   |

*Note: For EEG, a gain of 12× provides an LSB of approximately 0.42 µV. Data is typically 18-bit left-justified when read from `/Meas/ECG/256`.*

### 2. Using `MAX3000xProgrammer.swift` for EEG Setup

The `configureForEEG` method directly implements the sequence above:

```swift
import MovesenseShowcase // Or your app's module
// Assuming 'connectedDevice' is your MovesenseDevice instance
// Assuming 'maxProgrammer' is an instance of MAX3000xProgrammer

maxProgrammer.configureForEEG(device: connectedDevice) { result in
    switch result {
    case .success:
        print("Successfully configured MAX3000x for EEG.")
        // You can now subscribe to /Meas/ECG/256 to start streaming EEG data
        // e.g., using Movesense.api.subscribe(...) or equivalent
    case .failure(let error):
        print("Failed to configure MAX3000x for EEG: \\(error)")
    }
}
```

If you need to set these registers individually or in a different order, you can use the `writeRegister` and `sendCommand` methods directly:

```swift
let cnfGenAddress: UInt8 = 0x10
let cnfGenValue: UInt32 = 0x081007

let cnfEmuxAddress: UInt8 = 0x14
let cnfEmuxValue: UInt32 = 0x0B0000

let cnfEcgAddress: UInt8 = 0x15
let cnfEcgValueForEEG: UInt32 = 0x90DC00

let synchCommand: UInt8 = 0x00
let fifoRstCommand: UInt8 = 0x0A

// Execute sequentially, handling completion/errors for each step
maxProgrammer.writeRegister(device: connectedDevice, address: cnfGenAddress, value: cnfGenValue) { /* ... */ }
// ... then CNFG_EMUX, then CNFG_ECG, then SYNCH, then FIFO_RST ...

// Example of reading back a register to verify:
maxProgrammer.readRegister(device: connectedDevice, address: cnfEcgAddress) { result in
    switch result {
    case .success(let readValue):
        if readValue == cnfEcgValueForEEG {
            print("CNFG_ECG (0x15) successfully written and verified: 0x\\(String(format: "%08X", readValue))")
        } else {
            print("CNFG_ECG (0x15) verification failed. Read: 0x\\(String(format: "%08X", readValue)), Expected: 0x\\(String(format: "%08X", cnfEcgValueForEEG))")
        }
    case .failure(let error):
        print("Failed to read CNFG_ECG (0x15): \\(error)")
    }
}
```

### 3. Verification and Persistence

*   **Read-back:** Use the `maxProgrammer.readRegister(...)` method to verify that settings have been correctly written to the chip after a `writeRegister` call. This is crucial for debugging and ensuring configuration integrity.
*   **Data Streaming:** After configuration, subscribe to `/Meas/ECG/256` (or the configured sample rate) and observe the data. For EEG, you might look for alpha waves (~10 Hz, ~10 µV peak-to-peak) with eyes closed.
*   **Persistence:** Settings applied via `MAX3000xProgrammer.swift` are volatile and will be lost on battery pull or sensor reset. For persistent settings, the MAX3000x initialization values in the Movesense device firmware (e.g., in `Max3000x::init()` within `components/system/max3000x/Max3000xRegisters.h` of `movesense-device-library`) must be modified, and the firmware rebuilt and flashed to the sensor.

## III. Adapting for Other Measurements (e.g., sEMG)

The same `MAX3000xProgrammer.swift` module can be used to configure the AFE for other bio-potential measurements like sEMG by writing different values to the MAX3000x registers, primarily `CNFG_ECG (0x15)`.

**Key parameters to adjust for sEMG:**

*   **Sample Rate (`RATE` in `CNFG_ECG`):** ≥512 sps (e.g., `100` for 512 sps).
*   **Gain (`GAIN` in `CNFG_ECG`):** ×3 to ×6 to accommodate larger sEMG signal amplitudes (e.g., `010` for ×3).
*   **Low-Pass Filter (`DLPF` in `CNFG_ECG`):** 150 Hz (`10`) or bypass, matching typical sEMG bandwidth.
*   **High-Pass Filter (`DHPF` in `CNFG_ECG`):** 10–20 Hz (e.g., `11` for ~20 Hz) to reduce motion artifacts and ECG bleed-through.

**Example `CNFG_ECG` value for an sEMG setup (Gain ×3, 512sps, HPF≈20Hz, LPF≈150Hz): `0x48FC00`**

To apply this for sEMG:
```swift
let cnfEcgAddress: UInt8 = 0x15
let cnfEcgValueForSEMG: UInt32 = 0x48FC00

maxProgrammer.writeRegister(device: connectedDevice, address: cnfEcgAddress, value: cnfEcgValueForSEMG) { result in
    // ... handle result, then send SYNCH and FIFO_RST commands ...
}
```

Always consult the MAX30003 datasheet for detailed register maps and bit field definitions when calculating custom register values.

## IV. Important Considerations

*   **Threading:** Completion handlers from `MAX3000xProgrammer` methods are executed on a background queue by the MDSWrapper. If you need to update UI elements from these completion handlers, ensure you dispatch those updates to the main queue:
    ```swift
    DispatchQueue.main.async {
        // Update your UI here
    }
    ```
*   **Error Handling:** Robustly check the `Result` in completion handlers to manage any errors during communication or configuration.
*   **Sensor State:** Always ensure the `MovesenseDevice` is connected (`device.isConnected`) before attempting to send commands or write/read registers.

By using `MAX3000xProgrammer.swift`, developers can directly control the MAX3000x AFE from iOS, enabling customized configurations for various advanced bio-potential sensing applications. 