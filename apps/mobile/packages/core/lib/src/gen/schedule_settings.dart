/// 排课器节次作息契约镜像（`GET /api/pk/section-times` 的 data）。
///
/// 手写维护；与后端响应形状一致。服务端未配置时返回内置默认表
/// （与 mobile `pk_section_times.dart` 的 kDefaultSectionTimes12 同源）。
library;

/// 单个节次的起止时间（HH:MM）。
class SectionTimeSetting {
  const SectionTimeSetting({
    required this.section,
    required this.start,
    required this.end,
  });

  final int section;
  final String start;
  final String end;

  factory SectionTimeSetting.fromJson(Map<String, dynamic> json) =>
      SectionTimeSetting(
        section: (json['section'] as num?)?.toInt() ?? 0,
        start: json['start'] as String? ?? '',
        end: json['end'] as String? ?? '',
      );
}

/// GET /api/pk/section-times 响应 data。
class SectionTimesPayload {
  const SectionTimesPayload({
    required this.sectionTimes,
    required this.maxRowsDefault,
  });

  final List<SectionTimeSetting> sectionTimes;

  /// 默认行数（恒 12；11 节新制由客户端按 calendarId>=120 裁剪）。
  final int maxRowsDefault;

  factory SectionTimesPayload.fromJson(Map<String, dynamic> json) =>
      SectionTimesPayload(
        sectionTimes: (json['sectionTimes'] as List<dynamic>? ?? const [])
            .map(
              (e) => SectionTimeSetting.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        maxRowsDefault: (json['maxRowsDefault'] as num?)?.toInt() ?? 12,
      );
}
