import Foundation
import CryptoKit

/// Liczenie sum kontrolnych pliku BACKUP.
///
/// Który algorytm faktycznie jest w pliku — jeszcze nie wiemy. Dlatego jest tu
/// kilka najczęstszych kandydatów plus funkcja `identify`, która próbuje je po
/// kolei i mówi, który pasuje. Precedens z PulsoKita jest dobry: pliki TD0
/// noszą MD5 i dało się to obsłużyć.
enum Checksum {

    // MARK: - Pojedyncze algorytmy

    static func sum8(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        var total: UInt8 = 0
        for byte in bytes { total = total &+ byte }
        return total
    }

    static func xor8(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        var total: UInt8 = 0
        for byte in bytes { total ^= byte }
        return total
    }

    static func sum32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var total: UInt32 = 0
        for byte in bytes { total = total &+ UInt32(byte) }
        return total
    }

    /// CRC-16/MODBUS: wielomian 0xA001 (odwrócony 0x8005), wartość początkowa 0xFFFF.
    static func crc16Modbus(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }

    /// CRC-32 taki jak w zip i PNG: wielomian odwrócony 0xEDB88320.
    static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    static func md5(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        let digest = Insecure.MD5.hash(data: Data(bytes))
        return Array(digest)
    }

    // MARK: - Liczenie zgodnie ze specyfikacją

    /// Zakres bajtów objętych sumą. Domyślnie: cały plik poza samą sumą.
    private static func coverage(spec: ChecksumSpec, size: Int) -> [Range<Int>] {
        if let range = spec.coverage {
            let lower = Swift.max(0, range.start)
            let upper = Swift.min(size, range.end + 1)
            return lower < upper ? [lower..<upper] : []
        }
        var parts: [Range<Int>] = []
        if spec.offset > 0 {
            parts.append(0..<Swift.min(spec.offset, size))
        }
        let after = spec.offset + spec.length
        if after < size {
            parts.append(after..<size)
        }
        return parts
    }

    private static func covered(spec: ChecksumSpec, over bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        for range in coverage(spec: spec, size: bytes.count) {
            out.append(contentsOf: bytes[range])
        }
        return out
    }

    /// Wylicza sumę i zwraca ją jako bajty gotowe do wpisania w plik.
    static func computeBytes(spec: ChecksumSpec, over bytes: [UInt8]) -> [UInt8]? {
        let data = covered(spec: spec, over: bytes)[...]
        switch spec.algorithm {
        case .none:
            return nil
        case .sum8:
            return [sum8(data)]
        case .xor8:
            return [xor8(data)]
        case .sum32LE:
            let value = sum32(data)
            return [
                UInt8(value & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 24) & 0xFF)
            ]
        case .crc16Modbus:
            let value = crc16Modbus(data)
            return [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
        case .crc32:
            let value = crc32(data)
            return [
                UInt8(value & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 24) & 0xFF)
            ]
        case .md5:
            return md5(data)
        }
    }

    /// To samo, ale jako tekst heks — do porównania z tym, co leży w pliku.
    static func compute(spec: ChecksumSpec, over bytes: [UInt8]) -> String? {
        guard let raw = computeBytes(spec: spec, over: bytes) else { return nil }
        return raw.map { String(format: "%02X", $0) }.joined()
    }

    // MARK: - Rozpoznawanie

    /// Próbuje odgadnąć algorytm: bierze bajty, które według analizy
    /// różnicowej są sumą kontrolną, i sprawdza, który algorytm daje
    /// dokładnie tę wartość.
    ///
    /// - Parameters:
    ///   - bytes: cała zawartość pliku
    ///   - offset: gdzie leży suma
    ///   - length: ile bajtów zajmuje
    /// - Returns: pasujące algorytmy; pusta lista = żaden z prostych kandydatów.
    static func identify(bytes: [UInt8], offset: Int, length: Int) -> [ChecksumAlgorithm] {
        guard offset >= 0, offset + length <= bytes.count else { return [] }
        let stored = Array(bytes[offset..<(offset + length)])
        var matches: [ChecksumAlgorithm] = []

        for algorithm in ChecksumAlgorithm.allCases where algorithm != .none {
            let spec = ChecksumSpec(offset: offset,
                                    length: length,
                                    algorithm: algorithm,
                                    coverage: nil)
            guard let computed = computeBytes(spec: spec, over: bytes) else { continue }
            guard computed.count == length else { continue }
            if computed == stored {
                matches.append(algorithm)
            }
        }
        return matches
    }
}
