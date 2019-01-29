import 'package:flutter/material.dart';
import 'package:whalechat_app/utils/app_config.dart';
import 'package:whalechat_app/widgets/ok_dialog.dart';
import 'package:whalechat_app/widgets/app_button.dart';
import 'package:whalechat_app/widgets/password_field.dart';
import 'package:whalechat_app/utils/app_state.dart';

class NewPinScreen extends StatefulWidget {
  final StatefulWidget nextScreen;

  const NewPinScreen(this.nextScreen);

  @override
  State<StatefulWidget> createState() => _NewPinScreen();
}

class _NewPinScreen extends State<NewPinScreen> {
  final GlobalKey<FormFieldState<String>> _passwordFieldKey = GlobalKey<FormFieldState<String>>();
  final GlobalKey<FormFieldState<String>> _passwordFieldKeyConfirm = GlobalKey<FormFieldState<String>>();

  final passwordFieldController = TextEditingController();
  final passwordFieldControllerConfirm = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomPadding: false,
      body: Column(
        children: [
          Spacer(),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: PasswordField(
              fieldKey: _passwordFieldKey,
              labelText: 'Password',
              onFieldSubmitted: (String value) {
                setState(() {});
              },
              controller: passwordFieldController
            ),
          ),

          SizedBox(height: 24.0),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: PasswordField(
              fieldKey: _passwordFieldKeyConfirm,
              labelText: 'Confirm password',
              onFieldSubmitted: (String value) {
                setState(() {});
              },
              controller: passwordFieldControllerConfirm
            ),
          ),

          SizedBox(height: 24.0),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text("Your private key will be encrypted using this password. Therefore, choose a strong password, which should be at least 8 characters long, containing upper/lowercase letters, digits and special characters.",
            style: TextStyle(fontWeight: FontWeight.w300)),
          ),

          Spacer(),

          AppButton.buildBig(context, "Save", horizontalInset: 16, onPressed: () {
            if (passwordFieldController.text != passwordFieldControllerConfirm.text) {
              showDialog(
                context: context,
                builder: (_) => OkDialog.build(
                  context: context,
                  title: "",
                  content: "Passwords don't match!",
                  onOk: (){}
                ));
              return;
            }

            AppState.instance.password = passwordFieldController.text;
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => widget.nextScreen));
          }),

          SizedBox(height: 8),
        ],
      ));
  }
}

class PinScreen extends StatefulWidget {
  final StatefulWidget nextScreen;
  PinScreen(this.nextScreen);

  @override
  State<StatefulWidget> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final GlobalKey<FormFieldState<String>> _passwordFieldKey = GlobalKey<FormFieldState<String>>();
  final _passwordFieldController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final children = [
      Expanded(child: Column()),
      PasswordField(
        fieldKey: _passwordFieldKey,
        labelText: 'Password',
        onFieldSubmitted: (String value) {
          setState(() {});
        },
        controller: _passwordFieldController),
      Expanded(child: Column()),
      AppButton.buildBig(context, "Unlock", onPressed: () {
        AppState.instance.password = _passwordFieldController.text;
        AppState.instance.loadIdentity().then((ok) {
          if (ok) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => widget.nextScreen));
          } else {
            showDialog(
              context: context,
              builder: (_) => OkDialog.build(
                context: context,
                title: "Wrong password",
                content: "Please try again",
                onOk: () {
                  _passwordFieldController.clear();
                }
              )
            );
          }
        });
      }),
    ];

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: Column(
          children: children,
        )
      )
    );
  }
}
