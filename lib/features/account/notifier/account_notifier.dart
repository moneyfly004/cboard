import 'dart:convert';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/account/data/account_api.dart';
import 'package:hiddify/features/account/notifier/account_subscription_sync.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final accountApiProvider = Provider<AccountApi>((ref) => AccountApi());

final accountNotifierProvider = StateNotifierProvider<AccountNotifier, AccountState>((ref) {
  return AccountNotifier(
    ref.watch(accountApiProvider),
    ref.watch(accountSubscriptionSyncProvider),
    ref.watch(sharedPreferencesProvider).requireValue,
  );
});

class AccountState {
  const AccountState({
    this.token,
    this.refreshToken,
    this.user,
    this.dashboard,
    this.packages = const [],
    this.paymentMethods = const [],
    this.orders = const [],
    this.devices = const [],
    this.deviceTotal = 0,
    this.deviceOnline = 0,
    this.deviceMobile = 0,
    this.deviceDesktop = 0,
    this.loading = false,
    this.syncingSubscription = false,
    this.authExpired = false,
    this.savedEmail,
    this.message,
  });

  final String? token;
  final String? refreshToken;
  final AccountUser? user;
  final AccountDashboard? dashboard;
  final List<AccountPackage> packages;
  final List<PaymentMethod> paymentMethods;
  final List<AccountOrder> orders;
  final List<AccountDevice> devices;
  final int deviceTotal;
  final int deviceOnline;
  final int deviceMobile;
  final int deviceDesktop;
  final bool loading;
  final bool syncingSubscription;
  final bool authExpired;
  final String? savedEmail;
  final String? message;

  bool get isAuthenticated =>
      (token != null && token!.isNotEmpty) || (refreshToken != null && refreshToken!.isNotEmpty);

  bool get hasSavedCredentials => savedEmail != null && savedEmail!.isNotEmpty;

  AccountState copyWith({
    String? token,
    String? refreshToken,
    AccountUser? user,
    AccountDashboard? dashboard,
    List<AccountPackage>? packages,
    List<PaymentMethod>? paymentMethods,
    List<AccountOrder>? orders,
    List<AccountDevice>? devices,
    int? deviceTotal,
    int? deviceOnline,
    int? deviceMobile,
    int? deviceDesktop,
    bool? loading,
    bool? syncingSubscription,
    bool? authExpired,
    String? savedEmail,
    String? message,
    bool clearAuth = false,
    bool clearSavedCredentials = false,
  }) {
    return AccountState(
      token: clearAuth ? null : token ?? this.token,
      refreshToken: clearAuth ? null : refreshToken ?? this.refreshToken,
      user: clearAuth ? null : user ?? this.user,
      dashboard: clearAuth ? null : dashboard ?? this.dashboard,
      packages: packages ?? this.packages,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      orders: clearAuth ? const [] : orders ?? this.orders,
      devices: clearAuth ? const [] : devices ?? this.devices,
      deviceTotal: clearAuth ? 0 : deviceTotal ?? this.deviceTotal,
      deviceOnline: clearAuth ? 0 : deviceOnline ?? this.deviceOnline,
      deviceMobile: clearAuth ? 0 : deviceMobile ?? this.deviceMobile,
      deviceDesktop: clearAuth ? 0 : deviceDesktop ?? this.deviceDesktop,
      loading: loading ?? this.loading,
      syncingSubscription: syncingSubscription ?? this.syncingSubscription,
      authExpired: authExpired ?? (!clearAuth && this.authExpired),
      savedEmail: clearSavedCredentials ? null : savedEmail ?? this.savedEmail,
      message: message,
    );
  }
}

class AccountNotifier extends StateNotifier<AccountState> {
  AccountNotifier(this._api, this._subscriptionSync, this._preferences) : super(const AccountState()) {
    _restore();
  }

  final AccountApi _api;
  final AccountSubscriptionSync _subscriptionSync;
  final SharedPreferences _preferences;
  Future<void>? _accountRefreshOperation;
  Future<String>? _tokenRefreshOperation;

  static const _tokenKey = 'cboard_account_access_token';
  static const _refreshTokenKey = 'cboard_account_refresh_token';
  static const _userKey = 'cboard_account_user';
  static const _emailKey = 'cboard_account_email';
  static const _passwordKey = 'cboard_account_password';

