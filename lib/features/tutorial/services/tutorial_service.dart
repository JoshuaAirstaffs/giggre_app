import 'package:shared_preferences/shared_preferences.dart';

class TutorialService {
  String _key(String flowId) => 'tutorial.$flowId.completed';
  String _devKey(String flowId) => 'tutorial.$flowId.devEnabled';

  Future<bool> hasCompleted(String flowId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(flowId)) ?? false;
  }

  Future<void> markCompleted(String flowId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(flowId), true);
  }

  Future<void> reset(String flowId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(flowId));
  }

  // Per-flow switch for TutorialFlow.devOnly flows — off by default, only
  // reachable via the hidden Developer Mode entry point.
  Future<bool> isDevEnabled(String flowId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_devKey(flowId)) ?? false;
  }

  Future<void> setDevEnabled(String flowId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_devKey(flowId), enabled);
  }
}
