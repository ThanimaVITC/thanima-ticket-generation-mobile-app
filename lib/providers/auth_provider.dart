import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;

  Future<void> checkAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      final user = await _apiService.getMe();
      _user = user;
    } catch (e) {
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.login(email, password);
      // The updated API returns the token in the body
      if (response.containsKey('token')) {
        await _apiService.setToken(response['token']);
      }
      
      _user = User.fromJson(response['user']);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> logout() async {
    await _apiService.removeToken();
    _user = null;
    notifyListeners();
  }
}
