/// Represents an MTG card from Scryfall
class MtgCard {
  final String id;
  final String name;
  final String? manaCost;
  final int? cmc;
  final String? typeLine;
  final String? oracleText;
  final String? power;
  final String? toughness;
  final CardImages images;

  MtgCard({
    required this.id,
    required this.name,
    this.manaCost,
    this.cmc,
    this.typeLine,
    this.oracleText,
    this.power,
    this.toughness,
    required this.images,
  });

  factory MtgCard.fromJson(Map<String, dynamic> json) {
    return MtgCard(
      id: json['id'],
      name: json['name'],
      manaCost: json['mana_cost'],
      cmc: json['cmc']?.toInt(),
      typeLine: json['type_line'],
      oracleText: json['oracle_text'],
      power: json['power'],
      toughness: json['toughness'],
      images: CardImages.fromJson(json['image_uris'] ?? {}),
    );
  }

  /// Check if this is a creature
  bool get isCreature => typeLine?.toLowerCase().contains('creature') ?? false;

  /// Get P/T string if applicable
  String? get ptString => power != null && toughness != null 
      ? '$power/$toughness' 
      : null;
}

/// Card image URLs from Scryfall
class CardImages {
  final String? small;
  final String? normal;
  final String? large;
  final String? artCrop;
  final String? borderCrop;

  CardImages({
    this.small,
    this.normal,
    this.large,
    this.artCrop,
    this.borderCrop,
  });

  factory CardImages.fromJson(Map<String, dynamic> json) {
    return CardImages(
      small: json['small'],
      normal: json['normal'],
      large: json['large'],
      artCrop: json['art_crop'],
      borderCrop: json['border_crop'],
    );
  }

  /// Best image for thermal printing (full card)
  String? get forPrinting => normal ?? large ?? borderCrop ?? small;
}
