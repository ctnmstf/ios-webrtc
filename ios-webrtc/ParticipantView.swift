//
//  ParticipantView.swift
//  ios-webrtc
//
//  Created by devmc on 24.08.2024.
//

import Foundation
import SwiftUI

struct ParticipantView: View {
    
    @StateObject var viewModel: ParticipantViewModel
    @State var connectionState: WebRTCManager.webRTCManagerConnectionState = .disconnected
    @State var connectionStateInfo: String = ""
    @State private var isMuted: Bool = false
    @State private var isVideoEnabled: Bool = true
    
    var body: some View {
        GeometryReader { reader in
            ZStack {
                if connectionState == .connected {
                    RtcVideoView(
                        containerSize: reader.size,
                        rtcViewInit: viewModel.rtcRemoteViewInit,
                        isMirror: true
                    )
                    .aspectRatio(contentMode: .fill)
                    .frame(width: reader.size.width, height: reader.size.height)
                    .clipped()
                    VStack {
                    Spacer()
                    HStack {
                        RtcVideoView(
                            containerSize: CGSize(width: reader.size.width / 3, height: reader.size.height / 3),
                                    rtcViewInit: viewModel.rtcLocalViewInit,
                            isMirror: true
                                            )
                                            .frame(width: reader.size.width / 3, height: reader.size.height / 3)
                                            .cornerRadius(8)
                                            .shadow(radius: 4)
                                Spacer()
                            }
                            .padding()
                        }
                    VStack {
                                        Spacer()
                                        HStack {
                                            Button(action: {
                                                isMuted.toggle()
                                                if isMuted {
                                                    viewModel.muteAudio()
                                                } else {
                                                    viewModel.unmuteAudio()
                                                }
                                            }) {
                                                Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(isMuted ? .red : .white)
                                                    .padding()
                                                    .background(Color.black.opacity(0.7))
                                                    .clipShape(Circle())
                                            }
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                isVideoEnabled.toggle()
                                                if isVideoEnabled {
                                                    viewModel.showVideo()
                                                } else {
                                                    viewModel.hideVideo()
                                                }
                                            }) {
                                                Image(systemName: isVideoEnabled ? "video.fill" : "video.slash.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(isVideoEnabled ? .green : .red)
                                                    .padding()
                                                    .background(Color.black.opacity(0.7))
                                                    .clipShape(Circle())
                                            }
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                viewModel.endCall()
                                            }) {
                                                Image(systemName: "phone.down.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(.red)
                                                    .padding()
                                                    .background(Color.black.opacity(0.7))
                                                    .clipShape(Circle())
                                            }
                                        }
                                        .padding(.horizontal, 40)
                                        .padding(.bottom, 20)
                                    }
                } else {
                    VStack {
                        Spacer()
                        HStack{
                            Spacer()
                            Text(connectionStateInfo)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
        }
        .task {
            await viewModel.retryConnect()
        }
        .task {
            for await connectionState in viewModel.connectionState {
                withAnimation {
                    self.connectionState = connectionState
                }
            }
        }
        .task {
            for await connectionStateInfo in viewModel.connectionStateInfo {
                withAnimation {
                    self.connectionStateInfo = connectionStateInfo
                }
            }
        }
        
    }
}

struct GuestViewPreview: PreviewProvider {
    static var previews: some View {
        ParticipantView(
            viewModel: ParticipantViewModel(
                chatRoomId: "",
                currentPeer: WebRTCManager.peer.host
            )
        )
    }
}
