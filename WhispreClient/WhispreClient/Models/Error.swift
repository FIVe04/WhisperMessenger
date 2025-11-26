//
//  Error.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 08.11.2025.
//

struct APIErrorResponse: Codable {
    let detail: String
}

struct APIValidationErrorDetail: Codable {
    let type: String
    let loc: [String]
    let msg: String
    let input: String?
    let ctx: [String: String]?
}

struct APIValidationErrorResponse: Codable {
    let detail: [APIValidationErrorDetail]
}
