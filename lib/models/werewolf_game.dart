import 'dart:math';
import '../data/village_names.dart';

enum WerewolfRole {
  villager,
  werewolf,
  seer,
  witch,
  hunter,
  bodyguard,
  cupid,
}

extension WerewolfRoleExt on WerewolfRole {
  String get displayName {
    switch (this) {
      case WerewolfRole.villager: return 'VILLAGER';
      case WerewolfRole.werewolf: return 'WEREWOLF';
      case WerewolfRole.seer: return 'SEER';
      case WerewolfRole.witch: return 'WITCH';
      case WerewolfRole.hunter: return 'HUNTER';
      case WerewolfRole.bodyguard: return 'BODYGUARD';
      case WerewolfRole.cupid: return 'CUPID';
    }
  }

  String get emoji {
    switch (this) {
      case WerewolfRole.villager: return '🏠';
      case WerewolfRole.werewolf: return '🐺';
      case WerewolfRole.seer: return '👁️';
      case WerewolfRole.witch: return '🧙';
      case WerewolfRole.hunter: return '🏹';
      case WerewolfRole.bodyguard: return '🛡️';
      case WerewolfRole.cupid: return '💘';
    }
  }

  String get description {
    switch (this) {
      case WerewolfRole.villager:
        return 'You are a simple villager.\nFind and eliminate the wolves.';
      case WerewolfRole.werewolf:
        return 'You wake to the howl.\nChoose a victim with your pack.';
      case WerewolfRole.seer:
        return 'You wake to the chime.\nPoint at someone to learn\nif they are a wolf.';
      case WerewolfRole.witch:
        return 'You have one heal potion\nand one poison potion.\nUse them wisely.';
      case WerewolfRole.hunter:
        return 'When you die, you may\ntake someone with you.';
      case WerewolfRole.bodyguard:
        return 'Each night, choose someone\nto protect from the wolves.';
      case WerewolfRole.cupid:
        return 'On the first night, choose\ntwo lovers. If one dies,\nthe other dies of grief.';
    }
  }

  String get wakeCue {
    switch (this) {
      case WerewolfRole.villager: return ''; // Doesn't wake
      case WerewolfRole.werewolf: return 'howl'; // Wolf howl
      case WerewolfRole.seer: return 'chime'; // Mystical chime
      case WerewolfRole.witch: return 'bubble'; // Bubbling potion
      case WerewolfRole.hunter: return ''; // Doesn't wake at night normally
      case WerewolfRole.bodyguard: return 'shield'; // Shield sound
      case WerewolfRole.cupid: return 'heartbeat'; // Heartbeat (first night only)
    }
  }

  int get nightOrder {
    // Order in which roles act at night
    switch (this) {
      case WerewolfRole.cupid: return 0; // First night only
      case WerewolfRole.bodyguard: return 1;
      case WerewolfRole.werewolf: return 2;
      case WerewolfRole.witch: return 3;
      case WerewolfRole.seer: return 4;
      case WerewolfRole.hunter: return 99;
      case WerewolfRole.villager: return 99;
    }
  }
}

class WerewolfPlayer {
  final int seatPosition; // 1-indexed position around table
  final String name;
  WerewolfRole role;
  bool isMayor;
  bool isAlive;
  bool isProtected; // Bodyguard protection
  int? lovedBy; // Seat position of lover (Cupid)

  WerewolfPlayer({
    required this.seatPosition,
    required this.name,
    required this.role,
    this.isMayor = false,
    this.isAlive = true,
    this.isProtected = false,
    this.lovedBy,
  });
}

class RoleConfig {
  final WerewolfRole role;
  final int count;
  final bool guaranteed; // false = part of random pool

  RoleConfig(this.role, this.count, {this.guaranteed = true});
}

class WerewolfGame {
  final List<WerewolfPlayer> players;
  int dayNumber = 0;
  bool isNight = true;
  int? nightKillTarget;
  int? witchHealTarget;
  int? witchPoisonTarget;
  bool witchHealUsed = false;
  bool witchPoisonUsed = false;

  WerewolfGame(this.players);

