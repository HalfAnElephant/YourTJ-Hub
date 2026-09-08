package pkcontroller

import (
	"errors"
	"time"

	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/models/forum/pk"
	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/service/pkservice"
)

// GetPlans GET /api/pk/plans（issue #537）：返回登录用户云端快照；
// 云端为空时 data=null（前端据此判定首登自动上传）。userId 由 routes 包的
// pkAuthNoReq 包装从 JWTAuthCheck 写入的 gin 上下文填充。
func GetPlans(req Request[Null]) Response {
	if req.UserId == 0 {
		return BadRequest("缺少登录态")
	}
	entity, err := pk.GetScheduleSnapshotByUser(req.UserId)
	if errors.Is(err, pk.ErrScheduleSnapshotNotFound) {
		return Ok(nil)
	}
	if err != nil {
		return Internal("读取排课方案失败")
	}
	return Ok(PlansSnapshotResponse{
		Plans:         entity.Plans,
		ActivePlanId:  entity.ActivePlanId,
		MajorSelected: entity.MajorSelected,
		WeekView:      entity.WeekView,
		UpdatedAt:     entity.UpdatedAt.UTC().Format(time.RFC3339Nano),
	})
}

// PutPlansReq PUT /api/pk/plans 请求体：快照四字段整体替换。
type PutPlansReq struct {
	Plans         pk.PlanList              `json:"plans"`
	ActivePlanId  string                   `json:"activePlanId"`
	MajorSelected pk.MajorSelectionPayload `json:"majorSelected"`
	WeekView      pk.WeekViewPayload       `json:"weekView"`
}

// PutPlans PUT /api/pk/plans：整体快照 upsert。服务端浅校验（方案数 1..10、
// id/name 非空、activePlanId 引用、1MB 体积），深度 sanitize 留在客户端加载路径。
// updated_at 服务端时钟在保存时刷新，响应带回供客户端更新 pk.syncedAt。
func PutPlans(req Request[PutPlansReq]) Response {
	if req.UserId == 0 {
		return BadRequest("缺少登录态")
	}
	params := req.Params
	if err := pkservice.ValidatePlanSnapshot(params.Plans, params.ActivePlanId); err != nil {
		return BadRequest(err.Error())
	}
	if err := pkservice.ValidatePlanSnapshotSize(pkservice.PlanSnapshotPayload{
		Plans:         params.Plans,
		ActivePlanId:  params.ActivePlanId,
		MajorSelected: params.MajorSelected,
		WeekView:      params.WeekView,
	}); err != nil {
		return BadRequest(err.Error())
	}
	entity := &pk.ScheduleSnapshotEntity{
		UserId:        req.UserId,
		Plans:         params.Plans,
		ActivePlanId:  params.ActivePlanId,
		MajorSelected: params.MajorSelected,
		WeekView:      params.WeekView,
	}
	if err := pk.UpsertScheduleSnapshot(entity); err != nil {
		return Internal("保存排课方案失败")
	}
	return Ok(PlansPutResponse{
		UpdatedAt: entity.UpdatedAt.UTC().Format(time.RFC3339Nano),
	})
}

// DeletePlans DELETE /api/pk/plans：清除云端副本（保留本地），幂等。
func DeletePlans(req Request[Null]) Response {
	if req.UserId == 0 {
		return BadRequest("缺少登录态")
	}
	if err := pk.DeleteScheduleSnapshotByUser(req.UserId); err != nil {
		return Internal("删除排课方案失败")
	}
	return Ok(map[string]bool{"deleted": true})
}

// PlansSnapshotResponse GET /api/pk/plans 的 data（成功且云端有快照时）。
type PlansSnapshotResponse struct {
	Plans         pk.PlanList              `json:"plans"`
	ActivePlanId  string                   `json:"activePlanId"`
	MajorSelected pk.MajorSelectionPayload `json:"majorSelected"`
	WeekView      pk.WeekViewPayload       `json:"weekView"`
	// UpdatedAt 服务端权威同步时钟（RFC3339 纳秒精度 UTC）；客户端存为
	// pk.syncedAt，下次进页与云端比对决定是否弹冲突窗。
	UpdatedAt string `json:"updatedAt"`
}

// PlansPutResponse PUT /api/pk/plans 的 data。
type PlansPutResponse struct {
	UpdatedAt string `json:"updatedAt"`
}
