//
//  Encoder.swift
//  
//
//  Created by Alsey Coleman Miller on 12/6/22.
//

import Foundation
import Socket

/// Gunbound Packet Encoder
public struct GunBoundEncoder {
    
    // MARK: - Properties
    
    /// Any contextual information set by the user for encoding.
    public var userInfo = [CodingUserInfoKey : Any]()
    
    /// Logging handler
    public var log: ((String) -> ())?
        
    // MARK: - Initialization
    
    public init() { }
    
    // MARK: - Methods
    
    public func encode<T>(_ value: T, for command: Command, id: Packet.ID? = nil) throws -> Packet where T: Encodable {
        log?("Will encode \(command) packet")
        // TODO: reserve buffer capacity
        // initialize encoder
        let encoder = Encoder(
            userInfo: userInfo,
            log: log,
            command: command
        )
        // encode value
        try value.encode(to: encoder)
        // set size
        encoder.packet.size = numericCast(encoder.packet.data.count)
        // set packet ID / sequence number (might be based on length)
        if let id = id {
            encoder.packet.id = id
        } else {
            encoder.packet.id = .init(packetLength: Int(encoder.packet.size))
        }
        // return value
        return encoder.packet
    }
}

internal extension GunBoundEncoder {
    
    final class Encoder: Swift.Encoder {
        
        // MARK: - Properties
        
        /// The path of coding keys taken to get to this point in encoding.
        fileprivate(set) var codingPath: [CodingKey]
        
        /// Any contextual information set by the user for encoding.
        let userInfo: [CodingUserInfoKey : Any]
        
        /// Logger
        let log: ((String) -> ())?
        
        fileprivate(set) var packet: Packet
        
        // MARK: - Initialization
        
        fileprivate init(codingPath: [CodingKey] = [],
             userInfo: [CodingUserInfoKey : Any],
             log: ((String) -> ())?,
             command: Command) {
            
            self.codingPath = codingPath
            self.userInfo = userInfo
            self.log = log
            self.packet = Packet(command: command)
        }
        
        // MARK: - Encoder
        
        func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
            log?("Requested container keyed by \(type.sanitizedName) for path \"\(codingPath.path)\"")
            let keyedContainer = GunBoundKeyedEncodingContainer<Key>(referencing: self)
            return KeyedEncodingContainer(keyedContainer)
        }
        
        func unkeyedContainer() -> UnkeyedEncodingContainer {
            log?("Requested unkeyed container for path \"\(codingPath.path)\"")
            return GunBoundUnkeyedEncodingContainer(referencing: self)
        }
        
        func singleValueContainer() -> SingleValueEncodingContainer {
            log?("Requested single value container for path \"\(codingPath.path)\"")
            return GunBoundSingleValueEncodingContainer(referencing: self)
        }
    }
}

internal extension GunBoundEncoder.Encoder {
    
    func write<C>(_ data: C) where C: Collection, C.Element == UInt8 {
        self.packet.data.reserveCapacity(self.packet.data.count + data.count)
        self.packet.data.append(contentsOf: data)
    }
    
    func box <T: GunBoundRawEncodable> (_ value: T) -> Data {
        return value.binaryData
    }
    
    func boxString(_ value: String) throws -> Data {
        return try boxLengthPrefixString(value)
    }
    
    func boxInteger <T: GunBoundRawEncodable & FixedWidthInteger> (_ value: T) -> Data {
        return withUnsafePointer(to: value.littleEndian, { Data(bytes: $0, count: MemoryLayout<T>.size) })
    }
    
    func boxDouble(_ double: Double) -> Data {
        return boxInteger(double.bitPattern)
    }
    
    func boxFloat(_ float: Float) -> Data {
        return boxInteger(float.bitPattern)
    }
    
