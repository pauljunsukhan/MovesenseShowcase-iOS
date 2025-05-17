# TODO: Implement MAX3000x Register Configuration in Movesense Showcase iOS App

This document outlines the necessary investigation and implementation steps to allow the Movesense Showcase iOS app to configure MAX3000x registers directly, replicating the functionality of the provided `wbcmd` script for EEG-friendly setup.

## I. Core `MovesenseApi.framework` Investigation

The primary task is to understand how to use the Swift `MovesenseApi.framework` to send low-level `PUT` requests to the `/Component/MAX3000x/Register` and `/Component/MAX3000x/Command` paths with specific binary payloads.

Refer to the Movesense developer documentation, specifically any details on the Swift API for advanced requests or direct Whiteboard path interaction. The provided "Write or read to the chipset registers directly" documentation snippet (showing C++ `asyncPut` with multiple parameters) is a key reference.

### 1. Resource Path Specification:
   - **Action:** Determine how to specify the literal string paths `/Component/MAX3000x/Register` and `/Component/MAX3000x/Command` when creating a `MovesenseRequest`.
   - **Questions to Answer:**
     - Can `MovesenseResourceType` be initialized from a raw string (e.g., `MovesenseResourceType(rawValue: "/Component/MAX3000x/Register")`)?
     - Is there a generic `MovesenseResourceType` case (e.g., `.customPath(String)`)?
     - Does the `MovesenseDevice.sendRequest(...)` method (or a similar one) accept a raw string path directly, bypassing `MovesenseResourceType` if it's too restrictive?
   - **==ANSWERS:==**
     - **Primary Method:** The `MovesenseApi.framework` represents resources via the `MovesenseResource` class. A `MovesenseDevice` instance contains `device.resources: [MovesenseResource]`. To get the `MovesenseResourceType` for a specific path like `/Component/MAX3000x/Register`:
       1. Connect to the Movesense device.
       2. Iterate through the `device.resources` array.
       3. Find the `MovesenseResource` object where its `path: String` property matches the target path (e.g., `"/Component/MAX3000x/Register"`).
       4. Use the `resourceType: MovesenseResourceType` property from this found `MovesenseResource` object in your `MovesenseRequest`.
     - **Direct Initialization of `MovesenseResourceType`:**
       - The Showcase codebase does not show `MovesenseResourceType` being initialized directly from a raw string or a generic `.customPath(String)` case. Relying on discovering the resource from `device.resources` is the documented and observed pattern.
     - **Raw String Path in `sendRequest`:** The standard `MovesenseDevice.sendRequest(...)` requires a `MovesenseRequest` object, which in turn needs a `MovesenseResourceType`. No alternative methods accepting raw string paths directly are evident in the Showcase app's usage.

