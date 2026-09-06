package defaultconfig

import (
	"strings"
	"testing"

	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/models/forum/pageConfig"
)

func TestPageConfigDefaultsLoad(t *testing.T) {
	defaults, err := loadPageConfigDefaults()
	if err != nil {
		t.Fatalf("load page config defaults: %v", err)
	}
	if defaults.Site.SiteName != "YourTJHub" {
		t.Fatalf("site name = %q, want YourTJHub", defaults.Site.SiteName)
	}
	if len(defaults.FriendLinks) == 0 {
		t.Fatal("friend links defaults should not be empty")
	}
	if len(defaults.Sponsors.Rules) == 0 {
		t.Fatal("sponsor rules defaults should not be empty")
	}
	if defaults.Posting.UploadControl.MaxAttachmentSizeKb == 0 {
		t.Fatal("posting max attachment size should not be zero")
	}
	if !defaults.Terms.Enabled || defaults.Terms.Content == "" {
		t.Fatal("terms defaults should be enabled with content")
	}
	for _, needle := range []string{"30", "恢复", "治理"} {
		if !strings.Contains(defaults.Terms.Content, needle) {
			t.Fatalf("terms content missing %q: %q", needle, defaults.Terms.Content)
		}
	}
	if !defaults.Privacy.Enabled || defaults.Privacy.Content == "" {
		t.Fatal("privacy defaults should be enabled with content")
	}
	for _, needle := range []string{"30", "恢复", "治理", "6 个月", "网络"} {
		if !strings.Contains(defaults.Privacy.Content, needle) {
			t.Fatalf("privacy content missing %q: %q", needle, defaults.Privacy.Content)
		}
	}
}

func TestPageConfigDefaultGettersReturnCopies(t *testing.T) {
	links := GetDefaultFriendLinksConfig()
	links[0].Links[0].Name = "changed"
	if got := GetDefaultFriendLinksConfig()[0].Links[0].Name; got == "changed" {
		t.Fatal("friend links getter returned shared mutable data")
	}

	site := GetDefaultSiteSettingsConfig()
	site.SiteName = "changed"
	if got := GetDefaultSiteSettingsConfig().SiteName; got == "changed" {
		t.Fatal("site settings getter returned shared mutable data")
	}

	chrome := GetDefaultSiteChromeConfig()
	chrome.FooterInfo.List[0].Name = "changed"
	if got := GetDefaultSiteChromeConfig().FooterInfo.List[0].Name; got == "changed" {
		t.Fatal("site chrome getter returned shared mutable footer data")
	}

	sponsors := GetDefaultSponsorsConfig()
	sponsors.Rules[0].Content = "changed"
	if got := GetDefaultSponsorsConfig().Rules[0].Content; got == "changed" {
		t.Fatal("sponsors getter returned shared mutable rules")
	}
}

func TestNormalizeStoredScheduleSettings(t *testing.T) {
	rows := func(pairs ...[3]string) []pageConfig.ScheduleSectionTime {
		times := make([]pageConfig.ScheduleSectionTime, 0, len(pairs))
		for i, p := range pairs {
			times = append(times, pageConfig.ScheduleSectionTime{Section: i + 1, Start: p[0], End: p[1]})
		}
		return times
	}
	sections := func(times []pageConfig.ScheduleSectionTime) map[int]pageConfig.ScheduleSectionTime {
		out := make(map[int]pageConfig.ScheduleSectionTime, len(times))
		for _, item := range times {
			out[item.Section] = item
		}
		return out
	}

	t.Run("存量旧 12 节默认表（第 9 节 17:10）按旧编号重映射", func(t *testing.T) {
		legacy := pageConfig.ScheduleSettingsConfig{SectionTimes: rows(
			[3]string{"08:00", "08:45"}, [3]string{"08:50", "09:35"}, [3]string{"10:00", "10:45"},
			[3]string{"10:50", "11:35"}, [3]string{"13:30", "14:15"}, [3]string{"14:20", "15:05"},
			[3]string{"15:30", "16:15"}, [3]string{"16:20", "17:05"}, [3]string{"17:10", "17:55"},
			[3]string{"18:30", "19:15"}, [3]string{"19:20", "20:05"}, [3]string{"20:10", "20:55"},
		)}
		got := sections(NormalizeStoredScheduleSettings(legacy).SectionTimes)
		if len(got) != 11 {
			t.Fatalf("normalized rows = %d, want 11", len(got))
		}
		want := map[int][2]string{9: {"18:30", "19:15"}, 10: {"19:20", "20:05"}, 11: {"20:10", "20:55"}}
		for section, times := range want {
			item, ok := got[section]
			if !ok || item.Start != times[0] || item.End != times[1] {
				t.Fatalf("normalized section %d = %#v, want %v", section, item, times)
			}
		}
		for _, item := range got {
			if item.Start == "17:10" {
				t.Fatalf("legacy 17:10 row survived normalization: %#v", got)
			}
		}
	})

	t.Run("旧 12 节配置的白天自定义行在重映射后保留", func(t *testing.T) {
		legacy := pageConfig.ScheduleSettingsConfig{SectionTimes: rows(
			[3]string{"08:30", "09:15"}, [3]string{"08:50", "09:35"}, [3]string{"10:00", "10:45"},
			[3]string{"10:50", "11:35"}, [3]string{"13:30", "14:15"}, [3]string{"14:20", "15:05"},
			[3]string{"15:30", "16:15"}, [3]string{"16:20", "17:05"}, [3]string{"17:10", "17:55"},
			[3]string{"18:30", "19:15"}, [3]string{"19:20", "20:05"}, [3]string{"20:10", "20:55"},
		)}
		got := sections(NormalizeStoredScheduleSettings(legacy).SectionTimes)
		if item := got[1]; item.Start != "08:30" {
			t.Fatalf("custom daytime row lost: %#v", item)
		}
		if item := got[9]; item.Start != "18:30" {
			t.Fatalf("legacy evening not remapped: %#v", item)
		}
	})

	t.Run("现行 11 节语义的存量（含重复第 12 行）按新编号读取并丢弃 >11 节行", func(t *testing.T) {
		stored := pageConfig.ScheduleSettingsConfig{SectionTimes: rows(
			[3]string{"08:00", "08:45"}, [3]string{"08:50", "09:35"}, [3]string{"10:00", "10:45"},
			[3]string{"10:50", "11:35"}, [3]string{"13:30", "14:15"}, [3]string{"14:20", "15:05"},
			[3]string{"15:30", "16:15"}, [3]string{"16:20", "17:05"}, [3]string{"18:30", "19:15"},
			[3]string{"19:20", "20:05"}, [3]string{"20:10", "20:55"}, [3]string{"20:10", "20:55"},
		)}
		got := NormalizeStoredScheduleSettings(stored).SectionTimes
		if len(got) != 11 {
			t.Fatalf("normalized rows = %d, want 11", len(got))
		}
		if item := got[8]; item.Section != 9 || item.Start != "18:30" {
			t.Fatalf("new-numbered row 9 shifted: %#v", item)
		}
	})

	t.Run("空配置原样返回", func(t *testing.T) {
		empty := pageConfig.ScheduleSettingsConfig{}
		if got := NormalizeStoredScheduleSettings(empty); len(got.SectionTimes) != 0 {
			t.Fatalf("empty config changed: %#v", got)
		}
	})
}
