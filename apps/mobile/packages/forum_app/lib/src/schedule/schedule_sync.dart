// 排课方案云端同步控制器（issue #537，web 同规则）。
//
// 职责边界：store 只负责本地状态与持久化（pk.* 键 + pk.syncedAt），
// 本文件负责传输编排——进页拉取对账、冲突上抛（页面弹窗二选一）、
// 本地变更防抖上行、失败分类（400 停本轮 / 401 停至下次进页 / 网络错误
// 保持 dirty 重试）与登出零请求。传输走 [PkPlansTransport] 抽象，
// 测试注入 fake；生产实现桥接 [PkRepository] 的 plans 三端点。
//
// 同步语义（锁定）：
// - 进页（已登录）GET plans：data==null → localEmpty ? 不动 : PUT(本地)；
//   data=快照 → localEmpty ? 整包采用 : (dirty ? 弹窗 : (syncedAt==
//   快照.updatedAt ? 不动 : 弹窗))。
// - 弹窗「使用云端」→ store.applyRemoteSnapshot（applyingRemote 守卫，
//   绝不回灌）；「保留本地」→ 立即 PUT。一次性（每次进页至多一次）。
// - 本地变更（store 钩子）→ dirty + 3s 防抖 → PUT；成功推进 syncedAt。
import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'schedule_store.dart';

/// 方案快照传输抽象（GET/PUT /api/pk/plans；测试注入 fake）。
abstract class PkPlansTransport {
  /// 拉取云端快照；云端为空返回 null。
  Future<PkPlansSnapshot?> fetchPlans();

  /// 整包上行快照；返回服务端新同步时钟 updatedAt。
  Future<String> uploadPlans(PkPlanSnapshotPayload payload);
}

/// [PkPlansTransport] 的生产实现：桥接 [PkRepository]。
class PkPlansRepositoryTransport implements PkPlansTransport {
  PkPlansRepositoryTransport(this._repository);

  final PkRepository _repository;

  @override
  Future<PkPlansSnapshot?> fetchPlans() => _repository.getPlans();

  @override
  Future<String> uploadPlans(PkPlanSnapshotPayload payload) async =>
      (await _repository.putPlans(payload)).updatedAt;
}

/// 方案云同步控制器（每应用一个实例；由 Provider 创建并绑定 store 钩子）。
class ScheduleSyncController {
  ScheduleSyncController({
    required this.transport,
    required this.tokenStorage,
    required this.store,
    Timer Function(Duration delay, void Function() onFire)? debounceTimer,
  }) : _debounceTimer = debounceTimer ?? _defaultDebounceTimer {
    scheduleLocalPlansChanged = _onLocalPlansChanged;
  }

  static Timer _defaultDebounceTimer(Duration delay, void Function() onFire) =>
      Timer(delay, onFire);

  final PkPlansTransport transport;
  final TokenStorage tokenStorage;
  final ScheduleStoreNotifier store;
  final Timer Function(Duration delay, void Function() onFire) _debounceTimer;

  /// 本地变更防抖窗口（web 同款 3s）。
  static const Duration debounceDelay = Duration(seconds: 3);

  bool _dirty = false;
  bool _stopped = false; // 401 后停至下次进页
  bool _uploading = false;
  bool _disposed = false;
  int _localChangeSeq = 0;
  Timer? _pendingUpload;

  /// 是否有未上行的本地变更（测试/诊断用）。
  bool get isDirty => _dirty;

  /// 释放：解绑 store 钩子并取消挂起防抖。
  void dispose() {
    _disposed = true;
    _pendingUpload?.cancel();
    _pendingUpload = null;
    if (identical(scheduleLocalPlansChanged, _onLocalPlansChanged)) {
      scheduleLocalPlansChanged = null;
    }
  }

