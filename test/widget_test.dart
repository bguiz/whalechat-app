import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:async';
import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart';
import 'package:whalechat_app/models/assetProof.dart';
import 'package:whalechat_app/models/cryptoAccount.dart';
import 'package:whalechat_app/models/identity.dart';
import 'package:whalechat_app/protocol/transport.dart';
import 'package:whalechat_app/screens/new_address_proof_screen.dart';
import 'package:whalechat_app/screens/whale_chat_app.dart';
import 'package:whalechat_app/utils/app_state.dart';
import 'package:whalechat_app/utils/crypto_utils.dart';

import 'mocks/SharedPreferencesMock.dart';

var assetProofFixtures;

File fixture(path) {
  final whereami = dirname(Platform.script.path);
  return File(whereami.contains("/test") ? join(whereami, "fixtures", path) : join(whereami, "test", "fixtures", path));
}

void main() {
  final httpClient0 = AppState.instance.httpClient;

  setUpAll(() async {
    assetProofFixtures = jsonDecode(await fixture('assetProof.json').readAsString());
    AppState.instance.httpClient = MockClient((req) async {
      if (req.url.toString() == BIP39_ENGLISH_WORDLIST_URL) {
        return http.Response(await fixture('bip39_wordlist.txt').readAsString(), 200);
      } else if (req.url.toString() == 'https://api.github.com/repos/whalechat/whalechat-app/releases/latest') {
        return http.Response(await fixture('github_latest_release.json').readAsString(), 200);
      } else if (req.url.toString().contains('api.blockcypher.com')) {
        final words = req.url.toString().split('/');
        final symbol = words[4];
        final address = words[7];
        final method = words[8];
        return http.Response(jsonEncode(assetProofFixtures['api.blockcypher.com'][symbol][address][method]), 200);
      } else {
        throw Exception("Unmocked HTTP request ${req.method} ${req.url}");
      }
    });
  });

  tearDownAll(() {
    AppState.instance.httpClient = httpClient0;
  });

  testWidgets('Create a new identity', (WidgetTester tester) async {
    await tester.pumpWidget(new WhaleChatApp());
    await tester.pumpAndSettle();
    expect(find.text('Create a new identity'), findsOneWidget);
    await tester.tap(find.text('Create a new identity'));
    await tester.pump();
  });

  test("mnemonicFromPrivateKey", () async {
    final wordlist = (await fixture('bip39_wordlist.txt').readAsString()).trim().split("\n");

    expect(mnemonicFromPrivateKey(wordlist, '4490ff3bba8131b960038dc23359ff9c').join(" "), 'duty margin solve insect basic syrup length immune season onion lend day');
    expect(mnemonicToPrivateKey(wordlist, 'duty margin solve insect basic syrup length immune season onion lend day'.split(" ")), '0x4490ff3bba8131b960038dc23359ff9c');
    expect(mnemonicFromPrivateKey(wordlist, '7dc7387266e8f3eea149915ddc12360045352780d41344768cab8ff93a1779c6').join(" "), 'lava degree broken soccer monkey warrior lunch cram fruit they mirror above fashion need addict list dutch refuse cliff cable neck arm train stock');
    expect(mnemonicToPrivateKey(wordlist, 'lava degree broken soccer monkey warrior lunch cram fruit they mirror above fashion need addict list dutch refuse cliff cable neck arm train stock'.split(" ")), '0x7dc7387266e8f3eea149915ddc12360045352780d41344768cab8ff93a1779c6');
  });

  test("assetProof", () async {
    AppState.instance.storage.prefs = new SharedPreferencesMock();
    AppState.instance.storage.secretKeyEncrypted = assetProofFixtures['identity']['secretKeyEncrypted'];
    AppState.instance.publicKey = assetProofFixtures['identity']['publicKey'];
    AppState.instance.secretKey = assetProofFixtures['identity']['secretKey'];
    AppState.instance.storage.passwordHashSaltHex = assetProofFixtures['identity']['passwordHashSaltHex'];
    AppState.instance.storage.nonceHex = assetProofFixtures['identity']['nonceHex'];
    AppState.instance.storage.nickname = assetProofFixtures['identity']['nickname'];

    AppState.instance.cryptoUtilsChannel = new CryptoUtilsChannelMock();
    await testparseAssetProofSignature();
    await testSaveAssetProofs();
    await testSendAssetProofs();
    await testRequestAssetProofs();
  });
}

class CryptoUtilsChannelMock extends CryptoUtilsChannel {
  Future<bool> verifyEth(String sig, String msg, String address) async {
    for (final assetProof in assetProofFixtures['assetProofs']['eth']) {
      if (assetProof['payload']['address'] == address) {
        assert(assetProof['payload']['sig'] == sig);
        assert(jsonEncode(assetProof['payload']['msg']) == jsonEncode(jsonDecode(msg)));
        return true;
      }
    }
    throw ('Could not find signature in fixtures');
  }

