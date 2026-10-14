// SPDX-License-Identifier: GPL-3.0-or-later
using KeePassPasskey.Ipc;
using KeePassPasskeyShared;
using KeePassPasskeyShared.Settings;
using Newtonsoft.Json;
using Xunit;

namespace KeePassPasskeyPlugin.Tests;

public class ControlledBuildTests
{
	[Theory]
	[InlineData("KeePassPasskeyProvider_rcm79ea08mqe4")]
	[InlineData("51133UweKgel.KeePassPasskey_2xyhjw5z6d8g4")]
	[InlineData("KeePassPasskeyProvider_hdweypz22wfyt")]
	[InlineData("Badigit.KeePassPasskey_v6qz1enbfjpbm_attacker")]
	[InlineData(null)]
	public void UpstreamAndLookalikePackagesAreRejected(string? name)
	{
		Assert.False(ClientVerifier.IsAllowedPackage(name));
	}

	[Fact]
	public void OnlyControlledPackageIsAllowed()
	{
		Assert.True(ClientVerifier.IsAllowedPackage(ControlledBuild.PackageFamilyName));
	}

	[Fact]
	public void PersistedSettingsCannotEnableUpdaterOrDisableHello()
	{
		var settings = JsonConvert.DeserializeObject<KeePassPasskeySettings>(
			"{\"checkForPluginUpdates\":true,\"registrationVerification\":0,\"signInVerification\":0}");
		Assert.NotNull(settings);
		Assert.False(settings!.CheckForPluginUpdates);
		Assert.True(settings.RegistrationVerification.HasFlag(UserVerificationMode.WindowsHello));
		Assert.True(settings.SignInVerification.HasFlag(UserVerificationMode.WindowsHello));
	}
}
