import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;
import 'package:logging/logging.dart';
import 'package:web_socket_channel/io.dart';
import 'package:whalechat_app/models/identity.dart';
import 'package:whalechat_app/models/message.dart';
import 'package:whalechat_app/models/assetProof.dart';
import 'package:whalechat_app/models/lobby.dart';
import 'package:whalechat_app/models/room.dart';
import 'package:whalechat_app/protocol/validation.dart';
import 'package:whalechat_app/utils/app_config.dart';
import 'package:whalechat_app/utils/app_state.dart';
import 'package:whalechat_app/utils/utils.dart';

class ApiService {
  final _logger = Logger("ApiService");

  final mockLobby = Lobby(rooms: [
    Room(title: "BTC megawhales", subtitle: "Requirement: 100k+ BTC", requiredCurrency: 'BTC', requiredAmount: 100000, category: "BTC", topic: "0x77686178"),
    Room(title: "BTC miniwhales", subtitle: "Requirement: 10+ BTC", category: "BTC", requiredCurrency: 'BTC', requiredAmount: 10, topic: "0x77686177"),
    Room(title: "ETH megawhales", subtitle: "Requirement: 100k+ ETH", requiredCurrency: 'ETH', requiredAmount: 100000, category: "ETH", topic: "0x77686179"),
    Room(title: "ETH miniwhales", subtitle: "Requirement: 10 ETH", requiredCurrency: 'ETH', requiredAmount: 10, category: "ETH", topic: "0x77686175"),
  ]);

  json_rpc.Client __client;

  json_rpc.Client get _client {
    if (__client == null || __client.isClosed) {
      __client = json_rpc.Client(IOWebSocketChannel.connect(appServerUrl).cast<String>());
      __client.listen();
    }
    return __client;
  }

  Future<void> ping() async {
    dbgPrint(await _client.sendRequest("v1/ping"));
  }

  Future<Lobby> getLobby() async {
    final sig = await AppState.instance.cryptoUtilsChannel.ecSign(AppState.instance.publicKey, AppState.instance.secretKey);
    final rv = await _client.sendRequest("v1/get_lobby", [
      AppState.instance.identity.publicKey, sig.signature
    ]);
    return Lobby.fromJson(rv);
  }

  Future<void> logMessage(String topic, Message message) async {
    final rv = await _client.sendRequest("v1/log_message", [
      topic, message.body, message.sender, message.sentAt.toUtc().toIso8601String()]);

    if (rv != 'ok')
      throw("Error: $rv");
  }

  Future<List<Message>> fetchHistory(String topic, DateTime from) async {
    final List<dynamic> rv = (await _client.sendRequest("v1/fetch_history", [
      topic,
      from.toUtc().toIso8601String(),
      AppState.instance.publicKey,
      (await AppState.instance.cryptoUtilsChannel.ecSign(AppState.instance.publicKey, AppState.instance.secretKey)).signature,
    ]))['messages'];

    return rv.map((x) => Message.fromJson(x)).toList();
  }

  Future<void> register(String nickname, String identityPubKey, String chatPubKey) async {
    final rv = await _client.sendRequest("v1/register_nickname", [nickname, identityPubKey, chatPubKey]);

    if (rv != 'ok')
      throw("Error: $rv");
  }

  Future<String> createChat(Identity id1, Identity id2) async {
    final sig = await AppState.instance.cryptoUtilsChannel.ecSign(AppState.instance.publicKey, AppState.instance.secretKey);

    final rv = await _client.sendRequest("v1/create_chat", [
      id1.publicKey, id2.publicKey, sig.signature,
    ]);

    return rv['topic'];
  }

  Future<void> joinRoom(Room room, String signedTxid) async {
    final sig = await AppState.instance.cryptoUtilsChannel.ecSign(AppState.instance.publicKey, AppState.instance.secretKey);

    final rv = await _client.sendRequest("v1/join_room", [
      room.topic,
      AppState.instance.publicKey,
      sig.signature
    ]);

    if (rv != 'ok')
      throw("Error: $rv");

    await logMessage(room.topic, Message(
      body: "<<<JOIN>>>",
      sender: AppState.instance.storage.nickname,
      sentAt: DateTime.now()
    ));

    final actuallySubscribe = (
      !room.isDirectMessage &&
        AppState.instance.allNotificationsEnabled &&
        AppState.instance.chatroomMessagesNotificationsEnabled
    ) || (
      room.isDirectMessage &&
        AppState.instance.allNotificationsEnabled &&
        AppState.instance.privateMessagesNotificationsEnabled
    );

    AppState.instance.fcmSubscribeToTopic(
      room.topic, actuallySubscribe: actuallySubscribe);
  }

  Future<void> leaveRoom(Room room) async {
    AppState.instance.fcmUnsubscribeFromTopic(room.topic);

    await logMessage(room.topic, Message(
      body: "<<<LEAVE>>>",
      sender: AppState.instance.storage.nickname,
      sentAt: DateTime.now()
    ));

    final sig = await AppState.instance.cryptoUtilsChannel.ecSign(AppState.instance.publicKey, AppState.instance.secretKey);

    final rv = await _client.sendRequest("v1/leave_room", [
      room.topic,
      AppState.instance.publicKey,
      sig.signature
    ]);

    if (rv != 'ok')
      throw("Error: $rv");
  }

  void onRoomUpdated() {}

  Future<void> registerAssetProof(String symbol, String address, String signature) async {
    final rv = await _client.sendRequest("v1/register_assetproof", [
      symbol,
      address,
      signature,
      AppState.instance.publicKey,
    ]);

    if (rv != 'ok') throw ("Error: $rv");
  }

  Future<List<AssetProof>> requestAssetProofs(String publicKey) async {
    final rv = await _client.sendRequest("v1/request_assetproofs", [publicKey]);

    if (rv is String) throw ("Error: $rv");

    final List<dynamic> rv2 = rv['assetProofs'];
    final assetProofs = rv2.map((x) => AssetProof.fromJson(x)).toList();

    final List<AssetProof> ret = [];
    for (final assetProof in assetProofs) {
      try {
        await validateAssetProof(assetProof);
        ret.add(assetProof);
      } catch (e) {
        _logger.warning(e);
      }
    }

    return ret;
  }

  void dispose() {
    __client?.close();
  }
}