### 2. Constructing the `PUT` Request Payload (Parameters/Body):
   - **Action:** Figure out how to structure the `MovesenseRequest` (or the parameters passed to `sendRequestForDevice`) to correctly form the binary payload for the `PUT` requests.
   - **Reference `wbcmd` script:**
     - For `/Component/MAX3000x/Register`: `--op PUT --opdatatype uint8 <reg_addr> --opdatatype uint32 <reg_val>`
     - For `/Component/MAX3000x/Command`: `--op PUT --opdatatype uint8 <command_val>`
   - **Questions to Answer (referencing C++ `asyncPut(..., registerAddress, value);` as a hint):**
     - How are multiple, ordered, typed parameters (like `registerAddress` (UInt8) and `value` (UInt32) for the register path, or a single `commandByte` (UInt8) for the command path) passed to the Swift API's equivalent of `asyncPut`?
     - Does `MovesenseRequestParameter` have initializers for basic types like `UInt8`, `UInt32` that the `MovesenseApi` will serialize in the correct order to form the request body?
     - Can `MovesenseRequestParameter` encapsulate a raw `Data` object that represents the pre-formatted binary payload (e.g., `address_byte + value_bytes`)? If so, what's the correct byte order (endianness) expected by the MAX3000x/Whiteboard? (Assume Big Endian for multi-byte values unless specified otherwise).
     - Does `MovesenseRequest` have a separate property for a `Data` body, distinct from its `parameters` array (which might be for URL query parameters)?
     - How does the Swift API map to the concept of `--opdatatype` used by `wbcmd`?
   - **==ANSWERS (Revised based on C++ `asyncPut` examples, API reference, `wbcmd` usage, and analysis of MovesenseShowcase-iOS structure):==**
     - **Ordered, Typed Parameters & `MovesenseRequestParameter` Creation for `PUT` Body (e.g., for `/Component/MAX3000x/Register`):**
       - The C++ examples (`asyncPut(RES_ID, opts, registerAddress, value);`) and `wbcmd` usage (`--opdatatype uint8 <addr> --opdatatype uint32 <val>`) strongly confirm that parameters for paths like `/Component/MAX3000x/Register` are an ordered sequence of typed primitive values forming the request body.
       - **Primary Mechanism (Deduced for Swift):**
         1.  **Obtain `MovesenseResource`:** Get the `MovesenseResource` instance for the target path (e.g., `"/Component/MAX3000x/Register"`) from the connected `MovesenseDevice`'s `resources` array.
         2.  **Use `MovesenseResource` to Create Parameters with Values:** The `MovesenseResource` object, knowing its own schema (from its YAML, defining expected parameter types and order for `PUT` bodies), is responsible for creating the `[MovesenseRequestParameter]` array from your Swift primitive values.
             - It is strongly inferred that `MovesenseResource` in Swift provides a method to generate each `MovesenseRequestParameter` correctly from your Swift primitive values (e.g., `UInt8`, `UInt32`), respecting the schema's order and type requirements.
             - **Conceptual Swift Implementation (to be verified by developer by inspecting `MovesenseResource` public interface in Xcode):**
               ```swift
               // Example for /Component/MAX3000x/Register (schema: UInt8 address, UInt32 value)
               // Assuming 'maxRegisterResource' is the MovesenseResource for this path.
               // The method name 'parameterForSchemaWithValue' is hypothetical.

               guard let addressParam = maxRegisterResource.parameterForSchemaWithValue(index: 0, value: yourRegisterAddressUInt8),
                     let valueParam = maxRegisterResource.parameterForSchemaWithValue(index: 1, value: yourRegisterValueUInt32) else {
                   // Handle error: parameter creation failed
                   return
               }
               let requestParameters = [addressParam, valueParam]

               // Example for /Component/MAX3000x/Command (schema: UInt8 command)
               // Assuming 'maxCommandResource' is the MovesenseResource for this path.
               guard let commandParam = maxCommandResource.parameterForSchemaWithValue(index: 0, value: yourCommandUInt8) else {
                   // Handle error
                   return
               }
               let requestParametersForCommand = [commandParam]
               ```
             - The `MovesenseApi.framework` (via `MovesenseResource`) handles serializing these Swift values into the `MovesenseRequestParameter` objects with correct Whiteboard types (e.g., `uint8`, `uint32`) and endianness (typically Big Endian for multi-byte register values unless specified otherwise by Movesense).
         3.  The `parameters` array in the `MovesenseRequest` object will then be this generated `[requestParameters]` array for the request body.
     - **Raw `Data` Object:** Direct construction of a raw `Data` object by the app for the request body is less likely if the API provides schema-aware parameter creation through `MovesenseResource`. The typed approach is safer.
     - **`MovesenseRequest.object: Any?` vs. `parameters: [MovesenseRequestParameter]?`:**
       - The `object: Any?` field in `MovesenseRequest` is typically used when the *entire* request body is a single, complex Swift object that the API knows how to serialize (e.g., sending a complete `AccConfig` struct to `/Meas/Acc/Config`).
       - For paths like `/Component/MAX3000x/Register` that expect a sequence of distinct primitive parameters in the body (not a single container object), the `parameters: [MovesenseRequestParameter]?` array is used, constructed as described above.
     - **Direct `MovesenseRequestParameter(value: ...)` Initializer:** Grep searches of the Showcase codebase did not find common usage of this direct initializer for constructing sequenced, typed `PUT` request bodies. Its use, if any, might be for simpler cases like single query parameters rather than ordered body parameters.
     - **`movesenseResource.requestParameter(index: Int)` (as seen in `DashboardContainerViewModel`):** This method appears to retrieve a parameter *definition* or *template* based on its index in the resource's schema, likely for path parameters (e.g., `SampleRate` in `/Meas/ECG/{SampleRate}`) or for understanding parameter requirements, rather than directly creating a parameter instance with an assigned value for a `PUT` body from a Swift variable.
     - **Mapping `--opdatatype`:** This is handled implicitly by `MovesenseResource` when it creates the `MovesenseRequestParameter` from your Swift value and its schema knowledge.

