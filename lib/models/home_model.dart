import 'package:hive_ce/hive_ce.dart';

part 'home_model.g.dart';

// Represents one home record cached locally so the Home tab can render
// instantly (offline-first) before/without a network round-trip.
@HiveType(typeId: 0)
class HomeModel extends HiveObject {
  @HiveField(0)
  String? id;

  @HiveField(1)
  String address;

  @HiveField(2)
  String pincode;

  // roomKey -> list of appliance maps (product, brand, warranty, createdAt, roomName...)
  @HiveField(3)
  Map<String, List<Map<String, dynamic>>> rooms;

  @HiveField(4)
  List<Map<String, dynamic>> members;

  @HiveField(5)
  String? homeName;

  // Pin location confirmed on the map (null for old / Default homes).
  @HiveField(6)
  double? latitude;

  @HiveField(7)
  double? longitude;

  HomeModel({
    this.id,
    required this.address,
    required this.pincode,
    required this.rooms,
    required this.members,
    this.homeName,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'address': address,
        'pincode': pincode,
        'rooms': rooms,
        'members': members,
        'homeName': homeName,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory HomeModel.fromMap(Map<String, dynamic> map) => HomeModel(
        id: map['id']?.toString(),
        address: map['address']?.toString() ?? '',
        pincode: map['pincode']?.toString() ?? '',
        rooms: (map['rooms'] as Map?)?.map(
              (key, value) => MapEntry(
                key.toString(),
                (value as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList(),
              ),
            ) ??
            {},
        members: (map['members'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [],
        homeName: map['homeName']?.toString(),
        latitude: double.tryParse(map['latitude']?.toString() ?? ''),
        longitude: double.tryParse(map['longitude']?.toString() ?? ''),
      );
}