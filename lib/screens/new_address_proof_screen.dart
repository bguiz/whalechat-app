import 'dart:convert';
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:whalechat_app/protocol/transport.dart';
import 'package:whalechat_app/screens/address_proof_list_screen.dart';
import 'package:whalechat_app/utils/app_state.dart';
import 'package:whalechat_app/utils/utils.dart';
import 'package:whalechat_app/widgets/app_button.dart';
import 'package:whalechat_app/widgets/flexible_scroll_view.dart';

String messageToSign() {
  return '{"application": "wc", "version": "1", "pubKey": "' + AppState.instance.publicKey + '"}';
}

class NewAddressProofScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _NewAddressProofScreenState();
}

class _NewAddressProofScreenState extends State<NewAddressProofScreen> {
  String _selectedCurrency;
  final _depositAddressController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _hintText = "";

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme.title.copyWith(color: Colors.black45);

    return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(title: Text("Add Proof of Wallet Ownership")),
        body: FlexibleScrollView.build(
          context: context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("1. Select Currency", style: title),
              SizedBox(height: 8),
              DropdownButton(
                value: _selectedCurrency,
                items: ['BTC', 'ETH'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
                onChanged: (ccy) {
                  setState(() {
                    _selectedCurrency = ccy;
                  });
                  if (_selectedCurrency == 'BTC') {
                    setState(() {
                      _hintText = [
                        'Example:',
                        '-----BEGIN BITCOIN SIGNED MESSAGE-----',
                        messageToSign(),
                        '-----BEGIN SIGNATURE-----',
                        '<PASTE ADDRESS HERE>',
                        '<PASTE SIGNATURE HERE>',
                        '-----END BITCOIN SIGNED MESSAGE-----',
                      ].join("\n");
                    });
                  } else if (_selectedCurrency == 'ETH') {
                    setState(() {
                      _hintText = ['Example:', '{', '  "address": "<PASTE ADDRESS HERE>",', '  "msg": "${messageToSign().replaceAll('"', '\\"')}",', '  "sig": "<PASTE SIGNATURE HERE>",', '  "version": "3",', '  "signer": "web3"', '}'].join("\n");
                    });
                  } else {
                    throw ('Unknown currency: ' + _selectedCurrency);
                  }
                },
              ),
              Divider(),
              Text("2. Copy Message Template", style: title),
              SizedBox(height: 8),
              Row(children: [
                AppButton.build(context, "Copy", icon: Icons.content_copy, onPressed: () {
                  Clipboard.setData(ClipboardData(text: messageToSign()));
                  _scaffoldKey.currentState.showSnackBar(SnackBar(
                    content: Text("Message was copied to clipboard"),
                  ));
                }),
                FlatButton(
                    child: Text('Learn sign methods'),
                    textColor: Colors.blue,
                    onPressed: () {
                      launchBrowser('https://github.com/whalechat');
                    })
              ]),
              Divider(),
              Text("3. Paste Signature", style: title),
              SizedBox(height: 8),
              TextFormField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: _hintText,
                  labelText: 'Signature',
                ),
                maxLines: 7,
                controller: _depositAddressController,
              ),
              AppButton.build(context, "Paste", icon: Icons.content_paste, onPressed: () async => _depositAddressController.text = (await Clipboard.getData('text/plain')).text),
              Spacer(),
              AppButton.buildBig(context, "Verify & Add", onPressed: _sendAssetProof)
            ],
          ),
        ));
  }

  Future<void> _sendAssetProof() async {
    var assetProofData;

    try {
      assetProofData = await parseAssetProofSignature(_selectedCurrency, _depositAddressController.text);
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), gravity: ToastGravity.CENTER, backgroundColor: Color(0xff444444), textColor: Colors.white);
      return;
    }

    final ok = await sendSignature(_selectedCurrency, assetProofData['address'], assetProofData['msg'], assetProofData['sig']);
    if (ok) {
      await AppState.instance.storage.saveAssetProof(_selectedCurrency, assetProofData['address'], assetProofData['sig']);
      await AppState.instance.storage.save();

      Fluttertoast.showToast(msg: "Account ownership verified!", gravity: ToastGravity.CENTER, backgroundColor: Color(0xff444444), textColor: Colors.white);

      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => AddressProofListScreen()), (_) => false);
    } else {
      Fluttertoast.showToast(msg: "An error occurred while verifying signature", gravity: ToastGravity.TOP, backgroundColor: Color(0xff444444), textColor: Colors.white);
    }
  }
}

Future<String> _createAssetProofMessage(String address, String msg, String sig) async {
  return await signMessage(jsonEncode({
    "address": address,
    "msg": jsonDecode(msg),
    "sig": sig,
  }));
}

Future parseAssetProofSignature(currency, signatureContents) async {
  if (currency == 'BTC' || currency == 'ETH') {
    String msg, address, sig;

    try {
      if (currency == 'BTC') {
        final lines = signatureContents.split('\n');
        if (lines[0] == "-----BEGIN BITCOIN SIGNED MESSAGE-----" && lines[lines.length - 4] == "-----BEGIN SIGNATURE-----" && lines[lines.length - 1] == "-----END BITCOIN SIGNED MESSAGE-----") {
          msg = lines.sublist(1, lines.length - 5 + 1).join("\n");
          address = lines[lines.length - 3];
          sig = lines[lines.length - 2];
          await AppState.instance.cryptoUtilsChannel.verifyBtc(sig, msg, address);
        } else
          throw ('Wrong signature format');
      } else if (currency == 'ETH') {
        try {
          signatureContents = signatureContents.replaceAll("\\", "");
          signatureContents = signatureContents.replaceAll("\"{", "{");
          signatureContents = signatureContents.replaceAll("}\"", "}");
          Map<String, dynamic> signatureJson = json.decode(signatureContents);

          address = signatureJson['address'];
          msg = jsonEncode(signatureJson['msg']);
          sig = signatureJson['sig'];
          sig = sig.replaceAll('0x', '');
        } catch (_) {
          throw ('Wrong signature format');
        }
        await AppState.instance.cryptoUtilsChannel.verifyEth(sig, msg, address);
      }

      if (AppState.instance.storage.cryptoAccounts.where((cryptoAccount) => cryptoAccount.address == address).isNotEmpty) {
        throw ('Proof for address $address was already entered');
      }
    } catch (e, s) {
      throw ('Could not verify the provided signed message');
    }

    return {"address": address, "msg": msg, "sig": sig};
  } else {
    throw ('Unknown currency: ' + currency);
  }
}

Future<bool> sendSignature(String currency, String address, String msg, String sig) async {
  await AppState.instance.apiService.registerAssetProof(currency, address, await _createAssetProofMessage(address, msg, sig));
  return true;
}
