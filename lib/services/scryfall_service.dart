import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/card.dart';

/// Service for fetching random cards from Scryfall API
class ScryfallService {
  static const _baseUrl = 'https://api.scryfall.com';
  
  // Rate limiting: Scryfall wants 50-100ms between requests
  DateTime? _lastRequest;
  
  Future<void> _rateLimit() async {
    if (_lastRequest != null) {
      final elapsed = DateTime.now().difference(_lastRequest!);
      if (elapsed.inMilliseconds < 100) {
        await Future.delayed(Duration(milliseconds: 100 - elapsed.inMilliseconds));
      }
    }
    _lastRequest = DateTime.now();
  }

  /// Get a random creature with the specified mana value (Momir Vig)
  Future<MtgCard> getRandomCreature(int manaValue) async {
    await _rateLimit();
    
    final query = Uri.encodeComponent('type:creature cmc:$manaValue');
    final response = await http.get(
      Uri.parse('$_baseUrl/cards/random?q=$query'),
    );
    
    if (response.statusCode == 200) {
      return MtgCard.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 404) {
      throw NoCardFoundException('No creature found at MV $manaValue');
    } else {
      throw ScryfallException('Scryfall error: ${response.statusCode}');
    }
  }

  /// Get a random instant or sorcery with the specified mana value (Jhoira)
  Future<MtgCard> getRandomInstantOrSorcery(int manaValue) async {
    await _rateLimit();
    
    final query = Uri.encodeComponent('(type:instant OR type:sorcery) cmc:$manaValue');
    final response = await http.get(
      Uri.parse('$_baseUrl/cards/random?q=$query'),
    );
    
    if (response.statusCode == 200) {
      return MtgCard.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 404) {
      throw NoCardFoundException('No instant/sorcery found at MV $manaValue');
    } else {
      throw ScryfallException('Scryfall error: ${response.statusCode}');
    }
  }
}

class ScryfallException implements Exception {
  final String message;
  ScryfallException(this.message);
  
  @override
  String toString() => message;
}

class NoCardFoundException extends ScryfallException {
  NoCardFoundException(super.message);
}
