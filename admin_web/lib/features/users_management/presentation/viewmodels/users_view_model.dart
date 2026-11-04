import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/users_management/domain/models/app_user.dart';
import 'package:srs_review_ai_admin_web/features/users_management/data/repositories/users_repository.dart';

/// State cho Users
class UsersState {
  const UsersState({
    this.users = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
  });

  final List<AppUser> users;
  final bool isLoading;
  final String? error;
  final String searchQuery;

  UsersState copyWith({
    List<AppUser>? users,
    bool? isLoading,
    String? error,
    String? searchQuery,
  }) {
    return UsersState(
      users: users ?? this.users,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  List<AppUser> get filteredUsers {
    if (searchQuery.isEmpty) {
      return users;
    }
    return users
        .where((user) =>
            user.displayName.toLowerCase().contains(searchQuery.toLowerCase()) ||
            user.email.toLowerCase().contains(searchQuery.toLowerCase()) ||
            user.uid.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();
  }
}

/// ViewModel cho Users Tab — lắng nghe Firestore stream từ repository.
class UsersViewModel extends Notifier<UsersState> {
  StreamSubscription<List<AppUser>>? _subscription;

  @override
  UsersState build() {
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    _listen();
    return const UsersState(isLoading: true);
  }

  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription = ref.read(usersRepositoryProvider).watchUsers().listen(
      (users) {
        state = state.copyWith(users: users, isLoading: false, error: null);
      },
      onError: (Object error) {
        debugPrint('Error loading users: $error');
        state = state.copyWith(isLoading: false, error: error.toString());
      },
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    _listen();
  }
}

/// Provider cho Users ViewModel
final usersViewModelProvider =
    NotifierProvider<UsersViewModel, UsersState>(
  UsersViewModel.new,
);
