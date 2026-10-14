// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.IO;
using KeePassLib;
using KeePassLib.Keys;
using KeePassLib.Security;
using KeePassLib.Serialization;
using KeePassPasskey.Passkey;
using KeePassPasskey.Storage;
using KeePassPasskeyShared.Passkey;
using Xunit;

namespace KeePassPasskeyPlugin.Tests;

public class DatabaseBoundaryTests
{
    [Fact]
    public void CrossEntryPasswordReferenceCannotLeakThroughMetadataTitle()
    {
        var db = new PwDatabase();
        var master = new CompositeKey();
        master.AddUserKey(new KcpPassword("test-only"));
        try
        {
            db.New(IOConnectionInfo.FromPath(Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".kdbx")), master);
            var secret = new PwEntry(true, true);
            secret.Strings.Set("Password", new ProtectedString(true, "synthetic-cross-entry-secret"));
            db.RootGroup.AddEntry(secret, true);
            var metadataEntry = new PwEntry(true, true);
            metadataEntry.Strings.Set("Title", new ProtectedString(false, "{REF:P@I:" + secret.Uuid.ToHexString() + "}"));
            db.RootGroup.AddEntry(metadataEntry, true);
            var metadata = PasskeyEntryStorage.ExtractCredentialMetadata(metadataEntry, db);
            Assert.DoesNotContain("synthetic-cross-entry-secret", metadata.Title);
        }
        finally { db.Close(); }
    }

    [Theory]
    [InlineData(PasskeyAlgorithm.ES256)]
    [InlineData(PasskeyAlgorithm.EdDSA)]
    [InlineData(PasskeyAlgorithm.RS256)]
    public void SyntheticDatabaseRoundtripProtectsKeyAndMetadataDoesNotExposeIt(PasskeyAlgorithm algorithm)
    {
        var path = Path.Combine(Path.GetTempPath(), "controlled-passkey-" + Guid.NewGuid().ToString("N") + ".kdbx");
        var db = new PwDatabase();
        var master = new CompositeKey();
        master.AddUserKey(new KcpPassword("disposable-test-password"));
        try
        {
            db.New(IOConnectionInfo.FromPath(path), master);
            var key = PasskeyKeyHelper.GenerateKeyPair(algorithm);
            var credential = new PasskeyCredential {
                CredentialId = "dGVzdC1jcmVkZW50aWFs", PrivateKeyPem = key.privateKeyPem,
                RelyingParty = "example.invalid", UserHandle = "dGVzdA", Username = "synthetic", BackupEligible = true, BackupState = true
            };
            var entry = new PwEntry(true, true);
            entry.Strings.Set("Title", new ProtectedString(false, "Synthetic passkey"));
            entry.Strings.Set("Password", new ProtectedString(true, "existing-test-password"));
            PasskeyEntryStorage.ApplyPasskeyFields(entry, credential);
            db.RootGroup.AddEntry(entry, true);
            db.Save(null);
            db.Close();
            db.Open(IOConnectionInfo.FromPath(path), master, null);
            var reopened = db.RootGroup.GetEntries(true).GetAt(0);
            Assert.True(reopened.Strings.Get("KPEX_PASSKEY_PRIVATE_KEY_PEM").IsProtected);
            Assert.Equal(key.privateKeyPem, reopened.Strings.ReadSafe("KPEX_PASSKEY_PRIVATE_KEY_PEM"));
            Assert.Equal("existing-test-password", reopened.Strings.ReadSafe("Password"));
            var metadata = PasskeyEntryStorage.ExtractCredentialMetadata(reopened, db);
            Assert.Null(metadata.PrivateKeyPem);
            Assert.Equal("example.invalid", metadata.RelyingParty);
            Assert.Equal(credential.CredentialId, metadata.CredentialId);
        }
        finally
        {
            db.Close();
            if (File.Exists(path)) File.Delete(path);
        }
    }
}
