// SPDX-FileCopyrightText: Copyright (C) 2026 Uwe Koegel
// SPDX-License-Identifier: GPL-3.0-or-later
using KeePassPasskeyShared;

namespace KeePassPasskeyProvider.Authenticator;

/// <summary>Distribution channel a build belongs to; selected at compile time.</summary>
internal enum DistributionChannel
{
	/// <summary>Debug build with the dev identity (CN=KeePassPasskey Dev).</summary>
	Dev,
	/// <summary>Self-signed release published on GitHub.</summary>
	GitHub,
	/// <summary>Release published to the Microsoft Store (/p:Store=true).</summary>
	Store,
}

internal static class PluginConstants
{
	/// <summary>Separate COM identity; upstream packages cannot activate this fork.</summary>
	public static readonly Guid KeePassPasskeyProviderClsid = new(ControlledBuild.ProviderClsid);
	public const DistributionChannel Channel = DistributionChannel.GitHub;
	public static readonly Guid KeePassPasskeyProviderAaguid = new("c98c97f9-5c19-4d16-9259-9e167a264f41");

	/// <summary>Readable channel name, appended to copied version strings.</summary>
	public static string ChannelDisplayName => "Controlled local build";

	/// <summary>Provider log file name</summary>
	public const string ProviderLogFileName = "Provider.log";

	/// <summary>AAGUID as 16 bytes in RFC 4122 big-endian order, for use in authenticatorData and CBOR.</summary>
	public static readonly byte[] KeePassPasskeyProviderAaguidBytes = AaguidToRfc4122Bytes(KeePassPasskeyProviderAaguid);

	/// <summary>Converts a GUID to 16 bytes in RFC 4122 big-endian order (authenticatorData / CBOR layout).</summary>
	internal static byte[] AaguidToRfc4122Bytes(Guid guid)
	{
		var bytes = new byte[16];
		guid.TryWriteBytes(bytes, bigEndian: true, out _);
		return bytes;
	}

	public const string PluginName = "KeePassPasskey Controlled ";

	// Named kernel objects (mutexes + the tray "show" event) are namespaced by the MSIX
	// Package Family Name so each installed package (Debug dev / GitHub / Store) gets its own
	// session-local names and the packages can coexist without contending on shared handles.
	private static readonly string SyncObjectBase = ResolveSyncObjectBase();

	private static string ResolveSyncObjectBase()
	{
		try
		{
			return $@"Local\{Windows.ApplicationModel.Package.Current.Id.FamilyName}";
		}
		catch
		{
			// Running unpackaged (no Package.Current): fall back to a fixed base.
			return @"Local\KeePassPasskeyProvider_DEV";
		}
	}

	/// <summary>Single-instance guard for the on-demand COM server.</summary>
	public static readonly string ComServerMutexName = SyncObjectBase + "_COM";
	/// <summary>Single-instance guard for the tray/management app.</summary>
	public static readonly string ManagementUiMutexName = SyncObjectBase + "_UI";
	/// <summary>Cross-process lock serializing Windows credential-cache writes.</summary>
	public static readonly string CacheSyncMutexName = SyncObjectBase + "_CacheSync";
	/// <summary>Event signalling the running management app to show its window.</summary>
	public static readonly string ShowEventName = SyncObjectBase + "_Show";
	/// <summary>Same, but landing on the Settings page (KeePass's Tools menu opens it there).</summary>
	public static readonly string ShowSettingsEventName = SyncObjectBase + "_ShowSettings";

	public const string PluginRpId = "keepasspasskey.github.io";

	public const string StartupTaskTrayApp = "KeePassPasskeyTrayApp";

	/// <summary>PFNs of the official provider packages.</summary>
	public static readonly string[] OfficialPackageFamilyNames =
	{
		ControlledBuild.PackageFamilyName,
	};

	public static bool IsOfficialPackageFamilyName(string familyName) =>
		Array.Exists(OfficialPackageFamilyNames, n => string.Equals(n, familyName, StringComparison.OrdinalIgnoreCase));
}
