// SPDX-FileCopyrightText: Copyright (C) 2026 Uwe Koegel
// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.Diagnostics;
using System.IO;
using KeePassPasskeyShared;

namespace KeePassPasskey;

/// <summary>
/// Launches only the controlled provider discovered by exact package family identity.
/// No executable alias or upstream Store/GitHub package is used, including in Debug.
/// </summary>
internal static class ProviderLauncher
{
	/// <summary>Launches <c>/synccredential</c> on the appropriate installed provider(s).</summary>
	internal static void LaunchSync()
	{
		LaunchOnAllInstalledPackages();
	}

	/// <summary>Opens the installed controlled app on its Settings page.</summary>
	internal static bool LaunchSettings()
	{
		var package = ProviderPackageLocator.FindNewestBundledPlugin(m => Log.Warn(m))
			?? ProviderPackageLocator.FindPreferredPackage(m => Log.Warn(m));
		return package != null && Launch(package.ProviderExePath, "/settings", package.PackageFamilyName);
	}

	private static void LaunchOnAllInstalledPackages()
	{
		int launched = 0;
		foreach (var package in ProviderPackageLocator.FindInstalledPackages(m => Log.Warn(m)))
			if (Launch(package.ProviderExePath, "/synccredential", package.PackageFamilyName))
				launched++;

		if (launched == 0)
			Log.Debug("no installed provider package found to sync");
	}

	private static bool Launch(string exe, string arguments, string packageFamilyName)
	{
		try
		{
			if (!File.Exists(exe))
			{
				Log.Warn("provider exe not found: " + exe);
				return false;
			}

			Process.Start(new ProcessStartInfo
			{
				FileName = exe,
				Arguments = arguments,
				UseShellExecute = false,
				CreateNoWindow = true,
			});
			Log.Debug("launched provider " + arguments + ": " + exe);
			return true;
		}
		catch (Exception ex)
		{
			Log.Warn("failed to launch provider " + arguments + " (" + packageFamilyName + "): " + ex.Message);
			return false;
		}
	}
}
