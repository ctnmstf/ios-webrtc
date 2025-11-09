//
//  WebRTCClient.swift
//  ios-webrtc
//
//  Created by devmc on 24.08.2024.
//

import Accelerate
import Combine
import CoreMedia
import Foundation
import WebRTC
import MLKit

class WebRTCClient: NSObject {
    enum peerConnectionError: Error {
        case peerConnectionNotInitialized
        case sdpNull
        case peerCollectionAlreadyInitialized
    }

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        videoEncoderFactory.preferredCodec = RTCVideoCodecInfo(name: kRTCVideoCodecVp9Name)
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()

    private let rtcAudioSession = RTCAudioSession.sharedInstance()
    private let mediaConstrains = [
        kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
        kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
    ]
    private var videoCapturer: RTCCameraVideoCapturer?
    private var localVideoTrack: RTCVideoTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    private var remoteDataChannel: RTCDataChannel?
    private var videoSource: RTCVideoSource?
    private var iceServers: [String]
    private var peerConnection: RTCPeerConnection?
    var audioRecorder: AVAudioRecorder?
    @Published private var connectionState: RTCIceConnectionState?
    private var candidateSubject = PassthroughSubject<RTCIceCandidate, Never>()
    private let peerConnectionSemaphore = DispatchSemaphore(value: 1)
    private let audioQueue = DispatchQueue(label: "audio")
    private let videoProcessingQueue = DispatchQueue(label: "videoProcessingQueue", qos: .userInitiated)
    private var lastProcessedFrame: RTCVideoFrame?
    private var isProcessing = false
    private let fps: Int32 = 60
    private var videoSourceSizeInitialized = false
    var isRemoteDescriptionSet: Bool {
        peerConnection?.remoteDescription != nil
    }
    private let faceDetector: FaceDetector

    init(iceServers: [String] = Config.default.webRTCIceServers) throws {
        self.iceServers = iceServers
        let options = FaceDetectorOptions()
        options.performanceMode = .fast
        options.landmarkMode = .all
        options.classificationMode = .none
        self.faceDetector = FaceDetector.faceDetector(options: options)
        
        super.init()
    }

    deinit {
        print("WebRTCClientAsync deinit")
    }

    func getConnectionState() -> AsyncStream<RTCIceConnectionState> {
        AsyncStream {  continuation in
            let subscription = $connectionState
                .sink(receiveValue: { connectionState in
                    if let connectionState = connectionState {
                        continuation.yield(connectionState)
                    }
                })
            continuation.onTermination = { @Sendable _ in
                subscription.cancel()
            }
        }
    }
    func getCandidates() -> AsyncStream<RTCIceCandidate> {
        AsyncStream { continuation in
            let subscription = candidateSubject
                .sink(receiveValue: { candidate in
                    continuation.yield(candidate)
                })
            continuation.onTermination = { @Sendable _ in
                subscription.cancel()
            }
        }
    }

