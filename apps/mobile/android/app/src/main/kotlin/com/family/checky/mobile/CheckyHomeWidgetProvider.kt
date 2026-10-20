package com.family.checky.mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONObject

class CheckyHomeWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (
            intent.action == Intent.ACTION_DATE_CHANGED ||
            intent.action == Intent.ACTION_TIME_CHANGED ||
            intent.action == Intent.ACTION_TIMEZONE_CHANGED ||
            intent.action == Intent.ACTION_CONFIGURATION_CHANGED
        ) {
            updateAll(context)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId -> updateWidget(context, appWidgetManager, appWidgetId) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    companion object {
        private const val preferencesName = "HomeWidgetPreferences"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val componentName = android.content.ComponentName(context, CheckyHomeWidgetProvider::class.java)
            manager.getAppWidgetIds(componentName).forEach { appWidgetId ->
                updateWidget(context, manager, appWidgetId)
            }
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            val palette = widgetPalette(context, preferences)
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            val schedulePrefix = if (
                preferences.getString("nextSchedule.snapshotDate", "") == today
            ) {
                "nextSchedule"
            } else {
                "schedule"
            }
            val savedItemCount = preferences.getInt("$schedulePrefix.itemCount", 0).coerceIn(0, 5)
            val isCompact = appWidgetManager.getAppWidgetOptions(appWidgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250) < 200
            val limit = if (isCompact) 2 else 3
            val itemCount = savedItemCount.coerceAtMost(limit)
            val moreCount = preferences.getInt("$schedulePrefix.moreCount", 0) + (savedItemCount - itemCount)
            val views = RemoteViews(
                context.packageName,
                if (isCompact) R.layout.checky_home_widget_compact else R.layout.checky_home_widget,
            )

            // ImageView color filters are RemoteViews-safe on old Android too,
            // and tint the existing rounded shapes without replacing their corners.
            views.setInt(R.id.widget_background, "setColorFilter", palette.background)
            views.setTextColor(R.id.widget_schedule_heading, palette.primary)
            views.setTextColor(R.id.widget_parking_heading, palette.primary)
            views.setInt(R.id.widget_section_divider, "setBackgroundColor", palette.border)
            views.setTextViewText(R.id.widget_schedule_heading, heading("오늘 일정", moreCount))
            views.removeAllViews(R.id.widget_schedule_list)
            if (itemCount == 0) {
                val empty = RemoteViews(context.packageName, R.layout.checky_home_widget_empty)
                empty.setTextColor(R.id.widget_empty_message, palette.textSecondary)
                views.addView(R.id.widget_schedule_list, empty)
            } else {
                repeat(itemCount) { index ->
                    val startsAt = preferences.getString("$schedulePrefix.item.$index.startsAt", "") ?: ""
                    val endsAt = preferences.getString("$schedulePrefix.item.$index.endsAt", "") ?: ""
                    val title = preferences.getString("$schedulePrefix.item.$index.title", "") ?: ""
                    val memberName = preferences.getString("$schedulePrefix.item.$index.memberName", "") ?: ""
                    val memberColor = preferences.getString(
                        "$schedulePrefix.item.$index.memberColor",
                        "gray",
                    ) ?: "gray"
                    val item = RemoteViews(
                        context.packageName,
                        if (isCompact) R.layout.checky_home_widget_line else R.layout.checky_home_widget_item_safe,
                    )
                    styleRow(item, palette)
                    val timeText = if (isCompact || endsAt.isBlank()) startsAt else "$startsAt - $endsAt"
                    item.setTextViewText(
                        R.id.widget_item_summary,
                        scheduleSummary(
                            timeText = timeText,
                            title = title,
                            memberName = memberName,
                            memberColor = memberColor,
                            isCompact = isCompact,
                            secondaryColor = palette.textSecondary,
                        ),
                    )
                    views.addView(R.id.widget_schedule_list, item)
                }
            }
            val savedParkingCount = preferences.getInt("parking.itemCount", 0).coerceIn(0, 5)
            // GONE also removes layout weight and divider margins, so the remaining
            // section fills the widget. Keep both empty-state messages when neither exists.
            val showSchedule = savedItemCount > 0 || savedParkingCount == 0
            val showParking = savedParkingCount > 0 || savedItemCount == 0
            views.setViewVisibility(R.id.widget_schedule_section, if (showSchedule) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_parking_section, if (showParking) View.VISIBLE else View.GONE)
            views.setViewVisibility(
                R.id.widget_section_divider,
                if (showSchedule && showParking) View.VISIBLE else View.GONE,
            )
            val parkingCount = savedParkingCount.coerceAtMost(limit)
            val parkingMore = preferences.getInt("parking.moreCount", 0) + savedParkingCount - parkingCount
            views.setTextViewText(R.id.widget_parking_heading, heading("주차 위치", parkingMore))
            views.removeAllViews(R.id.widget_parking_list)
            if (parkingCount == 0) {
                val empty = RemoteViews(context.packageName, R.layout.checky_home_widget_line)
                styleRow(empty, palette)
                empty.setTextColor(R.id.widget_item_summary, palette.textSecondary)
                empty.setTextViewText(R.id.widget_item_summary, "등록된 주차 위치가 없습니다.")
                views.addView(R.id.widget_parking_list, empty)
            } else {
                repeat(parkingCount) { index ->
                    val name = preferences.getString("parking.item.$index.vehicleName", "차량") ?: "차량"
                    val location = preferences.getString("parking.item.$index.location", "") ?: ""
                    val row = RemoteViews(
                        context.packageName,
                        if (isCompact) R.layout.checky_home_widget_line else R.layout.checky_home_widget_item_safe,
                    )
                    styleRow(row, palette)
                    row.setTextViewText(
                        R.id.widget_item_summary,
                        if (isCompact) "$name · $location" else "$name\n$location",
                    )
                    views.addView(R.id.widget_parking_list, row)
                }
            }
            val font = runCatching {
                JSONObject(preferences.getString("appearance", "") ?: "").optString("font", "system")
            }.getOrDefault("system")
            val displayViews = CheckyWidgetFontRenderer.render(
                context, views, appWidgetManager.getAppWidgetOptions(appWidgetId), font,
            )
            displayViews.setOnClickPendingIntent(
                R.id.widget_content,
                PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            appWidgetManager.updateAppWidget(appWidgetId, displayViews)
        }

        private fun heading(title: String, moreCount: Int): String =
            if (moreCount > 0) "$title  +$moreCount" else title

        private data class WidgetPalette(
            val background: Int,
            val surface: Int,
            val primary: Int,
            val textPrimary: Int,
            val textSecondary: Int,
            val border: Int,
        )

        private fun widgetPalette(context: Context, preferences: SharedPreferences): WidgetPalette {
            val appearance = runCatching { JSONObject(preferences.getString("appearance", "") ?: "") }
                .getOrNull()
            val dark = when (appearance?.optString("mode")) {
                "light" -> false
                "dark" -> true
                else -> context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
                    Configuration.UI_MODE_NIGHT_YES
            }
            val values = appearance?.optJSONObject(if (dark) "dark" else "light")
            val fallback = if (dark) {
                longArrayOf(0xFF244A40, 0xFF182725, 0xFF75DAC5, 0xFFF0FCF7, 0xFFC3D9D0, 0xFF365148)
            } else {
                longArrayOf(0xFFD5EEE7, 0xFFF8FFFC, 0xFF067168, 0xFF142E29, 0xFF405F56, 0xFFC8DED5)
            }
            fun color(key: String, index: Int) = (values?.optLong(key, fallback[index]) ?: fallback[index]).toInt()
            return WidgetPalette(
                color("background", 0), color("surface", 1), color("primary", 2),
                color("textPrimary", 3), color("textSecondary", 4), color("border", 5),
            )
        }

        private fun styleRow(row: RemoteViews, palette: WidgetPalette) {
            row.setInt(R.id.widget_item_background, "setColorFilter", palette.surface)
            row.setTextColor(R.id.widget_item_summary, palette.textPrimary)
        }

        private fun scheduleSummary(
            timeText: String,
            title: String,
            memberName: String,
            memberColor: String,
            isCompact: Boolean,
            secondaryColor: Int,
        ): CharSequence {
            val color = memberColorValue(memberColor)
            return SpannableStringBuilder().apply {
                val accentStart = length
                append("▌ ")
                setSpan(
                    ForegroundColorSpan(color),
                    accentStart,
                    length,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
                if (isCompact) {
                    val timeStart = length
                    append("$timeText  $title")
                    setSpan(ForegroundColorSpan(secondaryColor), timeStart, timeStart + timeText.length,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    return@apply
                }
                if (title.isNotBlank()) {
                    append(title)
                } else {
                    val timeStart = length
                    append(timeText)
                    setSpan(ForegroundColorSpan(secondaryColor), timeStart, length,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
                if (!isCompact && title.isNotBlank() && memberName.isNotBlank()) {
                    append(" ")
                    val badgeStart = length
                    append(" ")
                    append(memberName)
                    append(" ")
                    setSpan(
                        BackgroundColorSpan(color),
                        badgeStart,
                        length,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                    setSpan(
                        ForegroundColorSpan(
                            if (memberColor == "yellow") Color.rgb(61, 47, 0) else Color.WHITE,
                        ),
                        badgeStart,
                        length,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                }
                if (title.isNotBlank()) {
                    append("\n")
                    val timeStart = length
                    append(timeText)
                    setSpan(
                        ForegroundColorSpan(secondaryColor),
                        timeStart,
                        length,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                    setSpan(
                        StyleSpan(Typeface.NORMAL),
                        timeStart,
                        length,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                }
            }
        }

        private fun memberColorValue(color: String): Int = when (color) {
            "red" -> Color.rgb(229, 57, 53)
            "blue" -> Color.rgb(30, 136, 229)
            "green" -> Color.rgb(67, 160, 71)
            "orange" -> Color.rgb(251, 140, 0)
            "purple" -> Color.rgb(142, 36, 170)
            "pink" -> Color.rgb(216, 27, 96)
            "teal" -> Color.rgb(0, 137, 123)
            "yellow" -> Color.rgb(253, 216, 53)
            "indigo" -> Color.rgb(57, 73, 171)
            "mint" -> Color.rgb(0, 172, 193)
            else -> Color.rgb(107, 114, 128)
        }
    }
}
