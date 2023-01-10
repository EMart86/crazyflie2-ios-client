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

enum CrazyFlieHeader: UInt8 {
    case commander = 0x30
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
    private(set) var bluetoothLink:BluetoothLink!

    var commander: CrazyFlieCommander?
    
    init(bluetoothLink:BluetoothLink? = BluetoothLink(), delegate: CrazyFlieDelegate?) {
        
        state = .idle
        self.delegate = delegate
        
        self.bluetoothLink = bluetoothLink
        super.init()
    
        bluetoothLink?.onStateUpdated { [weak self] (state) in
            guard let self = self else { return }
            switch state {
            case "idle":
                self.state = .idle
            case "connected":
                self.state = .connected
            case "scanning":
                self.state = .scanning
            case "connecting":
                self.state = .connecting
            case "services":
                self.state = .services
            case "characteristics":
                self.state = .characteristics
            default:
                break
            }
        }
    }
    
    func connect(_ callback:((Bool) -> Void)?) {
        guard state == .idle else {
            self.disconnect()
            return
        }
        
        self.bluetoothLink.connect(nil, callback: {[weak self] (connected) in
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
                    title = "Error"
                    body = self?.bluetoothLink.getError()
                }
                
                self?.delegate?.didFail(with: title, message: body)
                return
            }
            
            self?.startTimer()
        })
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
    
    @objc
    private func updateData(timer: Timer) {
        guard let commander = commander else {
            return
        }

        commander.prepareData()
        sendFlightData(commander.roll, pitch: commander.pitch, thrust: commander.thrust, yaw: commander.yaw)
    }
    
    private func sendFlightData(_ roll:Float, pitch:Float, thrust:Float, yaw:Float) {
        let commandPacket = CommanderPacket(header: CrazyFlieHeader.commander.rawValue, roll: roll, pitch: pitch, yaw: yaw, thrust: UInt16(thrust))
        let data = CommandPacketCreator.data(from: commandPacket)
        bluetoothLink.sendPacket(data!, callback: nil)
        print("pitch: \(pitch) roll: \(roll) thrust: \(thrust) yaw: \(yaw)")
    }
}
