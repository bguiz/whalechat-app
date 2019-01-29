import 'package:json_annotation/json_annotation.dart';
import 'package:decimal/decimal.dart';
import 'package:whalechat_app/models/assetProof.dart';
import 'package:whalechat_app/utils/balance.dart';
part 'cryptoAccount.g.dart';

@JsonSerializable(includeIfNull: false)
class CryptoAccount {
  final String symbol; // e.g. BTC, ETH, etc.
  final String address;
  String balance; // Minimum unit (e.g. satoshi if BTC, wei if ETH)
  int balanceTimestamp;
  AssetProof assetProof;

  CryptoAccount({this.symbol, this.address});

  factory CryptoAccount.fromJson(Map<String, dynamic> json) => _$CryptoAccountFromJson(json);
  Map<String, dynamic> toJson() => _$CryptoAccountToJson(this);

  Future<String> refreshBalance() async {
    this.balance = await getBalance(this.symbol, this.address);
    this.balanceTimestamp = new DateTime.now().millisecondsSinceEpoch;
    return this.balance;
  }

  String get displayBalance {
    if (symbol == "BTC") {
      return "${(Decimal.parse(balance) / Decimal.parse('1e8')).toStringAsFixed(4)} BTC";
    } else if (symbol == "ETH") {
      return "${(Decimal.parse(balance) / Decimal.parse('1e18')).toStringAsFixed(4)} ETH";
    } else {
      throw AssertionError("Unsupported symbol $symbol");
    }
  }
}