    func writeEncodable <T: Encodable> (_ value: T) throws {
        
        if let data = value as? Data {
            write(boxData(data))
        } else if let date = value as? Date {
            try writeDate(date)
        } else if let encodable = value as? GunBoundEncodable {
            // encode using Encodable, container should write directly.
            let container = GunBoundEncodingContainer(referencing: self)
            try encodable.encode(to: container)
        } else {
            // encode using Encodable, container should write directly.
            try value.encode(to: self)
        }
    }
}

private extension GunBoundEncoder.Encoder {
    
    func boxData(_ data: Data) -> Data {
        var encodedData = Data(capacity: 2 + data.count)
        let length = UInt16(data.count)
        encodedData.append(length.bigEndian.binaryData)
        encodedData.append(data)
        return encodedData
    }
    
    func boxNullTerminatedString(_ value: String) -> Data {
        return Data(unsafeBitCast(value.utf8CString, to: ContiguousArray<UInt8>.self))
    }
    
    func boxLengthPrefixString(_ value: String) throws -> Data {
        let stringData = Data(value.utf8)
        guard stringData.count <= UInt8.max else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "String must be less than \(Int(UInt8.max) + 1) characters to be encoded."))
        }
        var encodedData = Data(capacity: 1 + stringData.count)
        let length = UInt8(stringData.count)
        encodedData.append(length)
        encodedData.append(stringData)
        return encodedData
    }
    
    func writeDate(_ value: Date) throws {
        let timeInterval = Int32(value.timeIntervalSince1970)
        write(boxInteger(timeInterval))
    }
}

// MARK: - KeyedEncodingContainerProtocol

internal struct GunBoundKeyedEncodingContainer <K : CodingKey> : KeyedEncodingContainerProtocol {
    
    typealias Key = K
    
    // MARK: - Properties
    
    /// A reference to the encoder we're writing to.
    let encoder: GunBoundEncoder.Encoder
    
    /// The path of coding keys taken to get to this point in encoding.
    let codingPath: [CodingKey]
    
    // MARK: - Initialization
    
    init(referencing encoder: GunBoundEncoder.Encoder) {
        
        self.encoder = encoder
        self.codingPath = encoder.codingPath
    }
    
    // MARK: - Methods
    
    func encodeNil(forKey key: K) throws {
        // do nothing
    }
    
    func encode(_ value: Bool, forKey key: K) throws {
        try encodeGunBound(value, forKey: key)
    }
    
    func encode(_ value: Int, forKey key: K) throws {
        try encodeNumeric(Int32(value), forKey: key)
    }
    
    func encode(_ value: Int8, forKey key: K) throws {
        try encodeGunBound(value, forKey: key)
    }
    
    func encode(_ value: Int16, forKey key: K) throws {
        try encodeNumeric(value, forKey: key)
    }
    
    func encode(_ value: Int32, forKey key: K) throws {
        try encodeNumeric(value, forKey: key)
    }
    
    func encode(_ value: Int64, forKey key: K) throws {
        try encodeNumeric(value, forKey: key)
    }
    
    func encode(_ value: UInt, forKey key: K) throws {
        try encodeNumeric(UInt32(value), forKey: key)
    }
    
    func encode(_ value: UInt8, forKey key: K) throws {
        try encodeGunBound(value, forKey: key)
    }
    
    func encode(_ value: UInt16, forKey key: K) throws {
        try encodeNumeric(value, forKey: key)
    }
    
    func encode(_ value: UInt32, forKey key: K) throws {
        try encodeNumeric(value, forKey: key)
    }
    
    func encode(_ value: UInt64, forKey key: K) throws {
        try encodeNumeric(value, forKey: key)
    }
    
    func encode(_ value: Float, forKey key: K) throws {
        try encodeNumeric(value.bitPattern, forKey: key)
    }
    
    func encode(_ value: Double, forKey key: K) throws {
        try encodeNumeric(value.bitPattern, forKey: key)
    }
    
    func encode(_ value: String, forKey key: K) throws {
        self.encoder.codingPath.append(key)
        defer { self.encoder.codingPath.removeLast() }
        let data = try encoder.boxString(value)
        try setValue(value, data: data, for: key)
    }
    
