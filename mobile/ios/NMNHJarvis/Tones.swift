import Foundation

/// Звуки, собранные в памяти: тишина для фонового «плеера» и короткие сигналы для очков.
enum Tones {
    /// WAV 16 бит моно. samples - значения от -1 до 1.
    static func wav(_ samples: [Double], rate: Int = 16_000) -> Data {
        var data = Data()
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); put32(36 + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put32(16); put16(1); put16(1)
        put32(UInt32(rate)); put32(UInt32(rate * 2)); put16(2); put16(16)
        data.append(contentsOf: Array("data".utf8)); put32(bytes)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * Double(Int16.max))
            put16(UInt16(bitPattern: v))
        }
        return data
    }

    /// Тишина: iOS считает приложение плеером, пока она играет в цикле.
    static func silence(seconds: Double = 10, rate: Int = 16_000) -> Data {
        wav([Double](repeating: 0, count: Int(seconds * Double(rate))), rate: rate)
    }

    /// Сигнал из нот подряд (частота, длительность), с мягким краем без щелчка.
    static func chime(_ notes: [(Double, Double)], volume: Double = 0.35, rate: Int = 16_000) -> Data {
        var out: [Double] = []
        for (freq, length) in notes {
            let n = Int(length * Double(rate))
            let edge = max(1, min(n / 5, rate / 100))
            for i in 0..<n {
                let fade = Double(min(i, n - 1 - i, edge)) / Double(edge)
                out.append(sin(2 * .pi * freq * Double(i) / Double(rate)) * volume * min(1, fade))
            }
        }
        return wav(out, rate: rate)
    }

    static let listen = chime([(660, 0.09), (990, 0.12)])  // «слушаю»
    static let sent = chime([(990, 0.09), (660, 0.12)])    // «отправила»
    static let error = chime([(330, 0.18), (250, 0.25)])   // «не вышло»
}
