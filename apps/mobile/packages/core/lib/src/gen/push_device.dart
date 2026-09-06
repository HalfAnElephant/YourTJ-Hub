/// 原生推送设备注册契约镜像（push/device/register|unregister、push/config.native）。
///
/// 手写维护；与后端契约一致：platform 取值 "ios"|"android"，
/// token 为 FCM/APNs 注册令牌（全局唯一索引）。
library;

/// GET push/config 响应中的原生通道门控。
class NativePushConfig {
  const NativePushConfig({required this.apnsEnabled, required this.fcmEnabled});

  final bool apnsEnabled;
  final bool fcmEnabled;

  /// 任一通道启用即视为原生推送可用（iOS 走 APNs、Android 走 FCM）。
  bool get anyEnabled => apnsEnabled || fcmEnabled;

  factory NativePushConfig.fromJson(Map<String, dynamic> json) =>
      NativePushConfig(
        apnsEnabled: json['apnsEnabled'] as bool? ?? false,
        fcmEnabled: json['fcmEnabled'] as bool? ?? false,
      );
}

/// POST push/device/register 请求体。
class RegisterPushDeviceInput {
  const RegisterPushDeviceInput({required this.platform, required this.token});

  /// "ios" | "android"。
  final String platform;
  final String token;

  Map<String, dynamic> toJson() => {'platform': platform, 'token': token};
}

/// POST push/device/unregister 请求体。
class UnregisterPushDeviceInput {
  const UnregisterPushDeviceInput({required this.token});

  final String token;

  Map<String, dynamic> toJson() => {'token': token};
}

/// GET push/config 响应（web push + native 门控；native 由后端未配置时省略）。
class PushConfigPayload {
  const PushConfigPayload({
    required this.configured,
    this.applicationServerKey,
    this.native,
  });

  /// Web Push（VAPID）通道是否启用。
  final bool configured;

  /// VAPID 公钥（仅 web push 启用时返回）。
  final String? applicationServerKey;

  /// 原生推送（APNs/FCM）通道门控；后端未部署原生支持时为 null。
  final NativePushConfig? native;

  factory PushConfigPayload.fromJson(Map<String, dynamic> json) =>
      PushConfigPayload(
        configured: json['configured'] as bool? ?? false,
        applicationServerKey: json['applicationServerKey'] as String?,
        native: json['native'] == null
            ? null
            : NativePushConfig.fromJson(
                Map<String, dynamic>.from(json['native'] as Map),
              ),
      );
}
