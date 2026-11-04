import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Abstract service for Admin Authentication
abstract class AdminAuthService {
  Future<bool> isAdmin();
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}

/// Mock implementation for Admin Auth Service
class MockAdminAuthService implements AdminAuthService {
  @override
  Future<bool> isAdmin() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true; // Mock as admin
  }

  @override
  Future<void> signIn(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Mock sign in
  }

  @override
  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 300));
  }
}

/// Provider for Admin Auth Service
final adminAuthServiceProvider = Provider<AdminAuthService>((ref) {
  return MockAdminAuthService();
});
