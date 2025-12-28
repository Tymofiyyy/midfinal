// lib/providers/auth_provider.dart - ЧИСТИЙ З NULL SAFETY
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';

class AuthProvider with ChangeNotifier {
  late final GoogleSignIn _googleSignIn;
  final ApiService _apiService = ApiService();

  User? _user;
  String? _token;
  bool _isLoading = true;

  User? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null && _token != null;

  AuthProvider() {
    // Конфігурація Google Sign In
    _googleSignIn = GoogleSignIn(
      clientId: AppConfig.googleClientId,
      scopes: [
        'email',
        'profile',
        'openid',
      ],
    );

    // Встановлюємо callback для автоматичного оновлення токена
    _apiService.setTokenRefreshCallback(() async {
      debugPrint('🔄 Auth: Token refresh requested by ApiService');
      if (_token != null) {
        try {
          final userData = await _apiService.getCurrentUser(_token!);
          if (userData != null) {
            _user = User.fromJson(userData);
            notifyListeners();
            return _token;
          }
        } catch (e) {
          debugPrint('❌ Auth: Token refresh failed: $e');
        }
      }
      return null;
    });

    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('authToken');

      if (_token != null) {
        // ВАЖЛИВО: Встановлюємо токен в ApiService ОДРАЗУ
        _apiService.setToken(_token);
        debugPrint('✅ Auth: Token restored and set in ApiService');

        // Для тестового входу
        if (_token == 'test-token-12345') {
          _user = User(
            id: '1',
            email: 'test@solar.com',
            name: 'Test User',
            picture: null,
          );
        } else {
          final userData = await _apiService.getCurrentUser(_token!);
          if (userData != null) {
            _user = User.fromJson(userData);
          } else {
            debugPrint('❌ Auth: Failed to get user data, clearing token');
            await logout();
            return;
          }
        }
      } else {
        debugPrint('⚠️ Auth: No saved token found');
      }
    } catch (e) {
      debugPrint('❌ Auth: Error checking auth status: $e');
      await logout();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Тестовий вхід для розробки
  Future<bool> testLogin() async {
    try {
      // Використовуємо API для створення/отримання тестового користувача
      final response = await _apiService.testLogin();

      _token = response['token'];
      _user = User.fromJson(response['user']);

      // ВАЖЛИВО: Встановлюємо токен в ApiService
      _apiService.setToken(_token);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('authToken', _token!);

      debugPrint('✅ Auth: Test login successful');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Auth: Error in test login: $e');
      return false;
    }
  }

  Future<bool> signInWithGoogle() async {
    try {
      // Спочатку вийдемо з попереднього акаунту
      await _googleSignIn.signOut();

      // Для веб платформи використовуємо інший підхід
      GoogleSignInAccount? googleUser;

      if (kIsWeb) {
        // Спробуємо silent sign in спочатку
        googleUser = await _googleSignIn.signInSilently();
        if (googleUser == null) {
          // Якщо не вдалося, використовуємо звичайний sign in
          googleUser = await _googleSignIn.signIn();
        }
      } else {
        // Для мобільних платформ
        googleUser = await _googleSignIn.signIn();
      }

      if (googleUser == null) {
        debugPrint('Google Sign In cancelled by user');
        return false;
      }

      debugPrint('Google user: ${googleUser.email}');
      debugPrint('Google user ID: ${googleUser.id}');
      debugPrint('Google user name: ${googleUser.displayName}');

      final GoogleSignInAuthentication googleAuth;

      try {
        googleAuth = await googleUser.authentication;
      } catch (e) {
        debugPrint('Error getting authentication: $e');
        return false;
      }

      // Для веб платформи idToken може бути null
      String? idToken = googleAuth.idToken;
      String? accessToken = googleAuth.accessToken;

      debugPrint('ID Token: ${idToken != null ? "received" : "null"}');
      debugPrint('Access Token: ${accessToken != null ? "received" : "null"}');

      // Якщо немає idToken, використовуємо інформацію з googleUser
      if (idToken == null && kIsWeb) {
        // Для веб можемо використати access token або створити тимчасовий користувач
        _token = 'web-temp-token-${googleUser.id}';
        _user = User(
          id: googleUser.id,
          email: googleUser.email,
          name: googleUser.displayName ?? 'User',
          picture: googleUser.photoUrl,
        );

        // ВАЖЛИВО: Встановлюємо токен в ApiService
        _apiService.setToken(_token);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('authToken', _token!);

        debugPrint('✅ Auth: Web temp token login successful');
        notifyListeners();
        return true;
      }

      if (idToken == null) {
        debugPrint('No ID token received');
        return false;
      }

      debugPrint('Got ID token, sending to backend...');

      final response = await _apiService.authenticateWithGoogle(idToken);

      _token = response['token'];
      _user = User.fromJson(response['user']);

      // ВАЖЛИВО: Встановлюємо токен в ApiService
      _apiService.setToken(_token);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('authToken', _token!);

      debugPrint('✅ Auth: Google login successful');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Auth: Error signing in with Google: $e');
      debugPrint('Error details: ${e.toString()}');

      // Якщо помилка пов'язана з People API, все одно спробуємо
      if (e.toString().contains('People API')) {
        debugPrint('People API error - trying alternative approach');
        // Можна спробувати альтернативний підхід
      }

      return false;
    }
  }

  Future<void> logout() async {
    debugPrint('🚪 Auth: Logging out...');

    await _googleSignIn.signOut();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');

    _user = null;
    _token = null;

    // ВАЖЛИВО: Очищуємо токен з ApiService
    _apiService.setToken(null);

    debugPrint('✅ Auth: Logged out successfully');
    notifyListeners();
  }

  // Метод для оновлення токена (якщо потрібно)
  Future<void> refreshToken() async {
    if (_token == null) return;

    try {
      // Перевіряємо чи токен ще дійсний
      final userData = await _apiService.getCurrentUser(_token!);
      if (userData != null) {
        _user = User.fromJson(userData);
        debugPrint('✅ Auth: Token refreshed successfully');
        notifyListeners();
      } else {
        debugPrint('❌ Auth: Token refresh failed - no user data');
        await logout();
      }
    } catch (e) {
      debugPrint('❌ Auth: Token refresh failed: $e');
      await logout();
    }
  }

  // Геттер для ApiService (якщо потрібен в інших частинах програми)
  ApiService get apiService => _apiService;
}