    func createPeerConnection() throws {
        RTCSetMinDebugLogLevel(.info)
        peerConnectionSemaphore.wait()
        defer {
            peerConnectionSemaphore.signal()
        }
        if peerConnection != nil {
            throw peerConnectionError.peerCollectionAlreadyInitialized
        }
        let config = RTCConfiguration()

        config.iceServers = [
            RTCIceServer(
                urlStrings: [
                    "stun:stun.l.google.com:19302",
                    "stun:stun1.l.google.com:19302",
                    "stun:stun2.l.google.com:19302",
                    "stun:stun3.l.google.com:19302",
                    "stun:stun4.l.google.com:19302"
                ],
            )
        ]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue])
        self.peerConnection = WebRTCClient.factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self)
        try self.createMediaSenders()
    }
    func answer() async throws -> RTCSessionDescription {
        guard let peerConnection = peerConnection else {
            throw peerConnectionError.peerConnectionNotInitialized
        }
        let constrains = RTCMediaConstraints(
            mandatoryConstraints: self.mediaConstrains,
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            peerConnection.answer(for: constrains) { sdp, _ in
                if let sdp = sdp {
                    peerConnection.setLocalDescription(sdp, completionHandler: { _ in
                        continuation.resume(returning: sdp)
                    })
                } else {
                    continuation.resume(throwing: peerConnectionError.sdpNull)
                }
            }
        }
    }
    func offer() async throws -> RTCSessionDescription {
        let constrains = RTCMediaConstraints(
            mandatoryConstraints: self.mediaConstrains,
            optionalConstraints: nil
        )
        guard let peerConnection = peerConnection else {
            throw peerConnectionError.peerConnectionNotInitialized
        }
        return try await withCheckedThrowingContinuation {( continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            peerConnection.offer(for: constrains) { sdp, _ in
                if let sdp = sdp {
                    peerConnection.setLocalDescription(sdp, completionHandler: { _ in
                        continuation.resume(returning: sdp)
                    })
                } else {
                    continuation.resume(throwing: peerConnectionError.sdpNull)
                }
            }
        }
    }
    // MARK: Media
   
    func renderRemoteVideo(frame: CGRect) -> UIView {
        #if arch(arm64)
            let remoteRenderer = RTCMTLVideoView(frame: frame)
            remoteRenderer.videoContentMode = .scaleAspectFit
        #else
            let remoteRenderer = RTCEAGLVideoView(frame: frame)
        #endif
        self.remoteVideoTrack?.add(remoteRenderer)
        return remoteRenderer
    }
    
    func renderLocalVideo(frame: CGRect) -> UIView {
        #if arch(arm64)
            let localRenderer = RTCMTLVideoView(frame: frame)
            localRenderer.videoContentMode = .scaleAspectFit
        #else
            let localRenderer = RTCEAGLVideoView(frame: frame)
        #endif
        self.localVideoTrack?.add(localRenderer)
        return localRenderer
    }
    
    func startCaptureLocalVideo() {
        guard let capturer = self.videoCapturer as? RTCCameraVideoCapturer else {
            return
        }

        guard let frontCamera = (RTCCameraVideoCapturer.captureDevices().first { $0.position == .front }),
            let format = (RTCCameraVideoCapturer.supportedFormats(for: frontCamera).sorted { (f1, f2) -> Bool in
                let width1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription).width
                let width2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription).width
                return width1 < width2
            }).last,
            let fps = (format.videoSupportedFrameRateRanges.sorted { return $0.maxFrameRate < $1.maxFrameRate }.last) else {
            return
        }

        capturer.startCapture(with: frontCamera, format: format, fps: Int(fps.maxFrameRate))
    }
    
    func closePeerConnection() {
        peerConnection?.close()
    }
    func set(remoteSdp: RTCSessionDescription) async throws {
        guard let peerConnection = peerConnection else {
            throw peerConnectionError.peerConnectionNotInitialized
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>)  in
            peerConnection.setRemoteDescription(remoteSdp, completionHandler: {error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    func set(remoteCandidate: RTCIceCandidate) async throws {
        guard let peerConnection = peerConnection else {
            throw peerConnectionError.peerConnectionNotInitialized
        }
        try await peerConnection.add(remoteCandidate)
    }
    private func createMediaSenders() throws {
        let streamId = "stream"
        guard let peerConnection = peerConnection else {
            throw peerConnectionError.peerConnectionNotInitialized
        }
        // Audio
        let audioTrack = self.createAudioTrack()
        peerConnection.add(audioTrack, streamIds: [streamId])
        // Video
        let videoTrack = self.createVideoTrack()
        self.localVideoTrack = videoTrack
        peerConnection.add(videoTrack, streamIds: [streamId])
        self.remoteVideoTrack =
        peerConnection.transceivers.first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
    }

    // MARK: Data Channels
    private func createDataChannel() -> RTCDataChannel? {
        let config = RTCDataChannelConfiguration()
        guard let dataChannel = self.peerConnection!.dataChannel(forLabel: "WebRTCData", configuration: config) else {
            debugPrint("Warning: Couldn't create data channel.")
            return nil
        }
        return dataChannel
    }

    private func createAudioTrack() -> RTCAudioTrack {
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = WebRTCClient.factory.audioSource(with: audioConstrains)
        let audioTrack = WebRTCClient.factory.audioTrack(with: audioSource, trackId: "audio0")
        return audioTrack
    }

    private func createVideoTrack() -> RTCVideoTrack {
        let videoSource = WebRTCClient.factory.videoSource()
        self.videoSource = videoSource
        
        #if TARGET_OS_SIMULATOR
        self.videoCapturer = RTCFileVideoCapturer(delegate: videoSource)
        #else
        self.videoCapturer = RTCCameraVideoCapturer(delegate: self)
        #endif
        
        let videoTrack = WebRTCClient.factory.videoTrack(with: videoSource, trackId: "video0")
        
        return videoTrack
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    }
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        self.connectionState = newState
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        self.candidateSubject.send(candidate)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        self.remoteDataChannel = dataChannel
    }
}

extension WebRTCClient {
    private func setTrackEnabled<T: RTCMediaStreamTrack>(_ type: T.Type, isEnabled: Bool) {
        guard let peerConnection = peerConnection else { return }
        peerConnection.transceivers
            .compactMap { $0.sender.track as? T }
            .forEach { $0.isEnabled = isEnabled }
    }
}

// MARK: - Video control
extension WebRTCClient {
    func hideVideo() {
        self.setVideoEnabled(false)
    }
    func showVideo() {
        self.setVideoEnabled(true)
    }
    private func setVideoEnabled(_ isEnabled: Bool) {
        setTrackEnabled(RTCVideoTrack.self, isEnabled: isEnabled)
    }
}

// MARK: - Audio control
extension WebRTCClient {
    func muteAudio() {
        self.setAudioEnabled(false)
    }

    func unmuteAudio() {
        self.setAudioEnabled(true)
    }

    func speakerOff() {
        self.audioQueue.async { [weak self] in
            guard let self = self else {
                return
            }

            self.rtcAudioSession.lockForConfiguration()
            do {
                try self.rtcAudioSession.setCategory(AVAudioSession.Category.playAndRecord, mode: .videoChat)
                try self.rtcAudioSession.overrideOutputAudioPort(.none)
            } catch {
                debugPrint("Error setting AVAudioSession category: \(error)")
            }
            self.rtcAudioSession.unlockForConfiguration()
        }
    }

    func speakerOn() {
        self.audioQueue.async { [weak self] in
            guard let self = self else {
                return
            }

            self.rtcAudioSession.lockForConfiguration()
            do {
                try self.rtcAudioSession.setCategory(AVAudioSession.Category.playAndRecord, 
                                                     mode: .videoChat, 
                                                     options: [.defaultToSpeaker])
                try self.rtcAudioSession.setActive(true)
            } catch {
                debugPrint("Couldn't force audio to speaker: \(error)")
            }
            self.rtcAudioSession.unlockForConfiguration()
        }
    }

    private func setAudioEnabled(_ isEnabled: Bool) {
        setTrackEnabled(RTCAudioTrack.self, isEnabled: isEnabled)
    }
}

// MARK: - Cleanup
extension WebRTCClient {
    func stopCaptureLocalVideo() {
        if let capturer = self.videoCapturer as? RTCCameraVideoCapturer {
            capturer.stopCapture()
        }
        self.localVideoTrack = nil
    }

    func resetAudioSession() {
        self.audioQueue.async { [weak self] in
            guard let self = self else {
                return
            }

            self.rtcAudioSession.lockForConfiguration()
            do {
                try self.rtcAudioSession.setCategory(AVAudioSession.Category.playAndRecord)
                try self.rtcAudioSession.setActive(false)
            } catch {
                debugPrint("Error resetting AVAudioSession: \(error)")
            }
            self.rtcAudioSession.unlockForConfiguration()
        }
    }
}

extension WebRTCClient: RTCVideoCapturerDelegate {
    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        guard let imageBuffer = frame.buffer as? RTCCVPixelBuffer else {
            self.videoSource?.capturer(capturer, didCapture: frame)
            return
        }

        let pixelBuffer = imageBuffer.pixelBuffer
        guard let sampleBuffer = createSampleBuffer(from: pixelBuffer, timestamp: frame.timeStampNs) else {
            self.videoSource?.capturer(capturer, didCapture: frame)
            return
        }

        let image = VisionImage(buffer: sampleBuffer)
        image.orientation = .up

        if isProcessing {
            if let lastProcessedFrame = self.lastProcessedFrame {
                self.videoSource?.capturer(capturer, didCapture: lastProcessedFrame)
            } else {
                self.videoSource?.capturer(capturer, didCapture: frame)
            }
            return
        }

        isProcessing = true

        faceDetector.process(image) { [weak self] faces, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Face detection failed: \(error.localizedDescription)")
                self.videoSource?.capturer(capturer, didCapture: frame)
                self.isProcessing = false
                return
            }
            
            guard let faces = faces, !faces.isEmpty else {
                print("No faces detected")
                self.videoSource?.capturer(capturer, didCapture: frame)
                self.isProcessing = false
                return
            }
            
            self.drawFaceLandmarksAsync(on: pixelBuffer, faces: faces) { processedBuffer in
                if let processedBuffer = processedBuffer,
                   let processedFrame = self.createVideoFrame(from: processedBuffer, timestamp: frame.timeStampNs) {
                    self.lastProcessedFrame = processedFrame
                    self.videoSource?.capturer(capturer, didCapture: processedFrame)
                } else {
                    self.videoSource?.capturer(capturer, didCapture: frame)
                }
                self.isProcessing = false
            }
        }
    }

    private func drawFaceLandmarksAsync(on pixelBuffer: CVPixelBuffer, faces: [Face], completion: @escaping (CVPixelBuffer?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext(options: nil)
            
            var resultImage = ciImage
            
            for face in faces {
                for landmark in face.landmarks ?? [] {
                    switch landmark.type {
                    case .leftEye:
                        resultImage = self.drawPoint(on: resultImage, at: landmark.position, color: .green)
                    case .rightEye:
                        resultImage = self.drawPoint(on: resultImage, at: landmark.position, color: .green)
                    case .noseBase:
                        resultImage = self.drawPoint(on: resultImage, at: landmark.position, color: .green)
                    case .mouthLeft, .mouthRight:
                        resultImage = self.drawPoint(on: resultImage, at: landmark.position, color: .green)
                    default:
                        break
                    }
                }
            }
            
            let outputPixelBuffer = pixelBuffer
            context.render(resultImage, to: outputPixelBuffer)
            
            DispatchQueue.main.async {
                completion(outputPixelBuffer)
            }
        }
    }

    private func drawPoint(on image: CIImage, at position: VisionPoint, color: UIColor) -> CIImage {
        let point = CIVector(x: position.x, y: image.extent.height - position.y)
        let colorComponents = color.cgColor.components ?? [0, 1, 0, 1]
        let ciColor = CIColor(red: colorComponents[0], green: colorComponents[1], blue: colorComponents[2], alpha: 1.0)
        
        let pointOverlay = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": point,
            "inputRadius0": 0,
            "inputRadius1": 5,
            "inputColor0": ciColor,
            "inputColor1": CIColor(red: ciColor.red, green: ciColor.green, blue: ciColor.blue, alpha: 0)
        ])!
        
        return image.composited(over: pointOverlay.outputImage!)
    }

    private func createVideoFrame(from pixelBuffer: CVPixelBuffer, timestamp: Int64) -> RTCVideoFrame? {
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timeStampNs = CMTimeGetSeconds(CMTimeMake(value: timestamp, timescale: 1000000000))
        let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: Int64(timeStampNs * 1000000000))
        return videoFrame
    }

    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer, timestamp: Int64) -> CMSampleBuffer? {
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: CMTime(value: timestamp, timescale: 1000000000),
            decodeTimeStamp: CMTime.invalid
        )

        var videoInfo: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &videoInfo)

        guard let videoInfo = videoInfo else { return nil }

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: videoInfo,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }
}
