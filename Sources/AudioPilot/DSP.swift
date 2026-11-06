import CoreAudio
import Foundation
import os
import Synchronization

/// Alles, was der Audio-Thread pro App braucht. Fixe Größe, kein Heap (SIMD statt Array).
struct DSPConfig {
    var gain: Float = 1
    var eqOn = false
    var bands = SIMD16<Float>(repeating: 0)   // 10 genutzt
    var compOn = false
    var threshold: Float = -20, ratio: Float = 3, attack: Float = 10, release: Float = 150, makeup: Float = 0, knee: Float = 6
}

/// Brücke Main-Thread ↔ Audio-Thread: Konfiguration hinter einem Lock, das der Audio-Thread
/// nur *versucht* (nie wartet), plus Atomics für Pegel und Lebenszeichen.
final class DSPParams: Sendable {
    private let config = OSAllocatedUnfairLock(initialState: DSPConfig())
    let version = Atomic<Int>(0)
    let peakBits = Atomic<UInt32>(0)
    let callbacks = Atomic<Int>(0)          // Watchdog: steigt bei jedem Audio-Callback
    let reductionBits = Atomic<UInt32>(0)   // Kompressor: aktuelle Absenkung in dB (für die Anzeige)

    var peak: Float { Float(bitPattern: peakBits.load(ordering: .relaxed)) }
    var reduction: Float { Float(bitPattern: reductionBits.load(ordering: .relaxed)) }
    var gain: Float { config.withLock { $0.gain } }

    func update(gain: Float, setting: AppSetting) {
        var c = DSPConfig()
        c.gain = gain
        c.eqOn = setting.eq.on && !setting.eq.isNeutral
        for (i, b) in setting.eq.bands.prefix(10).enumerated() { c.bands[i] = b }
        let k = setting.comp
        c.compOn = k.on
        (c.threshold, c.ratio, c.attack, c.release, c.makeup, c.knee) = (k.threshold, k.ratio, k.attack, k.release, k.makeup, k.knee)
        let final = c
        config.withLock { $0 = final }
        version.wrappingAdd(1, ordering: .releasing)
    }

    /// Nur vom Audio-Thread: nil, wenn das Lock gerade belegt ist (dann nächstes Mal).
    func tryRead() -> DSPConfig? { config.withLockIfAvailable { $0 } }
}

/// 10-Band-EQ (RBJ-Biquads), Kompressor, Verstärkung mit Rampe, Limiter + Soft-Clip. Stereo.
/// Der Limiter am Ende hält das Signal immer unter −1 dBFS: Boost macht lauter/dichter,
/// kann aber nie mehr als ein normal ausgesteuertes Lied an die Lautsprecher schicken.
final class DSPState: @unchecked Sendable {
    private static let bandCount = 10
    private let fs: Float
    private let coeffs = UnsafeMutablePointer<Float>.allocate(capacity: 50)   // 10 × b0 b1 b2 a1 a2
    private let z = UnsafeMutablePointer<Float>.allocate(capacity: 40)        // 10 × 2 Kanäle × 2
    private let active = UnsafeMutablePointer<Bool>.allocate(capacity: 10)
    private var version = -1
    private var cfg = DSPConfig()
    private var curGain: Float
    private var gr: Float = 0                     // Kompressor-Absenkung (dB, geglättet)
    private var cAttack: Float = 0, cRelease: Float = 0, cMakeup: Float = 1
    private var limGain: Float = 1
    private let limRelease: Float
    private static let ceiling: Float = 0.89      // −1 dBFS

    init(sampleRate: Double, params: DSPParams) {
        fs = Float(sampleRate > 0 ? sampleRate : 48000)
        coeffs.initialize(repeating: 0, count: 50)
        z.initialize(repeating: 0, count: 40)
        active.initialize(repeating: false, count: 10)
        curGain = params.gain
        limRelease = expf(-1 / (0.08 * fs))
    }

    deinit { coeffs.deallocate(); z.deallocate(); active.deallocate() }

