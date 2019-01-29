import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:whalechat_app/models/room.dart';
import 'package:whalechat_app/models/cryptoAccount.dart';
import 'package:whalechat_app/screens/chat_screen.dart';
import 'package:whalechat_app/utils/app_state.dart';
import 'package:whalechat_app/widgets/app_button.dart';
import 'package:whalechat_app/widgets/identicon.dart';

import '../models/identity.dart';

ListTile _buildTile(BuildContext context, CryptoAccount account) {
  return ListTile(
    title: Text(account.displayBalance),
    onTap: () {
    },
  );
}

class IdentityDetailScreen extends StatelessWidget {
  final Identity identity;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  IdentityDetailScreen({Key key, @required this.identity}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final accounts = this.identity.accounts;

    final widgets = [
      Row(children: [Identicon.of(identity), Expanded(child: Text(identity.nickname))]),
      Text("")
    ];

    if (identity.publicKey != AppState.instance.publicKey) {
      widgets.addAll([Text(""), AppButton.buildBig(
        context, "Message ${identity.nickname}",
        onPressed: () => _startDirectMessage(context, identity), icon: Icons.message)]);
    }

    if (accounts != null && accounts.length > 0) {
      widgets.addAll([
        SizedBox(height: 8),
        AppButton.build(
          context, "Show asset proof signatures",
          onPressed: () => _showAssetProofSignatures(context, identity), icon: Icons.link)
      ]);

      widgets.add(Flexible(child: ListView(
        children: accounts.map((a) => _buildTile(context, a)).toList())));
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(title: Text(identity.nickname)),
      body: Container(padding: EdgeInsets.all(24.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets)),
    );
  }

  Future<void> _startDirectMessage(BuildContext context, Identity identity) async {
    final dmRooms = (await AppState.instance.apiService.getLobby()).rooms.where(
        (x) => x.category == 'Direct Messages');

    final me = AppState.instance.identity;
    Room r = dmRooms.isEmpty ? null : dmRooms.firstWhere(
        (r) => r.isDirectMessage && r.members.contains(identity) && r.members.contains(me), orElse: () => null);

    if (r == null) {
      final topic = await AppState.instance.apiService.createChat(me, identity);

      // Get back the full room object by get_lobby
      r = (await AppState.instance.apiService.getLobby()).rooms.firstWhere((r1) => r1.topic == topic);
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(room: r)));
  }

  Future<void> _showAssetProofSignatures(BuildContext context, Identity identity) async {
     // TODO
    _scaffoldKey.currentState.showSnackBar(SnackBar(content: Text("Not yet implemented")));
  }
}