### 3. Finding the Correct API Call:
   - **Action:** Identify the precise Swift function in `MovesenseApi.framework` for sending these `PUT` requests.
   - **Questions to Answer:**
     - Is it `MovesenseDevice.sendRequest(MovesenseRequest, observer: Observer?)`?
     - Is there a more specialized version for `PUT` operations with custom data, or for non-standard paths?
   - **==ANSWERS:==**
     - **`MovesenseDevice.sendRequest(MovesenseRequest, observer: MovesenseObserver?) -> MovesenseOperation?` is the standard and correct API call.**
     - The Showcase app uses this method (or the `Movesense.api.sendRequestForDevice(...)` wrapper) for all its interactions, including `PUT` operations for configurations (e.g., `AccConfig`, `GyroConfig`).
     - There is no evidence in the Showcase app of a more specialized API call for this purpose. The existing method is designed to be generic enough to handle any valid `MovesenseRequest`.

## II. Implementation Strategy

### 1. Create a Dedicated Service/Helper:
   - **Action:** Develop a new Swift class or extension (e.g., `MAX3000xProgrammer.swift` or similar) to encapsulate the logic for these register writes and commands.
   - **Rationale:** Keeps low-level control separate from existing ViewModels.

### 2. Implement and Test Incrementally:
   - **Action:** Start by implementing a single `wbcmd` line from the script.
     - **Priority 1:** Write to `/Component/MAX3000x/Register`. Example:
       `wbcmd --path Component/MAX3000x/Register --op PUT --opdatatype uint8 0x10 --opdatatype uint32 0x081007`
     - **Priority 2:** Write to `/Component/MAX3000x/Command`. Example:
       `wbcmd --path Component/MAX3000x/Command --op PUT --opdatatype uint8 0x00`
   - **Verification:**
     - After a `PUT`, attempt a `GET` request to the same register path to read back the value and confirm it was written correctly.
       - `wbcmd --path Component/MAX3000x/Register --op GET --opdatatype uint8 <reg_addr>`
     - Observe sensor behavior if applicable (though this might be harder to quantify initially).

### 3. Full Script Implementation:
   - **Action:** Once individual commands are working, implement functions in your helper class to execute the entire sequence from the provided EEG setup script:
     - `CNFG_GEN (0x10) = 0x081007`
     - `CNFG_EMUX (0x14) = 0x0B0000`
     - `CNFG_ECG (0x15) = 0x90DC00`
     - `Command SYNCH (0x00)`
     - `Command FIFO_RST (0x0A)`

## III. Handling Responses and Errors

   - **Action:** Properly handle callbacks and responses from the `MovesenseApi` calls.
   - **Considerations:**
     - Check for success (e.g., HTTP 200 OK) or error codes.
     - Log relevant information for debugging.
     - Provide feedback to the user/app if a command fails.

## IV. Firmware and Persistence Considerations

   - **Action:** Confirm that the Movesense device firmware being used:
     - Exposes `/Component/MAX3000x/Register` and `/Component/MAX3000x/Command`.
     - Allows `PUT` operations on these paths from a connected BLE client. (The Movesense documentation suggests this is standard).
   - **Note on Persistence (as per user's script notes):**
     - Runtime changes made via these commands are likely volatile (i.e., will not survive a battery pull or sensor reset).
     - For persistent settings, the device firmware itself needs to be modified to apply these register values during its initialization sequence (e.g., in `Max3000x::init()`). This task is separate from the iOS app implementation but crucial for a robust solution.

## V. Subscribing to ECG Data Post-Configuration
   - **Action:** After successfully sending the configuration commands, ensure the app can subscribe to `/Meas/ECG/256` (or the configured sample rate) to stream and verify the EEG data. This part should leverage existing data subscription mechanisms in the Showcase app. 