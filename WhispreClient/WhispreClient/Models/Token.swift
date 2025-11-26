//
//  Token.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 22.10.2025.
//

struct Token: Codable {
    let access_token: String
    let refresh_token: String
    let token_type: String
}
