//
//  User.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import Foundation

struct User: Codable, Identifiable {
    let id: String
    let username: String
    let email: String
    let accessToken: String
    let refreshToken: String
}

struct UserRegisterResponseModel: Codable {
    let id: String
}


struct UserResponse: Codable {
    let id: String
    let email: String
    let username: String?
}

struct Friend: Codable, Identifiable {
    let id: String
    let username: String
}
