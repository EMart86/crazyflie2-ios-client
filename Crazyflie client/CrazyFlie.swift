//
//  CrazyFlie.swift
//  Crazyflie client
//
//  Created by Martin Eberl on 15.07.16.
//  Copyright © 2016 Bitcraze. All rights reserved.
//

import UIKit

protocol CrazyFlieCommander {
    var pitch: Float { get }
    var roll: Float { get }
    var thrust: Float { get }
    var yaw: Float { get }
    
    func prepareData()
}

protocol CrazyFlieTocRequester {
    func request()
}

protocol CrazyFlieTocLogRequester {
    func request()
}

enum TocDatatype: UInt8 {
    case uint8_t = 0x01
    case uint16_t = 0x02
    case uint32_t = 0x03
    case int8_t = 0x04
    case int16_t = 0x05
    case int32_t = 0x06
    case float = 0x07
    case FP16 = 0x08
}

/*types = {0x01: ("uint8_t",  '<B', 1),
    0x02: ("uint16_t", '<H', 2),
    0x03: ("uint32_t", '<L', 4),
    0x04: ("int8_t",   '<b', 1),
    0x05: ("int16_t",  '<h', 2),
    0x06: ("int32_t",  '<i', 4),
    0x08: ("FP16",     '<h', 2),
    0x07: ("float",    '<f', 4)}
*/

enum CrazyFlieHeader: UInt8 {
    case console = 0x00
    case parameter = 0x20
    case commander = 0x30
    case memory = 0x40
    case logging = 0x50
    case platform = 0x13
}




enum CrazyFlieState {
    case idle, connected , scanning, connecting, services, characteristics
}

protocol CrazyFlieDelegate {
    func didSend()
    func didUpdate(state: CrazyFlieState)
    func didFail(with title: String, message: String?)
}

open class CrazyFlie: NSObject {
    
    private(set) var state:CrazyFlieState {
        didSet {
            delegate?.didUpdate(state: state)
        }
    }
    private var timer:Timer?
    private var delegate: CrazyFlieDelegate?
    private(set) var bluetoothLink: BluetoothLink

    var commander: CrazyFlieCommander?
    var tocRequester: CrazyFlieTocRequester?
    
    init(bluetoothLink:BluetoothLink = BluetoothLink(), delegate: CrazyFlieDelegate?) {
        
        state = .idle
        self.delegate = delegate
        
        self.bluetoothLink = bluetoothLink
        self.tocRequester = TocRequester(bluetoothLink: bluetoothLink)
        super.init()
    
        bluetoothLink.onStateUpdated{[weak self] (state) in
            if state.isEqual(to: "idle") {
                self?.state = .idle
            } else if state.isEqual(to: "connected") {
                self?.state = .connected
            } else if state.isEqual(to: "scanning") {
                self?.state = .scanning
            } else if state.isEqual(to: "connecting") {
                self?.state = .connecting
            } else if state.isEqual(to: "services") {
                self?.state = .services
            } else if state.isEqual(to: "characteristics") {
                self?.state = .characteristics
            }
        }
        
        startTimer()
    }
    
    func connect(_ callback:((Bool) -> Void)?) {
        guard state == .idle else {
            disconnect()
            return
        }
        
        bluetoothLink.connect(nil, callback: {[weak self] (connected) in
            callback?(connected)
            guard connected else {
                if self?.timer != nil {
                    self?.timer?.invalidate()
                    self?.timer = nil
                }
                
                var title:String
                var body:String?
                
                // Find the reason and prepare a message
                if self?.bluetoothLink.getError() == "Bluetooth disabled" {
                    title = "Bluetooth disabled"
                    body = "Please enable Bluetooth to connect a Crazyflie"
                } else if self?.bluetoothLink.getError() == "Timeout" {
                    title = "Connection timeout"
                    body = "Could not find Crazyflie"
                } else {
                    title = "Error";
                    body = self?.bluetoothLink.getError()
                }
                
                self?.delegate?.didFail(with: title, message: body)
                return
            }
            
            self?.startTimer()
            self?.setTocReadRequest()
        })
        
        setTocReadRequest()
    }
    
    func disconnect() {
        bluetoothLink.disconnect()
        stopTimer()
    }
    
    // MARK: - Private Methods
    
    private func startTimer() {
        stopTimer()
        
        self.timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(self.updateData), userInfo:nil, repeats:true)
    }
    
    private func stopTimer() {
        if timer != nil {
            timer?.invalidate()
            timer = nil
        }
    }
    
    @objc private func updateData(_ timter:Timer){
        guard timer != nil, let commander = commander else {
            return
        }

        commander.prepareData()
        sendFlightData(commander.roll, pitch: commander.pitch, thrust: commander.thrust, yaw: commander.yaw)
    }
    
    private func sendFlightData(_ roll:Float, pitch:Float, thrust:Float, yaw:Float) {
        let commandPacket = CommanderPacket(header: CrazyFlieHeader.commander.rawValue, roll: roll, pitch: pitch, yaw: yaw, thrust: UInt16(thrust))
        let data = PacketCreator.data(fromCommander: commandPacket)
        bluetoothLink.sendPacket(data!, callback: nil)
    }
    
    private func setTocReadRequest() {
        tocRequester?.request()
    }
}
