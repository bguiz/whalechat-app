import 'dart:async';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:faker/faker.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_sodium/flutter_sodium.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:whalechat_app/screens/chat_screen.dart';
import 'package:whalechat_app/services/whisper_service.dart';
import 'package:whalechat_app/utils/app_state_storage.dart';
import 'package:whalechat_app/utils/crypto_utils.dart';
import 'package:whalechat_app/utils/utils.dart';
import 'package:whalechat_app/models/identity.dart';
import 'package:whalechat_app/services/api_service.dart';
import 'package:whalechat_app/utils/app_config.dart' as AppConfig;
import 'package:quiver/iterables.dart';

enum AppEnvironment { development, production }

/// Generates a secret key and a corresponding public key deterministically from a seed.
Future<KeyPair> generateKeyPairFromSeed(var seed) async {
  var map = await Sodium.cryptoBoxSeedKeypair(seed);
  return KeyPair.fromMap(map);
}


class AppState {
  static final AppState instance = AppState._();

  CryptoUtilsChannelAbstract cryptoUtilsChannel = new CryptoUtilsChannel();

  AppStateStorage storage = new AppStateStorage();

  String password;
  String secretKey; // secp256k1 keypair only used for crypto address generation \
  String publicKey; // and ECDSA signature of chat messages
  KeyPair chatKeyPair; // NaCl's default asymmetrical encryption keypair only used for asymmetrical encryption of chat messages

  String get fingerprint => partition(partition(hex.encode(sha256.convert(hex.decode(publicKey)).bytes).split(""), 8).map((xs) => xs.join("")), 4).map((xs) => xs.join(" ")).join("\n");

  String shhSymKeyId;
  String shhRpcServerUrl = AppConfig.shhRpcServerUrl;

  var httpClient = http.Client();

  var env = AppEnvironment.development;

  var _inited = false;
  final _logger = Logger("AppState");

  final apiService = ApiService();
  final whisperService = WhisperService();
  final fcm = FirebaseMessaging();

  bool triedCheckUpdate = false;

  var allNotificationsEnabled = true;
  var chatroomMessagesNotificationsEnabled = true;
  var chatroomMentionsNotificationsEnabled = true;
  var privateMessagesNotificationsEnabled = true;

  // HACK: used to decide whether to pop up push notification or not
  String currentChatTopic;

  var wcCryptoAddresses = {}; // addresses derived from `publicKey` inside the app

  AppState._();

