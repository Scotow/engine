import libc
import Core

/// Frame format:
///
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-------+-+-------------+-------------------------------+
/// |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
/// |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
/// |N|V|V|V|       |S|             |   (if payload len==126/127)   |
/// | |1|2|3|       |K|             |                               |
/// +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
/// |     Extended payload length continued, if payload len == 127  |
/// + - - - - - - - - - - - - - - - +-------------------------------+
/// |                               |Masking-key, if MASK set to 1  |
/// +-------------------------------+-------------------------------+
/// | Masking-key (continued)       |          Payload Data         |
/// +-------------------------------- - - - - - - - - - - - - - - - +
/// :                     Payload Data continued ...                :
/// + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
/// |                     Payload Data continued ...                |
/// +---------------------------------------------------------------+
///
/// A WebSocket frame contains a payload
///
/// Interfacing with this class directly is usually not necessary and not recommended unless you know how WebSockets work.
public final class Frame {
    /// The type of payload
    public enum OpCode: Byte {
        /// This message is a continuation of a previous frame and it's associated payload
        case continuation = 0x00
        
        /// This message is (the start of) a text (`String`) based payload
        case text = 0x01
        
        /// This message is (the start of) a binary payload
        case binary = 0x02
        
        /// This message is an indication of closing the connection
        case close = 0x08
        
        /// This message is a ping, it's contents must be `pong`-ed back
        case ping = 0x09
        
        /// This message is a pong and must contain the original `ping`'s contents
        case pong = 0x0a
    }
    
    /// If `true`, this is the final message in it's sequence
    public let final: Bool
    
    /// The type of frame (and payload)
    public let opCode: OpCode
    
    /// The serialized message
    let buffer: MutableByteBuffer
    var headerUntil: Int
    let mask: [UInt8]?
    
    /// The payload of this frame
    public var payload: ByteBuffer {
        return ByteBuffer(start: buffer.baseAddress, count: buffer.count &- headerUntil)
    }
    
    /// Creates a new payload by referencing the original payload.
    ///
    /// Do **not** deallocate the original payload whilst this Frame is still being used
    public init(op: OpCode, payload: ByteBuffer, mask: [UInt8]?, final: Bool = true) throws {
        if !final {
            guard op == .binary || op == .continuation else {
                throw WebSocketError.invalidFrameParameters
            }
        }
        
        self.opCode = op
        self.final = final
        
        let payloadLengthSize: Int
        var number: [UInt8]
        
        // the amount of bytes needed for this payload
        if payload.count < 126 {
            payloadLengthSize = 1
            number = []
            
        // Serialize as UInt16
        } else if payload.count <= Int(UInt16.max) {
            payloadLengthSize = 3
            
            var length = UInt16(payload.count).littleEndian
            
            number = [UInt8](repeating: 0, count: 2)
            
            memcpy(&number, &length, 2)
            
        // Serialize as UInt64
        } else {
            payloadLengthSize = 9
            
            var length = UInt64(payload.count).littleEndian
            
            number = [UInt8](repeating: 0, count: 8)
            
            memcpy(&number, &length, 8)
        }
        
        // create a buffer for the entire message
        let bufferSize = 2 + payloadLengthSize + payload.count
        let pointer = MutableBytesPointer.allocate(capacity: bufferSize)
        
        // set final bit if needed and rawValue
        pointer.pointee = (final ? 0b10000000 : 0) | op.rawValue
        
        if let mask = mask {
            guard mask.count == 4 else {
                throw WebSocketError.invalidMask
            }
            
            pointer.advanced(by: 2 &+ payloadLengthSize).assign(from: mask, count: 4)
            self.mask = mask
            
        } else {
            self.mask = nil
        }
        
        self.buffer = MutableByteBuffer(start: pointer, count: bufferSize)
        headerUntil = 2 &+ payloadLengthSize &+ (mask == nil ? 0 : 4)
    }
}

public enum WebSocketError : Error {
    case invalidFrame
    case invalidUpgrade
    case couldNotConnect
    case invalidMask
    case invalidBuffer
    case invalidFrameParameters
}
