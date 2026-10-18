# CarSpeak — 5G-Resilient Hands-Free CarPlay Conversational AI Engine

**Copyright 2026 A. Alex Mohit**  
**Bundle ID:** `com.AlexMohit.CarSpeak`  
**Live Edge Endpoint & Web Companion:** [https://carspeak-api.mohalex.workers.dev](https://carspeak-api.mohalex.workers.dev)

## Overview
`CarSpeak` is a dedicated iOS & Apple CarPlay hands-free voice AI engine engineered to survive highway 5G tower handoffs without conversation dropouts, while providing voice-activated switching across archived conversations and complete memory of all **56 Antigravity (AG) projects** developed by Dr. A. Alex Mohit.

## Core Architecture
1. **5G Tower-Handoff Resilience (`OutboxRingBuffer` + `CellularHandoffMonitor` + `SessionResumptionConfig`):**
   - 5.0-second lock-free circular PCM16 audio outbox buffer preserves spoken syllables during cellular tower transitions.
   - `NWPathMonitor` multipath handoff detection triggers sub-250ms socket healing using Gemini 3.8 Live `sessionResumptionUpdate.newHandle` and `SlidingWindow` context compression.
2. **Voice-Activated Conversation Archive (`ConversationVaultClient`):**
   - Switch between archived conversations at any time by voice (*"Switch to our conversation on DuralGuard"*, *"List my archived conversations"*, *"Start a new conversation on Spine-Measure"*).
3. **56-Project Antigravity Portfolio Memory (`AGPortfolioSeed.json` + Cloudflare KV `CARSPEAK_KV`):**
   - Pre-indexed and cloud-synced with all 56 Antigravity applications (`Radix`, `SnapEdge`, `ScreenDrop`, `LearnLab`, `Futurus`, `DuralGuard`, `HardwareHazard`, `PJKPredict`, `Spine-Measure`, `VigilOR`, `MDEsq`, `JurisShield`, `CPTArmor`, `Hands-Free Lingo`, `Vocalis`, `SomnaLux`, `TrialCompass`, etc.).
4. **Dual-Path CarPlay Launch:**
   - **Siri Eyes-Free Launch (`AppIntents`):** *"Hey Siri, start CarSpeak"* + Steering Wheel Media Controls (`MPRemoteCommandCenter`) + CarPlay "Now Playing" Dashboard.
   - **Native CarPlay Voice Dashboard (`CPVoiceControlTemplate` & `CPListTemplate`):** Ready for the Apple Developer account's **CarPlay Voice Based Conversation** capability (`523MJL63MC`).
