# CoolCumber Privacy Policy

Last updated: August 20, 2026

CoolCumber is a local-first macOS utility. System telemetry such as thermal
state, available sensor readings, fan state, memory pressure, storage capacity,
network rates, and process resource usage is processed on the Mac to present the
app's monitoring and diagnostic features.

CoolCumber does not include advertising or third-party analytics. The app does
not upload system telemetry by default.

## Optional online AI analysis

Online AI analysis is optional and starts only when the user explicitly invokes
it after configuring their own provider API key. The request can include the
verified metrics visible in the app and a small number of process names. It does
not include filesystem paths. Requests are sent directly to the provider chosen
by the user (currently DeepSeek or Alibaba Cloud DashScope) and are governed by
that provider's terms and privacy policy.

API keys are stored in the macOS Keychain. Builds released before this policy
may have stored a key in application preferences; the current app migrates and
removes that legacy plaintext value after a successful Keychain save.

## Privileged helper

The direct-download edition may install a signed privileged helper after the
user explicitly approves it in macOS System Settings. The helper is used only
for hardware capabilities that are unavailable to a sandboxed app. The Mac App
Store edition does not contain or connect to this helper.

## Storage and retention

Local preferences and diagnostic history remain on the Mac until the user
removes them or uninstalls the app. CoolCumber does not operate an account or
cloud telemetry database for the current product.

## Contact

Privacy questions can be sent to hi@slmcamp.com.
