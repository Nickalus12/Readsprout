// GENERATED CODE - DO NOT MODIFY BY HAND
// (Manually written TypeAdapters matching @HiveType annotations)

part of 'player_profile.dart';

// ── PlayerProfile adapter (typeId: 0) ─────────────────────────────

class PlayerProfileAdapter extends TypeAdapter<PlayerProfile> {
  @override
  final int typeId = 0;

  @override
  PlayerProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlayerProfile(
      name: fields[0] as String,
      avatar: fields[1] as AvatarConfig,
      currentStreak: fields[2] as int,
      bestStreak: fields[3] as int,
      lastPlayDate: fields[4] as DateTime?,
      unlockedItems: (fields[5] as List?)?.cast<String>(),
      earnedStickers: (fields[6] as List?)?.cast<String>(),
      totalWordsEverCompleted: fields[7] as int,
    );
  }

  @override
  void write(BinaryWriter writer, PlayerProfile obj) {
    writer
      ..writeByte(8) // number of fields
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.avatar)
      ..writeByte(2)
      ..write(obj.currentStreak)
      ..writeByte(3)
      ..write(obj.bestStreak)
      ..writeByte(4)
      ..write(obj.lastPlayDate)
      ..writeByte(5)
      ..write(obj.unlockedItems)
      ..writeByte(6)
      ..write(obj.earnedStickers)
      ..writeByte(7)
      ..write(obj.totalWordsEverCompleted);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerProfileAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// ── AvatarConfig adapter (typeId: 1) ──────────────────────────────
//
// Fields 11-18 added in the avatar overhaul. Old profiles that only have
// fields 0-10 will get default values (0) for the new fields.

class AvatarConfigAdapter extends TypeAdapter<AvatarConfig> {
  @override
  final int typeId = 1;

  @override
  AvatarConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AvatarConfig(
      faceShape: fields[0] as int,
      skinTone: fields[1] as int,
      hairStyle: fields[2] as int,
      hairColor: fields[3] as int,
      eyeStyle: fields[4] as int,
      mouthStyle: fields[5] as int,
      accessory: fields[6] as int,
      bgColor: fields[7] as int,
      hasSparkle: fields[8] as bool,
      hasRainbowSparkle: fields[9] as bool,
      hasGoldenGlow: fields[10] as bool,
      // New fields default to 0 for old profiles
      eyeColor: (fields[11] as int?) ?? 0,
      eyelashStyle: (fields[12] as int?) ?? 0,
      eyebrowStyle: (fields[13] as int?) ?? 0,
      lipColor: (fields[14] as int?) ?? 0,
      cheekStyle: (fields[15] as int?) ?? 0,
      noseStyle: (fields[16] as int?) ?? 0,
      glassesStyle: (fields[17] as int?) ?? 0,
      facePaint: (fields[18] as int?) ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, AvatarConfig obj) {
    writer
      ..writeByte(19) // number of fields
      ..writeByte(0)
      ..write(obj.faceShape)
      ..writeByte(1)
      ..write(obj.skinTone)
      ..writeByte(2)
      ..write(obj.hairStyle)
      ..writeByte(3)
      ..write(obj.hairColor)
      ..writeByte(4)
      ..write(obj.eyeStyle)
      ..writeByte(5)
      ..write(obj.mouthStyle)
      ..writeByte(6)
      ..write(obj.accessory)
      ..writeByte(7)
      ..write(obj.bgColor)
      ..writeByte(8)
      ..write(obj.hasSparkle)
      ..writeByte(9)
      ..write(obj.hasRainbowSparkle)
      ..writeByte(10)
      ..write(obj.hasGoldenGlow)
      ..writeByte(11)
      ..write(obj.eyeColor)
      ..writeByte(12)
      ..write(obj.eyelashStyle)
      ..writeByte(13)
      ..write(obj.eyebrowStyle)
      ..writeByte(14)
      ..write(obj.lipColor)
      ..writeByte(15)
      ..write(obj.cheekStyle)
      ..writeByte(16)
      ..write(obj.noseStyle)
      ..writeByte(17)
      ..write(obj.glassesStyle)
      ..writeByte(18)
      ..write(obj.facePaint);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvatarConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// ── StickerRecord adapter (typeId: 2) ─────────────────────────────

class StickerRecordAdapter extends TypeAdapter<StickerRecord> {
  @override
  final int typeId = 2;

  @override
  StickerRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StickerRecord(
      stickerId: fields[0] as String,
      dateEarned: fields[1] as DateTime,
      category: fields[2] as String,
      isNew: fields[3] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, StickerRecord obj) {
    writer
      ..writeByte(4) // number of fields
      ..writeByte(0)
      ..write(obj.stickerId)
      ..writeByte(1)
      ..write(obj.dateEarned)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.isNew);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StickerRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
