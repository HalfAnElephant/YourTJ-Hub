// PushController 单元测试（原生推送通道门控 + 设备注册生命周期）。
//
// 全部走 @visibleForTesting 注入点，宿主测试环境无 Firebase 原生层；
// 仓库默认构建（无 dart-define Firebase 配置）= unsupported，验证
// 「未配置 = 通道关闭、零报错」语义。
library;

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:forum_app/src/providers.dart';
import 'package:forum_app/src/push/push_service.dart';

class _MemoryTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

/// 记录型 PushRepository：不发起真实网络请求。
class _RecordingPushRepository extends PushRepository {
  _RecordingPushRepository() : super(_newClient());

  static GfApiClient _newClient() => GfApiClient(
    dio: Dio(BaseOptions(baseUrl: 'http://test')),
    tokenStorage: _MemoryTokenStorage(),
  );

  final List<String> registered = <String>[];
  final List<String> unregistered = <String>[];
  PushConfigPayload configResponse = const PushConfigPayload(configured: false);
  bool failConfig = false;

  @override
  Future<PushConfigPayload> config() async {
    if (failConfig) throw Exception('network down');
    return configResponse;
  }

  @override
  Future<bool> registerDevice({
    required String platform,
    required String token,
  }) async {
    registered.add('$platform:$token');
    return true;
  }

  @override
  Future<bool> unregisterDevice({required String token}) async {
    unregistered.add(token);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryTokenStorage storage;
  late _RecordingPushRepository repo;

  PushConfigPayload serverEnabledConfig() => PushConfigPayload(
    configured: false,
    native: NativePushConfig(apnsEnabled: true, fcmEnabled: false),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = _MemoryTokenStorage();
    repo = _RecordingPushRepository();
    PushController.configuredOverride = null;
    PushController.initOverride = null;
    PushController.tokenProviderOverride = null;
    PushController.permissionOverride = null;
  });

  tearDown(() {
    PushController.configuredOverride = null;
    PushController.initOverride = null;
    PushController.tokenProviderOverride = null;
    PushController.permissionOverride = null;
  });

  ProviderContainer makeContainer() {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        pushRepositoryProvider.overrideWithValue(repo),
        tokenStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    // Riverpod Notifier 惰性构建：急切触发一次 read 让 build()（及其
    // restore 微任务链）在 settle() 排空前启动。
    container.read(pushControllerProvider);
    return container;
  }

  /// 排空 restore 的异步链（全部即时 fake，两轮事件队列足够）。
  Future<void> settle() async {
    await pumpEventQueue();
    await pumpEventQueue();
  }

  /// 注入「已配置构建 + 可用原生层」的完整测试环境。
  void configureEnabledBuild() {
    PushController.configuredOverride = true;
    PushController.initOverride = () async {};
    PushController.permissionOverride = () async => true;
    PushController.tokenProviderOverride = () => 'tok-1';
  }

  test('默认构建（无 dart-define Firebase 配置）= unsupported 通道关闭', () async {
    final ProviderContainer container = makeContainer();
    expect(container.read(pushControllerProvider), PushChannelStatus.unknown);
    await settle();
    expect(
      container.read(pushControllerProvider),
      PushChannelStatus.unsupported,
    );
  });

  test('unsupported 构建 enable() 为 no-op 且不注册设备', () async {
    final ProviderContainer container = makeContainer();
    await settle();
    await container.read(pushControllerProvider.notifier).enable();
    await settle();
    expect(
      container.read(pushControllerProvider),
      PushChannelStatus.unsupported,
    );
    expect(repo.registered, isEmpty);
  });

  test('已配置构建 + 无会话令牌 → serverDisabled（匿名不触发 401 拆链）', () async {
    PushController.configuredOverride = true;
    final ProviderContainer container = makeContainer();
    await settle();
    expect(
      container.read(pushControllerProvider),
      PushChannelStatus.serverDisabled,
    );
    expect(repo.failConfig, isFalse); // 未发起 config 查询（会话门控先拦截）
  });

  test('服务端 native 双通道关闭 → serverDisabled', () async {
    PushController.configuredOverride = true;
    storage.write('tok');
    final ProviderContainer container = makeContainer();
    await settle();
    expect(
      container.read(pushControllerProvider),
      PushChannelStatus.serverDisabled,
    );
  });

  test('服务端不可达（config 抛错）→ serverDisabled 零报错', () async {
    PushController.configuredOverride = true;
    storage.write('tok');
    repo.failConfig = true;
    final ProviderContainer container = makeContainer();
    await settle();
    expect(
      container.read(pushControllerProvider),
      PushChannelStatus.serverDisabled,
    );
  });

  test('服务端启用 + 用户未开启 → disabled；enable() 注册设备并落 enabled', () async {
    configureEnabledBuild();
    storage.write('tok');
    repo.configResponse = serverEnabledConfig();
    final ProviderContainer container = makeContainer();
    await settle();
    expect(container.read(pushControllerProvider), PushChannelStatus.disabled);

    await container.read(pushControllerProvider.notifier).enable();
    expect(container.read(pushControllerProvider), PushChannelStatus.enabled);
    // 测试宿主 Platform.isIOS=false → android。
    expect(repo.registered, <String>['android:tok-1']);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('push_enabled'), isTrue);
    expect(prefs.getString('push_token'), 'tok-1');
  });

  test('权限被拒 → permissionDenied 且保留用户意愿（push_enabled=true）', () async {
    configureEnabledBuild();
    PushController.permissionOverride = () async => false;
    storage.write('tok');
    repo.configResponse = serverEnabledConfig();
    final ProviderContainer container = makeContainer();
    await settle();
    await container.read(pushControllerProvider.notifier).enable();
    expect(
      container.read(pushControllerProvider),
      PushChannelStatus.permissionDenied,
    );
    expect(repo.registered, isEmpty);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('push_enabled'), isTrue);
  });

  test('disable() 注销设备并持久化关闭', () async {
    configureEnabledBuild();
    storage.write('tok');
    repo.configResponse = serverEnabledConfig();
    final ProviderContainer container = makeContainer();
    final PushController controller = container.read(
      pushControllerProvider.notifier,
    );
    await settle();
    await controller.enable();
    expect(repo.registered, hasLength(1));

    await controller.disable();
    expect(container.read(pushControllerProvider), PushChannelStatus.disabled);
    expect(repo.unregistered, <String>['tok-1']);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('push_enabled'), isFalse);
  });

  test('handleLogout 尽力注销当前设备绑定', () async {
    final ProviderContainer container = makeContainer();
    final PushController controller = container.read(
      pushControllerProvider.notifier,
    );
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('push_token', 'tok-logout');
    await controller.handleLogout();
    expect(repo.unregistered, <String>['tok-logout']);
  });
}
