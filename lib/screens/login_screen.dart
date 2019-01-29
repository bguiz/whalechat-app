import 'dart:async';

import 'package:flutter/material.dart';
import 'package:whalechat_app/screens/create_identity_screen.dart';
import 'package:whalechat_app/screens/import_identity_screen.dart';
import 'package:whalechat_app/screens/pin_screen.dart';
import 'package:whalechat_app/utils/app_config.dart';
import 'package:whalechat_app/utils/app_state.dart';
import 'package:whalechat_app/utils/utils.dart';
import 'package:whalechat_app/widgets/yes_no_dialog.dart';
import 'package:whalechat_app/widgets/app_button.dart';

class LoginScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  initState() {
    super.initState();

    checkUpdate(context);
    AppState.instance.configureFcm(context);

    _init();
  }

  Future<void> _init() async {
    if (!AppState.instance.storage.hasIdentity && AppState.instance.storage.telemetryEnabled == null) {
      Future.delayed(Duration.zero, () {
        showDialog(context: context, builder: (_) => YesNoDialog.build(
          context: context,
          title: "Telemetry",
          content: "Would you like to enable sending crash reports and anonymous usage statistics to the developers for us to improve the app?",
          onYes: () {
            AppState.instance.storage.telemetryEnabled = false;
            AppState.instance.storage.save();
          },
          onNo: () {
            AppState.instance.storage.telemetryEnabled = true;
            AppState.instance.storage.save();
          }
        ));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Expanded(
        child: Container(
          margin: EdgeInsets.all(35.0),
          decoration: BoxDecoration(image: DecorationImage(
            image: AssetImage('assets/wc-landing.png'),
            alignment: Alignment.center,
            fit: BoxFit.fitWidth)),
        ),
      ),

      AppButton.buildBig(context, "Create a new identity", horizontalInset: 16, onPressed: () =>
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => NewPinScreen(CreateIdentityScreen())))
      ),

      FlatButton(child: Text("Import existing identity"), onPressed: () =>
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => NewPinScreen(ImportIdentityScreen()))),
      ),

      Padding(padding: EdgeInsets.all(8))
    ];

    return Scaffold(
      body: Center(
        child: Container(
          decoration: BoxDecoration(color: Colors.white),
          child: Column(children: children)
        )
      )
    );
  }
}
