import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/io.dart';
import 'package:whalechat_app/models/message.dart';
import 'package:whalechat_app/screens/chat_member_list_screen.dart';
import 'package:whalechat_app/services/whisper_service.dart';
import 'package:whalechat_app/utils/app_state.dart';
import 'package:whalechat_app/utils/utils.dart';
import 'package:whalechat_app/widgets/identicon.dart';
import 'package:whalechat_app/widgets/yes_no_dialog.dart';
import 'package:whalechat_app/models/identity.dart';
import 'package:whalechat_app/models/room.dart';
import 'package:whalechat_app/protocol/crypto.dart';
import 'package:whalechat_app/protocol/transport.dart';

enum _PopupMenuChoice {
  viewMember,
  leave
}

final _logger = new Logger('ChatScreen');

class ChatScreen extends StatefulWidget {
  final Room room;

  ChatScreen({Key key, @required this.room}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ChatScreenState(room);
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final List<Message> _messages = List.of([]);
  final _messageController = TextEditingController();
  final _scrollController = ScrollController(initialScrollOffset: 999.0);
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final WhisperService shh = AppState.instance.whisperService;
  final _subscriptions = <StreamSubscription>[];

  IOWebSocketChannel channel;
  Room room;

  _ChatScreenState(this.room);

  @override
  void initState() {
    super.initState();

    _subscriptions.add(shh.toastMessages.listen((m) {
      Fluttertoast.showToast(
        msg: m, gravity: ToastGravity.TOP,
        backgroundColor: Color(0xff444444),
        textColor: Colors.white
      );
    }));

    WidgetsBinding.instance.addObserver(this);

    _startSubscription();
    _subscribeToFcmTopic();

    sharePublicKeyWithRoom();

    AppState.instance.currentChatTopic = room.topic;
  }

  Future<void> _subscribeToFcmTopic() async {
    if (!AppState.instance.storage.fcmSubscribedTopics.contains(room.topic)) {
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
  }

  Future<void> _refreshRoom() async => room =
    (await AppState.instance.apiService.getLobby()).rooms.firstWhere((r) => r.topic == room.topic);

  Future<void> _startSubscription() async {
    final shh = AppState.instance.whisperService;
    final api = AppState.instance.apiService;

    await shh.subscribeToRoom("0x" + room.topic);

    final history = await api.fetchHistory(room.topic, DateTime.utc(2018, 1, 1));

    final messages1 = <Message>[];

    for (final m in history) {
      try {
        Object obj = await decodeMessage(await verifyMessage(m.body));
        if (obj is String) {
          messages1.add(Message(body: obj, sender: m.sender, sentAt: m.sentAt));
        }
      } catch (_) {
        continue;
      }
    }

    setState(() {
      _messages.addAll(messages1);
    });

    _scrollToBottom();

    _subscriptions.add(shh.topicMessages["0x" + room.topic].listen(_receiveMessage));
  }

  Future<void> sharePublicKeyWithRoom() async {
    String payload = await (signMessage(createSharePublicKey()));
    Message message = new Message(sender: AppState.instance.storage.nickname, body: payload, sentAt: DateTime.now());
    shh.sendMessage("0x" + room.topic, message);
  }

  String get roomTitle {
    if (room.title != null)
      return room.title;
    assert(room.isDirectMessage);
    return room.members.firstWhere(
        (id) => id.publicKey != AppState.instance.publicKey).nickname;
  }

  void _scrollToBottom() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 100),
        curve: Curves.ease
      );
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _scrollToBottom();
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
    for (final sub in _subscriptions)
      sub.cancel();
    AppState.instance.whisperService.unsubscribeFromRoom("0x" + room.topic);
    AppState.instance.currentChatTopic = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(roomTitle),
        actions: [
          PopupMenuButton(
            onSelected: (val) {
              switch (val) {
                case _PopupMenuChoice.viewMember:
                  Navigator.push(context, MaterialPageRoute(builder: (_) =>
                    ChatMemberListScreen(room: room)
                  ));
                  break;

                case _PopupMenuChoice.leave:
                  showDialog(context: context, builder: (_) => YesNoDialog.build(
                    context: context,
                    title: "Are you sure?",
                    content: "You can rejoin the channel later if you meet the channel requirement. However, you will NOT be able to see the messages while you were not a member of the channel",
                    onYes: () {
                      AppState.instance.apiService.leaveRoom(room);
                      Navigator.of(context).pop();
                    },
                    onNo: () {}
                  ));
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: _PopupMenuChoice.viewMember, child: Text("View Members")),
              PopupMenuItem(value: _PopupMenuChoice.leave, child: Text("Leave")),
            ]
          )
        ]
      ),
      bottomNavigationBar: Transform.translate(
        offset: Offset(0.0, -MediaQuery.of(context).viewInsets.bottom),
        child: BottomAppBar(child: Form(child: Row(children: [
          Expanded(
            child: Container(padding: EdgeInsets.all(8.0), child: TextFormField(
              decoration: InputDecoration(
                hintText: "Message",
                contentPadding: EdgeInsets.all(8.0)
              ),
              controller: _messageController,

              // XXX Does not get submitted on Android
              // https://github.com/flutter/flutter/issues/19027
              onFieldSubmitted: (_) => _sendMessage(),
            ))),

          IconButton(
            icon: Icon(Icons.send),
            onPressed: _sendMessage,
          )
        ]))),
      ),

      body: Column(children: [
        Expanded(child: ListView.builder(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom > 0 ? 64 : 16),
          reverse: false,
          controller: _scrollController,
          itemCount: _messages.length,
          itemBuilder: (_, index) {
            final m = _messages[index];
            final id = room.members.firstWhere((id) => id.nickname == m.sender);

            final format = DateFormat.Hm();
            final timestampContainer = Container(
              child: Text(
                format.format(m.sentAt),
                style: TextStyle(color: Colors.grey),
              ),
              alignment: Alignment.centerRight,
            );

            if (m.body == "<<<JOIN>>>" || m.body == "<<<LEAVE>>>") {
              final m1 = m.body == "<<<JOIN>>>"
                ? "--- ${m.sender} joined the room ---"
                : "--- ${m.sender} left the room ---";

              return Container(
                child: Column(children: [
                  Center(child: Text(m1, style: TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ))),
                  timestampContainer
                ]),
                padding: EdgeInsets.fromLTRB(0, 24, 0, 24),
              );
            }

            return Column(children: [
              ListTile(
                leading: Identicon.of(id),
                title: Text(m.sender),
                subtitle: Text(m.body),
                onTap: () => null,
              ),
              timestampContainer
            ]);
          }
        )),
      ])
    );
  }

  Future<void> _sendMessage() async {
    final shh = AppState.instance.whisperService;
    final api = AppState.instance.apiService;

    if (_messageController.value.text.isEmpty)
      return;

    List<String> roomsPublicKeys = room.members.map((identity) => identity.chatPublicKey).toList();
    String payload = await signMessage(await createMessageToRoom(_messageController.value.text, room, roomsPublicKeys, room.pullNonce()));

    final m = Message(body: payload, sender: AppState.instance.storage.nickname, sentAt: DateTime.now());

    api.logMessage(room.topic, m);
    shh.sendMessage("0x" + room.topic, m);

    setState(() {
      _messageController.clear();
    });
  }

  Future<void> _receiveMessage(Message m) async {
    Object obj = await decodeMessage(await verifyMessage(m.body));

    if (obj is String) {
      Message message = new Message(body: obj, sender: m.sender, sentAt: m.sentAt);
      setState(() {
        _messages.add(message);
      });
      _scrollToBottom();
      if (message.body == "<<<JOIN>>>" || message.body == "<<<LEAVE>>>")
        await _refreshRoom();
    } else if (obj is Identity) {
      dbgPrint('Adding identity "' + obj.nickname + '" to room');
      final Identity id = await decodeMessage(await verifyMessage(m.body));
      if (room.members.firstWhere((m) => m.publicKey == id.publicKey, orElse: () => null) == null)
        room.members.add(id);
    } else {
      _logger.severe("Unknown object from message: $m");
    }
  }
}