    func encode <T: Encodable> (_ value: T, forKey key: K) throws {
        
        self.encoder.codingPath.append(key)
        defer { self.encoder.codingPath.removeLast() }
        encoder.log?("Will encode \(T.self) at path \"\(encoder.codingPath.path)\"")
        try encoder.writeEncodable(value)
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: K) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        fatalError()
    }
    
    func nestedUnkeyedContainer(forKey key: K) -> UnkeyedEncodingContainer {
        fatalError()
    }
    
    func superEncoder() -> Encoder {
        fatalError()
    }
    
    func superEncoder(forKey key: K) -> Encoder {
        fatalError()
    }
    
    // MARK: Private Methods
    
    private func encodeNumeric <T: GunBoundRawEncodable & FixedWidthInteger> (_ value: T, forKey key: K, isLittleEndian: Bool = false) throws {
        
        self.encoder.codingPath.append(key)
        defer { self.encoder.codingPath.removeLast() }
        let data = encoder.boxInteger(value)
        try setValue(value, data: data, for: key)
    }
    
    private func encodeGunBound <T: GunBoundRawEncodable> (_ value: T, forKey key: K) throws {
        
        self.encoder.codingPath.append(key)
        defer { self.encoder.codingPath.removeLast() }
        let data = encoder.box(value)
        try setValue(value, data: data, for: key)
    }
    
    private func setValue <T> (_ value: T, data: Data, for key: Key) throws {
        encoder.log?("Will encode \(T.self) at path \"\(encoder.codingPath.path)\"")
        self.encoder.write(data)
    }
}

// MARK: - Custom Encoding

/// GunBound Encoding Container
public struct GunBoundEncodingContainer {
    
    // MARK: - Properties
    
    /// A reference to the encoder we're writing to.
    internal let encoder: GunBoundEncoder.Encoder
    
    /// The path of coding keys taken to get to this point in encoding.
    public let codingPath: [CodingKey]
    
    // MARK: - Initialization
    
    fileprivate init(referencing encoder: GunBoundEncoder.Encoder) {
        
        self.encoder = encoder
        self.codingPath = encoder.codingPath
    }
    
    // MARK: - Methods
    
    public func encode(_ value: Bool) throws {
        try encodeGunBound(value)
    }
    
    public func encode(_ value: Int8) throws {
        try encodeGunBound(value)
    }
    
    public func encode(_ value: Int16, isLittleEndian: Bool = false) throws {
        try encodeNumeric(value, isLittleEndian: isLittleEndian)
    }
    
    public func encode(_ value: Int32, isLittleEndian: Bool = false) throws {
        try encodeNumeric(value, isLittleEndian: isLittleEndian)
    }
    
    public func encode(_ value: Int64, isLittleEndian: Bool = false) throws {
        try encodeNumeric(value, isLittleEndian: isLittleEndian)
    }
    
    public func encode(_ value: UInt8) throws {
        try encodeGunBound(value)
    }
    
    public func encode(_ value: UInt16, isLittleEndian: Bool = false) throws {
        try encodeNumeric(value, isLittleEndian: isLittleEndian)
    }
    
    public func encode(_ value: UInt32, isLittleEndian: Bool = false) throws {
        try encodeNumeric(value, isLittleEndian: isLittleEndian)
    }
    
    public func encode(_ value: UInt64, isLittleEndian: Bool = false) throws {
        try encodeNumeric(value, isLittleEndian: isLittleEndian)
    }
    
    public func encode(_ value: Float, isLittleEndian: Bool = false) throws {
        try encodeNumeric(value.bitPattern, isLittleEndian: isLittleEndian)
    }
    
    public func encode(_ value: Double, isLittleEndian: Bool = false) throws {
        try encodeNumeric(value.bitPattern, isLittleEndian: isLittleEndian)
    }
    
