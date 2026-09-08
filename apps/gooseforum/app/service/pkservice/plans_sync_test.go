package pkservice

import (
	"strings"
	"testing"

	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/models/forum/pk"
)

// makeValidPlanList 构造 n 套结构合法的方案（id/name 齐全）。
func makeValidPlanList(n int) pk.PlanList {
	plans := make(pk.PlanList, 0, n)
	for i := 1; i <= n; i++ {
		plans = append(plans, pk.PlanPayload{
			Id:              "plan-test-" + strings.Repeat("x", i),
			Name:            "方案 " + string(rune('0'+i)),
			CreatedAt:       1725000000000,
			StagedCourses:   []pk.StagedCoursePayload{},
			SelectedCourses: []string{},
			CustomEvents:    []pk.CustomEventPayload{},
		})
	}
	return plans
}

func TestValidatePlanSnapshotAcceptsSinglePlan(t *testing.T) {
	plans := makeValidPlanList(1)
	if err := ValidatePlanSnapshot(plans, plans[0].Id); err != nil {
		t.Fatalf("single plan snapshot should be valid: %v", err)
	}
}

func TestValidatePlanSnapshotAcceptsMaxPlans(t *testing.T) {
	plans := makeValidPlanList(MaxPlansPerSnapshot)
	if err := ValidatePlanSnapshot(plans, plans[len(plans)-1].Id); err != nil {
		t.Fatalf("max plans snapshot should be valid: %v", err)
	}
}

func TestValidatePlanSnapshotRejectsEmptyPlans(t *testing.T) {
	if err := ValidatePlanSnapshot(pk.PlanList{}, "plan-x"); err == nil {
		t.Fatal("empty plans should be rejected")
	}
}

func TestValidatePlanSnapshotRejectsOverLimit(t *testing.T) {
	plans := makeValidPlanList(MaxPlansPerSnapshot + 1)
	if err := ValidatePlanSnapshot(plans, plans[0].Id); err == nil {
		t.Fatal("over-limit plans should be rejected")
	}
}

func TestValidatePlanSnapshotRejectsBlankPlanIdentity(t *testing.T) {
	plans := makeValidPlanList(2)
	plans[1].Id = ""
	if err := ValidatePlanSnapshot(plans, plans[0].Id); err == nil {
		t.Fatal("plan with blank id should be rejected")
	}

	plans2 := makeValidPlanList(2)
	plans2[1].Name = "   "
	if err := ValidatePlanSnapshot(plans2, plans2[0].Id); err == nil {
		t.Fatal("plan with blank name should be rejected")
	}
}

func TestValidatePlanSnapshotRejectsDanglingActivePlanId(t *testing.T) {
	plans := makeValidPlanList(2)
	if err := ValidatePlanSnapshot(plans, "plan-not-exist"); err == nil {
		t.Fatal("activePlanId pointing outside plans should be rejected")
	}
}

func TestValidatePlanSnapshotSize(t *testing.T) {
	plans := makeValidPlanList(3)
	payload := PlanSnapshotPayload{
		Plans:         plans,
		ActivePlanId:  plans[0].Id,
		MajorSelected: pk.MajorSelectionPayload{},
		WeekView:      pk.WeekViewPayload{},
	}
	if err := ValidatePlanSnapshotSize(payload); err != nil {
		t.Fatalf("small payload should pass size check: %v", err)
	}

	// 体积上限：构造超过 1MB 的负载（大量课程行）。
	huge := make(pk.PlanList, MaxPlansPerSnapshot)
	for i := range huge {
		courses := make([]pk.StagedCoursePayload, 200)
		for j := range courses {
			courses[j] = pk.StagedCoursePayload{
				CourseCode: "1000" + strings.Repeat("f", 64),
				CourseName: strings.Repeat("课", 32),
				Teacher:    []pk.TeacherPayload{{TeacherName: strings.Repeat("师", 32), TeacherCode: strings.Repeat("T", 32)}},
				CourseDetail: []pk.CourseDetailPayload{{
					Code:     strings.Repeat("c", 64),
					Campus:   strings.Repeat("校区", 16),
					Teachers: []pk.TeacherPayload{{TeacherName: strings.Repeat("师", 32), TeacherCode: strings.Repeat("T", 32)}},
					ArrangementInfo: []pk.ArrangementPayload{{
						ArrangementText: strings.Repeat("安排", 32),
						OccupyDay:       1,
						OccupyTime:      []int{1, 2, 3, 4},
						OccupyWeek:      []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16},
						OccupyRoom:      strings.Repeat("楼", 32),
						TeacherAndCode:  strings.Repeat("师(T0000)", 16),
					}},
				}},
			}
		}
		huge[i] = pk.PlanPayload{
			Id:              "plan-huge-" + strings.Repeat("x", i+1),
			Name:            "方案",
			CreatedAt:       1725000000000,
			StagedCourses:   courses,
			SelectedCourses: []string{},
			CustomEvents:    []pk.CustomEventPayload{},
		}
	}
	hugePayload := PlanSnapshotPayload{Plans: huge, ActivePlanId: huge[0].Id}
	if err := ValidatePlanSnapshotSize(hugePayload); err == nil {
		t.Fatal("oversized payload should be rejected")
	}
}
