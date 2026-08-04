import 'package:shared_preferences/shared_preferences.dart';

class TutorialService {
  String _key(String flowId) => 'tutorial.$flowId.completed';

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
}