    public func encode <T: Encodable> (_ value: T, forKey key: CodingKey) throws {
        
        encoder.codingPath.append(key)
        defer { encoder.codingPath.removeLast() }
        encoder.log?("Will encode \(T.self) at path \"\(encoder.codingPath.path)\"")
        try encoder.writeEncodable(value)
    }
    
    public func encodeArray <C> (_ values: C, forKey key: CodingKey) throws where C: Collection, C.Element: Encodable {
        
        encoder.codingPath.append(key)
        defer { encoder.codingPath.removeLast() }
        encoder.log?("Will encode \(C.self) at path \"\(encoder.codingPath.path)\"")
        try values.forEach { try encoder.writeEncodable($0) }
    }
    
    public func encode<C>(_ data: C) throws where C: Collection, C.Element == UInt8 {
        try setValue(data, data: data)
    }
    
    private func encodeNumeric <T: GunBoundRawEncodable & FixedWidthInteger> (_ value: T, isLittleEndian: Bool = false) throws {
        
        let data = encoder.boxInteger(value)
        try setValue(value, data: data)
    }
    
    private func encodeGunBound <T: GunBoundRawEncodable> (_ value: T) throws {
        
        let data = encoder.box(value)
        try setValue(value, data: data)
    }
    
    private func setValue <T, C> (_ value: T, data: C) throws where C: Collection, C.Element == UInt8 {
        encoder.log?("Will encode \(T.self) (\(data.count) bytes)")
        encoder.write(data)
    }
}

// MARK: - SingleValueEncodingContainer

internal final class GunBoundSingleValueEncodingContainer: SingleValueEncodingContainer {
    
    // MARK: - Properties
    
    /// A reference to the encoder we're writing to.
    let encoder: GunBoundEncoder.Encoder
    
    /// The path of coding keys taken to get to this point in encoding.
    let codingPath: [CodingKey]
    
    /// Whether the data has been written
    private var didWrite = false
    
    // MARK: - Initialization
    
    init(referencing encoder: GunBoundEncoder.Encoder) {
        
        self.encoder = encoder
        self.codingPath = encoder.codingPath
    }
    
    // MARK: - Methods
    
    func encodeNil() throws {
        // do nothing
    }
    
    func encode(_ value: Bool) throws { write(encoder.box(value)) }
    
    func encode(_ value: String) throws { try write(encoder.boxString(value)) }
    
    func encode(_ value: Double) throws { write(encoder.boxDouble(value)) }
    
    func encode(_ value: Float) throws { write(encoder.boxFloat(value)) }
    
    func encode(_ value: Int) throws { write(encoder.boxInteger(Int32(value))) }
    
    func encode(_ value: Int8) throws { write(encoder.box(value)) }
    
    func encode(_ value: Int16) throws { write(encoder.boxInteger(value)) }
    
    func encode(_ value: Int32) throws { write(encoder.boxInteger(value)) }
    
    func encode(_ value: Int64) throws { write(encoder.boxInteger(value)) }
    
    func encode(_ value: UInt) throws { write(encoder.boxInteger(UInt32(value))) }
    
    func encode(_ value: UInt8) throws { write(encoder.box(value)) }
    
    func encode(_ value: UInt16) throws {
        write(encoder.boxInteger(value))
    }
    
    func encode(_ value: UInt32) throws { write(encoder.boxInteger(value)) }
    
    func encode(_ value: UInt64) throws { write(encoder.boxInteger(value)) }
    
    func encode <T: Encodable> (_ value: T) throws {
        precondition(didWrite == false, "Data already written")
        try encoder.writeEncodable(value)
        self.didWrite = true
    }
    
    // MARK: - Private Methods
    
    private func write(_ data: Data) {
        
        precondition(didWrite == false, "Data already written")
        self.encoder.write(data)
        self.didWrite = true
    }
}

// MARK: - UnkeyedEncodingContainer

