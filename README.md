# iOS WebRTC Video Chat with Face Detection

iOS application for real-time video communication using WebRTC. Includes Firebase Firestore for signaling and Google ML Kit for face detection.

## Features

- **Real-time Video Communication**: Peer-to-peer video calls using WebRTC
- **Face Detection**: Real-time face detection and landmark tracking using Google ML Kit
- **Firebase Integration**: Firestore database for chat room management and signaling
- **SwiftUI**: Simple and user-friendly interface
- **Multiple Chat Rooms**: Create and join different video chat rooms
- **Host/Guest Mode**: Support for different participant roles

## Requirements

- iOS 17.5+
- Xcode 15.4+
- CocoaPods
- Firebase account (for Firestore)
- Google ML Kit account

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/ctnmstf/ios-webrtc.git
cd ios-webrtc
```

### 2. Install CocoaPods dependencies

```bash
pod install
```

### 3. Configure Firebase

1. Create a new Firebase project at [Firebase Console](https://console.firebase.google.com/)
2. Add an iOS app to your Firebase project
3. Download `GoogleService-Info.plist` from Firebase Console
4. Place `GoogleService-Info.plist` in the `ios-webrtc/` directory
5. Update the bundle identifier in Xcode to match your Firebase app's bundle ID

### 4. Open the workspace

```bash
open ios-webrtc.xcworkspace
```

### 5. Build and run

Select your target device or simulator and press `Cmd + R` to build and run the app.

## Usage

### Creating a Chat Room

1. Launch the app
2. Tap "Create chat room"
3. Enter a room name
4. Wait for participants to join

### Joining a Chat Room

1. Launch the app
2. Tap "Join chat room"
3. Select a room from the list
4. Start video chatting!

### Face Detection

The app automatically detects faces in the video stream and highlights facial landmarks (eyes, nose, mouth) in real-time.

## Project Structure

```
ios-webrtc/
├── WebRTC/
│   ├── WebRTCClient.swift      # WebRTC implementation
│   ├── WebRTCManager.swift     # WebRTC session management
│   ├── SignalingClient.swift   # Firebase Firestore signaling
│   ├── Config.swift            # ICE server configuration
│   ├── SessionDescription.swift # SDP handling
│   └── IceCandidate.swift      # ICE candidate handling
├── Data/
│   ├── VideoChatRepository.swift # Firestore data operations
│   ├── FirebaseKeys.swift      # Firebase collection keys
│   └── ChatRoom.swift          # Chat room data model
└── IosWebRTCApp.swift          # App entry point
```

## Configuration

### ICE Servers

The app uses Google's public STUN servers by default. You can modify the ICE servers in `WebRTC/Config.swift`:

```swift
private let defaultIceServers = [
    "stun:stun.l.google.com:19302",
    "stun:stun1.l.google.com:19302",
    // Add your TURN servers here if needed
]
```
## Dependencies

- **WebRTC-lib**: WebRTC framework for iOS
- **FirebaseFirestore**: Real-time database for signaling
- **GoogleMLKit/FaceDetection**: Face detection and landmark tracking

## Info

- Add your own `GoogleService-Info.plist` file (not included in the repo)

---

Made with ❤️ using SwiftUI, WebRTC, Firebase, and ML Kit
