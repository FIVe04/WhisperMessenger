//
//  Device.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//


import Foundation

struct DeviceResponse: Codable, Identifiable {
    let id: UUID
    let device_id: String
    let device_name: String?
    let identity_key: String
    let signed_prekey: String
    let signed_prekey_signature: String
    let created_at: Date

    enum CodingKeys: String, CodingKey {
        case id
        case device_id = "device_id"
        case device_name = "device_name"
        case identity_key = "identity_key"
        case signed_prekey = "signed_prekey"
        case signed_prekey_signature = "signed_prekey_signature"
        case created_at = "created_at"
    }
}
