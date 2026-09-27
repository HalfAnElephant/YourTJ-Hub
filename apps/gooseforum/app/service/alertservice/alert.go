// Package alertservice 实现站内运维告警的聚合编排（issue #855）：
// 认领告警接收人（SiteManager 及 Admin 超级集角色）、按来源去重并逐人发送
// 系统站内通知。告警链路是 best-effort：任何失败只记日志，绝不影响调用方
// （如排课同步流程）的错误路径与返回。
package alertservice

import (
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/bundles/localcache"
	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/cacheconfig"
	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/models/forum/pk"
	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/models/forum/role"
	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/models/forum/users"
	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/service/notificationservice"
	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/service/permission"
)

// alertWindow 是同一来源（受众）告警的去重窗口：窗口内重复失败不再提醒，
// 避免凭证持续失效时 cron/手动重试高频刷屏。
const alertWindow = 6 * time.Hour

// now 是可注入时钟：生产走 time.Now，测试可覆盖以控制记录的告警时间。
var now = time.Now

// pkAlertCache 记录 "最近一次告警的时间点" 标记；条目存活期 = alertWindow，
// 存活期内同 key 再次告警直接跳过。key 见 pkAlertKey。
var pkAlertCache = localcache.Cache[time.Time]{MaxEntries: cacheconfig.Current().RolePermission}

// errNoAlertMarker 表示缓存中没有该 key 的告警标记（本地缓存 loader 的
// 哨兵错误：时间窗口外应重新告警）。
var errNoAlertMarker = errors.New("alertservice: no alert marker")

// pkAlertKey 是告警去重 key：按来源（受众字符串）隔离，本科生/研究生互不影响。
func pkAlertKey(audience string) string {
	return "pk_alert:" + audience
}

// audienceLabel 把原始受众字符串转成中文标签；空/未知值回落「本科」
// （与 pkservice.audienceLabel 同口径）。
func audienceLabel(audience string) string {
	if pk.DefaultAudience(audience) == pk.AudienceGraduate {
		return "研究生"
	}
	return "本科"
}

// NotifyPkSyncFailed 在排课同步失败（fetchlog 标记 failed）时向拥有
// SiteManager 权限（含 Admin 超级集）的全部活跃用户发送站内系统通知。
//
//   - 去重：同一来源（受众）在 alertWindow（6h）窗口内只发送一次；
//   - best-effort：不 panic、不向调用方返回错误，单项失败仅 slog.Warn。
//
// 注意：message 来自同步错误文本（err.Error()），上游已脱敏，不包含凭证原文。
func NotifyPkSyncFailed(audience string, message string) {
	// 告警是旁路职责：即使下面某步 panic 也不能让同步流程跟着崩。
	defer func() {
		if r := recover(); r != nil {
			slog.Warn("alertservice: NotifyPkSyncFailed recovered", "audience", audience, "panic", r)
		}
	}()

	audience = string(pk.DefaultAudience(audience))
	key := pkAlertKey(audience)
	// 窗口内已告警过则跳过（本地缓存 TTL 实现时间窗）。
	if _, err := pkAlertCache.GetOrLoadE(key, func() (time.Time, error) {
		return time.Time{}, errNoAlertMarker
	}, alertWindow); err == nil {
		slog.Debug("alertservice: pk sync failure alert skipped (already notified in window)", "audience", audience)
		return
	}

	// 认领接收人：具备 SiteManager 权限的角色（CheckRole 对 Admin 角色视为超集）。
	roleIds := make([]uint64, 0, 4)
	for _, r := range role.AllEffective() {
		if r == nil {
			continue
		}
		if permission.CheckRole(r.Id, permission.SiteManager) {
			roleIds = append(roleIds, r.Id)
		}
	}
	userIDs := users.GetActiveUserIdsByRoleIds(roleIds)

	title := "一系统排课同步失败"
	content := fmt.Sprintf("【%s】同步失败：%s", audienceLabel(audience), message)

	for _, userID := range userIDs {
		if userID == 0 {
			continue
		}
		if err := notificationservice.SendSystemAlert(userID, title, content); err != nil {
			slog.Warn("alertservice: send pk sync failure alert failed", "userId", userID, "err", err)
		}
	}

	// 发送完成后记录标记，窗口内不再重复提醒。即便上面发送部分失败也记录，
	// 避免凭证持续失效时 cron 每轮重复打扰（站内通知可随时补发）。
	pkAlertCache.Set(key, now(), alertWindow)
}
