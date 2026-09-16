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
  let memberColor: String
}

struct CheckyHomeWidgetParkingItem: Identifiable {
  let id: Int
  let vehicleName: String
  let location: String
}

struct CheckyHomeWidgetEntry: TimelineEntry {
  let date: Date
  let title: String
  let weekday: String
  let day: String
  let fullDate: String
  let items: [CheckyHomeWidgetScheduleItem]
  let moreCount: Int
  var parkingItems: [CheckyHomeWidgetParkingItem] = []
  var parkingMoreCount: Int = 0
}

struct CheckyHomeWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> CheckyHomeWidgetEntry {
    exampleEntry
  }

  func getSnapshot(in context: Context, completion: @escaping (CheckyHomeWidgetEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CheckyHomeWidgetEntry>) -> Void) {
    let now = Date()
    let nextMidnight = Calendar.current.date(
      byAdding: .day,
      value: 1,
      to: Calendar.current.startOfDay(for: now)
    ) ?? now.addingTimeInterval(24 * 60 * 60)
    completion(
      Timeline(
        entries: [entry(at: now), entry(at: nextMidnight)],
        policy: .after(nextMidnight.addingTimeInterval(60 * 60))
      )
    )
  }

  private func entry(at date: Date = Date()) -> CheckyHomeWidgetEntry {
    let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    let prefix = defaults.string(forKey: "nextSchedule.snapshotDate") == dateKey(date)
      ? "nextSchedule"
      : "schedule"
    let count = defaults.integer(forKey: "\(prefix).itemCount").clamped(to: 0...5)
    let items = (0..<count).compactMap { index -> CheckyHomeWidgetScheduleItem? in
      guard let title = defaults.string(forKey: "\(prefix).item.\(index).title"), !title.isEmpty else {
        return nil
      }
      return CheckyHomeWidgetScheduleItem(
        id: index,
        startsAt: defaults.string(forKey: "\(prefix).item.\(index).startsAt") ?? "종일",
        endsAt: defaults.string(forKey: "\(prefix).item.\(index).endsAt") ?? "",
        title: title,
        memberName: defaults.string(forKey: "\(prefix).item.\(index).memberName") ?? "",
        memberColor: defaults.string(forKey: "\(prefix).item.\(index).memberColor") ?? "gray"
      )
    }
    return CheckyHomeWidgetEntry(
      date: date,
      title: defaults.string(forKey: "\(prefix).title")?.nonEmpty ?? "체키 오늘 일정",
      weekday: defaults.string(forKey: "\(prefix).weekday")?.nonEmpty ?? "오늘",
      day: defaults.string(forKey: "\(prefix).day")?.nonEmpty ?? "",
      fullDate: defaults.string(forKey: "\(prefix).fullDate")?.nonEmpty ?? "오늘",
      items: items,
      moreCount: defaults.integer(forKey: "\(prefix).moreCount"),
      parkingItems: (0..<defaults.integer(forKey: "parking.itemCount").clamped(to: 0...5)).map { index in
        CheckyHomeWidgetParkingItem(
          id: index,
          vehicleName: defaults.string(forKey: "parking.item.\(index).vehicleName") ?? "차량",
          location: defaults.string(forKey: "parking.item.\(index).location") ?? ""
        )
      },
      parkingMoreCount: defaults.integer(forKey: "parking.moreCount")
    )
  }

  private func dateKey(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private var exampleEntry: CheckyHomeWidgetEntry {
    CheckyHomeWidgetEntry(
      date: Date(),
      title: "체키 오늘 일정",
      weekday: "목요일",
      day: "20",
      fullDate: "8월 20일 목요일",
      items: [
        CheckyHomeWidgetScheduleItem(id: 0, startsAt: "09:00", endsAt: "09:50", title: "가족 일정", memberName: "엄마", memberColor: "blue"),
        CheckyHomeWidgetScheduleItem(id: 1, startsAt: "14:00", endsAt: "15:00", title: "약속", memberName: "아빠", memberColor: "orange"),
      ],
      moreCount: 1,
      parkingItems: [
        CheckyHomeWidgetParkingItem(id: 0, vehicleName: "우리 차", location: "아파트 B2 · A구역"),
        CheckyHomeWidgetParkingItem(id: 1, vehicleName: "출퇴근 차", location: "회사 B1 · 12번")
      ]
    )
  }
}

struct CheckyHomeWidgetView: View {
  @Environment(\.widgetFamily) private var widgetFamily

  let entry: CheckyHomeWidgetEntry

