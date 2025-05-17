import Foundation
import MovesenseApi // For MovesenseDevice, DeviceConnectionState
import MovesenseMds // For MDSWrapper

enum MAX3000xError: Error {
    case mdsError(Error)
    case deviceNotConnected
    case responseError(statusCode: Int, message: String)
    case unknownError(String)
}

// Internal helper for direct MDS calls
private enum MAX3000xMdsWriter {
    private static let registerBasePath = "/Component/MAX3000x/Register"
    private static let commandBasePath = "/Component/MAX3000x/Command"

    static func writeRegister(deviceSerial: String, address: UInt8, value: UInt32,
                              completion: @escaping (MAX3000xError?) -> Void) {
        let paramsArray: [Any] = [NSNumber(value: Int(address)),
                                  NSNumber(value: Int(value))]
        let fullPath = "/\(deviceSerial)\(registerBasePath)"

        MDSWrapper.shared.doPut(fullPath, contract: paramsArray) { response in
            if response.statusCode == 200 {
                completion(nil)
            } else {
                let errorMsg = String(data: response.bodyData, encoding: .utf8) ?? "Unknown MDS error"
                completion(.responseError(statusCode: response.statusCode, message: errorMsg))
            }
        }
    }

    static func readRegister(deviceSerial: String, address: UInt8,
                             completion: @escaping (Result<UInt32, MAX3000xError>) -> Void) {
        let paramsArray: [Any] = [NSNumber(value: Int(address))]
        let fullPath = "/\(deviceSerial)\(registerBasePath)"

        MDSWrapper.shared.doGet(fullPath, contract: paramsArray) { response in
            if response.statusCode == 200 {
                if let body = response.bodyDictionary, let params = body["Parameters"] as? [NSNumber], params.count == 2 {
                    completion(.success(params[1].uint32Value))
                } else if let directArray = response.bodyDictionary?.values.first as? [NSNumber], directArray.count == 2 {
                    completion(.success(directArray[1].uint32Value))
                } else if let directArrayFromData = try? JSONSerialization.jsonObject(with: response.bodyData, options: []) as? [NSNumber], directArrayFromData.count == 2 {
                    completion(.success(directArrayFromData[1].uint32Value))
                } else {
                    let errorMsg = "Failed to parse register value array from response. BodyDict: \(response.bodyDictionary ?? [:]), BodyData: \(String(data: response.bodyData, encoding: .utf8) ?? "Non-UTF8 data")"
                    completion(.failure(.responseError(statusCode: response.statusCode, message: errorMsg)))
                }
            } else {
                let errorMsg = String(data: response.bodyData, encoding: .utf8) ?? "Unknown MDS error"
                completion(.failure(.responseError(statusCode: response.statusCode, message: errorMsg)))
            }
        }
    }

    static func sendCommand(deviceSerial: String, command: UInt8,
                            completion: @escaping (MAX3000xError?) -> Void) {
        let paramsArray: [Any] = [NSNumber(value: Int(command))]
        let fullPath = "/\(deviceSerial)\(commandBasePath)"

        MDSWrapper.shared.doPut(fullPath, contract: paramsArray) { response in
            if response.statusCode == 200 {
                completion(nil)
            } else {
                let errorMsg = String(data: response.bodyData, encoding: .utf8) ?? "Unknown MDS error"
                completion(.responseError(statusCode: response.statusCode, message: errorMsg))
            }
        }
    }
}

class MAX3000xProgrammer {

    // Note: Movesense.api is not used here as we are making direct MDSWrapper calls.

    // MARK: - Public API

    /// Writes a 32-bit value to a specific register on the MAX3000x chip.
    func writeRegister(device: MovesenseDevice,
                       address: UInt8,
                       value: UInt32,
                       completion: @escaping (Result<Void, MAX3000xError>) -> Void) {

        guard device.isConnected else {
            completion(.failure(.deviceNotConnected))
            return
        }

        MAX3000xMdsWriter.writeRegister(deviceSerial: device.serialNumber, address: address, value: value) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    /// Reads a 32-bit value from a specific register on the MAX3000x chip.
    func readRegister(device: MovesenseDevice,
                      address: UInt8,
                      completion: @escaping (Result<UInt32, MAX3000xError>) -> Void) {
        guard device.isConnected else {
            completion(.failure(.deviceNotConnected))
            return
        }

        MAX3000xMdsWriter.readRegister(deviceSerial: device.serialNumber, address: address, completion: completion)
    }

    /// Sends an 8-bit command to the MAX3000x chip.
    func sendCommand(device: MovesenseDevice,
                     command: UInt8,
                     completion: @escaping (Result<Void, MAX3000xError>) -> Void) {

        guard device.isConnected else {
            completion(.failure(.deviceNotConnected))
            return
        }

        MAX3000xMdsWriter.sendCommand(deviceSerial: device.serialNumber, command: command) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    /// Executes the EEG setup sequence by writing to predefined registers and sending commands.
    func configureForEEG(device: MovesenseDevice,
                         completion: @escaping (Result<Void, MAX3000xError>) -> Void) {
        // Sequence:
        // 1. CNFG_GEN (0x10) = 0x081007
        // 2. CNFG_EMUX (0x14) = 0x0B0000
        // 3. CNFG_ECG (0x15) = 0x90DC00
        // 4. Command SYNCH (0x00)
        // 5. Command FIFO_RST (0x0A)

        writeRegister(device: device, address: 0x10, value: 0x081007) { [weak self] result in
            guard self != nil else { return }
            switch result {
            case .success:
                self?.writeRegister(device: device, address: 0x14, value: 0x0B0000) { [weak self] result in
                    guard self != nil else { return }
                    switch result {
                    case .success:
                        self?.writeRegister(device: device, address: 0x15, value: 0x90DC00) { [weak self] result in
                            guard self != nil else { return }
                            switch result {
                            case .success:
                                self?.sendCommand(device: device, command: 0x00) { [weak self] result in // SYNCH
                                    guard self != nil else { return }
                                    switch result {
                                    case .success:
                                        self?.sendCommand(device: device, command: 0x0A) { result in // FIFO_RST
                                            completion(result)
                                        }
                                    case .failure(let error):
                                        completion(.failure(error))
                                    }
                                }
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
} 