//
//  AuthenticationRequest.swift
//  
//
//  Created by Alsey Coleman Miller on 12/6/22.
//

import Foundation

public struct AuthenticationRequest: GunBoundPacket, Equatable, Hashable, Decodable {
    
    public static var opcode: Opcode { .authenticationRequest }
    
    public let username: String
    
    public let clientVersion: ClientVersion
}

extension AuthenticationRequest: GunBoundDecodable {
    
    public init(from container: GunBoundDecodingContainer) throws {
        // decode username
        self.username = try container.decode(length: 0x10) {
            let decryptedData = try Crypto.AES.decrypt($0, key: .login)
            return decryptedData.withUnsafeBytes {
                $0.baseAddress?.withMemoryRebound(to: Int8.self, capacity: decryptedData.count) {
                    return String(cString: $0, encoding: .ascii)
                }
            }
        }
        // decode rest
        
        
        // TODO: Decode
        self.clientVersion = 280
    }
}
