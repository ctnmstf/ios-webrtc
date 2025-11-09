//
//  CallManeger.swift
//  ios-webrtc
//
//  Created by devmc on 24.08.2024.
//

import Foundation
import FirebaseFirestore

class CallManager: ObservableObject {

    @Published var shouldShowAnswerButton = false
    @Published var should = false

    @Published var answer : String = "test"

    private var listener: ListenerRegistration?
    private var answerListener: ListenerRegistration?



    
    private var db = Firestore.firestore()
    
    func listenForCalls(documentId: String) {
           listener?.remove()

           listener = db.collection("calls").document(documentId)
               .addSnapshotListener { [weak self] snapshot, error in
                   guard let self = self else { return }
                   if let error = error {
                       print("Error listening for calls: \(error)")
                       return
                   }

                   if let document = snapshot, document.exists {
                       self.shouldShowAnswerButton = true
                   } else {
                       self.shouldShowAnswerButton = false
                   }
               }
       }
    
    func listenForAnswer(document: String) {
        answerListener?.remove()

               
               answerListener = db.collection("calls").document(document)
                   .addSnapshotListener { [weak self] snapshot, error in
                       guard let self = self else { return }
                       if let error = error {
                           print("Error listening for answer: \(error)")
                           return
                       }

                       if let document = snapshot, document.exists, let data = document.data() {
                           if let status = data["status"] as? String {
                               self.answer = status
                               print("durum = " + status)
                               if status == "connecting"{

                                   should = true
                               }else{
                                   should = false

                               }
                           }
                       } else {
                       }
                   }


       }

       deinit {
           answerListener?.remove()
           listener?.remove()
       }
    
    func startCall(with userID: String) {
        let docRef = db.collection("calls").document(userID)
        docRef.setData(["status": "calling", "callerId": userID], merge: true) { error in
            if let error = error {
                print("Error starting call: \(error)")
            } else {
                DispatchQueue.main.async {
                   
                }
            }
        }
    }
    
    
    func answerCall(with userID: String) {
        
        let docRef = db.collection("calls").document(userID)
        docRef.updateData(["status": "answered"]) { error in
            if let error = error {
                print("Error updating call status: \(error)")
            } else {
                DispatchQueue.main.async {
                   
                }
            }
        }
    }

    
    func connectingCall(with userID: String) {
        
        let docRef = db.collection("calls").document(userID)
        docRef.updateData(["status": "connecting"]) { error in
            if let error = error {
                print("Error updating call status: \(error)")
            } else {
                DispatchQueue.main.async {
                   
                }
            }
        }
    }
    
    
    
    func cancelCall(for userID: String) {
        let docRef = db.collection("calls").document(userID)
        docRef.delete { error in
            if let error = error {
                print("Error canceling call: \(error)")
            } else {
                DispatchQueue.main.async {
                    
                }
            }
        }
    }
}
