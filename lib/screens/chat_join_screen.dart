import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:whalechat_app/screens/chat_screen.dart';
import 'package:whalechat_app/utils/app_state.dart';
import 'package:whalechat_app/widgets/app_button.dart';
import 'package:whalechat_app/models/room.dart';

class ChatJoinScreen extends StatelessWidget {
  final Room room;
  num roomRequiredAmount;
  ChatJoinScreen({Key key, @required this.room}) : super(key: key);

  @override
  Widget build(BuildContext context) {

    if (room.requiredCurrency.toUpperCase() == 'BTC') {
      roomRequiredAmount = room.requiredAmount * 1e8;
    }
    if (room.requiredCurrency.toUpperCase() == 'ETH') {
      roomRequiredAmount = room.requiredAmount * 1e18;
    }

    return Scaffold(
      appBar: AppBar(title: Text(room.title)),
      body: Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Spacer(),

              Text(room.title, style: Theme.of(context).textTheme.headline, textAlign: TextAlign.center),
              SizedBox(height: 16),
              Text(room.subtitle, style: Theme.of(context).textTheme.subhead, textAlign: TextAlign.center),

              Divider(),

              Center(child: AppState.instance.storage.getBalance(room.requiredCurrency) < Decimal.parse(room.requiredAmount.toString())
                ? _buildCantJoinWidget()
                : _buildJoinWidget(context)
              ),

              Spacer(),
            ]
          )
        )
      )
    );
  }

  Widget _buildJoinWidget(BuildContext context) {
    return AppButton.buildBig(context, "Join", onPressed: () async {
      await AppState.instance.apiService.joinRoom(room, null);
      final room1 = (await AppState.instance.apiService.getLobby()).rooms.firstWhere(
          (r) => r.topic == room.topic);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) =>
        ChatScreen(room: room1)
      ));
    });
  }

  Widget _buildCantJoinWidget() {
    return Text(
      "You are not allowed to join this room: You need to prove that you own at least ${room.requiredAmount} ${room.requiredCurrency}",
      style: TextStyle(color: Colors.grey), textAlign: TextAlign.center);
  }
}
