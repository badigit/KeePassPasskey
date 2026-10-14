// SPDX-License-Identifier: GPL-3.0-or-later
using System.Security.Cryptography;
using KeePassPasskeyProvider.Authenticator;
using PeterO.Cbor;
using Xunit;

namespace KeePassPasskeyProvider.Tests;

public class PlatformBoundaryTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void PlatformSignatureRejectsAlteredPayloadAndSignature(bool rsa)
    {
        byte[] data = "synthetic platform operation"u8.ToArray();
        byte[] keyBlob;
        byte[] signature;
        if (rsa)
        {
            using var key = new RSACng(2048);
            keyBlob = key.Key.Export(CngKeyBlobFormat.GenericPublicBlob);
            signature = key.SignData(data, HashAlgorithmName.SHA256, RSASignaturePadding.Pss);
        }
        else
        {
            using var key = new ECDsaCng(ECCurve.NamedCurves.nistP256);
            keyBlob = key.Key.Export(CngKeyBlobFormat.GenericPublicBlob);
            signature = key.SignData(data, HashAlgorithmName.SHA256);
        }
        Assert.Equal(0, SignatureVerifier.VerifySignature(data, keyBlob, signature));
        data[0] ^= 1;
        Assert.NotEqual(0, SignatureVerifier.VerifySignature(data, keyBlob, signature));
        data[0] ^= 1;
        signature[0] ^= 1;
        Assert.NotEqual(0, SignatureVerifier.VerifySignature(data, keyBlob, signature));
    }

    [Fact]
    public void MissingNativeRequestsAreRejectedWithoutPrompting()
    {
        var authenticator = new PluginAuthenticator();
        Assert.NotEqual(0, authenticator.MakeCredential(0, 0));
        Assert.NotEqual(0, authenticator.GetAssertion(0, 0));
        Assert.NotEqual(0, authenticator.CancelOperation(0));
    }

    [Fact]
    public void DescriptorDoesNotAdvertiseUnimplementedSecretExtensions()
    {
        var descriptor = CBORObject.DecodeFromBytes(PluginRegistration.BuildAuthenticatorInfoCbor());
        Assert.Equal(0, descriptor[2].Count);
        Assert.Equal(3, descriptor[10].Count);
    }
}