internal final class GunBoundUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    
    // MARK: - Properties
    
    /// A reference to the encoder we're writing to.
    let encoder: GunBoundEncoder.Encoder
    
    /// The path of coding keys taken to get to this point in encoding.
    let codingPath: [CodingKey]
        
    private var countOffset: Int?
        
    /// The number of elements encoded into the container.
    private(set) var count: Int = 0
    
    // MARK: - Initialization
    
    deinit {
        // update count byte
        self.countOffset.flatMap { self.encoder.packet.data[$0] = UInt8(self.count) }
    }
    
    init(referencing encoder: GunBoundEncoder.Encoder) {
        self.encoder = encoder
        self.codingPath = encoder.codingPath
        // write count byte
        self.countOffset = self.encoder.packet.data.count
        self.encoder.write(Data([0]))
    }
    
    // MARK: - Methods
    
    func encodeNil() throws {
        throw EncodingError.invalidValue(Optional<Any>.self, EncodingError.Context(codingPath: self.codingPath, debugDescription: "Cannot encode nil in an array"))
    }
    
    func encode(_ value: Bool) throws { append(encoder.box(value)) }
    
    func encode(_ value: String) throws { try append(encoder.boxString(value)) }
    
    func encode(_ value: Double) throws { append(encoder.boxInteger(value.bitPattern)) }
    
    func encode(_ value: Float) throws { append(encoder.boxInteger(value.bitPattern)) }
    
    func encode(_ value: Int) throws { append(encoder.boxInteger(Int32(value))) }
    
    func encode(_ value: Int8) throws { append(encoder.box(value)) }
    
    func encode(_ value: Int16) throws { append(encoder.boxInteger(value)) }
    
    func encode(_ value: Int32) throws { append(encoder.boxInteger(value)) }
    
    func encode(_ value: Int64) throws { append(encoder.boxInteger(value)) }
    
    func encode(_ value: UInt) throws { append(encoder.boxInteger(UInt32(value))) }
    
    func encode(_ value: UInt8) throws { append(encoder.box(value)) }
    
    func encode(_ value: UInt16) throws {
        append(encoder.boxInteger(value))
    }
    
    func encode(_ value: UInt32) throws { append(encoder.boxInteger(value)) }
    
    func encode(_ value: UInt64) throws { append(encoder.boxInteger(value)) }
    
    func encode <T: Encodable> (_ value: T) throws {
        assert(count < Int(UInt8.max), "Cannot encode more than \(UInt8.max) elements")
        try encoder.writeEncodable(value)
        count += 1
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        fatalError()
    }
    
    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError()
    }
    
    func superEncoder() -> Encoder {
        fatalError()
    }
    
    // MARK: - Private Methods
    
    private func append(_ data: Data) {
        assert(count < Int(UInt8.max), "Cannot encode more than \(UInt8.max) elements")
        // write element data
        encoder.write(data)
        count += 1
    }
}

// MARK: - Data Types

/// Private protocol for encoding GunBound values into raw data.
internal protocol GunBoundRawEncodable {
    
    var binaryData: Data { get }
}

internal extension GunBoundRawEncodable {
    
    var binaryData: Data {
        return withUnsafePointer(to: self, { Data(bytes: $0, count: MemoryLayout<Self>.size) })
    }
}

extension Bool: GunBoundRawEncodable {
    
    public var binaryData: Data {
        return UInt8(self ? 1 : 0).binaryData
    }
}

extension UInt8: GunBoundRawEncodable { }

extension UInt16: GunBoundRawEncodable { }

extension UInt32: GunBoundRawEncodable { }

extension UInt64: GunBoundRawEncodable { }

extension Int8: GunBoundRawEncodable { }

extension Int16: GunBoundRawEncodable { }

extension Int32: GunBoundRawEncodable { }

extension Int64: GunBoundRawEncodable { }

extension Float: GunBoundRawEncodable {
    
    public var binaryData: Data {
        return bitPattern.binaryData
    }
}

extension Double: GunBoundRawEncodable {
    
    public var binaryData: Data {
        return bitPattern.binaryData
    }
}

extension IPv4Address: GunBoundRawEncodable { }