    /// RBJ-Biquad für Band `i` (0 = Low-Shelf, 9 = High-Shelf, sonst Peaking Q ≈ 1.4), normiert auf a0.
    /// Auch für die EQ-Kurve im Menü – so zeigt die Kurve genau das, was zu hören ist.
    static func coefficients(_ i: Int, dB: Float, fs: Float) -> (b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        let f = EQSettings.freqs[min(max(i, 0), bandCount - 1)]
        let A = powf(10, dB / 40), w = 2 * Float.pi * min(f, fs * 0.45) / fs
        let c = cosf(w), s = sinf(w), sqA = sqrtf(A)
        var b0: Float, b1: Float, b2: Float, a0: Float, a1: Float, a2: Float
        if i == 0 {          // Low-Shelf
            let al = s / 2 * sqrtf(2)
            b0 = A * ((A + 1) - (A - 1) * c + 2 * sqA * al)
            b1 = 2 * A * ((A - 1) - (A + 1) * c)
            b2 = A * ((A + 1) - (A - 1) * c - 2 * sqA * al)
            a0 = (A + 1) + (A - 1) * c + 2 * sqA * al
            a1 = -2 * ((A - 1) + (A + 1) * c)
            a2 = (A + 1) + (A - 1) * c - 2 * sqA * al
        } else if i == bandCount - 1 {   // High-Shelf
            let al = s / 2 * sqrtf(2)
            b0 = A * ((A + 1) + (A - 1) * c + 2 * sqA * al)
            b1 = -2 * A * ((A - 1) + (A + 1) * c)
            b2 = A * ((A + 1) + (A - 1) * c - 2 * sqA * al)
            a0 = (A + 1) - (A - 1) * c + 2 * sqA * al
            a1 = 2 * ((A - 1) - (A + 1) * c)
            a2 = (A + 1) - (A - 1) * c - 2 * sqA * al
        } else {             // Peaking, Q ≈ 1.4 (Oktavbänder)
            let al = s / (2 * 1.4)
            b0 = 1 + al * A; b1 = -2 * c; b2 = 1 - al * A
            a0 = 1 + al / A; a1 = -2 * c; a2 = 1 - al / A
        }
        return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    }

    /// Betrag der Gesamt-Kurve in dB bei Frequenz `f` (nur fürs Zeichnen, nicht Echtzeit).
    static func response(bands: [Float], at f: Float, fs: Float = 48000) -> Float {
        let w = 2 * Float.pi * f / fs
        let c1 = cosf(w), s1 = sinf(w), c2 = cosf(2 * w), s2 = sinf(2 * w)
        var db: Float = 0
        for (i, g) in bands.prefix(bandCount).enumerated() where g != 0 && g.isFinite {
            let k = coefficients(i, dB: g, fs: fs)
            let nr = k.b0 + k.b1 * c1 + k.b2 * c2, ni = -(k.b1 * s1 + k.b2 * s2)
            let dr = 1 + k.a1 * c1 + k.a2 * c2, di = -(k.a1 * s1 + k.a2 * s2)
            db += 10 * log10f(max((nr * nr + ni * ni) / max(dr * dr + di * di, 1e-12), 1e-12))
        }
        return db
    }

    private func design(_ i: Int, dB: Float) {
        let k = Self.coefficients(i, dB: dB, fs: fs)
        let p = coeffs + i * 5
        p[0] = k.b0; p[1] = k.b1; p[2] = k.b2; p[3] = k.a1; p[4] = k.a2
    }

    private func sync(_ p: DSPParams) {
        let v = p.version.load(ordering: .acquiring)
        guard v != version, let c = p.tryRead() else { return }
        version = v
        let wasOn = cfg.eqOn
        cfg = c
        for i in 0..<Self.bandCount {
            active[i] = c.bands[i] != 0
            if active[i] { design(i, dB: c.bands[i]) }
        }
        if c.eqOn && !wasOn { z.update(repeating: 0, count: 40) }
        cAttack = expf(-1 / (max(c.attack, 0.1) * 0.001 * fs))
        cRelease = expf(-1 / (max(c.release, 10) * 0.001 * fs))
        cMakeup = powf(10, c.makeup / 20)
    }

    /// Kennlinie mit weichem Knie: wie viel dB über dem Ausgang abgesenkt wird.
    @inline(__always) private func reduction(_ x: Float) -> Float {
        let t = cfg.threshold, r = max(cfg.ratio, 1), w = cfg.knee
        let over = x - t
        if 2 * over <= -w { return 0 }
        if w > 0 && 2 * abs(over) < w { let q = over + w / 2; return (1 - 1 / r) * q * q / (2 * w) }
        return over * (1 - 1 / r)
    }

    @inline(__always) private func eq(_ x: Float, _ ch: Int) -> Float {
        var y = x
        for i in 0..<Self.bandCount where active[i] {
            let k = coeffs + i * 5, s = z + (i * 2 + ch) * 2
            let out = k[0] * y + s[0]
            s[0] = k[1] * y - k[3] * out + s[1]
            s[1] = k[2] * y - k[4] * out
            y = out
        }
        return y
    }

