import 'dart:convert';
import 'package:crypto/crypto.dart';

class SecureFolderModel {
  final String id;
  final String name;
  final String? pinHash;
  final DateTime createdAt;

  const SecureFolderModel({
    required this.id,
    required this.name,
    this.pinHash,
    required this.createdAt,
  });

  static String hashPin(String pin) =>
      sha256.convert(utf8.encode(pin)).toString();

  bool get hasPin => pinHash != null && pinHash!.isNotEmpty;

  bool verifyPin(String pin) => !hasPin || pinHash == hashPin(pin);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pinHash': pinHash,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SecureFolderModel.fromJson(Map<String, dynamic> json) =>
      SecureFolderModel(
        id: json['id'] as String,
        name: json['name'] as String,
        pinHash: json['pinHash'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