  Future<bool> verifyBtc(String sig, String msg, String address) async {
    for (final assetProof in assetProofFixtures['assetProofs']['btc']) {
      if (assetProof['payload']['address'] == address) {
        assert(assetProof['payload']['sig'] == sig);
        assert(jsonEncode(assetProof['payload']['msg']) == jsonEncode(jsonDecode(msg)));
        return true;
      }
    }
    throw ('Could not find signature in fixtures');
  }

  Future<Object> sign(String msg, String privKeyHex) async {
    return ["blah"];
  }

  Future<bool> verify(String signature, String msg, String pubKeyHex) async {
    return true;
  }
}

String composeSignatureContents(String currency) {
  String signatureContents;
  currency = currency.toLowerCase();
  if (currency == "btc") {
    signatureContents = """-----BEGIN BITCOIN SIGNED MESSAGE-----
""" +
        messageToSign();
    signatureContents += """\n-----BEGIN SIGNATURE-----
${assetProofFixtures['assetProofs']['btc'][0]['payload']['address']}
${assetProofFixtures['assetProofs']['btc'][0]['payload']['sig']}
-----END BITCOIN SIGNED MESSAGE-----""";
  } else {
    signatureContents = '''{
  "address": "${assetProofFixtures['assetProofs']['eth'][0]['payload']['address']}",
  "msg": "''' +
        messageToSign().replaceAll('"', '\\"') +
        '''",
  "sig": "${assetProofFixtures['assetProofs']['eth'][0]['payload']['sig']}",
  "version": "3",
  "signer": "web3"
  }''';
  }
  return signatureContents;
}

Future testparseAssetProofSignature() async {
  {
    String currency = 'ETH';
    String signatureContents = composeSignatureContents(currency);

    final assetProofData = await parseAssetProofSignature(currency, signatureContents);
    assert(assetProofData["address"] == assetProofFixtures['assetProofs']['eth'][0]['payload']['address']);
    assert(assetProofData["sig"] == assetProofFixtures['assetProofs']['eth'][0]['payload']['sig']);
  }

  {
    String currency = 'BTC';
    String signatureContents = composeSignatureContents(currency);

    final assetProofData = await parseAssetProofSignature(currency, signatureContents);
    assert(assetProofData["address"] == assetProofFixtures['assetProofs']['btc'][0]['payload']['address']);
    assert(assetProofData["sig"] == assetProofFixtures['assetProofs']['btc'][0]['payload']['sig']);
  }
}

Future testSaveAssetProofs() async {
  {
    String currency = 'ETH';
    String address = assetProofFixtures['assetProofs']['eth'][0]['payload']['address'];
    String sig = assetProofFixtures['assetProofs']['eth'][0]['payload']['sig'];
    await AppState.instance.storage.saveAssetProof(currency, address, sig);
    assert(AppState.instance.storage.cryptoAccounts[0].balance == assetProofFixtures['api.blockcypher.com']['eth'][address]['balance']['balance'].toString());
  }

  {
    String currency = 'BTC';
    String address = assetProofFixtures['assetProofs']['btc'][0]['payload']['address'];
    String sig = assetProofFixtures['assetProofs']['btc'][0]['payload']['sig'];
    await AppState.instance.storage.saveAssetProof(currency, address, sig);
    assert(AppState.instance.storage.cryptoAccounts[1].balance == assetProofFixtures['api.blockcypher.com']['btc'][address]['balance']['balance'].toString());
  }
}

Future testSendAssetProofs() async {
  await AppState.instance.apiService.register(AppState.instance.storage.nickname, AppState.instance.publicKey, 'someKey');

  {
    String currency = 'ETH';
    var msg = messageToSign();
    String address = assetProofFixtures['assetProofs']['eth'][0]['payload']['address'];
    String sig = assetProofFixtures['assetProofs']['eth'][0]['payload']['sig'];
    assert(await sendSignature(currency, address, msg, sig));
  }
  {
    String currency = 'BTC';
    var msg = messageToSign();
    String address = assetProofFixtures['assetProofs']['btc'][0]['payload']['address'];
    String sig = assetProofFixtures['assetProofs']['btc'][0]['payload']['sig'];
    assert(await sendSignature(currency, address, msg, sig));
  }
}

Future testRequestAssetProofs() async {
  await AppState.instance.storage.updateBookIdentityAssetProof(new Identity(publicKey: AppState.instance.publicKey, nickname: AppState.instance.storage.nickname, chatPublicKey: 'someKey'));

  assert(
    AppState.instance.storage.identityBook.first.accounts.firstWhere((account) =>
    (account.address == '17KLVypAzviYZwDvJv2jn7Xo7oeTEDUtDM') && (account.balance == assetProofFixtures['api.blockcypher.com']['btc'][account.address]['balance']['balance'].toString()))
    != null);

  assert(
    AppState.instance.storage.identityBook.first.accounts.firstWhere((account) =>
    (account.address == '0x83d3ccc6d538c9b085ae59c39d0cc11ab852d2be') && (account.balance == assetProofFixtures['api.blockcypher.com']['eth'][account.address]['balance']['balance'].toString()))
    != null);
}