  static WerewolfGame create({
    required int playerCount,
    required List<RoleConfig> roleConfigs,
    int werewolfCount = 2,
  }) {
    final random = Random();
    
    // Shuffle and pick names
    final shuffledNames = List<String>.from(villageNames)..shuffle(random);
    final names = shuffledNames.take(playerCount).toList();

    // Build role list
    final roles = <WerewolfRole>[];
    
    // Add werewolves
    for (int i = 0; i < werewolfCount; i++) {
      roles.add(WerewolfRole.werewolf);
    }

    // Add guaranteed roles
    for (final config in roleConfigs.where((c) => c.guaranteed)) {
      for (int i = 0; i < config.count; i++) {
        roles.add(config.role);
      }
    }

    // Handle random pool (pick X from pool)
    final randomPool = roleConfigs.where((c) => !c.guaranteed).toList();
    if (randomPool.isNotEmpty) {
      randomPool.shuffle(random);
      // Pick roles from pool until we can't add more
      for (final config in randomPool) {
        if (roles.length < playerCount) {
          roles.add(config.role);
        }
      }
    }

    // Fill remaining with villagers
    while (roles.length < playerCount) {
      roles.add(WerewolfRole.villager);
    }

    // Shuffle roles
    roles.shuffle(random);

    // Assign mayor (random villager if possible, otherwise random non-werewolf)
    int mayorIndex = -1;
    final villagerIndices = <int>[];
    final nonWolfIndices = <int>[];
    for (int i = 0; i < roles.length; i++) {
      if (roles[i] == WerewolfRole.villager) villagerIndices.add(i);
      if (roles[i] != WerewolfRole.werewolf) nonWolfIndices.add(i);
    }
    if (villagerIndices.isNotEmpty) {
      mayorIndex = villagerIndices[random.nextInt(villagerIndices.length)];
    } else if (nonWolfIndices.isNotEmpty) {
      mayorIndex = nonWolfIndices[random.nextInt(nonWolfIndices.length)];
    }

    // Create players
    final players = <WerewolfPlayer>[];
    for (int i = 0; i < playerCount; i++) {
      players.add(WerewolfPlayer(
        seatPosition: i + 1,
        name: names[i],
        role: roles[i],
        isMayor: i == mayorIndex,
      ));
    }

    return WerewolfGame(players);
  }

  List<WerewolfPlayer> get alivePlayers => players.where((p) => p.isAlive).toList();
  List<WerewolfPlayer> get aliveWerewolves => alivePlayers.where((p) => p.role == WerewolfRole.werewolf).toList();
  List<WerewolfPlayer> get aliveVillagers => alivePlayers.where((p) => p.role != WerewolfRole.werewolf).toList();

  bool get isGameOver {
    if (aliveWerewolves.isEmpty) return true; // Village wins
    if (aliveWerewolves.length > aliveVillagers.length) return true; // Wolves win (strict majority)
    return false;
  }

  String get winner {
    if (aliveWerewolves.isEmpty) return 'VILLAGE';
    return 'WEREWOLVES';
  }

  WerewolfPlayer? getPlayerBySeat(int seat) {
    return players.firstWhere((p) => p.seatPosition == seat, orElse: () => players.first);
  }

  /// Get roles that need to act this night, in order
  List<WerewolfRole> getNightActions() {
    final activeRoles = <WerewolfRole>{};
    for (final player in alivePlayers) {
      if (player.role.nightOrder < 99) {
        // Skip cupid after first night
        if (player.role == WerewolfRole.cupid && dayNumber > 0) continue;
        activeRoles.add(player.role);
      }
    }
    final list = activeRoles.toList();
    list.sort((a, b) => a.nightOrder.compareTo(b.nightOrder));
    return list;
  }

  /// Process night kill (returns victim name or null if saved)
  String? resolveNight() {
    if (nightKillTarget == null) return null;
    
    final target = getPlayerBySeat(nightKillTarget!);
    if (target == null) return null;

    // Check if protected by bodyguard
    if (target.isProtected) {
      nightKillTarget = null;
      return null;
    }

    // Check if witch healed
    if (witchHealTarget == nightKillTarget && !witchHealUsed) {
      witchHealUsed = true;
      nightKillTarget = null;
      return null;
    }

    // Kill target
    target.isAlive = false;
    final victimName = target.name;

    // Check for lover death
    if (target.lovedBy != null) {
      final lover = getPlayerBySeat(target.lovedBy!);
      if (lover != null && lover.isAlive) {
        lover.isAlive = false;
        // This is handled separately in morning news
      }
    }

    // Reset for next night
    nightKillTarget = null;
    for (final p in players) {
      p.isProtected = false;
    }

    return victimName;
  }

  void startDay() {
    isNight = false;
    dayNumber++;
  }

  void startNight() {
    isNight = true;
    nightKillTarget = null;
    witchHealTarget = null;
    witchPoisonTarget = null;
  }
}
