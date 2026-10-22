# CarSpeak: Ad-Hoc Direct IPA Distribution & Architecture Guide

## 1. Context & ASC Decoupling
* **Decoupled from App Store Connect (ASC):** `CarSpeak` was intentionally removed from App Store Connect to eliminate Guideline 4.3 scrutiny and declutter Dr. Mohit's account while `CycleHub` is under review.
* **Personal Tool Deployment:** CarSpeak is maintained strictly as Dr. Mohit's private personal tool. It is deployed directly to his physical iPhone without touching App Store Connect or TestFlight.

## 2. Hardware & Provisioning Profile Target
* **Target Device:** `Alex's iPhone`
* **UDID:** `00008150-001E7C892200401C` (Status: `ENABLED` in Apple Developer Team `523MJL63MC`)
* **Bundle ID:** `com.AlexMohit.CarSpeak` (`5MA6YXSVP3`)
* **Active Apple Capabilities:**
  * `CARPLAY_PLAYABLE_CONTENT`
  * `CARPLAY_VOICE_BASED_CONVERSATION`
* **Signing Profile:** Ad-Hoc / Release-Testing profile provisioned automatically on `macos-15` via App Store Connect API (`Key ID: 38F6WA87DU`). Valid for 365 days.

## 3. Automated Ad-Hoc Pipeline
* **Workflow File:** `.github/workflows/adhoc_build.yml`
* **Trigger:** `push` to `main` or manual `workflow_dispatch`.
* **Export Config:** `ExportOptions-AdHoc.plist` (`method: ad-hoc`, `destination: export`).
* **Artifact Output:** GitHub Actions exports and uploads `CarSpeak-AdHoc-IPA` containing `CarSpeak.ipa`.
* **Local Staged Copy:** `C:\Users\mohal\Documents\antigravity\CarSpeak\build_artifact\CarSpeak-AdHoc-IPA\CarSpeak.ipa`

## 4. Installation onto iPhone (USB via Sideloadly)
1. Plug iPhone into Windows PC.
2. Launch **Sideloadly**.
3. Drag `CarSpeak.ipa` into Sideloadly.
4. Sign in with developer Apple ID `mohalex@gmail.com`.
5. Click **Start** to install directly to home screen with 365-day validity.
