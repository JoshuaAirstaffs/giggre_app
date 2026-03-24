import 'package:flutter/material.dart';

class CurrentUserProvider extends ChangeNotifier {
  String? _currentEmail;
  String? _currentName;
  String? _uid;

  String? get currentEmail => _currentEmail;
  String? get currentName => _currentName;
  String? get uid => _uid;
  bool get isLoggedIn => _uid != null; 

  void setCurrentUserInfo(String? email, String? name, String? uid) {

    debugPrint(' setCurrentUserInfo: $email, $name, $uid');
    _currentEmail = email;
    _currentName = name;
    _uid = uid;
    notifyListeners();
  }

  void clearUser() { //for logout
    _currentEmail = null;
    _currentName = null;
    _uid = null;
    notifyListeners();
  }
}