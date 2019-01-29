package club.whalechat.app;


import android.os.Bundle;

import com.subgraph.orchid.encoders.Hex;

import io.flutter.app.FlutterActivity;
import io.flutter.plugins.GeneratedPluginRegistrant;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import org.bitcoinj.core.Address;
import org.bitcoinj.core.DumpedPrivateKey;
import org.bitcoinj.core.ECKey;
import org.bitcoinj.core.NetworkParameters;
import org.bitcoinj.params.MainNetParams;
import org.bitcoinj.wallet.Wallet;
import org.web3j.crypto.Credentials;
import org.web3j.crypto.ECKeyPair;
import org.web3j.crypto.Keys;
import org.web3j.crypto.Hash;
import org.web3j.crypto.Sign;

import java.math.BigInteger;
import java.util.Arrays;
import java.util.List;

public class MainActivity extends FlutterActivity {

    private static final String CHANNEL = "whalechat.club/cryptoUtils";

    public static String bytesToHex(byte[] bytes) {
        return (new BigInteger(bytes)).toString(16);
    }

    protected String getNewPrivateKey() {
        return (new ECKey()).getPrivKey().toString(16); // 256-bit in hex format
    }

    protected String getPublicKeyFromPrivateKey(String privKeyHex) {
        ECKey ecKey = ECKey.fromPrivate(new BigInteger(privKeyHex, 16));
        return ecKey.getPublicKeyAsHex();
    }

    protected String getAddressFromPrivateKey(String privKeyHex, String ccy) throws Exception {
        if (ccy.equals("BTC")) {
            NetworkParameters params = MainNetParams.get();
            ECKey ecKey = ECKey.fromPrivate(new BigInteger(privKeyHex, 16));
            Wallet wallet = new Wallet(params);
            wallet.importKey(ecKey);
            return ecKey.toAddress(params).toString();
        } else if (ccy.equals("ETH")) {
            Credentials credentials = Credentials.create(privKeyHex);
            return credentials.getAddress();
        } else {
            throw new Exception("Unknown currency: " + ccy);
        }
    }

    protected String signBtc(String plainMessage, String privKeyWif) throws Exception {
        DumpedPrivateKey dpk = DumpedPrivateKey.fromBase58(null, privKeyWif);
        ECKey key = dpk.getKey();
        String signatureBase64 = key.signMessage(plainMessage);
        return signatureBase64;
    }

    protected boolean verifyBtc(String signature, String plainMessage, String btcAddress) throws Exception {
        ECKey result = new ECKey().signedMessageToKey(plainMessage, signature);
        return ECKey.signedMessageToKey(plainMessage, signature).toAddress(Address.fromBase58(null, btcAddress).getParameters()).toString().equals(btcAddress);
    }

    protected String signEth(String plainMessage, String privKeyHex) throws Exception {
        BigInteger privKey = new BigInteger(privKeyHex, 16);
        plainMessage = "\u0019Ethereum Signed Message:\n" + plainMessage.length() + plainMessage;

        ECKeyPair ecKeyPair = ECKeyPair.create(privKey);
        byte[] message = plainMessage.getBytes();
        Sign.SignatureData signMessage = Sign.signMessage(message, ecKeyPair);
        String pubKey = Sign.signedMessageToKey(message, signMessage).toString(16);
        String signerAddress = Keys.getAddress(pubKey);
        Sign.SignatureData signatureObj = signMessage;

        byte[] signature = new byte[1 + 32 + 32];
        byte[] v = new byte[] { signatureObj.getV() };
        System.arraycopy(signatureObj.getR(), 0, signature, 0, 32);
        System.arraycopy(signatureObj.getS(), 0, signature, 32, 32);
        System.arraycopy(v, 0, signature, 64, 1);
        String signatureHex = bytesToHex(signature);
        return signatureHex;
    }

    protected boolean verifyEth(String signatureHex, String plainMessage, String ethAddress) throws Exception {
        byte[] signature = Hex.decode(signatureHex);
        plainMessage = "\u0019Ethereum Signed Message:\n" + plainMessage.length() + plainMessage;
        byte[] message = plainMessage.getBytes();
        byte[] v = new byte[1];
        byte[] r = new byte[32];
        byte[] s = new byte[32];
        System.arraycopy(signature, 0, r, 0, 32);
        System.arraycopy(signature, 32, s, 0, 32);
        System.arraycopy(signature, 64, v, 0, 1);

        Sign.SignatureData signatureObj2 = new Sign.SignatureData(v[0], r, s);
        BigInteger publicKey2 = Sign.signedMessageToKey(message, signatureObj2);

        String ethAddress2 = Keys.getAddress(publicKey2);

        ethAddress = ethAddress.replace("0x", "");
        ethAddress2 = ethAddress2.replace("0x", "");
        return ethAddress.compareToIgnoreCase(ethAddress2) == 0;
    }


