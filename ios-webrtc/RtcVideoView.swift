//
//  RtcVideoView.swift
//  ios-webrtc
//
//  Created by devmc on 24.08.2024.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
struct RtcVideoView: UIViewRepresentable {
    
    let containerSize: CGSize
    let rtcViewInit: (UIView, CGSize) -> UIView
    var isMirror: Bool = false
    
    init(containerSize: CGSize, rtcViewInit: @escaping (UIView, CGSize) -> UIView, isMirror: Bool) {
        self.containerSize = containerSize
        self.rtcViewInit = rtcViewInit
        self.isMirror = isMirror
    }

    func makeUIView(context: Context) -> UIView {
        let uiView = UIView()
        let rtcView = rtcViewInit(uiView, containerSize)
        if isMirror {
            rtcView.transform = CGAffineTransform(scaleX: -1.0, y: 1.0)
        }
        return rtcView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let rtcView = rtcViewInit(uiView, containerSize)
        if isMirror {
            rtcView.transform = CGAffineTransform(scaleX: -1.0, y: 1.0)
        } else {
            rtcView.transform = .identity
        }
    }
}
