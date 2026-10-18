import os
import json
import datetime
from pathlib import Path

AG_ROOT = Path(r"C:\Users\mohal\Documents\antigravity")
CARSPEAK_ROOT = AG_ROOT / "CarSpeak"

# Curated rich domain metadata for Dr. Mohit's Antigravity portfolio
CURATED_DOSSIERS = {
    "Radix": {
        "displayName": "Radix (RadixNeuro)",
        "category": "Neurosurgery & Clinical AI",
        "bundleId": "com.AlexMohit.RadixNeuro",
        "summary": "Neurosurgical & spinal clinical decision support, anatomical radiculopathy mapping, and diagnostic intelligence platform.",
        "techStack": ["SwiftUI", "iOS 18", "Cloudflare Workers", "Gemini AI"],
        "recentFocus": "Clinical radiculopathy localization, dermatome/myotome correlation, and TestFlight deployment."
    },
    "SnapEdge": {
        "displayName": "SnapEdge",
        "category": "AI Vision & Edge Utilities",
        "bundleId": "com.AlexMohit.SnapEdge",
        "summary": "Instant visual capture and edge AI analysis pipeline for rapid multimodal inspection.",
        "techStack": ["SwiftUI", "Cloudflare Workers", "Gemini Multimodal"],
        "recentFocus": "Low-latency camera-to-edge inference and structured visual extraction."
    },
    "ScreenDrop": {
        "displayName": "ScreenDrop Pro",
        "category": "Developer & Cross-Device Infrastructure",
        "bundleId": "com.AlexMohit.ScreenDrop",
        "summary": "Instant iPhone-to-PC visual transfer daemon (Port 7788) with iOS Double-Tap Shortcut, Tailscale, and Cloudflare Edge Relay.",
        "techStack": ["Python aiohttp", "Cloudflare Workers", "iOS Shortcuts"],
        "recentFocus": "Zero-latency screenshot auto-routing directly into active Antigravity conversation brains."
    },
    "LearnLab": {
        "displayName": "LearnLab Finance Education",
        "category": "Quantitative Finance & Education",
        "bundleId": "com.AlexMohit.LearnLab",
        "summary": "Interactive financial literacy, algorithmic investing, and quantitative market education studio.",
        "techStack": ["SwiftUI", "iOS 18", "Cloudflare Pages/Workers"],
        "recentFocus": "Interactive financial modules, options/ETF concepts, and App Store Connect sync."
    },
    "futurus": {
        "displayName": "Futurus AI Wealth",
        "category": "Quantitative Finance & Wealth",
        "bundleId": "com.AlexMohit.FuturusAI",
        "summary": "AI-driven wealth forecasting, portfolio trajectory modeling, and macro-financial scenario analysis.",
        "techStack": ["SwiftUI", "PWA", "Cloudflare Workers", "Gemini API"],
        "recentFocus": "Monte Carlo retirement/wealth simulations and real-time portfolio telemetry."
    },
    "hands-free-vocab": {
        "displayName": "Hands-Free Vocab",
        "category": "Commute Audio & Executive Rhetoric",
        "bundleId": "com.Alex.HandsFreeVocab",
        "summary": "Eyes-free audio vocabulary and rhetorical mastery trainer built for hands-free driving commutes.",
        "techStack": ["SwiftUI", "AVAudioSession", "Speech", "CarPlay Audio"],
        "recentFocus": "Continuous hands-free voice loop, lexical recall drills, and in-cabin audio routing."
    },
    "Vocalis": {
        "displayName": "Vocalis (ExecCommuteCoach)",
        "category": "Commute Audio & Executive Rhetoric",
        "bundleId": "com.alexmohit825.Vocalis",
        "summary": "Hands-free executive vocalization, prosody, and articulate speech coaching studio.",
        "techStack": ["SwiftUI", "AVAudioEngine", "Gemini Live/Audio"],
        "recentFocus": "Executive cadence analysis, acoustic feedback, and commute voice drills."
    },
    "HardwareHazard": {
        "displayName": "HardwareHazard",
        "category": "Neurosurgery & Spine Instrumentation",
        "bundleId": "com.AlexMohit.HardwareHazard",
        "summary": "Spinal and cranial instrumentation failure analysis, screw pullout/rod fracture biomechanics, and revision planning.",
        "techStack": ["SwiftUI", "Web/Cloudflare", "Gemini Vision"],
        "recentFocus": "Radiographic hardware complication detection and biomechanical revision strategies."
    },
    "DuralGuard": {
        "displayName": "DuralGuard",
        "category": "Neurosurgery & Perioperative Safety",
        "bundleId": "com.AlexMohit.DuralGuard",
        "summary": "CSF leak prevention, dural repair protocol optimizer, and postoperative pseudomeningocele risk stratification.",
        "techStack": ["SwiftUI", "iOS 18", "Cloudflare Workers"],
        "recentFocus": "Intraoperative dural closure algorithms and watertight seal risk scoring."
    },
    "ETF-Rebalancer": {
        "displayName": "ETF Rebalancer",
        "category": "Quantitative Finance & Wealth",
        "bundleId": "com.AlexMohit.ETFRebalancer",
        "summary": "Tax-aware multi-asset ETF portfolio drift analyzer and automated rebalancing allocation calculator.",
        "techStack": ["TypeScript", "React/Vite", "Cloudflare Pages"],
        "recentFocus": "Drift threshold alerts, Sharpe optimization, and capital-gains-minimized rebalance execution."
    },
    "GateCheck": {
        "displayName": "GateCheck",
        "category": "Verification & Pre-Flight Compliance",
        "bundleId": "com.AlexMohit.GateCheck",
        "summary": "Automated pre-flight verification gate and surgical/engineering checklist enforcement tool.",
        "techStack": ["SwiftUI", "Web", "Cloudflare"],
        "recentFocus": "Deterministic go/no-go safety verification workflows."
    },
    "CausationMatrix": {
        "displayName": "CausationMatrix",
        "category": "Medicolegal & Forensic Analysis",
        "bundleId": "com.AlexMohit.CausationMatrix",
        "summary": "Medicolegal proximate cause analyzer mapping trauma biomechanics, pre-existing pathology, and clinical timelines.",
        "techStack": ["React", "Cloudflare Workers", "Gemini Pro"],
        "recentFocus": "Differential etiology scoring and Daubert-grade causation matrices."
    },
    "CPTArmor": {
        "displayName": "CPTArmor",
        "category": "Medical Coding & Revenue Integrity",
        "bundleId": "com.AlexMohit.CPTArmor",
        "summary": "Defensive neurosurgical & spine CPT coding validator, NCCI edit scrubber, and payer denial shield.",
        "techStack": ["Web/PWA", "Cloudflare Workers", "Gemini API"],
        "recentFocus": "Operative note language audit to prevent payer bundling and downcoding."
    },
    "CPTcodes": {
        "displayName": "CPTcodes Reference Engine",
        "category": "Medical Coding & Revenue Integrity",
        "bundleId": "com.AlexMohit.CPTcodes",
        "summary": "Rapid spine and cranial CPT code lookup, RVU calculator, and modifier decision tree.",
        "techStack": ["JavaScript", "Cloudflare Pages"],
        "recentFocus": "Multi-level arthrodesis, decompression, and instrumentation RVU aggregation."
    },
    "cycleHub": {
        "displayName": "CycleHub AI",
        "category": "Performance Cycling & Biometrics",
        "bundleId": "com.AlexMohit.CycleHubAI",
        "summary": "Cycling telemetry, power-zone analytics, route weather/wind modeling, and endurance training hub.",
        "techStack": ["SwiftUI", "HealthKit", "Cloudflare Workers"],
        "recentFocus": "FTP power curve tracking and AI ride readiness briefings."
    },
    "ForensicReview": {
        "displayName": "ForensicReview",
        "category": "Medicolegal & Forensic Analysis",
        "bundleId": "com.AlexMohit.ForensicReview",
        "summary": "Expert witness medical record chronology builder, standard-of-care analysis, and deposition preparation platform.",
        "techStack": ["Web App", "Cloudflare Workers", "Gemini 2.5/3.8"],
        "recentFocus": "Automated multi-volume record synthesis and timeline discrepancy detection."
    },
    "somnalux": {
        "displayName": "SomnaLux",
        "category": "Circadian Health & Sleep Science",
        "bundleId": "com.Alex.SomnaLux",
        "summary": "Circadian rhythm optimizer, sleep architecture analyzer, and shift/call recovery engine.",
        "techStack": ["SwiftUI", "HealthKit", "iOS 18"],
        "recentFocus": "Post-call neurosurgical fatigue mitigation and smart light/melatonin phase timing."
    },
    "VocabRoady": {
        "displayName": "VocabRoady",
        "category": "Commute Audio & Executive Rhetoric",
        "bundleId": "com.Alex.VocabRoady",
        "summary": "Road-warrior conversational vocabulary builder with active spoken sentence evaluation.",
        "techStack": ["SwiftUI", "AVAudioSession", "iOS 18"],
        "recentFocus": "Hands-free spoken contextual usage grading while driving."
    },
    "RadRelay": {
        "displayName": "RadRelay",
        "category": "Neurosurgery & Neuroimaging",
        "bundleId": "com.AlexMohit.RadRelay",
        "summary": "Rapid spine/brain imaging triage and structured radiological finding relay.",
        "techStack": ["Web/Swift", "Cloudflare Workers", "Gemini Vision"],
        "recentFocus": "Key slice annotation and urgent neurosurgical pathology flagging."
    },
    "EHRLens": {
        "displayName": "EHRLens",
        "category": "Neurosurgery & Clinical AI",
        "bundleId": "com.AlexMohit.EHRLens",
        "summary": "Optical EHR screen reader and clinical context extractor for instant chart synthesis.",
        "techStack": ["Web/PWA", "Cloudflare Workers", "Gemini Multimodal"],
        "recentFocus": "Zero-PHI-leakage rapid lab, imaging report, and H&P summarization."
    },
    "ClinNote": {
        "displayName": "ClinNote",
        "category": "Neurosurgery & Clinical Documentation",
        "bundleId": "com.AlexMohit.ClinNote",
        "summary": "Ambient clinical dictation and structured neurosurgical operative/consult note generator.",
        "techStack": ["Web/iOS", "Cloudflare Workers", "Gemini API"],
        "recentFocus": "High-precision operative dictation formatting with medical billing alignment."
    },
    "Medicolegal-Case": {
        "displayName": "Medicolegal Case Studio",
        "category": "Medicolegal & Forensic Analysis",
        "bundleId": "com.AlexMohit.MedicolegalCase",
        "summary": "Comprehensive IME (Independent Medical Examination) and expert witness report workstation.",
        "techStack": ["Web/Cloudflare", "Gemini Pro"],
        "recentFocus": "Structured chronological narrative generation and citation linking."
    },
    "LucidPulse": {
        "displayName": "LucidPulse",
        "category": "Biometrics & Cognitive Performance",
        "bundleId": "com.AlexMohit.LucidPulse",
        "summary": "HRV, autonomic readiness, and cognitive focus state monitor.",
        "techStack": ["SwiftUI", "HealthKit"],
        "recentFocus": "Autonomic stress readiness before high-stakes surgical procedures."
    },
    "StreamGuard": {
        "displayName": "StreamGuard",
        "category": "Network & Media Reliability",
        "bundleId": "com.AlexMohit.StreamGuard",
        "summary": "Real-time stream integrity monitor and resilient packet recovery utility.",
        "techStack": ["TypeScript", "Cloudflare Workers"],
        "recentFocus": "Jitter telemetry and automatic stream failover."
    },
    "aptus-health": {
        "displayName": "Aptus Health (iOS + watchOS)",
        "category": "Biometrics & Preventive Health",
        "bundleId": "com.Alex.Aptus",
        "summary": "Integrated iPhone and Apple Watch physiological telemetry and longevity tracking suite.",
        "techStack": ["SwiftUI", "WatchKit", "HealthKit"],
        "recentFocus": "Companion WatchKit synchronization and real-time cardio-metabolic scoring."
    },
    "MDEsq": {
        "displayName": "MDEsq & MDEsq-PWA",
        "category": "Medicolegal & Forensic Analysis",
        "bundleId": "com.AlexMohit.MDEsq",
        "summary": "Physician-attorney dual-domain medicolegal intelligence engine for malpractice defense, IMEs, and tort analysis.",
        "techStack": ["React", "Cloudflare Pages/Workers", "Gemini API"],
        "recentFocus": "Standard-of-care breach matrix and automated medical timeline extraction."
    },
    "axon-forge": {
        "displayName": "Axon-Forge",
        "category": "AI Agent & Prompt Engineering",
        "bundleId": "com.AlexMohit.AxonForge",
        "summary": "Modular neural workflow builder and multi-agent orchestration studio.",
        "techStack": ["TypeScript", "Cloudflare Workers"],
        "recentFocus": "Agentic tool chains and deterministic verification loops."
    },
    "WinLens": {
        "displayName": "WinLens",
        "category": "Desktop AI & Visual Assistant",
        "bundleId": "com.AlexMohit.WinLens",
        "summary": "Windows desktop visual overlay and instant screen-region AI analyzer.",
        "techStack": ["Python", "Web", "Gemini Vision"],
        "recentFocus": "One-hotkey desktop capture and diagnostic analysis."
    },
    "Reputation-Manager": {
        "displayName": "Physician Reputation Manager",
        "category": "Practice Management & Digital Presence",
        "bundleId": "com.AlexMohit.ReputationManager",
        "summary": "Automated patient review monitoring, HIPAA-compliant response drafting, and SEO sentiment analytics.",
        "techStack": ["Web", "Cloudflare Workers", "Gemini API"],
        "recentFocus": "HIPAA-safe empathetic review response generation."
    },
    "Kalyx-Stocks": {
        "displayName": "Kalyx Stocks",
        "category": "Quantitative Finance & Equities",
        "bundleId": "com.AlexMohit.KalyxStocks",
        "summary": "Equity factor screener, earnings momentum tracker, and institutional flow analyzer.",
        "techStack": ["Web/React", "Cloudflare Workers"],
        "recentFocus": "Technical/fundamental confluence scoring and alert generation."
    },
    "PJKPredict": {
        "displayName": "PJKPredict & PJKPredictPWA",
        "category": "Neurosurgery & Spine Biomechanics",
        "bundleId": "com.AlexMohit.PJKPredict",
        "summary": "Proximal Junctional Kyphosis (PJK) & PJF preoperative risk calculator using spinopelvic alignment parameters (PI-LL, SVA, TPA, UIV).",
        "techStack": ["SwiftUI", "PWA", "Cloudflare Pages"],
        "recentFocus": "Sagittal balance biomechanics, UIV selection, and prophylactic tether/vertebroplasty thresholds."
    },
    "TrialCompass": {
        "displayName": "TrialCompass AI",
        "category": "Neurosurgery & Clinical Trials",
        "bundleId": "com.AlexMohit.TrialCompassAI",
        "summary": "ClinicalTrials.gov APIv2 neuro-oncology and spine trial matcher with instant eligibility screening.",
        "techStack": ["SwiftUI", "Cloudflare Workers", "ClinicalTrials.gov API"],
        "recentFocus": "Real-time NCT trial lookup and patient inclusion/exclusion matching."
    },
    "put-option-screener": {
        "displayName": "Put Option Screener",
        "category": "Quantitative Finance & Options",
        "bundleId": "com.AlexMohit.PutScreener",
        "summary": "Cash-secured put (CSP) and wheel-strategy options screener ranking annualized return on collateral, delta, and IV rank.",
        "techStack": ["Python/JS", "Cloudflare Pages"],
        "recentFocus": "High-probability OTM put yield filtering and assignment safety margins."
    },
    "deckmaster-ai": {
        "displayName": "DeckMaster AI",
        "category": "Executive Presentations & Medical Grand Rounds",
        "bundleId": "com.AlexMohit.DeckMasterAI",
        "summary": "Automated executive and academic slide deck generator with structured data storytelling.",
        "techStack": ["Web", "Cloudflare Workers", "Gemini API"],
        "recentFocus": "Grand rounds and investor presentation synthesis."
    },
    "spine-measure": {
        "displayName": "Spine-Measure",
        "category": "Neurosurgery & Spine Biomechanics",
        "bundleId": "com.AlexMohit.SpineMeasure",
        "summary": "Precision digital spinopelvic Cobb angle, Pelvic Incidence (PI), Lumbar Lordosis (LL), and SVA radiographic measurement workstation.",
        "techStack": ["HTML5 Canvas", "JavaScript", "GitHub Pages / Local Storage"],
        "recentFocus": "Sub-degree geometric vector tools for sagittal/coronal deformity planning."
    },
    "Axis-Albums": {
        "displayName": "Axis Albums",
        "category": "iOS Photo Intelligence",
        "bundleId": "com.AlexMohit.AxisAlbums",
        "summary": "AI-powered iOS photo library organizer and smart semantic album curator.",
        "techStack": ["SwiftUI", "PhotoKit", "CoreML / Vision"],
        "recentFocus": "On-device clustering and rapid album sorting."
    },
    "flora-finder": {
        "displayName": "FloraFinder AI",
        "category": "Botanical Vision & Pathology",
        "bundleId": "com.AlexMohit.FloraFinderAI",
        "summary": "AI plant species identifier and foliar pathology diagnostic guide.",
        "techStack": ["SwiftUI", "Gemini Vision", "Cloudflare Workers"],
        "recentFocus": "Instant camera taxonomic classification and care protocols."
    },
    "JurisShield": {
        "displayName": "JurisShield",
        "category": "Medicolegal & Asset/Liability Protection",
        "bundleId": "com.AlexMohit.JurisShield",
        "summary": "Medical malpractice defensive documentation auditor and legal risk mitigation suite.",
        "techStack": ["SwiftUI", "Cloudflare Workers", "Gemini API"],
        "recentFocus": "Chart audit for high-risk neurosurgical consent and follow-up documentation."
    },
    "synapse-bio": {
        "displayName": "SynapseBio AI",
        "category": "Biomedical Research & Genomics",
        "bundleId": "com.AlexMohit.SynapseBioAI",
        "summary": "Molecular target, pathway, and translational neurobiology research synthesizer.",
        "techStack": ["SwiftUI", "Cloudflare Workers", "PubMed/UniProt APIs"],
        "recentFocus": "Literature synthesis and therapeutic target discovery."
    },
    "re-scout": {
        "displayName": "RE Scout",
        "category": "Real Estate Investment Analytics",
        "bundleId": "com.AlexMohit.REScout",
        "summary": "Cap-rate, cash-on-cash return, and distressed property underwriting analyzer.",
        "techStack": ["SwiftUI", "Web", "Cloudflare"],
        "recentFocus": "Rapid multi-family and commercial deal screening."
    },
    "hands-free-lingo": {
        "displayName": "Hands-Free Lingo (NativeTongue / VocalLingo)",
        "category": "Commute Audio & Language Mastery",
        "bundleId": "com.Alex.NativeTongue",
        "summary": "CarPlay-enabled hands-free spoken language acquisition and real-time conversational fluency trainer.",
        "techStack": ["SwiftUI", "CarPlay Entitlement", "AVAudioSession", "Gemini Live"],
        "recentFocus": "Approved on CarPlay dashboard; continuous eyes-free bilingual immersion while driving."
    },
    "vigilor": {
        "displayName": "VigilOR Sentinel",
        "category": "Neurosurgery & Intraoperative Safety",
        "bundleId": "com.AlexMohit.VigilOR",
        "summary": "Intraoperative neuromonitoring (IONM), blood loss/timer tracking, and OR safety sentinel.",
        "techStack": ["SwiftUI", "iOS 18", "TestFlight"],
        "recentFocus": "Real-time OR status alerts and surgical milestone logging."
    },
    "preauthIQ": {
        "displayName": "PreAuthIQ",
        "category": "Medical Coding & Prior Authorization",
        "bundleId": "com.AlexMohit.PreAuthIQ",
        "summary": "Automated medical necessity letter generator citing payer LCD/NCD guidelines to overturn spine/neurosurgical prior-auth denials.",
        "techStack": ["Web", "Cloudflare Workers", "Gemini Pro"],
        "recentFocus": "Payer policy criteria matching and peer-to-peer rebuttal briefs."
    },
    "robot-solver": {
        "displayName": "ScreenBridge / Robot Solver",
        "category": "Autonomous Visual Automation",
        "bundleId": "com.AlexMohit.ScreenBridge",
        "summary": "Visual screen reasoning and automated UI interaction bridge.",
        "techStack": ["Python", "Gemini Vision"],
        "recentFocus": "Isolated in joyful-hawking workspace."
    },
    "CarSpeak": {
        "displayName": "CarSpeak",
        "category": "Commute Audio & Executive AI Engine",
        "bundleId": "com.AlexMohit.CarSpeak",
        "summary": "5G-resilient hands-free CarPlay conversational AI engine with voice-switchable conversation archives and full Antigravity portfolio memory.",
        "techStack": ["SwiftUI", "CarPlay Voice Template", "AppIntents", "Gemini 3.8 Live", "Cloudflare Workers KV"],
        "recentFocus": "Zero-dropout 5G tower handoff ring buffer, Siri + Steering Wheel media controls, and live voice thread switching."
    }
}

