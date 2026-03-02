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
    
    final query = Uri.encodeComponent('type:creature mv=$manaValue');
    final url = '$_baseUrl/cards/random?q=$query';
    
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      return MtgCard.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 404) {
      throw NoCardFoundException('No creature found at MV $manaValue');
    } else {
      final errorBody = _parseError(response.body);
      throw ScryfallException('Scryfall error ${response.statusCode}: $errorBody');
    }
  }

  /// Get a random instant (any mana value)
  Future<MtgCard> getRandomInstant() async {
    await _rateLimit();
    
    final query = Uri.encodeComponent('type:instant');
    final url = '$_baseUrl/cards/random?q=$query';
    
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      return MtgCard.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 404) {
      throw NoCardFoundException('No instant found');
    } else {
      final errorBody = _parseError(response.body);
      throw ScryfallException('Scryfall error ${response.statusCode}: $errorBody');
    }
  }

  /// Get a random sorcery (any mana value)
  Future<MtgCard> getRandomSorcery() async {
    await _rateLimit();
    
    final query = Uri.encodeComponent('type:sorcery');
    final url = '$_baseUrl/cards/random?q=$query';
    
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      return MtgCard.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 404) {
      throw NoCardFoundException('No sorcery found');
    } else {
      final errorBody = _parseError(response.body);
      throw ScryfallException('Scryfall error ${response.statusCode}: $errorBody');
    }
  }

  /// Get a random equipment with mana value <= specified (Stonehewer Giant)
  Future<MtgCard> getRandomEquipment(int maxManaValue) async {
    await _rateLimit();
    
    // Use mv<= for mana value comparison
    final query = Uri.encodeComponent('type:equipment mv<=$maxManaValue');
    final url = '$_baseUrl/cards/random?q=$query';
    
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      return MtgCard.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 404) {
      throw NoCardFoundException('No equipment found at MV ≤$maxManaValue');
    } else {
      final errorBody = _parseError(response.body);
      throw ScryfallException('Scryfall error ${response.statusCode}: $errorBody');
    }
  }

  String _parseError(String body) {
    try {
      final json = jsonDecode(body);
      return json['details'] ?? json['error'] ?? 'Unknown error';
    } catch (_) {
      return body.length > 100 ? '${body.substring(0, 100)}...' : body;
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
