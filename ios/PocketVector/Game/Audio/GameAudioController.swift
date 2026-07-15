import AVFAudio
import Foundation

enum GameAudioCue: String, CaseIterable {
    case uiSelect = "ui-select"
    case countdown
    case snap
    case throwRelease = "throw"
    case ballFlight = "flight"
    case catchCompletion = "catch"
    case deepCompletion = "deep-completion"
    case touchdown
    case bonusActivated = "bonus-active"
    case multiplierIncreased = "multiplier"
    case incompletion = "incomplete"
    case interception
    case meterLoss = "meter-loss"
    case timerExpired = "timer-warning"
    case gameOver = "game-over"

    var relativePath: String {
        "audio/sfx/\(rawValue).wav"
    }

    var gain: Float {
        switch self {
        case .ballFlight:
            1.35
        case .countdown, .snap:
            0.9
        default:
            1
        }
    }
}

enum GameAudioResources {
    static let musicRelativePath = "audio/music/pocket-vector-drive.wav"

    static func url(for cue: GameAudioCue, in bundle: Bundle = .main) -> URL? {
        GameAssetResources.url(for: cue.relativePath, in: bundle)
    }

    static func musicURL(in bundle: Bundle = .main) -> URL? {
        GameAssetResources.url(for: musicRelativePath, in: bundle)
    }
}

@MainActor
final class GameAudioController {
    static let musicVolume: Float = 0.38
    static let effectsVolume: Float = 0.72
    private static let maximumVoicesPerCue = 3

    private let session = AVAudioSession.sharedInstance()
    private let effectURLs: [GameAudioCue: URL]
    private var musicPlayer: AVAudioPlayer?
    private var effectPools: [GameAudioCue: [AVAudioPlayer]] = [:]
    private var nextVoiceIndex: [GameAudioCue: Int] = [:]
    private var sessionIsActive = false
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    private var resumeMusicAfterInterruption = false
    private(set) var settings: GameSettingsProjection
    private(set) var isMuted: Bool

    var isMusicPlaying: Bool {
        musicPlayer?.isPlaying == true
    }

    func isPlaying(_ cue: GameAudioCue) -> Bool {
        effectPools[cue]?.contains(where: \.isPlaying) == true
    }

    init(
        bundle: Bundle = .main,
        settings: PlayerSettings = PlayerSettings()
    ) {
        let projectedSettings = GameSettingsProjection(settings)
        self.settings = projectedSettings
        isMuted = projectedSettings.isMuted
        effectURLs = Dictionary(
            uniqueKeysWithValues: GameAudioCue.allCases.compactMap { cue in
                GameAudioResources.url(for: cue, in: bundle).map { (cue, $0) }
            }
        )
        configureSession()
        prepareMusic(in: bundle)
        _ = activateSession()
        observeInterruptions()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    @discardableResult
    func play(_ cue: GameAudioCue) -> Bool {
        guard activateSession() else {
            return false
        }

        var players = effectPools[cue, default: []]
        let index: Int
        if let availableIndex = players.firstIndex(where: { !$0.isPlaying }) {
            index = availableIndex
        } else if players.count < Self.maximumVoicesPerCue,
                  let player = makeEffectPlayer(for: cue) {
            players.append(player)
            effectPools[cue] = players
            index = players.count - 1
        } else if !players.isEmpty {
            index = nextVoiceIndex[cue, default: 0] % players.count
        } else {
            return false
        }

        nextVoiceIndex[cue] = (index + 1) % players.count

        let player = players[index]
        player.currentTime = 0
        player.volume = isMuted ? 0 : min(1, settings.sfxVolume * cue.gain)
        return player.play()
    }

    func startMusic() {
        guard activateSession(), let musicPlayer, !musicPlayer.isPlaying else { return }
        musicPlayer.volume = isMuted ? 0 : settings.musicVolume
        musicPlayer.play()
    }

    func apply(_ playerSettings: PlayerSettings) {
        settings = GameSettingsProjection(playerSettings)
        isMuted = settings.isMuted
        applyVolumes()
    }

    @discardableResult
    func toggleMuted() -> Bool {
        isMuted.toggle()
        applyVolumes()
        return isMuted
    }

    func pauseMusic() {
        musicPlayer?.pause()
    }

    func stopMusic() {
        musicPlayer?.stop()
        musicPlayer?.currentTime = 0
    }

    func suspend() {
        resumeMusicAfterInterruption = false
        pauseMusic()
        stopEffects()
        guard sessionIsActive else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        sessionIsActive = false
    }

    @discardableResult
    func activateSession() -> Bool {
        if sessionIsActive { return true }
        do {
            try session.setActive(true)
            sessionIsActive = true
            return true
        } catch {
            #if DEBUG
            print("Pocket Vector audio session activation failed: \(error)")
            #endif
            return false
        }
    }

    private func configureSession() {
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } catch {
            #if DEBUG
            print("Pocket Vector audio session configuration failed: \(error)")
            #endif
        }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleInterruption(type: rawType, options: rawOptions)
            }
        }
    }

    private func handleInterruption(type rawType: UInt?, options rawOptions: UInt?) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            resumeMusicAfterInterruption = isMusicPlaying
            pauseMusic()
            stopEffects()
            sessionIsActive = false
        case .ended:
            sessionIsActive = false
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
            guard resumeMusicAfterInterruption, options.contains(.shouldResume) else {
                resumeMusicAfterInterruption = false
                return
            }
            resumeMusicAfterInterruption = false
            startMusic()
        @unknown default:
            sessionIsActive = false
        }
    }

    private func prepareMusic(in bundle: Bundle) {
        guard let url = GameAudioResources.musicURL(in: bundle) else {
            #if DEBUG
            print("Pocket Vector music resource is missing")
            #endif
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = settings.musicVolume
            player.prepareToPlay()
            musicPlayer = player
        } catch {
            #if DEBUG
            print("Pocket Vector music failed to load: \(error)")
            #endif
        }
    }

    private func makeEffectPlayer(for cue: GameAudioCue) -> AVAudioPlayer? {
        guard let url = effectURLs[cue], let player = try? AVAudioPlayer(contentsOf: url) else {
            return nil
        }
        player.volume = min(1, settings.sfxVolume * cue.gain)
        player.prepareToPlay()
        return player
    }

    private func applyVolumes() {
        musicPlayer?.volume = isMuted ? 0 : settings.musicVolume
        for (cue, players) in effectPools {
            let volume = isMuted ? 0 : min(1, settings.sfxVolume * cue.gain)
            for player in players {
                player.volume = volume
            }
        }
    }

    func stopEffects() {
        for player in effectPools.values.flatMap({ $0 }) where player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
    }
}
