import SwiftUI
import WidgetKit

private let appGroupIdentifier = "group.com.family.checky.mobile"
private let widgetKind = "CheckyHomeWidget"

struct CheckyHomeWidgetScheduleItem: Identifiable {
  let id: Int
  let startsAt: String
  let endsAt: String
  let title: String
  let memberName: String
}

struct CheckyHomeWidgetEntry: TimelineEntry {
  let date: Date
  let title: String
  let weekday: String
  let day: String
  let fullDate: String
  let items: [CheckyHomeWidgetScheduleItem]
  let moreCount: Int
}

struct CheckyHomeWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> CheckyHomeWidgetEntry {
    exampleEntry
  }

  func getSnapshot(in context: Context, completion: @escaping (CheckyHomeWidgetEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CheckyHomeWidgetEntry>) -> Void) {
    completion(Timeline(entries: [entry()], policy: .never))
  }

  private func entry() -> CheckyHomeWidgetEntry {
    let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    let count = defaults.integer(forKey: "schedule.itemCount").clamped(to: 0...5)
    let items = (0..<count).compactMap { index -> CheckyHomeWidgetScheduleItem? in
      guard let title = defaults.string(forKey: "schedule.item.\(index).title"), !title.isEmpty else {
        return nil
      }
      return CheckyHomeWidgetScheduleItem(
        id: index,
        startsAt: defaults.string(forKey: "schedule.item.\(index).startsAt") ?? "종일",
        endsAt: defaults.string(forKey: "schedule.item.\(index).endsAt") ?? "",
        title: title,
        memberName: defaults.string(forKey: "schedule.item.\(index).memberName") ?? ""
      )
    }
    return CheckyHomeWidgetEntry(
      date: Date(),
      title: defaults.string(forKey: "schedule.title")?.nonEmpty ?? "체키 오늘 일정",
      weekday: defaults.string(forKey: "schedule.weekday")?.nonEmpty ?? "오늘",
      day: defaults.string(forKey: "schedule.day")?.nonEmpty ?? "",
      fullDate: defaults.string(forKey: "schedule.fullDate")?.nonEmpty ?? "오늘",
      items: items,
      moreCount: defaults.integer(forKey: "schedule.moreCount")
    )
  }

  private var exampleEntry: CheckyHomeWidgetEntry {
    CheckyHomeWidgetEntry(
      date: Date(),
      title: "체키 오늘 일정",
      weekday: "목요일",
      day: "20",
      fullDate: "8월 20일 목요일",
      items: [
        CheckyHomeWidgetScheduleItem(id: 0, startsAt: "09:00", endsAt: "09:50", title: "가족 일정", memberName: "엄마"),
        CheckyHomeWidgetScheduleItem(id: 1, startsAt: "14:00", endsAt: "15:00", title: "약속", memberName: "아빠"),
      ],
      moreCount: 1
    )
  }
}

struct CheckyHomeWidgetView: View {
  @Environment(\.widgetFamily) private var widgetFamily

  let entry: CheckyHomeWidgetEntry

  private var isSmall: Bool { widgetFamily == .systemSmall }
  private var displayedItems: [CheckyHomeWidgetScheduleItem] {
    Array(entry.items.prefix(isSmall ? 2 : 5))
  }
  private var displayedMoreCount: Int {
    entry.moreCount + max(entry.items.count - displayedItems.count, 0)
  }
  private func timeText(for item: CheckyHomeWidgetScheduleItem) -> String {
    if isSmall || item.endsAt.isEmpty {
      return item.startsAt
    }
    return "\(item.startsAt) - \(item.endsAt)"
  }

  @ViewBuilder
  private func eventCard(_ item: CheckyHomeWidgetScheduleItem) -> some View {
    HStack(spacing: isSmall ? 4 : 6) {
      RoundedRectangle(cornerRadius: 3, style: .continuous)
        .fill(Color(red: 0.76, green: 0.54, blue: 0.40))
        .frame(width: 3)

      if isSmall {
        Text(timeText(for: item))
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(Color(red: 0.53, green: 0.38, blue: 0.31))
          .frame(width: 31, alignment: .leading)
          .lineLimit(1)
        Text(item.title)
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(Color(red: 0.29, green: 0.20, blue: 0.16))
          .lineLimit(1)
      } else {
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 3) {
            Text(item.title)
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(Color(red: 0.29, green: 0.20, blue: 0.16))
              .lineLimit(1)
            Spacer(minLength: 0)
            if !item.memberName.isEmpty {
              Text(item.memberName)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color(red: 0.53, green: 0.38, blue: 0.31))
                .lineLimit(1)
            }
          }
          Text(timeText(for: item))
            .font(.system(size: 9, weight: .regular))
            .foregroundStyle(Color(red: 0.53, green: 0.38, blue: 0.31))
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, isSmall ? 4 : 5)
    .padding(.vertical, isSmall ? 3 : 3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(red: 0.98, green: 0.96, blue: 0.95))
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private var dateColumn: some View {
    VStack(alignment: .leading, spacing: -3) {
      Text(entry.weekday)
        .font(.system(size: isSmall ? 13 : 14, weight: .bold))
        .foregroundStyle(Color(red: 0.18, green: 0.13, blue: 0.10))
        .lineLimit(1)
      Text(entry.day)
        .font(.system(size: isSmall ? 38 : 40, weight: .regular))
        .foregroundStyle(Color(red: 0.10, green: 0.08, blue: 0.07))
    }
  }

  @ViewBuilder
  private var eventList: some View {
    if entry.items.isEmpty {
      Text("오늘 등록된 일정이 없습니다.")
        .font(.system(size: isSmall ? 8 : 10))
        .foregroundStyle(.secondary)
        .frame(maxHeight: .infinity, alignment: .center)
    } else {
      ForEach(displayedItems) { item in
        eventCard(item)
      }
    }

    if displayedMoreCount > 0 {
      Text("더 보기 +\(displayedMoreCount)개")
        .font(.system(size: isSmall ? 8 : 9, weight: .bold))
        .foregroundStyle(Color(red: 0.60, green: 0.41, blue: 0.30))
    }
  }

  var body: some View {
    Group {
      if isSmall {
        VStack(alignment: .leading, spacing: 0) {
          dateColumn
          VStack(alignment: .leading, spacing: 3) {
            eventList
          }
          .padding(.top, 8)
          Spacer(minLength: 0)
        }
      } else {
        HStack(alignment: .top, spacing: 9) {
          dateColumn
            .frame(width: 48, alignment: .leading)
          VStack(alignment: .leading, spacing: 3) {
            Text(entry.fullDate)
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(Color(red: 0.51, green: 0.49, blue: 0.48))
              .lineLimit(1)
            eventList
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(isSmall ? 8 : 10)
    .widgetBackground()
  }
}

@main
struct CheckyHomeWidgetBundle: WidgetBundle {
  var body: some Widget { CheckyHomeWidget() }
}

struct CheckyHomeWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: widgetKind, provider: CheckyHomeWidgetProvider()) { entry in
      CheckyHomeWidgetView(entry: entry)
    }
    .configurationDisplayName("체키 오늘 일정")
    .description("오늘 등록된 일정을 빠르게 확인합니다.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private extension View {
  @ViewBuilder
  func widgetBackground() -> some View {
    let color = Color(red: 0.84, green: 0.95, blue: 0.93)
    if #available(iOS 17.0, *) {
      containerBackground(for: .widget) { color }
    } else {
      background(color)
    }
  }
}

private extension String {
  var nonEmpty: String? { isEmpty ? nil : self }
}

private extension Int {
  func clamped(to range: ClosedRange<Int>) -> Int {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
