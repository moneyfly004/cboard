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

    expect(dashboard.subscription?.importUrl, fallbackUrl);
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
    expect(dashboard.subscription?.importUrl, subscriptionUrl);
    expect(dashboard.subscription?.canImport, isTrue);
    expect(dashboard.recentOrders, hasLength(1));
    expect(dashboard.totalSpent, 12.5);
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
    expect(subscriptions.single.importUrl, subscriptionUrl);
    expect(subscriptions.single.canImport, isTrue);
  });
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);

  final Map<String, dynamic> body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
