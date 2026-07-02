import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/account/data/account_api.dart';

void main() {
  test('AccountDevicesResult parses subscription device list response', () {
    final result = AccountDevicesResult.fromJson({
      'data': {
        'devices': [
          {
            'id': 12,
            'subscription_id': 7,
            'device_name': 'MacBook Pro',
            'device_type': 'desktop',
            'software_name': 'Hiddify',
            'software_version': '3.0.0',
            'os_name': 'macOS',
            'os_version': '15.0',
            'device_model': 'MacBookPro18,3',
            'device_brand': 'Apple',
            'ip_address': '203.0.113.10',
            'last_access': '2026-06-18 12:00:00',
            'is_active': true,
            'is_allowed': true,
            'access_count': 3,
            'remark': 'work laptop',
          },
          {'id': 13, 'device_name': 'Pixel', 'device_type': 'mobile', 'is_active': 1, 'is_allowed': 'true'},
        ],
        'total': 8,
        'total_online': 2,
        'total_mobile': 5,
        'total_desktop': 3,
      },
    });

    expect(result.total, 8);
    expect(result.online, 2);
    expect(result.mobile, 5);
    expect(result.desktop, 3);
    expect(result.devices, hasLength(2));
    expect(result.devices.first.id, 12);
    expect(result.devices.first.displayName, 'MacBook Pro');
    expect(result.devices.first.softwareLabel, 'Hiddify 3.0.0');
    expect(result.devices.first.osLabel, 'macOS 15.0');
    expect(result.devices.first.modelLabel, 'MacBookPro18,3');
    expect(result.devices.last.isMobile, isTrue);
  });

  test('AccountDevicesResult accepts legacy raw list response', () {
    final result = AccountDevicesResult.fromJson({
      'data': [
        {'id': 1, 'device_type': 'desktop'},
        {'id': 2, 'device_type': 'tablet'},
      ],
    });

    expect(result.total, 2);
    expect(result.mobile, 1);
    expect(result.desktop, 1);
  });

  test('AccountDashboard uses first importable subscription as fallback', () {
    const fallbackUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=active-token';
    final dashboard =
        const AccountDashboard(
          subscription: AccountSubscription(
            universalUrl: 'https://dy.moneyfly.top/api/v1/client/subscribe?token=disabled-token',
            status: 'disabled',
            remainingDays: 30,
          ),
        ).withSubscriptionFallback(const [
          AccountSubscription(
            universalUrl: 'https://dy.moneyfly.top/api/v1/client/subscribe?token=expired-token',
            status: 'active',
            isActive: true,
            isExpired: true,
          ),
          AccountSubscription(universalUrl: fallbackUrl, status: 'active', remainingDays: 30, isActive: true),
        ]);

    expect(dashboard.subscription?.importUrl, '$fallbackUrl&type=singbox');
    expect(dashboard.subscription?.canImport, isTrue);
  });

  test('AccountDashboard parses backend user_info and subscriptions list', () {
    const subscriptionUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=dashboard-token';
    final dashboard = AccountDashboard.fromJson({
      'user_info': {'id': 9, 'username': 'alice', 'email': 'alice@example.com'},
      'subscriptions': [
        {
          'subscription_url': 'https://dy.moneyfly.top/api/v1/client/subscribe?token=expired-token',
          'status': 'active',
          'is_active': true,
          'is_expired': true,
        },
        {'subscription_url': subscriptionUrl, 'status': 'active', 'is_active': true, 'days_until_expire': 30},
      ],
      'orders': [
        {'id': 1, 'order_no': 'ORD001'},
      ],
      'statistics': {'total_spent': 12.5},
    });

    expect(dashboard.user.id, 9);
    expect(dashboard.user.email, 'alice@example.com');
    expect(dashboard.subscription?.importUrl, '$subscriptionUrl&type=singbox');
    expect(dashboard.subscription?.canImport, isTrue);
    expect(dashboard.recentOrders, hasLength(1));
    expect(dashboard.totalSpent, 12.5);
  });

  test('AccountDashboard expands raw subscription list token for import', () {
    final dashboard = AccountDashboard.fromJson({
      'user_info': {'id': 9, 'username': 'alice'},
      'subscriptions': [
        {'subscription_url': 'raw-dashboard-token', 'status': 'active', 'is_active': true, 'days_until_expire': 30},
      ],
    });

    expect(
      dashboard.subscription?.importUrl,
      'https://dy.moneyfly.top/api/v1/client/subscribe?token=raw-dashboard-token&type=singbox',
    );
    expect(dashboard.subscription?.canImport, isTrue);
  });

  test('AccountDashboard imports root-level subscription fields', () {
    final dashboard = AccountDashboard.fromJson({
      'username': 'alice',
      'email': 'alice@example.com',
      'subscription_url': 'root-dashboard-token',
      'subscription_status': 'active',
      'is_active': true,
      'remaining_days': 30,
    });

    expect(dashboard.user.username, 'alice');
    expect(
      dashboard.subscription?.importUrl,
      'https://dy.moneyfly.top/api/v1/client/subscribe?token=root-dashboard-token&type=singbox',
    );
    expect(dashboard.subscription?.canImport, isTrue);
  });

  test('AccountDashboard keeps recent orders from generic map entries', () {
    final dashboard = AccountDashboard.fromJson({
      'user_info': {'id': 9, 'username': 'alice'},
      'orders': <dynamic>[
        <dynamic, dynamic>{'id': 7, 'order_no': 'ORD007', 'final_amount': '6.5', 'status': 'paid'},
      ],
    });

    expect(dashboard.recentOrders, hasLength(1));
    expect(dashboard.recentOrders.single.id, 7);
    expect(dashboard.recentOrders.single.orderNo, 'ORD007');
    expect(dashboard.recentOrders.single.amount, 6.5);
  });

  test('AccountSubscription parses backend expired flag', () {
    final subscription = AccountSubscription.fromJson({
      'universal_url': 'https://dy.moneyfly.top/api/v1/client/subscribe?token=expired-token',
      'status': 'active',
      'is_active': true,
      'is_expired': true,
      'days_until_expire': 0,
    });

    expect(subscription.isExpired, isTrue);
    expect(subscription.canImport, isFalse);
  });

  test('AccountSubscription expands raw backend subscription token', () {
    final subscription = AccountSubscription.fromJson({
      'subscription_url': 'raw-model-token',
      'status': 'active',
      'is_active': true,
      'days_until_expire': 30,
    });

    expect(
      subscription.importUrl,
      'https://dy.moneyfly.top/api/v1/client/subscribe?token=raw-model-token&type=singbox',
    );
    expect(subscription.canImport, isTrue);
  });

  test('AccountSubscription accepts backend subscribe url alias', () {
    final subscription = AccountSubscription.fromJson({
      'subscribe_url': 'https://dy.moneyfly.top/api/v1/client/subscribe?token=alias-token&type=clash',
      'status': 'active',
      'is_active': true,
      'remaining_days': 30,
    });

    expect(subscription.importUrl, 'https://dy.moneyfly.top/api/v1/client/subscribe?token=alias-token&type=clash');
    expect(subscription.canImport, isTrue);
  });

  test('AccountUser accepts numeric and string boolean flags', () {
    final activeUser = AccountUser.fromJson({
      'id': '21',
      'username': 'active',
      'is_admin': '1',
      'is_verified': ' true ',
      'is_active': 1,
    });
    final disabledUser = AccountUser.fromJson({'username': 'disabled', 'is_active': '0'});

    expect(activeUser.id, 21);
    expect(activeUser.isAdmin, isTrue);
    expect(activeUser.isVerified, isTrue);
    expect(activeUser.isActive, isTrue);
    expect(disabledUser.isActive, isFalse);
  });

  test('AccountSubscription prefers backend sing-box subscribe url for import', () {
    final subscription = AccountSubscription.fromJson({
      'subscription_url': 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash',
      'universal_url': 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token',
      'singbox_url': 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox',
      'status': 'active',
      'is_active': true,
      'days_until_expire': 30,
    });

    expect(subscription.importUrl, 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox');
    expect(subscription.importUrls, [
      'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox',
      'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token',
      'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash',
    ]);
    expect(subscription.canImport, isTrue);
  });

  test('AccountSubscription derives sing-box subscribe url from universal client subscribe url', () {
    final subscription = AccountSubscription.fromJson({
      'universal_url': 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token',
      'status': 'active',
      'is_active': true,
      'days_until_expire': 30,
    });

    expect(subscription.importUrl, 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox');
    expect(subscription.importUrls, [
      'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox',
      'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token',
    ]);
    expect(subscription.canImport, isTrue);
  });

  test('AccountSubscription accepts non-boolean active flags and normalizes status', () {
    final subscription = AccountSubscription.fromJson({
      'universal_url': 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token',
      'status': ' Active ',
      'is_active': '1',
      'is_expired': 'false',
      'days_until_expire': '30',
    });

    expect(subscription.status, 'active');
    expect(subscription.canImport, isTrue);
  });

  test('AccountPackage accepts numeric and string recommended flags', () {
    expect(AccountPackage.fromJson({'id': 1, 'name': 'Pro', 'is_recommended': ' true '}).isRecommended, isTrue);
    expect(AccountPackage.fromJson({'id': 2, 'name': 'Basic', 'is_recommended': 1}).isRecommended, isTrue);
    expect(AccountPackage.fromJson({'id': 3, 'name': 'Lite', 'is_recommended': '0'}).isRecommended, isFalse);
  });

  test('AccountOrderStatus normalizes backend status before comparisons', () {
    final status = AccountOrderStatus.fromJson({'order_no': 'ORD001', 'status': ' Paid ', 'amount': '9.9'});

    expect(status.status, 'paid');
    expect(status.isPaid, isTrue);
    expect(status.isFinished, isTrue);
  });

  test('AccountOrderStatus treats backend canceled spelling as finished', () {
    final status = AccountOrderStatus.fromJson({'order_no': 'ORD002', 'status': 'canceled'});

    expect(status.status, 'canceled');
    expect(status.isPaid, isFalse);
    expect(status.isFinished, isTrue);
  });

  test('AccountApi parses nested subscriptions list response', () async {
    const subscriptionUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=active-token';
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = _JsonAdapter({
        'data': {
          'subscriptions': [
            {'subscription_url': subscriptionUrl, 'status': 'active', 'is_active': true, 'days_until_expire': 30},
          ],
          'total': 1,
        },
      });
    final api = AccountApi(dio: dio);

    final subscriptions = await api.getSubscriptions('access-token');

    expect(subscriptions, hasLength(1));
    expect(subscriptions.single.importUrl, '$subscriptionUrl&type=singbox');
    expect(subscriptions.single.canImport, isTrue);
  });

  test('AccountApi expands raw backend subscription token into client subscribe URL', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://dy.moneyfly.top/api/v1'))
      ..httpClientAdapter = _JsonAdapter({
        'data': [
          {
            'subscription_url': 'raw-subscription-token',
            'status': 'active',
            'is_active': true,
            'days_until_expire': 30,
          },
        ],
      });
    final api = AccountApi(dio: dio);

    final subscriptions = await api.getSubscriptions('access-token');

    expect(subscriptions, hasLength(1));
    expect(
      subscriptions.single.importUrl,
      'https://dy.moneyfly.top/api/v1/client/subscribe?token=raw-subscription-token&type=singbox',
    );
    expect(subscriptions.single.canImport, isTrue);
  });

  test('AccountApi expands raw dashboard token with configured API base URL', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://client.example.com/api/v1'))
      ..httpClientAdapter = _JsonAdapter({
        'data': {
          'user_info': {'id': 9, 'username': 'alice'},
          'subscription': {
            'subscription_url': 'dashboard-token',
            'status': 'active',
            'is_active': true,
            'days_until_expire': 30,
          },
        },
      });
    final api = AccountApi(dio: dio);

    final dashboard = await api.getDashboard('access-token');

    expect(
      dashboard.subscription?.importUrl,
      'https://client.example.com/api/v1/client/subscribe?token=dashboard-token&type=singbox',
    );
    expect(dashboard.subscription?.canImport, isTrue);
  });

  test('AccountApi expands raw subscription model token with configured API base URL', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://client.example.com/api/v1'))
      ..httpClientAdapter = _JsonAdapter({
        'data': [
          {'subscription_url': 'model-token', 'status': 'active', 'is_active': true, 'days_until_expire': 30},
        ],
      });
    final api = AccountApi(dio: dio);

    final subscriptions = await api.getSubscriptions('access-token');

    expect(
      subscriptions.single.importUrl,
      'https://client.example.com/api/v1/client/subscribe?token=model-token&type=singbox',
    );
    expect(subscriptions.single.canImport, isTrue);
  });

  test('AccountApi parses backend paginated orders response', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = _JsonAdapter({
        'data': {
          'orders': [
            {'id': 15, 'order_no': 'ORD015', 'package_name': 'Pro', 'final_amount': '19.9', 'status': 'paid'},
          ],
          'total': 1,
          'page': 1,
          'size': 20,
          'pages': 1,
        },
      });
    final api = AccountApi(dio: dio);

    final orders = await api.getOrders('access-token');

    expect(orders, hasLength(1));
    expect(orders.single.orderNo, 'ORD015');
    expect(orders.single.packageName, 'Pro');
    expect(orders.single.amount, 19.9);
  });

  test('AccountApi pays order with selected payment method key', () async {
    final adapter = _JsonAdapter({
      'data': {
        'transaction_id': 9,
        'order_no': 'ORD009',
        'payment_url': 'https://pay.example/qr',
        'payment_qr_code': 'https://pay.example/qr',
        'payment_method': 'yipay_wxpay',
      },
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))..httpClientAdapter = adapter;
    final api = AccountApi(dio: dio);

    final payment = await api.payOrder(
      token: 'access-token',
      orderNo: 'ORD009',
      paymentMethodId: 3,
      paymentMethod: 'yipay_wxpay',
    );

    expect(adapter.requestPaths, ['/orders/ORD009/pay']);
    expect(adapter.requestBodies.single, {'payment_method_id': 3, 'payment_method': 'yipay_wxpay'});
    expect(payment.id, 9);
    expect(payment.orderNo, 'ORD009');
    expect(payment.paymentUrl, 'https://pay.example/qr');
  });
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);

  final Map<String, dynamic> body;
  final List<String> requestPaths = [];
  final List<Object?> requestBodies = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestPaths.add(options.path);
    final requestBytes = requestStream == null ? <int>[] : await requestStream.expand((chunk) => chunk).toList();
    requestBodies.add(requestBytes.isEmpty ? null : jsonDecode(utf8.decode(requestBytes)));
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
