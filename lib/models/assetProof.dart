import 'package:json_annotation/json_annotation.dart';
part 'assetProof.g.dart';

@JsonSerializable(includeIfNull: false)
class AssetProof {
  final String symbol;
  final String address;
  final String signature;
  
  const AssetProof({this.symbol, this.address, this.signature});

  factory AssetProof.fromJson(Map<String, dynamic> json) => _$AssetProofFromJson(json);
  Map<String, dynamic> toJson() => _$AssetProofToJson(this);
}
