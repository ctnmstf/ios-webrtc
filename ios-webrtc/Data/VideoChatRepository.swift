//
//  VideoChatRepository.swift
//  ios-webrtc
//
//  Created by devmc on 27.08.2024.
//

import Foundation
import FirebaseCore
import FirebaseFirestore

class VideoChatRepository {
    
    private let db = Firestore.firestore()
    
    func createChatRoom(chatRoomName: String) async throws -> String {
        try await db.collection(FirebaseKeys.roomsCollectionPath).addDocument(data: [
            FirebaseKeys.roomCollectionNameKey : chatRoomName
        ]).documentID
    }
    
    func getChatRooms() -> AsyncThrowingStream<[(String, ChatRoom)], Error> {
        AsyncThrowingStream { continuation in
            db.collection(FirebaseKeys.roomsCollectionPath).addSnapshotListener { snapshot, error in
                if let snapshot = snapshot {
                    var lst: [(String, ChatRoom)] = []
                    snapshot.documents.forEach { doc in
                        do {
                            let chatRoom = try doc.data(as: ChatRoom.self)
                            lst.append((doc.documentID, chatRoom))
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    continuation.yield(lst)
                } else if let err = error {
                    continuation.finish(throwing: err)
                }
            }
        }
    }
}
