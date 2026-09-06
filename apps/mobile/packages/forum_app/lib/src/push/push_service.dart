import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:core/core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart';
import '../router.dart';

/// 后台消息处理器（release AOT 需要 entry-point 标注）。
///
/// 服务端推送为展示型通知（系统托盘自动弹出），后台无需额外处理；
/// 点按路由统一走 [PushController._setupRouting] 注册的前台监听。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// 原生推送（APNs/FCM）通道状态。
enum PushChannelStatus {
  /// 初始未知（本地已配置的构建在服务端门控解析前）。
  unknown,

  /// 本地构建未注入 Firebase 配置（dart-define），推送能力不存在。
  /// 仓库永不携带 Firebase 凭据（Blueprint 硬约束）。
  unsupported,

  /// 服务端未启用原生通道（push/config.native 缺失或双通道均关）。
  serverDisabled,

  /// 用户已关闭推送。
  disabled,

  /// 已开启且设备已注册（token 已上报 push/device/register）。
  enabled,

  /// 用户已开启但系统通知权限被拒（引导跳系统设置）。
  permissionDenied,
}

/// 原生推送接入控制器（Route A 原生推送）。
///
/// 语义对齐 Web Push 通道：未配置 = 通道关闭（设置页隐藏入口、零报错）；
/// 服务端 `push/config.native` 与本地 Firebase 配置双重门控。
/// token 轮换重注册；登出尽力注销设备（token 唯一索引按 upsert 收敛到
/// 新账号，与 web push 订阅归属语义一致）。
class PushController extends Notifier<PushChannelStatus> {
  static const String _enabledKey = 'push_enabled';
  static const String _tokenKey = 'push_token';
  bool _listenersAttached = false;
  bool _restoring = false;

  @override
  PushChannelStatus build() {
    // 恢复流程含多个异步门控（会话/服务端/本地偏好），在 build 返回后
    // 以微任务启动，避免 build 返回值覆盖 restore 同步设置的中间状态。
    Future.microtask(_restore);
    return PushChannelStatus.unknown;
  }

  // ---- 测试注入点（宿主 widget 测试无法初始化 Firebase 原生层）----

  /// 覆盖本地配置判定（测试注入 true 模拟已注入 dart-define 的构建）。
  @visibleForTesting
  static bool? configuredOverride;

  /// 覆盖 Firebase 初始化（测试注入 no-op）。
  @visibleForTesting
  static Future<void> Function()? initOverride;

  /// 覆盖设备 token 获取（测试注入固定 token）。
  @visibleForTesting
  static String? Function()? tokenProviderOverride;

  /// 覆盖系统通知权限检查（测试注入授权/拒绝）。
  @visibleForTesting
  static Future<bool> Function()? permissionOverride;

  // ---- 配置 ----

  static String _define(String name) {
    const map = <String, String>{
      'YOURTJ_FB_PROJECT_ID': String.fromEnvironment('YOURTJ_FB_PROJECT_ID'),
      'YOURTJ_FB_SENDER_ID': String.fromEnvironment('YOURTJ_FB_SENDER_ID'),
      'YOURTJ_FB_ANDROID_API_KEY': String.fromEnvironment(
        'YOURTJ_FB_ANDROID_API_KEY',
      ),
      'YOURTJ_FB_ANDROID_APP_ID': String.fromEnvironment(
        'YOURTJ_FB_ANDROID_APP_ID',
      ),
      'YOURTJ_FB_IOS_API_KEY': String.fromEnvironment('YOURTJ_FB_IOS_API_KEY'),
      'YOURTJ_FB_IOS_APP_ID': String.fromEnvironment('YOURTJ_FB_IOS_APP_ID'),
    };
    return map[name] ?? '';
  }