  private var isSmall: Bool { widgetFamily == .systemSmall }
  private var displayedItems: [CheckyHomeWidgetScheduleItem] {
    Array(entry.items.prefix(isSmall ? 2 : 3))
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

  private func memberColor(for item: CheckyHomeWidgetScheduleItem) -> Color {
    switch item.memberColor {
    case "red": return Color(red: 0.90, green: 0.22, blue: 0.21)
    case "blue": return Color(red: 0.12, green: 0.53, blue: 0.90)
    case "green": return Color(red: 0.26, green: 0.63, blue: 0.28)
    case "orange": return Color(red: 0.98, green: 0.55, blue: 0.00)
    case "purple": return Color(red: 0.56, green: 0.14, blue: 0.67)
    case "pink": return Color(red: 0.85, green: 0.11, blue: 0.38)
    case "teal": return Color(red: 0.00, green: 0.54, blue: 0.48)
    case "yellow": return Color(red: 0.99, green: 0.85, blue: 0.21)
    case "indigo": return Color(red: 0.22, green: 0.29, blue: 0.67)
    case "mint": return Color(red: 0.00, green: 0.67, blue: 0.76)
    default: return Color(red: 0.42, green: 0.45, blue: 0.50)
    }
  }

  private func memberForegroundColor(for item: CheckyHomeWidgetScheduleItem) -> Color {
    item.memberColor == "yellow"
      ? Color(red: 0.24, green: 0.18, blue: 0.00)
      : .white
  }

  @ViewBuilder
  private func eventCard(_ item: CheckyHomeWidgetScheduleItem) -> some View {
    HStack(spacing: isSmall ? 4 : 6) {
      RoundedRectangle(cornerRadius: 3, style: .continuous)
        .fill(memberColor(for: item))
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
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(memberForegroundColor(for: item))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(memberColor(for: item))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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

  private var displayedParking: [CheckyHomeWidgetParkingItem] {
    Array(entry.parkingItems.prefix(isSmall ? 2 : 3))
  }

  private func heading(_ title: String, more: Int) -> some View {
    HStack(spacing: 2) {
      Text(title).font(.system(size: isSmall ? 10 : 12, weight: .bold))
      Spacer(minLength: 0)
      if more > 0 {
        Text("+\(more)").font(.system(size: 8, weight: .medium))
      }
    }
    .foregroundStyle(Color(red: 0.08, green: 0.38, blue: 0.35))
    .lineLimit(1)
  }

  private var scheduleSection: some View {
    VStack(alignment: .leading, spacing: 3) {
      heading("오늘 일정", more: displayedMoreCount)
      eventList
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var parkingSection: some View {
    VStack(alignment: .leading, spacing: 3) {
      heading("주차 위치", more: entry.parkingMoreCount + entry.parkingItems.count - displayedParking.count)
      if displayedParking.isEmpty {
        Text("등록된 주차 위치가 없습니다.")
          .font(.system(size: isSmall ? 8 : 10))
          .foregroundStyle(.secondary)
      }
      ForEach(displayedParking) { item in
        Group {
          if isSmall {
            HStack(spacing: 4) {
              Text(item.vehicleName).fontWeight(.bold)
                .frame(maxWidth: 44, alignment: .leading)
              Text(item.location).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 9))
          } else {
            VStack(alignment: .leading, spacing: 2) {
              Text(item.vehicleName).font(.system(size: 10, weight: .bold))
              Text(item.location).font(.system(size: 9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .lineLimit(1)
        .foregroundStyle(Color(red: 0.12, green: 0.33, blue: 0.30))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color(red: 0.95, green: 0.99, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private var eventList: some View {
    if entry.items.isEmpty {
      Text("오늘 등록된 일정이 없습니다.")
        .font(.system(size: isSmall ? 8 : 10))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      ForEach(displayedItems) { item in
        eventCard(item)
      }
    }

  }

  var body: some View {
    Group {
      if !entry.items.isEmpty && entry.parkingItems.isEmpty {
        scheduleSection
      } else if entry.items.isEmpty && !entry.parkingItems.isEmpty {
        parkingSection
      } else if isSmall {
        VStack(alignment: .leading, spacing: 5) {
          scheduleSection
          Divider()
          parkingSection
        }
      } else {
        HStack(alignment: .top, spacing: 8) {
          scheduleSection
          Divider()
          parkingSection
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(isSmall ? 0 : 2)
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
    .configurationDisplayName("체키 일정 · 주차")
    .description("오늘 일정과 차량별 주차 위치를 함께 확인합니다.")
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