    @inline(__always) private func softClip(_ x: Float) -> Float {
        guard x.isFinite else { return 0 }
        let t: Float = 0.9
        if x > t { return t + (1 - t) * tanhf((x - t) / (1 - t)) }
        if x < -t { return -t - (1 - t) * tanhf((-x - t) / (1 - t)) }
        return x
    }

    /// Nur messen: Ausgang still lassen (das Original spielt selbst), Spitzenpegel merken. Echtzeit-sicher.
    static func meter(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, params: DSPParams) {
        params.callbacks.wrappingAdd(1, ordering: .relaxed)
        for b in UnsafeMutableAudioBufferListPointer(output) { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard ins.count > 0, let d = ins[ins.count - 1].mData else { return }
        let n = Int(ins[ins.count - 1].mDataByteSize) / MemoryLayout<Float>.size
        let src = d.assumingMemoryBound(to: Float.self)
        var peak: Float = 0
        for i in 0..<n { let a = abs(src[i]); if a.isFinite && a > peak { peak = a } }
        params.peakBits.store(min(peak, 4).bitPattern, ordering: .relaxed)
    }

    /// Echtzeit: kein Allokieren, kein Warten auf Locks, kein Logging.
    func process(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, params: DSPParams) {
        params.callbacks.wrappingAdd(1, ordering: .relaxed)
        let outs = UnsafeMutableAudioBufferListPointer(output)
        for b in outs { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }

        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        // Der Tap-Stream hängt hinten an (nach eventuellen Eingängen des Ausgabegeräts).
        guard ins.count > 0, let inData = ins[ins.count - 1].mData else { return }
        let inBuf = ins[ins.count - 1]
        let inCh = max(1, Int(inBuf.mNumberChannels))
        let frames = Int(inBuf.mDataByteSize) / (MemoryLayout<Float>.size * inCh)
        guard frames > 0 else { return }
        let src = inData.assumingMemoryBound(to: Float.self)

        // Ziel: die ersten zwei Ausgangskanäle, egal wie sie auf Puffer verteilt sind.
        var dL: UnsafeMutablePointer<Float>?, sL = 1
        var dR: UnsafeMutablePointer<Float>?, sR = 1
        var n = frames
        var found = 0
        for b in outs where found < 2 {
            guard let d = b.mData else { continue }
            let ch = max(1, Int(b.mNumberChannels))
            let p = d.assumingMemoryBound(to: Float.self)
            n = min(n, Int(b.mDataByteSize) / (MemoryLayout<Float>.size * ch))
            for c in 0..<min(ch, 2 - found) {
                if found == 0 { dL = p + c; sL = ch } else { dR = p + c; sR = ch }
                found += 1
            }
        }
        guard let dL else { return }

        sync(params)
        let target = cfg.gain
        let step = (target - curGain) / Float(max(n, 1))
        var g = curGain
        let comp = cfg.compOn
        var peak: Float = 0

        for i in 0..<n {
            var l = src[i * inCh]
            var r = inCh > 1 ? src[i * inCh + 1] : l
            if cfg.eqOn { l = eq(l, 0); r = eq(r, 1) }
            if comp {
                let lvl = 20 * log10f(max(max(abs(l), abs(r)), 1e-6))
                let target = reduction(lvl)
                gr = target > gr ? cAttack * gr + (1 - cAttack) * target : cRelease * gr + (1 - cRelease) * target
                let cg = cMakeup * powf(10, -gr / 20)
                l *= cg; r *= cg
            }
            g += step
            l *= g; r *= g
            // Limiter: sofort runter, wenn über der Decke, langsam wieder hoch.
            let a = max(abs(l), abs(r))
            let need = a > Self.ceiling ? Self.ceiling / a : 1
            limGain = min(need, 1 - limRelease * (1 - limGain))
            l = softClip(l * limGain)
            r = softClip(r * limGain)
            if let dR {
                dL[i * sL] = l
                dR[i * sR] = r
            } else {
                dL[i * sL] = (l + r) * 0.5     // Mono-Gerät
            }
            peak = max(peak, abs(l), abs(r))
        }
        curGain = target
        params.peakBits.store(peak.bitPattern, ordering: .relaxed)
        params.reductionBits.store((comp ? gr : 0).bitPattern, ordering: .relaxed)
        // Filter nach NaN/Inf zurücksetzen, damit nichts hängen bleibt.
        if !(z[0].isFinite && z[39].isFinite && gr.isFinite && limGain.isFinite) {
            z.update(repeating: 0, count: 40); gr = 0; limGain = 1
        }
    }
}