  /// 当前平台的 FirebaseOptions；dart-define 缺失返回 null。
  static FirebaseOptions? get platformOptions {
    final String projectId = _define('YOURTJ_FB_PROJECT_ID');
    final String senderId = _define('YOURTJ_FB_SENDER_ID');
    if (projectId.isEmpty || senderId.isEmpty) return null;
    if (Platform.isIOS) {
      final String apiKey = _define('YOURTJ_FB_IOS_API_KEY');
      final String appId = _define('YOURTJ_FB_IOS_APP_ID');
      if (apiKey.isEmpty || appId.isEmpty) return null;
      return FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: senderId,
        projectId: projectId,
        iosBundleId: 'tj.yourtj.forumApp',
      );
    }
    final String apiKey = _define('YOURTJ_FB_ANDROID_API_KEY');
    final String appId = _define('YOURTJ_FB_ANDROID_APP_ID');
    if (apiKey.isEmpty || appId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
    );
  }

  /// 本地构建是否具备推送能力（dart-define 注入了 Firebase 配置）。
  static bool get isConfigured =>
      configuredOverride ?? (platformOptions != null);

  String? _tokenFromOverride() => tokenProviderOverride?.call();

  Future<void> _initFirebase() async {
    final Future<void> Function()? injected = initOverride;
    if (injected != null) return injected();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: platformOptions);
    }
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  Future<bool> _hasPermission() async {
    final Future<bool> Function()? injected = permissionOverride;
    if (injected != null) return injected();
    final NotificationSettings settings = await FirebaseMessaging.instance
        .requestPermission(alert: true, badge: true, sound: true);
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<String?> _obtainToken() async {
    final String? injected = _tokenFromOverride();
    if (injected != null) return injected;
    return FirebaseMessaging.instance.getToken();
  }

  // ---- 状态恢复（启动） ----

  Future<void> _restore() async {
    if (_restoring) return;
    _restoring = true;
    try {
      if (!isConfigured) {
        state = PushChannelStatus.unsupported;
        return;
      }
      // 会话门控：push/config 挂登录路由组（Bearer），匿名启动直接查询会
      // 触发全局 401 拆链把访客拽去登录页 —— 无令牌按通道关闭处理，
      // 登录后下次启动/手动开启时自动恢复。
      final bool hasToken = await hasSessionToken(
        ref.read(tokenStorageProvider),
      );
      if (!hasToken) {
        state = PushChannelStatus.serverDisabled;
        return;
      }
      // 服务端门控：native 缺失或全关 → 通道关闭。
      bool serverEnabled = false;
      try {
        final PushConfigPayload config = await ref
            .read(pushRepositoryProvider)
            .config();
        serverEnabled = config.native?.anyEnabled ?? false;
      } catch (_) {
        // 服务端不可达/旧后端：保持通道关闭，零报错。
      }
      if (!serverEnabled) {
        state = PushChannelStatus.serverDisabled;
        return;
      }
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool enabled = prefs.getBool(_enabledKey) ?? false;
      if (!enabled) {
        state = PushChannelStatus.disabled;
        return;
      }
      // 已开启：校验系统权限并恢复注册。
      try {
        await _initFirebase();
        if (!await _hasPermission()) {
          state = PushChannelStatus.permissionDenied;
          return;
        }
        await _register(prefs);
        state = PushChannelStatus.enabled;
        _setupRouting();
      } catch (_) {
        // 原生层异常（如测试宿主）：保持关闭，不阻塞启动。
        state = PushChannelStatus.disabled;
      }
    } finally {
      _restoring = false;
    }
  }

  // ---- 用户开关 ----

  /// 开启推送：权限 → token → 注册。失败回退 disabled 并静默（设置页
  /// 三态展示由状态驱动）。
  Future<void> enable() async {
    if (!isConfigured) return;
    try {
      await _initFirebase();
      if (!await _hasPermission()) {
        await _persistEnabled(true); // 保留意愿，启动时自动重试
        state = PushChannelStatus.permissionDenied;
        return;
      }
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await _register(prefs);
      await _persistEnabled(true);
      state = PushChannelStatus.enabled;
      _setupRouting();
    } catch (_) {
      state = PushChannelStatus.disabled;
    }
  }

  /// 关闭推送：尽力注销设备注册（幂等），本地保存意愿关闭。
  Future<void> disable() async {
    await _persistEnabled(false);
    state = PushChannelStatus.disabled;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString(_tokenKey);
      if (token != null && token.isNotEmpty) {
        await ref.read(pushRepositoryProvider).unregisterDevice(token: token);
      }
    } catch (_) {
      // 注销失败静默：服务端下行失败时会按 410/UNREGISTERED 清理。
    }
  }

  /// 登出时尽力注销当前设备的用户绑定（幂等；本地意愿保留，
  /// 新账号登录后启动/开启时按 token 唯一索引重新收敛注册）。
  Future<void> handleLogout() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString(_tokenKey);
      if (token != null && token.isNotEmpty) {
        await ref.read(pushRepositoryProvider).unregisterDevice(token: token);
      }
    } catch (_) {
      // 尽力而为：注销失败不阻塞登出流程。
    }
  }

  /// 打开系统设置（权限被拒引导；使用 app_settings 插件）。
  Future<void> openSystemSettings() => AppSettings.openAppSettings();

  Future<void> _register(SharedPreferences prefs) async {
    final String? token = await _obtainToken();
    if (token == null || token.isEmpty) return;
    await prefs.setString(_tokenKey, token);
    await ref
        .read(pushRepositoryProvider)
        .registerDevice(
          platform: Platform.isIOS ? 'ios' : 'android',
          token: token,
        );
    _attachTokenRefresh(prefs);
  }

  void _attachTokenRefresh(SharedPreferences prefs) {
    if (!isConfigured || _listenersAttached) return;
    if (tokenProviderOverride != null) return; // 测试注入无真实 token 流
    _listenersAttached = true;
    FirebaseMessaging.instance.onTokenRefresh.listen((String token) async {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        if (!(prefs.getBool(_enabledKey) ?? false)) return;
        await prefs.setString(_tokenKey, token);
        await ref
            .read(pushRepositoryProvider)
            .registerDevice(
              platform: Platform.isIOS ? 'ios' : 'android',
              token: token,
            );
      } catch (_) {
        // 重注册失败静默：下次轮换或开启时重试。
      }
    });
  }

  // ---- 点按路由 ----

  /// 通知点按 → payload.route → 应用内路由（cold-start 与后台点按统一；
  /// 路由失败回退首页不崩溃）。
  void _setupRouting() {
    if (!isConfigured || _routingAttached) return;
    if (initOverride != null) return; // 测试宿主不挂原生监听
    _routingAttached = true;
    void goRoute(String? route) {
      if (route == null || route.isEmpty) return;
      try {
        appRouter.push(route);
      } catch (_) {
        try {
          appRouter.go('/');
        } catch (_) {}
      }
    }

    FirebaseMessaging.instance.getInitialMessage().then(
      (RemoteMessage? message) => goRoute(message?.data['route'] as String?),
    );
    FirebaseMessaging.onMessageOpenedApp.listen(
      (RemoteMessage message) => goRoute(message.data['route'] as String?),
    );
  }

  bool _routingAttached = false;

  Future<void> _persistEnabled(bool value) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (_) {
      // 持久化失败保留会话内选择。
    }
  }
}

/// 启动引导：GfApp 挂载后异步恢复推送状态（配置的构建自动重注册 + 点按路由）。
final pushBootstrapProvider = FutureProvider<void>((ref) async {
  // 触发 controller build（_restore 异步执行）；等待一拍让路由完成挂载，
  // 点按路由监听随后注册时 appRouter 已可用。
  ref.watch(pushControllerProvider);
  await Future<void>.delayed(Duration.zero);
});

final pushControllerProvider =
    NotifierProvider<PushController, PushChannelStatus>(PushController.new);
