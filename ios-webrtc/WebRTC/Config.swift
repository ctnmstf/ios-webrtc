//
//  Config.swift
//  ios-webrtc
//
//  Created by devmc on 24.08.2024.
//

import Foundation

private let defaultIceServers = [
    "stun:stun.l.google.com:19302",
    "stun:stun1.l.google.com:19302",
    "stun:stun2.l.google.com:19302",
    "stun:stun3.l.google.com:19302",
    "stun:stun4.l.google.com:19302"
]

struct Config {
    static let `default` = Config(webRTCIceServers: defaultIceServers)
    let webRTCIceServers: [String]
}
