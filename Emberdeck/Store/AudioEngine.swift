//
//  AudioEngine.swift
//  Emberdeck
//
//  Three kinds of sound: short effect chimes, a card's own audio pulled out of
//  an Anki deck, and text-to-speech for cards that have none. All of it goes
//  through the ambient session so it respects the silent switch and mixes with
//  whatever music is playing.
//

import AVFoundation
import Foundation

enum SoundEffect: String, CaseIterable {
    case correct, wrong, flip, combo, complete, streak
}

@MainActor
final class AudioEngine: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    static let shared = AudioEngine()

    private var effectPlayers: [SoundEffect: AVAudioPlayer] = [:]
    private var cardPlayer: AVAudioPlayer?
    private var cardQueue: [URL] = []
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionReady = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    private func prepareSession() {
        guard !sessionReady else { return }
        sessionReady = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Effects

    func play(_ effect: SoundEffect, enabled: Bool) {
        guard enabled else { return }
        prepareSession()
        if effectPlayers[effect] == nil,
           let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.prepareToPlay()
            effectPlayers[effect] = player
        }
        guard let player = effectPlayers[effect] else { return }
        player.currentTime = 0
        player.play()
    }

    // MARK: - Card audio

    /// Plays every audio file the field references, one after another.
    /// Returns false when there was nothing playable, so the caller can fall
    /// back to speech.
    @discardableResult
    func playCardAudio(_ names: [String]) -> Bool {
        let urls = names
            .filter { MediaStore.isPlayableAudio($0) && MediaStore.exists($0) }
            .map { MediaStore.url(for: $0) }
        guard !urls.isEmpty else { return false }
        prepareSession()
        stopCardAudio()
        cardQueue = urls
        playNextInQueue()
        return true
    }

    func stopCardAudio() {
        cardPlayer?.stop()
        cardPlayer = nil
        cardQueue.removeAll()
    }

    private func playNextInQueue() {
        guard !cardQueue.isEmpty else { cardPlayer = nil; return }
        let url = cardQueue.removeFirst()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { playNextInQueue(); return }
        player.delegate = self
        cardPlayer = player
        player.play()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playNextInQueue() }
    }

    // MARK: - Speech

    func speak(_ text: String, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        prepareSession()
        stopSpeaking()
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    func stopEverything() {
        stopCardAudio()
        stopSpeaking()
    }
}