    protected List<String> sign(String messageHex, String privKeyHex) throws Exception {
        BigInteger privKey = new BigInteger(privKeyHex, 16);
        byte[] message = Hex.decode(messageHex);

        byte[] messageHash = Hash.sha3(message);
        ECKeyPair ecKeyPair = ECKeyPair.create(privKey);

        Sign.SignatureData signatureObj = Sign.signMessage(messageHash, ecKeyPair);

        byte[] signature = new byte[1 + 32 + 32];
        byte[] v = new byte[] { signatureObj.getV() };
        System.arraycopy(v, 0, signature, 0, 1);
        System.arraycopy(signatureObj.getR(), 0, signature, 1, 32);
        System.arraycopy(signatureObj.getS(), 0, signature, 1 + 32, 32);

        return Arrays.asList(bytesToHex(signature), bytesToHex(messageHash));
    }

    protected boolean verify(String signatureHex, String messageHex, String pubKeyHex) throws Exception {

        byte[] signature = Hex.decode(signatureHex);
        byte[] message = Hex.decode(messageHex);
        byte[] messageHash = Hash.sha3(message);

        byte[] v = new byte[1];
        byte[] r = new byte[32];
        byte[] s = new byte[32];

        System.arraycopy(signature, 0, v, 0, 1);
        System.arraycopy(signature, 1, r, 0, 32);
        System.arraycopy(signature, 1 + 32, s, 0, 32);

        Sign.SignatureData signatureObj2 = new Sign.SignatureData(v[0], r, s);
        BigInteger publicKey2 = Sign.signedMessageToKey(messageHash, signatureObj2);

        String publicKeyHex2Slice = publicKey2.toString(16).substring(0, 64);

        if (!publicKeyHex2Slice.equalsIgnoreCase(pubKeyHex.substring(2, 66))
                || publicKeyHex2Slice.equalsIgnoreCase(pubKeyHex.substring(1, 65))) {
            throw new Exception("Could not verify signature: " + publicKey2 + " <=> " + pubKeyHex);
        }
        return true;
    }

    @SuppressWarnings("unchecked")
    public static <T extends List<?>> T cast(Object obj) {
        return (T) obj;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        GeneratedPluginRegistrant.registerWith(this);

        new MethodChannel(getFlutterView(), CHANNEL).setMethodCallHandler(new MethodCallHandler() {
            @Override
            public void onMethodCall(MethodCall call, Result result) {
                List<Object> arguments = cast(call.arguments());
                try {
                    if (call.method.equals("getNewPrivateKey")) {
                        result.success(getNewPrivateKey());
                    } else if (call.method.equals("getPublicKeyFromPrivateKey")) {
                        result.success(getPublicKeyFromPrivateKey(arguments.get(0).toString()));
                    } else if (call.method.equals("getAddressFromPrivateKey")) {
                        result.success(
                                getAddressFromPrivateKey(arguments.get(0).toString(), arguments.get(1).toString()));
                    } else if (call.method.equals("sign")) {
                        result.success(sign(arguments.get(0).toString(), arguments.get(1).toString()));
                    } else if (call.method.equals("verify")) {
                        try {
                            result.success(verify(arguments.get(0).toString(), arguments.get(1).toString(),
                                    arguments.get(2).toString()));
                        } catch (Exception e) {
                            result.success(false);
                        }
                    } else if (call.method.equals("signEth")) {
                        result.success(signEth(arguments.get(0).toString(), arguments.get(1).toString()));
                    } else if (call.method.equals("verifyEth")) {
                        result.success(verifyEth(arguments.get(0).toString(), arguments.get(1).toString(),
                                arguments.get(2).toString()));
                    } else if (call.method.equals("signBtc")) {
                        result.success(signBtc(arguments.get(0).toString(), arguments.get(1).toString()));
                    } else if (call.method.equals("verifyBtc")) {
                        result.success(verifyBtc(arguments.get(0).toString(), arguments.get(1).toString(),
                                arguments.get(2).toString()));
                    }
                    else {
                        result.notImplemented();
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        });
    }
}
