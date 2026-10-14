# Controlled KeePassPasskey fork

Owner: badigit/KeePassPasskey. Upstream baseline: v1.4.0,
`502d8b3af9a650c9025110c438033a2a96489b1a`.
Only `main` is the maintained fork; other inherited branches are upstream references.
No automatic upstream sync, Store channel, or release updater is used for this build.
GitHub Actions are disabled on the fork.

## Trust boundary and review

The DLL runs inside KeePass and can access the unlocked database. It is not sandboxed.
The separate Windows provider receives metadata and signatures over a local named pipe;
the private keys remain in KeePass. This is a focused source review, not a proof that
the complete application, libraries, compiler or OS contain no vulnerabilities.

The reviewed paths cover initialization, database enumeration/storage, generation/signing,
IPC framing and client identity, Windows operation/Hello signature verification,
cancellation, credential-cache synchronization, logging, plugin installation and updates.
No direct HTTP/socket transmission implementation was found in the runtime C# sources.
Build tools restore packages from nuget.org; these dependencies remain trusted inputs.
Windows credential cache contains site/user/credential metadata, not private keys.
Operational logs may contain RP IDs and errors; do not publish real logs unreviewed.

Changes from the baseline:

- Separate package `Badigit.KeePassPasskey`, publisher `CN=badigit.KeePassPasskey`,
  family `Badigit.KeePassPasskey_v6qz1enbfjpbm`, CLSID
  `be5cbbd1-3aaf-45ba-8963-9cabd07e21b4`, and private IPC namespace.
- The plugin accepts this exact family only, including in Debug. Upstream Store/GitHub
  clients are rejected and are never selected by the plugin package locator.
- Updater implementation is excluded from the plugin, its menu/startup path and update
  URL are removed, and persisted settings cannot re-enable it. The provider can still
  install the DLL bundled in our own manually installed package after an explicit action.
- IPC logs contain message types and sizes, not JSON payloads. Hello and credential lookup
  no longer log the user name or entry title.
- Metadata titles and new-entry templates do not evaluate KeePass references. A regression
  test demonstrated that `{REF:P@I:...}` in a title exposed another entry's password in
  metadata despite the clone's protected fields being blanked. Titles are now literal;
  only the explicit `{RP_NAME}` token in a new-entry template is substituted.
- Failure to create the pipe security descriptor stops the server instead of falling back
  to the default ACL. OS package installation and the local account remain trust boundaries.
- Windows Hello is mandatory. Previously users could disable every verifier while UP/UV
  flags were still asserted in the authenticator response.
- PRF/hmac-secret are not advertised: the baseline does not implement their outputs.
- Package sources, NuGet dependency content hashes, SDK and packaging/tool versions are pinned.

Known limits: the pipe client still has no per-message I/O timeout (connect is bounded);
trusted provider installation does not itself grant permission to use arbitrary credentials,
but a compromised provider is still a signing-oracle risk. Broad local-account compromise
is outside the protection provided by a fork. Full browser and Strongbox interoperability
require manual tests; unit tests do not establish them.

## Build and sign

Use PowerShell 5.1 or newer. Obtain .NET SDK 10.0.402, Windows SDK BuildTools
10.0.26100.7705 and the official KeePass 2.61.1 executable. URLs and expected hashes are
in `scripts/controlled-inputs.json`. Put KeePass.exe in `build/KeePass.exe`.
The SDK is under `%LOCALAPPDATA%/KeePassPasskey-buildtools/dotnet`; packaging tools are
in the standard Windows Kits installation. Install SDK features `OptionId.SigningTools`
and `OptionId.UWPManaged`. Pass `-DotNetPath` and `-WindowsSdkBin` for other locations.

```powershell
.\scripts\Build-Controlled.ps1
.\scripts\Sign-Controlled.ps1 -CertificateThumbprint "<local signing certificate thumbprint>"
```

Build-Controlled requires clean, committed sources and locked restores. It executes both
test suites with a 60-second hang limit and checks nonempty test results, provider payload
files, merged plugin size and MSIX creation. It records the commit and payload SHA256 hashes.
The provider is self-contained, untrimmed and without ReadyToRun so the build does not need
Visual Studio/DesktopBridge. MakeAppx validates and packages the manifest.
`-InitializeLock` is reserved for reviewed dependency changes. `-AllowDirty` is for diagnosis;
Sign-Controlled refuses its output. Archive `build/controlled` before rebuilding.
Do not run the upstream Publish-Package or InstallMsix scripts for this fork.

Create a local code-signing certificate with subject `CN=badigit.KeePassPasskey` and code-signing
EKU; keep its private key outside Git. Install trusts only the public certificate required
by Windows package deployment, in `LocalMachine/TrustedPeople` (not the Root CA store).
Its elevated helper checks the expected thumbprint, publisher and code-signing EKU.
The UAC prompt must be approved by the user. Never disable Windows signature verification or anti-malware.

## Controlled updates and recovery

For an update, fetch upstream, choose an explicit commit and inspect the diff against the
accepted baseline. Review dependency locks, build scripts, package identities, IPC, network,
logging and confirmation changes. Merge only reviewed changes, commit, build and test on a
synthetic database, sign and explicitly install. Never use an unattended pull/build/install.
Uninstall the author's Store package when replacing it; its independent updates are outside
this process. The controlled package has no AppInstaller update URI or Store identity.

Source and dependency/tool pins are backed by the GitHub fork. Generated builds and the
synthetic database are disposable; reconstruct them from the committed source. Keep the
previous signed MSIX and provenance before upgrading. The local non-exportable signing key
is not backed up: host loss requires a new certificate with the same publisher, explicit
local trust and a rebuild. This does not lose passkeys: those are in the user's separately
backed-up KDBX. Never put a real KDBX, signing private key, raw browsing report or private
log into this public repository.

## Manual acceptance

`scripts/Prepare-ControlledTest.ps1` creates a separate portable KeePass, a synthetic KDBX
and a Desktop shortcut. It can prepare the files while Windows installation awaits UAC;
it copies only the plugin whose hash matches the signed build's provenance.

Use only the isolated portable KeePass and synthetic KDBX. Enable the controlled provider
in Windows passkey settings; approve Windows Hello yourself. Register a disposable user on
a WebAuthn test site, save, authenticate, test cancellation and a locked database. Transfer
only the test KDBX to Strongbox and test both directions. A registration or signature test
does not establish database durability: save and reopen the KDBX before declaring success.
