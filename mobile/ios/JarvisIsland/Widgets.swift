import SwiftUI
import WidgetKit

/// Настройки виджетов (вид - в Shared/WidgetViews.swift, его же показывает демо приложения).
// MARK: Заметки

struct NotesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nmnh.notes", provider: PultProvider()) { NotesWidgetView(entry: $0) }
            .configurationDisplayName("Заметки")
            .description("Напоминания Джарвис: что запланировано, что ждёт ответа «сделал?», что выполнено.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Деньги

struct MoneyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nmnh.money", provider: PultProvider()) { MoneyWidgetView(entry: $0) }
            .configurationDisplayName("Деньги")
            .description("Комиссия сегодня против плана дня, годовой темп, рефералы, подписки.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Сервер

struct ServerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nmnh.server", provider: PultProvider()) { ServerWidgetView(entry: $0) }
            .configurationDisplayName("Сервер")
            .description("Процессор, память, диск, службы, ошибки и копия базы.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Агенты

struct AgentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nmnh.agents", provider: PultProvider()) { AgentsWidgetView(entry: $0) }
        .configurationDisplayName("Агенты")
        .description("Джарвис, агент на сервере и Claude на ПК: кто работает и над чем.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Задачи и цели

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nmnh.tasks", provider: PultProvider()) { TasksWidgetView(entry: $0) }
        .configurationDisplayName("Задачи и цели")
        .description("Поручения агенту, цели Джарвис и ближайшие точки календаря.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Весь пульт

struct PultWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nmnh.pult", provider: PultProvider()) { PultWidgetView(entry: $0) }
        .configurationDisplayName("Пульт")
        .description("Деньги, сервер, сделки и люди - одним большим виджетом.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Экран блокировки

struct LockMoneyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nmnh.lock.money", provider: PultProvider()) { LockMoneyView(entry: $0) }
        .configurationDisplayName("Комиссия")
        .description("Комиссия сегодня на экране блокировки.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct LockServerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nmnh.lock.server", provider: PultProvider()) { LockServerView(entry: $0) }
        .configurationDisplayName("Сервер")
        .description("Загрузка сервера на экране блокировки.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