def scan_ag_portfolio():
    projects = []
    if not AG_ROOT.exists():
        return projects

    for item in sorted(AG_ROOT.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True):
        if not item.is_dir() or item.name.startswith(".") or item.name == "_inbox":
            continue
        name = item.name
        mtime = datetime.datetime.fromtimestamp(item.stat().st_mtime).strftime("%Y-%m-%d")
        curated = CURATED_DOSSIERS.get(name, {})

        # Read-only snippet from README.md if present
        readme_excerpt = ""
        for rname in ["README.md", "readme.md"]:
            rpath = item / rname
            if rpath.exists():
                try:
                    lines = [
                        ln.strip() for ln in rpath.read_text(encoding="utf-8", errors="ignore").splitlines()
                        if ln.strip() and not ln.strip().startswith("#") and not ln.strip().startswith("!")
                    ]
                    if lines:
                        readme_excerpt = " ".join(lines[:3])[:280]
                except Exception:
                    pass
                break

        entry = {
            "id": name.lower().replace("_", "-"),
            "folderName": name,
            "displayName": curated.get("displayName", name),
            "category": curated.get("category", "Antigravity Application"),
            "bundleId": curated.get("bundleId", f"com.AlexMohit.{name}"),
            "lastModified": mtime,
            "summary": curated.get("summary") or readme_excerpt or f"Antigravity project {name} developed by Dr. A. Alex Mohit.",
            "techStack": curated.get("techStack", ["Web/iOS", "Cloudflare", "Gemini AI"]),
            "recentFocus": curated.get("recentFocus", "Active development and verification in Antigravity workspace."),
            "roadmapNotes": []
        }
        projects.append(entry)

    # Also include additional App Store Connect native iOS apps
    extra_asc_apps = [
        {
            "id": "neurocall",
            "folderName": "NeuroCall",
            "displayName": "NeuroCall Neurosurgery",
            "category": "Neurosurgery & Clinical AI",
            "bundleId": "com.AlexMohit.NeuroCall",
            "lastModified": "2026-10-01",
            "summary": "On-call neurosurgical triage, GCS/Hunt-Hess/Fisher grading, and emergent consult coordination.",
            "techStack": ["SwiftUI", "iOS 18"],
            "recentFocus": "Rapid cranial and spinal emergency triage protocols.",
            "roadmapNotes": []
        },
        {
            "id": "neurosurgiq",
            "folderName": "NeurosurgIQ",
            "displayName": "NeurosurgIQ Neurosurgery",
            "category": "Neurosurgery & Board Mastery",
            "bundleId": "com.AlexMohit.NeurosurgIQ",
            "lastModified": "2026-10-01",
            "summary": "ABNS neurosurgical board review, neuroanatomy, and operative case simulation.",
            "techStack": ["SwiftUI", "iOS 18"],
            "recentFocus": "High-yield neurosurgical case vignettes and anatomical pearls.",
            "roadmapNotes": []
        },
        {
            "id": "trephine",
            "folderName": "Trephine",
            "displayName": "Trephine Neurosurgery",
            "category": "Neurosurgery & Cranial Planning",
            "bundleId": "com.AlexMohit.Trephine",
            "lastModified": "2026-10-01",
            "summary": "Cranial burr hole, craniotomy trajectory, and hematoma evacuation planning utility.",
            "techStack": ["SwiftUI", "iOS 18"],
            "recentFocus": "Cranial surface landmark localization.",
            "roadmapNotes": []
        },
        {
            "id": "craniospine",
            "folderName": "CranioSpine",
            "displayName": "CranioSpine Neurosurgery",
            "category": "Neurosurgery & Spine Biomechanics",
            "bundleId": "com.AlexMohit.CranioSpine",
            "lastModified": "2026-10-01",
            "summary": "Integrated cranial and spinal surgical reference, classification systems, and outcome scores.",
            "techStack": ["SwiftUI", "iOS 18"],
            "recentFocus": "Comprehensive spine and cranial grading scales.",
            "roadmapNotes": []
        },
        {
            "id": "cortexcall",
            "folderName": "CortexCall",
            "displayName": "CortexCall Neurosurgery",
            "category": "Neurosurgery & Clinical AI",
            "bundleId": "com.AlexMohit.CortexCall",
            "lastModified": "2026-10-01",
            "summary": "Voice-first neurosurgical clinical assistant and call shift handoff manager.",
            "techStack": ["SwiftUI", "iOS 18"],
            "recentFocus": "Structured sign-out and ICU neuro-check tracking.",
            "roadmapNotes": []
        }
    ]
    existing_ids = {p["id"] for p in projects}
    for app in extra_asc_apps:
        if app["id"] not in existing_ids:
            projects.append(app)

    return projects

def main():
    projects = scan_ag_portfolio()
    print(f"Indexed {len(projects)} Antigravity projects.")

    # Write JS module for Cloudflare Worker
    worker_seed_path = CARSPEAK_ROOT / "worker" / "src" / "ag_portfolio_seed.js"
    js_content = f"// Auto-generated by scripts/sync_ag_projects.py — {len(projects)} Antigravity Projects\n"
    js_content += "export const AG_PORTFOLIO_SEED = " + json.dumps(projects, indent=2) + ";\n"
    worker_seed_path.write_text(js_content, encoding="utf-8")

    # Write JSON seed for iOS App Bundle
    ios_seed_path = CARSPEAK_ROOT / "CarSpeak" / "Models" / "AGPortfolioSeed.json"
    ios_seed_path.write_text(json.dumps(projects, indent=2), encoding="utf-8")
    print(f"Wrote {worker_seed_path} and {ios_seed_path}")

if __name__ == "__main__":
    main()
