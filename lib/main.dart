import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:whalechat_app/screens/whale_chat_app.dart';
import 'package:whalechat_app/utils/app_state.dart';
import 'package:whalechat_app/utils/app_config.dart';
import 'package:sentry/sentry.dart';

void mainImpl() async {
  Logger.root.onRecord.listen((rec) {
    debugPrint("${rec.time}: [${rec.level.name}] ${rec.loggerName}: ${rec.message}");
  });

  await AppState.instance.init();

  SentryClient sentry;

  runZoned(() {
    runApp(new WhaleChatApp());
  }, onError: (e, st) {
    if (AppState.instance.storage.telemetryEnabled ?? false) {
      sentry ??= SentryClient(dsn: sentryDsn);
      sentry.captureException(exception: e, stackTrace: st);
    }

    Fluttertoast.showToast(
      backgroundColor: Colors.red,
      textColor: Colors.white,
      gravity: ToastGravity.TOP,
      msg: e.toString()
    );

    throw e;
  });
}

void main() async {
  Logger.root.level = Level.WARNING;
  AppState.instance.env = AppEnvironment.production;

  mainImpl();
}