  Future<bool> _hasToken() async {
    try {
      final String? token = await tokenStorage.read();
      return token != null && token.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 进页同步对账；返回待决冲突快照（null = 无需弹窗）。每次进页至多
  /// 返回一次（弹窗一次性）。未登录直接返回 null，零网络请求。
  Future<PkPlansSnapshot?> syncOnEnter() async {
    if (_disposed || !await _hasToken()) return null;
    _stopped = false; // 新一次进页：重置 401 停止标记
    final PkPlansSnapshot? remote;
    try {
      remote = await transport.fetchPlans();
    } on ApiException catch (e) {
      if (e.statusCode == 401) _stopped = true;
      return null; // 网络/服务端失败：本次进页放弃对账
    }
    if (remote == null) {
      if (!store.isLocalEmpty) {
        await _uploadNow(); // 云端空且本地有货 → 上行本地
      }
      return null;
    }
    if (store.isLocalEmpty) {
      await adoptRemote(remote); // 本地空壳 → 无条件整包采用
      return null;
    }
    if (_dirty) return remote; // 本地有未上行变更 → 冲突
    if (store.syncedAt != remote.updatedAt) return remote; // 云端更新 → 冲突
    return null; // 一致 → 不动
  }

  /// 冲突弹窗「使用云端」：整包采用（store 内 applyingRemote 守卫，
  /// 不触发本地变更钩子，不回灌上行）。
  Future<void> adoptRemote(PkPlansSnapshot snapshot) async {
    if (_disposed) return;
    _pendingUpload?.cancel();
    _pendingUpload = null;
    _dirty = false;
    store.applyRemoteSnapshot(snapshot);
  }

  /// 冲突弹窗「保留本地」：取消防抖立即 PUT。
  Future<void> keepLocal() async {
    if (_disposed) return;
    _pendingUpload?.cancel();
    _pendingUpload = null;
    await _uploadNow();
  }

  /// App 生命周期 paused 时的尽力冲刷（dirty 且未停止时立即上行；
  /// 登录态由 [_uploadNow] 统一把关，未登录零网络请求）。
  Future<void> flushPendingUpload() async {
    if (_disposed || !_dirty || _stopped || _uploading) return;
    _pendingUpload?.cancel();
    _pendingUpload = null;
    await _uploadNow();
  }

  /// 页面离场（dispose）时取消挂起的上行防抖。dirty 保留、store 钩子保持
  /// 绑定（控制器为应用级实例，生命周期不随页面销毁）；未上行的变更由
  /// 下次进页对账（dirty → 冲突分支）或后续本地变更重新排程承接。
  /// 否则 3s 防抖 Timer 会在组件树销毁后仍挂起。
  void cancelPendingUpload() {
    _pendingUpload?.cancel();
    _pendingUpload = null;
  }

  // ---- 本地变更钩子（store _persistPlanData / setWeekView 尾部触发）----

  void _onLocalPlansChanged() {
    if (_disposed) return;
    // 即使已停止（401）也保持 dirty：下次进页对账需知道本地有未上行
    // 变更（dirty → 弹窗分支），只是不再排程上行。
    _dirty = true;
    if (_stopped) return;
    _localChangeSeq++;
    // 立即排程防抖（spec：dirty + 3s debounce 同步发生）；未登录时防抖
    // 到期由 _uploadNow 统一拦截（零网络请求）。
    _pendingUpload?.cancel();
    _pendingUpload = _debounceTimer(debounceDelay, _onDebounceFired);
  }

  Future<void> _onDebounceFired() async {
    _pendingUpload = null;
    if (!_disposed && _dirty) {
      await _uploadNow();
    }
  }

  Future<void> _uploadNow() async {
    if (_disposed || _stopped || _uploading) return;
    if (!await _hasToken()) return; // 登出后零网络请求
    _uploading = true;
    final int seqAtStart = _localChangeSeq;
    try {
      final String updatedAt = await transport.uploadPlans(
        store.buildSnapshotPayload(),
      );
      if (_localChangeSeq != seqAtStart) {
        // 上行期间又有本地变更：保留 dirty 并再排一轮防抖。
        _onLocalPlansChanged();
        return;
      }
      _dirty = false;
      store.markSyncedAt(updatedAt);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        _stopped = true; // 停至下次进页
      } else if (e.statusCode == 400) {
        // 结构校验失败：该载荷重试无意义，静默停本轮（debugPrint 留痕）。
        debugPrint('pk plans sync rejected (400): ${e.params?['detail']}');
        _dirty = false;
      }
      // 其余（429/5xx/网络错误）：保持 dirty，等待下次触发（变更/进页/
      // paused 冲刷）重试。
    } finally {
      _uploading = false;
    }
  }
}

/// 方案云同步控制器 Provider（页面进页对账 + 冲突弹窗 + paused 冲刷）。
final Provider<ScheduleSyncController> scheduleSyncControllerProvider =
    Provider<ScheduleSyncController>((ref) {
      final ScheduleSyncController controller = ScheduleSyncController(
        transport: PkPlansRepositoryTransport(ref.watch(pkRepositoryProvider)),
        tokenStorage: ref.watch(tokenStorageProvider),
        store: ref.watch(scheduleStoreProvider.notifier),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });
