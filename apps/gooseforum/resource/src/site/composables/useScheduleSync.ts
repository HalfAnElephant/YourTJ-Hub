// 排课方案云同步（issue #537 PR-2）—— localStorage 方案快照与云端三端点同步。
//
// 同步语义（两端锁定，web/移动同规则）：
// - 进页（已登录）GET /api/pk/plans：
//   data=null（云端空）→ 本机空则不动，否则首登自动上传本机快照；
//   data=快照 → 本机空则整包采用（云端）；本机非空时，dirty（本会话有未上传
//   变更）或 syncedAt ≠ 快照.updatedAt → 弹窗二选一，否则不动。
// - 弹窗二选一：「使用云端」= applyRemoteSnapshot 整包采用；「保留本机」=
//   立即 PUT 本机快照。一次性，选后不再问（关闭弹窗 = 暂缓，下次进页仍提示）。
// - 本地任意方案变更（store.solidify 尾部钩子注入）→ dirty + 防抖 3s PUT：
//   成功 syncedAt=服务端 updatedAt、dirty=false；400/403 静默停止本轮（console.warn
//   诊断，dirty 保持不重试，下次变更开新一轮）；网络错误保持 dirty 待下次触发；
//   401 停止触发直至下次进页。
// - 登出/离页：停同步，本地数据原样保留；未登录全程零网络请求（不 start 即不变更）。
// - web 额外：document visibilitychange → hidden 时 best-effort 冲刷未落盘的防抖 PUT。

import { shallowRef, type ShallowRef } from 'vue'
import { setSolidifyHook, useScheduleStore } from './useScheduleStore'

// ---- OpenAPI 契约 wire 形状（手写镜像 packages/api-contract 的 PkPlanPayload /
// PkPlansPutRequest / PkPlansGetResponse 相关 schema；后续 `pnpm run generate:ts`
// 再生后可替换为 @gooseforum/client 生成类型）----

/** 教师（PkTeacherItem）。 */
export interface PkSyncTeacher {
  teacherName: string
  teacherCode: string
}

/** 一次上课安排（PkArrangementItem）。 */
export interface PkSyncArrangement {
  arrangementText: string
  /** 星期 1-7 */
  occupyDay: number
  /** 节次 1-12 */
  occupyTime: number[]
  /** 周次（展开） */
  occupyWeek: number[]
  occupyRoom: string
  teacherAndCode: string
}

/** 教学班（PkCourseDetailItem）。 */
export interface PkSyncCourseDetail {
  arrangementInfo: PkSyncArrangement[]
  campus: string
  code: string
  teachingClassId?: number
  isExclusive?: boolean
  /** 0 未选 / 1 备选 / 2 已选 */
  status?: number
  teachers: PkSyncTeacher[]
  teachingLanguage: string
}

/** 备选课程（PkStagedCourseItem）。 */
export interface PkSyncStagedCourse {
  courseCode: string
  courseName: string
  courseNameReserved: string
  credit: number
  courseType: string
  courseNature: string[]
  teacher: PkSyncTeacher[]
  status: number
  courseDetail: PkSyncCourseDetail[]
}

/** 自定义占位事件（PkCustomEventItem）。 */
export interface PkSyncCustomEvent {
  id: string
  label: string
  /** 星期 1-7 */
  day: number
  /** 节次集合（1-12） */
  sections: number[]
  /** 周次集合 */
  weeks: number[]
}

/** 排课方案（PkPlanItem；与前端 PkPlan 字段完全一致）。 */
export interface PkSyncPlan {
  id: string
  name: string
  createdAt: number
  stagedCourses: PkSyncStagedCourse[]
  /** 已选班级课号（含班号） */
  selectedCourses: string[]
  customEvents: PkSyncCustomEvent[]
}

/** majorSelected（学期/年级/专业三元组）。 */
export interface PkSyncMajorSelection {
  calendarId?: number
  grade?: number
  major?: string
  majorName?: string
}

/** weekView（周次视图；week=null 表示全部周次堆叠）。 */
export interface PkSyncWeekView {
  week: number | null
  useCurrent: boolean
}

/** PUT /api/pk/plans 请求体（PkPlansPutRequest）。 */
export interface PkSyncPayload {
  plans: PkSyncPlan[]
  activePlanId: string
  majorSelected: PkSyncMajorSelection
  weekView: PkSyncWeekView
}

/** GET /api/pk/plans 的 data（PkPlansSnapshot；null = 云端空）。 */
export interface PkSyncRemoteSnapshot extends PkSyncPayload {
  /** 服务端权威时钟（RFC3339Nano UTC），存入 pk.syncedAt 供进页冲突判定。 */
  updatedAt: string
}

// ---- 传输层 ----

/** 同步错误类别：401 未登录 / 服务端拒绝（400 结构校验、403 冻结）/ 网络错误。 */
export type PkSyncErrorKind = 'unauthenticated' | 'rejected' | 'network'

export class PkSyncError extends Error {
  readonly status: number
  readonly kind: PkSyncErrorKind

  constructor(message: string, status: number, kind: PkSyncErrorKind) {
    super(message)
    this.name = 'PkSyncError'
    this.status = status
    this.kind = kind
  }
}

export interface PkSyncTransport {
  /** GET 云端快照；云端空返回 null。401/网络错误/结构失败抛 PkSyncError。 */
  fetchCloudSnapshot(): Promise<PkSyncRemoteSnapshot | null>
  /** PUT 整包快照；返回服务端新 updatedAt。 */
  putCloudSnapshot(payload: PkSyncPayload): Promise<{ updatedAt: string }>
}

/** PK 域信封（{code, msg, data}；成功 code===0，负载在 data）。 */
interface PkSyncEnvelope {
  code?: number
  msg?: string
  data?: unknown
}

/**
 * 默认传输层：同源 fetch（cookie 自动携带），信封解析对齐 runtime/pk-api.ts，
 * 但错误以 PkSyncError（kind + status）抛出供同步状态机区分处理。
 */
function createFetchTransport(): PkSyncTransport {
  async function request(path: string, init?: RequestInit): Promise<Response> {
    try {
      return await fetch(path, init)
    } catch {
      throw new PkSyncError('网络错误', 0, 'network')
    }
  }

  /** 解析 PK 信封：401 视为未登录；code!==0 视为服务端拒绝；非 2xx 兜底。 */
  async function readEnvelope(response: Response): Promise<unknown> {
    if (response.status === 401) {
      // 401 由论坛中间件产生（forum 信封 auth.required），视为未登录。
      throw new PkSyncError('未登录', 401, 'unauthenticated')
    }
    const envelope = (await response.json().catch(() => undefined)) as PkSyncEnvelope | undefined
    const code = envelope?.code
    if (code !== undefined && code !== 0) {
      throw new PkSyncError(envelope?.msg || '请求失败', response.status, 'rejected')
    }
    if (!response.ok) {
      throw new PkSyncError(`HTTP ${response.status}`, response.status, 'rejected')
    }
    return envelope?.data
  }

  return {
    async fetchCloudSnapshot() {
      const data = await readEnvelope(await request('/api/pk/plans'))
      if (data === null || data === undefined) return null
      if (typeof data !== 'object') {
        throw new PkSyncError('云端快照格式异常', 0, 'rejected')
      }
      return data as PkSyncRemoteSnapshot
    },
    async putCloudSnapshot(payload) {
      const response = await request('/api/pk/plans', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      })
      const data = (await readEnvelope(response)) as { updatedAt?: unknown } | undefined
      return { updatedAt: typeof data?.updatedAt === 'string' ? data.updatedAt : '' }
    },
  }
}

// ---- 同步控制器（纯逻辑；测试注入 fake transport）----

/** 本地变更 → 上传的防抖窗口（ms）。 */
export const PK_SYNC_DEBOUNCE_MS = 3000

export interface ScheduleSyncController {
  /** 冲突弹窗状态：非空 = 云端快照待二选一（只读消费，写走下方方法）。 */
  readonly conflict: ShallowRef<PkSyncRemoteSnapshot | null>
  /** 进页同步：GET + 四分支决策（自动上传 / 整包采用 / 弹窗 / 不动）。失败静默。 */
  syncOnPageEnter(): Promise<void>
  /** 本地方案变更入口（store.solidify 尾部钩子）：标脏 + 防抖 PUT。 */
  onLocalChange(): void
  /** best-effort 冲刷未落盘的防抖 PUT（visibilitychange hidden / 离页）。 */
  flushPendingUpload(): void
  /** 弹窗选择「使用云端」：整包采用云端快照（不回灌上传）。 */
  useCloud(): void
  /** 弹窗选择「保留本机」：立即 PUT 本机快照覆盖云端。 */
  keepLocal(): void
  /** 关闭弹窗（暂缓决策）：本轮不再询问，下次进页若仍分歧再提示。 */
  dismissConflict(): void
  /** 启用同步（已登录进页时调用）。 */
  start(): void
  /** 停止同步（登出/离页）：取消防抖与弹窗，本地数据不动。 */
  stop(): void
  /** 是否有未上传的本地变更（诊断/测试）。 */
  isDirty(): boolean
}

export function createScheduleSyncController(deps: { transport: PkSyncTransport }): ScheduleSyncController {
  const store = useScheduleStore()
  const conflict = shallowRef<PkSyncRemoteSnapshot | null>(null)

  let enabled = false
  let dirty = false
  /** 401 后停摆标志：直至下次进页（syncOnPageEnter）才恢复触发。 */
  let authStopped = false
  /** 进页 GET 防重入。 */
  let entering = false
  /** PUT 串行化（防抖到期与手动冲刷并发时只放一个）。 */
  let putting = false
  let debounceTimer: ReturnType<typeof setTimeout> | null = null

  function clearDebounce(): void {
    if (debounceTimer !== null) {
      clearTimeout(debounceTimer)
      debounceTimer = null
    }
  }

  /** localEmpty := 仅一个方案且三组用户数据全空（首登/清空后的空壳）。 */
  function isLocalEmpty(): boolean {
    const plans = store.state.plans
    if (plans.length !== 1) return false
    const plan = plans[0]
    return (
      plan.stagedCourses.length === 0 &&
      plan.selectedCourses.length === 0 &&
      plan.customEvents.length === 0
    )
  }

  async function pushSnapshot(): Promise<void> {
    if (!enabled || putting || authStopped) return
    putting = true
    try {
      // 前端 PkStagedCourse.courseNature 类型为可选（sanitize 恒回填数组，wire 恒有值），
      // 此处对齐契约必填形状做一次性结构收窄。
      const payload = store.snapshotForSync() as PkSyncPayload
      const { updatedAt } = await deps.transport.putCloudSnapshot(payload)
      store.markSynced(updatedAt)
      dirty = false
    } catch (err) {
      if (err instanceof PkSyncError) {
        if (err.kind === 'unauthenticated') {
          // 401：停止触发直至下次进页；dirty 保持（数据不丢，重登后可续传）。
          authStopped = true
        } else if (err.kind === 'rejected') {
          // 400/403：静默停止本轮（诊断日志），dirty 保持但不重试。
          console.warn('[pk-sync] 上传被服务端拒绝，已停止本轮同步：', err.message)
        }
        // network：保持 dirty，下次触发/下次进页重试。
      }
      // 非预期异常按网络错误语义处理（保持 dirty 待重试）。
    } finally {
      putting = false
    }
  }

  function onLocalChange(): void {
    if (!enabled || authStopped) return
    dirty = true
    clearDebounce()
    debounceTimer = setTimeout(() => {
      debounceTimer = null
      void pushSnapshot()
    }, PK_SYNC_DEBOUNCE_MS)
  }

  function flushPendingUpload(): void {
    if (!enabled || !dirty || putting) return
    clearDebounce()
    void pushSnapshot()
  }

  async function syncOnPageEnter(): Promise<void> {
    if (!enabled || entering) return
    entering = true
    // 新一轮进页：此前 401 停摆解除（可能已重新登录）。
    authStopped = false
    try {
      let snapshot: PkSyncRemoteSnapshot | null
      try {
        snapshot = await deps.transport.fetchCloudSnapshot()
      } catch (err) {
        // 进页同步失败静默：未登录（探测式 GET 401）或网络错误均不作为、不打扰。
        if (!(err instanceof PkSyncError)) {
          console.warn('[pk-sync] 进页同步失败：', err)
        }
        return
      }
      if (snapshot === null) {
        // 云端空：本机空则不动；非空 = 首登自动上传本机快照。
        if (!isLocalEmpty()) await pushSnapshot()
        return
      }
      if (isLocalEmpty()) {
        // 整包采用（云端）：store 内 applyingRemote 守卫防回灌，重建派生态。
        clearDebounce()
        store.applyRemoteSnapshot(snapshot)
        store.markSynced(snapshot.updatedAt)
        dirty = false
        return
      }
      if (!dirty && store.getSyncedAt() === snapshot.updatedAt) return // 已一致：不动
      conflict.value = snapshot // 本机非空且与云端分歧 → 二选一（一次性）
    } finally {
      entering = false
    }
  }

  function useCloud(): void {
    const snapshot = conflict.value
    conflict.value = null
    if (!snapshot) return
    clearDebounce()
    store.applyRemoteSnapshot(snapshot)
    store.markSynced(snapshot.updatedAt)
    dirty = false
  }

  function keepLocal(): void {
    conflict.value = null
    clearDebounce()
    void pushSnapshot()
  }

  function dismissConflict(): void {
    conflict.value = null
  }

  function start(): void {
    enabled = true
    authStopped = false
  }

  function stop(): void {
    enabled = false
    clearDebounce()
    conflict.value = null
    // dirty 保留：登出/离页时未上传的本机变更不丢——下次进页 GET 分支仍能以
    // dirty 分歧弹窗（一次性二选一），避免「停同步 → 重进 → 静默跳过上传」。
  }

  return {
    conflict,
    syncOnPageEnter,
    onLocalChange,
    flushPendingUpload,
    useCloud,
    keepLocal,
    dismissConflict,
    start,
    stop,
    isDirty: () => dirty,
  }
}

// ---- 单例接线（排课页生命周期驱动；未登录不 start 即零网络）----

export const scheduleSync = createScheduleSyncController({ transport: createFetchTransport() })

let wired = false

/** 首次启动时接线：注入 store.solidify 尾部钩子 + visibilitychange 冲刷（幂等）。 */
function wireOnce(): void {
  if (wired) return
  wired = true
  setSolidifyHook(() => scheduleSync.onLocalChange())
  if (typeof document !== 'undefined') {
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') scheduleSync.flushPendingUpload()
    })
  }
}

/** 启动云同步（已登录进入排课页时调用；之后由 solidify 钩子驱动增量上传）。 */
export function startScheduleSync(): void {
  wireOnce()
  scheduleSync.start()
}

/** 停止云同步（离开排课页/登出后调用）：取消防抖与弹窗，本地数据原样保留。 */
export function stopScheduleSync(): void {
  scheduleSync.stop()
}