  Future<void> login(String email, String password) async {
    await _run(() async {
      final normalizedEmail = email.trim();
      final response = await _api.login(email: normalizedEmail, password: password);
      state = state.copyWith(
        token: response.accessToken,
        refreshToken: response.refreshToken,
        user: response.user,
        authExpired: false,
        savedEmail: normalizedEmail,
      );
      await _persistAuth(response.accessToken, response.refreshToken, response.user);
      await _persistCredentials(normalizedEmail, password);
      await _refreshAccountData();
    });
  }

  Future<void> register({
    required String username,
    required String email,
    required String password,
    String? verificationCode,
    String? inviteCode,
  }) async {
    await _run(() async {
      final normalizedEmail = email.trim();
      final response = await _api.register(
        username: username.trim(),
        email: normalizedEmail,
        password: password,
        verificationCode: verificationCode?.trim(),
        inviteCode: inviteCode?.trim(),
      );
      state = state.copyWith(
        token: response.accessToken,
        refreshToken: response.refreshToken,
        user: response.user,
        authExpired: false,
        savedEmail: normalizedEmail,
      );
      await _persistAuth(response.accessToken, response.refreshToken, response.user);
      await _persistCredentials(normalizedEmail, password);
      await _refreshAccountData();
    });
  }

  Future<String> sendRegisterCode(String email) {
    return _runWithResult(() => _api.sendRegisterCode(email.trim()));
  }

  Future<String> forgotPassword(String email) {
    return _runWithResult(() => _api.forgotPassword(email.trim()));
  }

  Future<String> resetPassword({required String email, required String verificationCode, required String newPassword}) {
    final normalizedEmail = email.trim();
    return _runWithResult(() async {
      final message = await _api.resetPassword(
        email: normalizedEmail,
        verificationCode: verificationCode.trim(),
        newPassword: newPassword,
      );
      final savedEmail = _preferences.getString(_emailKey);
      if (savedEmail != null && savedEmail.toLowerCase() == normalizedEmail.toLowerCase()) {
        await _persistCredentials(normalizedEmail, newPassword);
      }
      return message;
    });
  }

  Future<void> refresh() async {
    if (!_hasAuthCredentials) {
      final email = _normalizedStoredEmail;
      final password = _preferences.getString(_passwordKey);
      if (email != null && password != null && password.isNotEmpty) {
        await _runAccountRefresh(() => _autoLoginWithStoredCredentials(email, password));
        return;
      }
      await loadPublicData();
      return;
    }
    await _runAccountRefresh(_refreshAccountData);
  }

  Future<void> syncSubscription() async {
    await _runAccountRefresh(() async {
      final dashboard = await _withAuthenticatedToken(_loadDashboardWithSubscriptionFallback);
      state = state.copyWith(user: dashboard.user, dashboard: dashboard, authExpired: false);
      await _persistAuth(state.token, state.refreshToken, dashboard.user);
      await _syncSubscription(dashboard, successMessage: '订阅已同步');
    });
  }

  Future<void> refreshActiveSubscription() async {
    await _runAccountRefresh(() async {
      state = state.copyWith(syncingSubscription: true);
      final dashboard = await _withAuthenticatedToken(_loadDashboardWithSubscriptionFallback);
      state = state.copyWith(user: dashboard.user, dashboard: dashboard, authExpired: false);
      await _persistAuth(state.token, state.refreshToken, dashboard.user);
      await _subscriptionSync.refreshActiveSubscription(dashboard);
      state = state.copyWith(syncingSubscription: false, message: '订阅已更新');
    });
  }

  Future<void> refreshSubscriptionStatusSilently() async {
    if (!_hasAuthCredentials) return;
    await _runAccountRefresh(() async {
      final dashboard = await _withAuthenticatedToken(_loadDashboardWithSubscriptionFallback);
      state = state.copyWith(user: dashboard.user, dashboard: dashboard, authExpired: false);
      await _persistAuth(state.token, state.refreshToken, dashboard.user);
      await _subscriptionSync.refreshActiveSubscription(dashboard);
    });
  }

  Future<void> loadPublicData() async {
    await _run(() async {
      final results = await Future.wait<Object>([_api.getPackages(), _api.getPaymentMethods()]);
      state = state.copyWith(
        packages: results[0] as List<AccountPackage>,
        paymentMethods: results[1] as List<PaymentMethod>,
      );
    });
  }

  Future<void> changePassword({required String oldPassword, required String newPassword}) async {
    final message = await _runWithResult(
      () => _withAuthenticatedToken(
        (token) => _api.changePassword(token: token, oldPassword: oldPassword, newPassword: newPassword),
      ),
    );
    final savedEmail = _preferences.getString(_emailKey) ?? state.user?.email;
    if (savedEmail != null && savedEmail.trim().isNotEmpty) {
      await _persistCredentials(savedEmail.trim(), newPassword);
    }
    state = state.copyWith(message: message);
  }

  Future<OrderResult> buyPackage({required AccountPackage package, PaymentMethod? paymentMethod}) {
    return _runWithResult(() async {
      final order = await _withAuthenticatedToken(
        (token) => _api.createOrder(token: token, packageId: package.id, paymentMethod: paymentMethod?.key),
      );
      OrderResult result = order;
      if ((result.paymentUrl == null || result.paymentUrl!.isEmpty) && paymentMethod != null && order.id > 0) {
        result = await _withAuthenticatedToken(
          (token) => _api.createPayment(token: token, orderId: order.id, paymentMethodId: paymentMethod.id),
        );
      }
      await _refreshAccountData();
      return result;
    });
  }

  Future<OrderResult> createPackageOrder(AccountPackage package) {
    return _runWithResult(
      () => _withAuthenticatedToken((token) => _api.createOrder(token: token, packageId: package.id)),
    );
  }

  Future<OrderResult> createOrderPayment({required int orderId, required PaymentMethod paymentMethod}) {
    return _runWithResult(
      () => _withAuthenticatedToken(
        (token) => _api.createPayment(token: token, orderId: orderId, paymentMethodId: paymentMethod.id),
      ),
    );
  }

  Future<AccountOrderStatus> checkOrderStatus(String orderNo) {
    return _withAuthenticatedToken((token) => _api.getOrderStatus(token: token, orderNo: orderNo));
  }

  Future<void> refreshDevices() async {
    await _runAccountRefresh(_refreshDevicesOnly);
  }

  Future<void> deleteDevice(int id) async {
    final message = await _runWithResult(() async {
      final result = await _withAuthenticatedToken((token) => _api.deleteDevice(token: token, id: id));
      await _refreshAccountSummaryAndDevices();
      return result;
    });
    state = state.copyWith(message: message);
  }

  Future<void> updateDeviceRemark({required int id, required String remark}) async {
    final message = await _runWithResult(() async {
      final result = await _withAuthenticatedToken(
        (token) => _api.updateDeviceRemark(token: token, id: id, remark: remark),
      );
      await _refreshDevicesOnly();
      return result;
    });
    state = state.copyWith(message: message);
  }

  Future<void> refreshAfterPayment() async {
    await refresh();
  }

  Future<void> logout() async {
    state = state.copyWith(loading: true);
    try {
      await _subscriptionSync.clearAccountSubscriptions();
      await _clearStoredAuth(clearCredentials: true);
      state = AccountState(packages: state.packages, paymentMethods: state.paymentMethods, message: '已退出登录');
    } catch (_) {
      state = state.copyWith(loading: false);
      rethrow;
    }
  }

  Future<void> _syncSubscription(AccountDashboard dashboard, {String? successMessage}) async {
    state = state.copyWith(syncingSubscription: true);
    try {
      await _subscriptionSync.sync(dashboard);
      state = state.copyWith(syncingSubscription: false, message: successMessage);
    } catch (_) {
      state = state.copyWith(syncingSubscription: false);
      rethrow;
    }
  }

  Future<void> _refreshAccountData() async {
    final results = await _withAuthenticatedToken(
      (token) => Future.wait<Object>([
        _loadDashboardWithSubscriptionFallback(token),
        _api.getPackages(),
        _api.getPaymentMethods(),
        _api.getOrders(token),
        _api.getDevices(token),
      ]),
    );
    final dashboard = results[0] as AccountDashboard;
    final devices = results[4] as AccountDevicesResult;
    state = state.copyWith(
      user: dashboard.user,
      dashboard: dashboard,
      packages: results[1] as List<AccountPackage>,
      paymentMethods: results[2] as List<PaymentMethod>,
      orders: results[3] as List<AccountOrder>,
      devices: devices.devices,
      deviceTotal: devices.total,
      deviceOnline: devices.online,
      deviceMobile: devices.mobile,
      deviceDesktop: devices.desktop,
      authExpired: false,
    );
    await _persistAuth(state.token, state.refreshToken, dashboard.user);
    await _syncSubscription(dashboard);
  }

  Future<void> _refreshAccountSummaryAndDevices() async {
    final results = await _withAuthenticatedToken(
      (token) => Future.wait<Object>([_loadDashboardWithSubscriptionFallback(token), _api.getDevices(token)]),
    );
    final dashboard = results[0] as AccountDashboard;
    final devices = results[1] as AccountDevicesResult;
    state = state.copyWith(
      user: dashboard.user,
      dashboard: dashboard,
      devices: devices.devices,
      deviceTotal: devices.total,
      deviceOnline: devices.online,
      deviceMobile: devices.mobile,
      deviceDesktop: devices.desktop,
      authExpired: false,
    );
    await _persistAuth(state.token, state.refreshToken, dashboard.user);
  }

  Future<void> _refreshDevicesOnly() async {
    final devices = await _withAuthenticatedToken((token) => _api.getDevices(token));
    state = state.copyWith(
      devices: devices.devices,
      deviceTotal: devices.total,
      deviceOnline: devices.online,
      deviceMobile: devices.mobile,
      deviceDesktop: devices.desktop,
      authExpired: false,
    );
  }

  Future<AccountDashboard> _loadDashboardWithSubscriptionFallback(String token) async {
    final dashboard = await _api.getDashboard(token);
    if (dashboard.subscription?.canImport == true) {
      return dashboard;
    }
    try {
      final subscriptions = await _api.getSubscriptions(token);
      return dashboard.withSubscriptionFallback(subscriptions);
    } catch (_) {
      return dashboard;
    }
  }

  void _restore() {
    final token = _preferences.getString(_tokenKey);
    final refreshToken = _preferences.getString(_refreshTokenKey);
    final userRaw = _preferences.getString(_userKey);
    final email = _normalizedStoredEmail;
    final password = _preferences.getString(_passwordKey);
    AccountUser? user;
    if (userRaw != null && userRaw.isNotEmpty) {
      try {
        final json = jsonDecode(userRaw);
        if (json is Map<String, dynamic>) {
          user = AccountUser.fromJson(json);
        }
      } catch (_) {
        _preferences.remove(_userKey);
      }
    }
    if ((token != null && token.isNotEmpty) || (refreshToken != null && refreshToken.isNotEmpty)) {
      state = state.copyWith(
        token: token,
        refreshToken: refreshToken,
        user: user,
        authExpired: false,
        savedEmail: email,
      );
    } else if (email != null) {
      state = state.copyWith(savedEmail: email);
    }
    if (email != null && password != null && password.isNotEmpty) {
      final storedEmail = email;
      final storedPassword = password;
      Future.microtask(() async {
        try {
          await _runAccountRefresh(() => _autoLoginWithStoredCredentials(storedEmail, storedPassword));
        } catch (_) {
          // Keep saved credentials so the next launch can retry unless the user logs out.
        }
      });
    } else if (_hasAuthCredentials) {
      Future.microtask(() async {
        try {
          await refresh();
        } catch (_) {
          // Keep the cached login/profile visible; callers can retry or log out explicitly.
        }
      });
    } else {
      Future.microtask(() async {
        await _subscriptionSync.clearAccountSubscriptions();
        await loadPublicData();
      });
    }
  }

  bool get _hasAuthCredentials {
    return (state.token != null && state.token!.isNotEmpty) ||
        (state.refreshToken != null && state.refreshToken!.isNotEmpty);
  }

  Future<T> _withAuthenticatedToken<T>(Future<T> Function(String token) action) async {
    final token = await _availableToken();
    try {
      return await action(token);
    } on AccountApiException catch (error) {
      if (!_canRefreshAfter(error)) {
        rethrow;
      }
      final refreshToken = state.refreshToken;
      if (refreshToken == null || refreshToken.isEmpty) {
        await _markAuthExpired();
        rethrow;
      }
      final refreshedToken = await _refreshAccessToken(refreshToken);
      try {
        return await action(refreshedToken);
      } on AccountApiException catch (refreshedError) {
        if (_canRefreshAfter(refreshedError)) {
          await _markAuthExpired();
        }
        rethrow;
      }
    }
  }

