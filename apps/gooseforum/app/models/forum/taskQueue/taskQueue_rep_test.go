package taskQueue

import (
	"testing"
	"time"

	db "github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/bundles/connect/dbconnect"
)

// 任务族谓词必须同时命中「族常量」行（新写入的 "webpush."）与历史
// 「族 + id」行（"webpush.123"）：升级后存量 Pending 推送任务仍要被领取，
// 不能被新格式的谓词排除在队列外永久卡住。
func TestTypeFamilyQueryMatchesConstantAndSuffixedTypes(t *testing.T) {
	conn := db.Connect()
	if err := conn.AutoMigrate(&Entity{}); err != nil {
		t.Fatalf("migrate task queue: %v", err)
	}
	conn.Where("type LIKE ?", "testfamily%").Delete(&Entity{})

	legacy := &Entity{Type: "testfamily.7", TaskJson: "{}"}
	current := &Entity{Type: "testfamily.", TaskJson: "{}"}
	other := &Entity{Type: "otherfamily.1", TaskJson: "{}"}
	for _, task := range []*Entity{legacy, current, other} {
		if err := conn.Create(task).Error; err != nil {
			t.Fatalf("create %q: %v", task.Type, err)
		}
	}

	claimed := map[uint64]bool{}
	for _, task := range GetPendingTasksByType("testfamily.", 10) {
		claimed[task.Id] = true
	}
	if !claimed[legacy.Id] || !claimed[current.Id] {
		t.Fatalf("family query missed a family row: %+v", claimed)
	}
	if claimed[other.Id] {
		t.Fatal("family query claimed another family")
	}

	// 终态清理走同一谓词：只删本族终态行。
	if err := conn.Model(legacy).Update("status", StatusSuccess).Error; err != nil {
		t.Fatal(err)
	}
	if err := conn.Model(current).Update("status", StatusSuccess).Error; err != nil {
		t.Fatal(err)
	}
	deleted, err := DeleteTerminalByTypePrefix("testfamily.", []int{StatusSuccess}, time.Now().Add(time.Minute), 10)
	if err != nil {
		t.Fatal(err)
	}
	if deleted != 2 {
		t.Fatalf("deleted %d terminal rows, want 2", deleted)
	}
	var remaining int64
	conn.Model(&Entity{}).Where("type LIKE ?", "testfamily%").Count(&remaining)
	if remaining != 0 {
		t.Fatalf("%d family rows survived terminal cleanup", remaining)
	}
	conn.Where("type LIKE ?", "otherfamily%").Delete(&Entity{})
}

// TypePrefix 是「族 + id」与「族常量」两种行共用的族提取器。
func TestTypePrefixKeepsFamilySeparator(t *testing.T) {
	for _, tc := range []struct{ taskType, want string }{
		{"webpush.9002", "webpush."},
		{"webpush.", "webpush."},
		{"search-maintenance", ""},
	} {
		if got := TypePrefix(tc.taskType); got != tc.want {
			t.Errorf("TypePrefix(%q) = %q, want %q", tc.taskType, got, tc.want)
		}
	}
}
