package pkservice

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/models/forum/pk"
)

// 排课方案云端同步（issue #537）的服务端浅校验。
//
// 深度 sanitize（周次钳制、非法安排丢弃、activePlanId 回退等）是客户端加载
// 路径的职责（web useScheduleStore / mobile schedule_store 各自的 sanitize
// 部落）；服务端只拒绝结构性非法的快照，保证落库数据自洽且体积有界。

const (
	// MaxPlansPerSnapshot 单用户方案数上限（与 web MAX_PLANS / mobile kMaxPlans 一致）。
	MaxPlansPerSnapshot = 10
	// MaxSnapshotBytes 快照整体负载上限：10 套方案 × 数十门课 × 完整教学班详情
	// ≈ 数百 KB，1MB 余量充足（localStorage 本就承载同量级数据）。
	MaxSnapshotBytes = 1 << 20
)

// PlanSnapshotPayload PUT /api/pk/plans 的请求负载（GET 响应同构，另含 updatedAt）。
type PlanSnapshotPayload struct {
	Plans         pk.PlanList              `json:"plans"`
	ActivePlanId  string                   `json:"activePlanId"`
	MajorSelected pk.MajorSelectionPayload `json:"majorSelected"`
	WeekView      pk.WeekViewPayload       `json:"weekView"`
}

// ValidatePlanSnapshot 结构浅校验：1..MaxPlansPerSnapshot 套方案、每套非空
// id/name、activePlanId 必须命中 plans 之一。错误信息为可读中文，直接作为
// PK 信封 BadRequest 的 msg 下发。
func ValidatePlanSnapshot(plans pk.PlanList, activePlanId string) error {
	if len(plans) < 1 {
		return fmt.Errorf("至少需要一套排课方案")
	}
	if len(plans) > MaxPlansPerSnapshot {
		return fmt.Errorf("排课方案数量超出上限（最多 %d 套）", MaxPlansPerSnapshot)
	}
	ids := make(map[string]struct{}, len(plans))
	for _, plan := range plans {
		if strings.TrimSpace(plan.Id) == "" || strings.TrimSpace(plan.Name) == "" {
			return fmt.Errorf("方案缺少 id 或名称")
		}
		ids[plan.Id] = struct{}{}
	}
	if _, ok := ids[activePlanId]; !ok {
		return fmt.Errorf("activePlanId 未指向任何方案")
	}
	return nil
}

// ValidatePlanSnapshotSize 快照整体序列化体积校验（≤ MaxSnapshotBytes）。
func ValidatePlanSnapshotSize(payload PlanSnapshotPayload) error {
	encoded, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("方案数据序列化失败")
	}
	if len(encoded) > MaxSnapshotBytes {
		return fmt.Errorf("方案数据过大（超过 %d MB 上限）", MaxSnapshotBytes>>20)
	}
	return nil
}