  Future<String> _availableToken() async {
    final token = state.token;
    if (token != null && token.isNotEmpty) {
      return token;
    }
    final refreshToken = state.refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      return _refreshAccessToken(refreshToken);
    }
    throw AccountApiException('请先登录');
  }

  Future<String> _refreshAccessToken(String refreshToken) {
    final existingOperation = _tokenRefreshOperation;
    if (existingOperation != null) {
      return existingOperation;
    }
    final operation = _refreshAccessTokenOnce(refreshToken);
    _tokenRefreshOperation = operation;
    return operation.whenComplete(() {
      if (identical(_tokenRefreshOperation, operation)) {
        _tokenRefreshOperation = null;
      }
    });
  }

  Future<String> _refreshAccessTokenOnce(String refreshToken) async {
    final AccountAuthResponse response;
    try {
      response = await _api.refreshToken(refreshToken);
    } on AccountApiException catch (error) {
      if (_isExpiredAuthError(error)) {
        await _markAuthExpired();
      }
      rethrow;
    }
    if (response.accessToken.isEmpty) {
      await _markAuthExpired();
      throw AccountApiException('登录状态已过期，请重新登录', statusCode: 401);
    }
    final nextRefreshToken = (response.refreshToken != null && response.refreshToken!.isNotEmpty)
        ? response.refreshToken
        : refreshToken;
    final nextUser = response.user.id == 0 ? state.user : response.user;
    state = state.copyWith(
      token: response.accessToken,
      refreshToken: nextRefreshToken,
      user: nextUser,
      authExpired: false,
      savedEmail: _normalizedStoredEmail,
    );
    await _persistAuth(response.accessToken, nextRefreshToken, nextUser);
    return response.accessToken;
  }

  bool _canRefreshAfter(AccountApiException error) {
    return error.statusCode == 401 || error.statusCode == 403;
  }

  bool _isExpiredAuthError(AccountApiException error) {
    return error.statusCode == 400 || error.statusCode == 401 || error.statusCode == 403;
  }

  Future<void> _autoLoginWithStoredCredentials(String email, String password) async {
    try {
      final response = await _api.login(email: email, password: password);
      state = state.copyWith(
        token: response.accessToken,
        refreshToken: response.refreshToken,
        user: response.user,
        authExpired: false,
        savedEmail: email,
      );
      await _persistAuth(response.accessToken, response.refreshToken, response.user);
      await _persistCredentials(email, password);
      await _refreshAccountData();
    } on AccountApiException catch (error) {
      if (_isExpiredAuthError(error) && !state.authExpired) {
        await _markAuthExpired(message: '自动登录失败，请重新登录');
      }
      rethrow;
    }
  }

  Future<void> _markAuthExpired({String message = '登录授权已失效，请重新登录'}) async {
    try {
      await _subscriptionSync.clearAccountSubscriptions();
    } catch (_) {
      // Authentication state should still be updated even if local cleanup fails.
    }
    await _clearStoredAuth(clearCredentials: false);
    state = state.copyWith(clearAuth: true, authExpired: true, savedEmail: _normalizedStoredEmail, message: message);
  }

  Future<void> _persistAuth(String? token, String? refreshToken, AccountUser? user) async {
    if (token != null && token.isNotEmpty) {
      await _preferences.setString(_tokenKey, token);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _preferences.setString(_refreshTokenKey, refreshToken);
    }
    if (user != null) {
      await _preferences.setString(_userKey, jsonEncode(user.toJson()));
    }
  }

  Future<void> _persistCredentials(String email, String password) async {
    if (email.isNotEmpty) {
      await _preferences.setString(_emailKey, email);
    }
    if (password.isNotEmpty) {
      await _preferences.setString(_passwordKey, password);
    }
  }

  Future<void> _clearStoredAuth({required bool clearCredentials}) async {
    await _preferences.remove(_tokenKey);
    await _preferences.remove(_refreshTokenKey);
    await _preferences.remove(_userKey);
    if (clearCredentials) {
      await _preferences.remove(_emailKey);
      await _preferences.remove(_passwordKey);
    }
  }

  String? get _normalizedStoredEmail {
    final email = _preferences.getString(_emailKey)?.trim();
    if (email == null || email.isEmpty) {
      return null;
    }
    return email;
  }

  Future<void> _run(Future<void> Function() action) async {
    state = state.copyWith(loading: true);
    try {
      await action();
      state = state.copyWith(loading: false, syncingSubscription: false);
    } catch (error) {
      state = state.copyWith(loading: false, syncingSubscription: false);
      rethrow;
    }
  }

  Future<void> _runAccountRefresh(Future<void> Function() action) {
    final existingOperation = _accountRefreshOperation;
    if (existingOperation != null) {
      return existingOperation;
    }
    final operation = _run(action);
    _accountRefreshOperation = operation;
    return operation.whenComplete(() {
      if (identical(_accountRefreshOperation, operation)) {
        _accountRefreshOperation = null;
      }
    });
  }

  Future<T> _runWithResult<T>(Future<T> Function() action) async {
    state = state.copyWith(loading: true);
    try {
      final result = await action();
      state = state.copyWith(loading: false, syncingSubscription: false);
      return result;
    } catch (error) {
      state = state.copyWith(loading: false, syncingSubscription: false);
      rethrow;
    }
  }
}
