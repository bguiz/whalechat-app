import 'package:json_annotation/json_annotation.dart';
import 'package:whalechat_app/models/cryptoAccount.dart';
import 'package:decimal/decimal.dart';
part 'identity.g.dart';

@JsonSerializable(includeIfNull: false)
class Identity {
  final String publicKey;
  final String nickname;
  List<CryptoAccount> accounts = new List<CryptoAccount>();
  final String chatPublicKey;

  Identity({this.publicKey, this.nickname, this.chatPublicKey});

  factory Identity.fromJson(Map<String, dynamic> json) => _$IdentityFromJson(json);
  Map<String, dynamic> toJson() => _$IdentityToJson(this);

  Decimal getBalance(String symbol) {
    Decimal balance = Decimal.parse('0');
    for (CryptoAccount account in accounts) {
      if (account.symbol == symbol) {
        balance += Decimal.parse(account.balance);
      }
    }
    return balance;
  }
}