  Future<void> configureFcm(BuildContext context) async {
    _logger.fine("Got FCM token: ${await fcm.getToken()}");

    final notifications = FlutterLocalNotificationsPlugin();

    notifications.initialize(
      InitializationSettings(
        AndroidInitializationSettings('launch_background'),
        IOSInitializationSettings()
      ),
      onSelectNotification: (String topic) async {
        final lobby = await apiService.getLobby();
        final room = lobby.rooms.firstWhere((r) => r.topic == topic);

        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(room: room)));
      }
    );

    fcm.configure(
      onMessage: (args) async {
        _logger.fine("FCM::onMessage: $args");
        // If the current screen is already there, do nothing
        // Otherwise, show local notification and when clicked, go to that ChatScreen

        if (AppState.instance.currentChatTopic != args["data"]["topic"]) {
          final topic = args["data"]["topic"];
          final lobby = await apiService.getLobby();
          final room = lobby.rooms.firstWhere((r) => r.topic == topic);

          notifications.show(0, "New Message", room.title, NotificationDetails(
            AndroidNotificationDetails(topic, room.title, room.title),
            IOSNotificationDetails(),
          ),payload: topic);
        }
      },

      onResume: (args) async {
        _logger.fine("FCM::onResume: $args");

        final lobby = await apiService.getLobby();
        final room = lobby.rooms.firstWhere((r) => r.topic == args['topic']);

        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(room: room)));
      },

      onLaunch: (args) async {
        _logger.fine("FCM::onLaunch: $args");

        final lobby = await apiService.getLobby();
        final room = lobby.rooms.firstWhere((r) => r.topic == args['topic']);

        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(room: room)));
      }
    );
  }

  Future<void> init() async {
    await storage.load();
    whisperService.connect();
    _inited = true;
  }

  Identity get identity => Identity(nickname: storage.nickname, publicKey: publicKey, chatPublicKey: hex.encode(chatKeyPair.publicKey));

  _ensureValidPassword(String password) async {
    return true;
  }

  generateNewIdentity() async {
    _ensureInited();
    _ensureValidPassword(password);

    secretKey = await cryptoUtilsChannel.getNewPrivateKey();
    publicKey = await cryptoUtilsChannel.getPublicKeyFromPrivateKey(secretKey);

    var salt = await PasswordHash.generateSalt();
    final hashKey = await PasswordHash.hash(password, salt, outlen: 32);
    final nonce = await PasswordHash.hash(password, salt, outlen: 24);

    var encrypted = await SecretBox.encrypt(secretKey, nonce, hashKey);

    storage.passwordHashSaltHex = hex.encode(salt);
    storage.secretKeyEncrypted = hex.encode(encrypted);
    storage.nonceHex = hex.encode(nonce);

    final chatKeyPairSeed = await RandomBytes.buffer(crypto_box_SEEDBYTES);
    chatKeyPair = await generateKeyPairFromSeed(chatKeyPairSeed);

    final chatKeyPairSeedEncrypted = await SecretBox.encrypt(hex.encode(chatKeyPairSeed), nonce, hashKey);
    storage.chatKeyPairSeedEncryptedHex = hex.encode(chatKeyPairSeedEncrypted);

    storage.nickname = Faker().internet.userName();

    final secretKeyCopy = secretKey;
    assert(secretKey == secretKeyCopy);
  }

  Future setIdentity(
      String _publicKey,
      String _secretKey,
      String _passwordHashSaltHex,
      String _nonceHex,
      String _nickname,
      String _chatKeyPairSeed) async {
    publicKey = _publicKey;
    secretKey = _secretKey;
    storage.passwordHashSaltHex = _passwordHashSaltHex;
    storage.nonceHex = _nonceHex;
    storage.nickname = _nickname;
    chatKeyPair = await generateKeyPairFromSeed(hex.decode(_chatKeyPairSeed));
  }

  Future<bool> loadIdentity() async {
    try {
      assert(password != null); // password needs to be inputted first

      await storage.load();
      final hashKey = await PasswordHash.hash(password, hex.decode(storage.passwordHashSaltHex), outlen: 32);
      final passwordHashHex = hex.encode(hashKey);
      secretKey = await SecretBox.decrypt(hex.decode(storage.secretKeyEncrypted), hex.decode(storage.nonceHex), hex.decode(passwordHashHex));

      publicKey = await cryptoUtilsChannel.getPublicKeyFromPrivateKey(secretKey);
      wcCryptoAddresses['BTC'] = await cryptoUtilsChannel.getAddressFromPrivateKey(secretKey, 'BTC');
      wcCryptoAddresses['ETH'] = await cryptoUtilsChannel.getAddressFromPrivateKey(secretKey, 'ETH');

      final chatKeyPairSeed = hex.decode(await SecretBox.decrypt(hex.decode(storage.chatKeyPairSeedEncryptedHex), hex.decode(storage.nonceHex), hex.decode(passwordHashHex)));
      chatKeyPair = await generateKeyPairFromSeed(chatKeyPairSeed);

      return true;
    } catch (e) {
      _logger.warning("Error: $e");
    }
    return false;
  }

  void clear() {
    publicKey = null;
    secretKey = null;
    chatKeyPair = null;
    storage.clear();
  }

  Future<void> fcmSubscribeToTopic(String topic, {bool actuallySubscribe = true}) async {
    // If the notification setting is disabled, just add it to the list
    // (so it can be re-enabled later) without actually subscribing to FCM
    if (actuallySubscribe)
      fcm.subscribeToTopic(topic);

    storage.fcmSubscribedTopics.add(topic);
  }

  Future<void> fcmUnsubscribeFromTopic(String topic) async {
    fcm.unsubscribeFromTopic(topic);
    storage.fcmSubscribedTopics.remove(topic);
  }

  /// Unsubscribes topics from FCM but keeps them in memory so that later we can re-enable them.
  Future<void> fcmDisableTopics(bool pred(String t)) async {
    for (final topic in storage.fcmSubscribedTopics.where(pred))
      fcm.unsubscribeFromTopic(topic);
  }

  /// Subscribes the stored FCM topics
  Future<void> fcmEnableAllTopics(bool pred(String t)) async {
    for (final topic in storage.fcmSubscribedTopics.where(pred))
      fcm.subscribeToTopic(topic);
  }

  bool get hasIdentity => storage.hasIdentity;

  void _ensureInited() {
    if (!_inited) throw Exception("AppState used before initialization");
  }
}
