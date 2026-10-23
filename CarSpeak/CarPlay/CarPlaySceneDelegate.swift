import Foundation
// CarSpeak is intentionally decoupled from the CarPlay Dashboard app grid (`CPTemplateApplicationScene`)
// per Dr. Mohit's directive:
// 1. On CarPlay: Uses native Siri voice relay (`StartCarSpeakIntent` / `SwitchCarSpeakConversationIntent` in `CarSpeakShortcuts.swift`).
// 2. On iPhone: Auto-starts full-duplex Gemini 3.8 Live (`Puck` voice) using the iPhone's built-in microphone while playing over car/phone speakers.
