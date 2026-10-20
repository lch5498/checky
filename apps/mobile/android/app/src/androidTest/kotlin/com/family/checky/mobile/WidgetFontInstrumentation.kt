package com.family.checky.mobile

import android.app.Instrumentation
import android.os.Bundle
import android.appwidget.AppWidgetManager
import android.graphics.drawable.BitmapDrawable
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.RemoteViews
import android.view.View
import java.io.File

/** Dependency-free native smoke tests: no Flutter engine, API, or account data. */
class WidgetFontInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        start()
    }

    override fun onStart() {
        val result = Bundle()
        try {
            var checked = 0
            runOnMainSync {
                val fonts = listOf("gowun-dodum", "gowun-batang", "park-dahyun", "poor-story", "incheon-himchan")
                for (compact in listOf(true, false)) {
                    for (state in listOf("both", "schedule", "parking", "empty")) {
                        for (font in fonts) {
                            val views = sample(compact, state)
                            val options = Bundle().apply {
                                putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, if (compact) 155 else 340)
                                putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 165)
                            }
                            val rendered = CheckyWidgetFontRenderer.render(targetContext, views, options, font)
                            check(rendered !== views) { "Font failed to load/render: $font" }
                            val root = rendered.apply(targetContext, FrameLayout(targetContext))
                            val image = root.findViewById<ImageView>(R.id.widget_font_image)
                            val bitmap = (image.drawable as BitmapDrawable).bitmap
                            check(bitmap.byteCount <= 800_000) { "Bitmap exceeds budget" }
                            check(image.contentDescription.contains("오늘 일정") || state == "parking")
                            val file = File(targetContext.cacheDir, "widget-font-$font-$compact-$state.png")
                            file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                            checked++
                        }
                    }
                }
                for (font in listOf("system", "removed-font")) {
                    val views = sample(false, "both")
                    check(CheckyWidgetFontRenderer.render(targetContext, views, Bundle(), font) === views)
                    checked++
                }
            }
            result.putString("stream", "\nPASS: $checked native widget font renders/fallbacks\n")
            finish(-1, result)
        } catch (error: Throwable) {
            result.putString("stream", "\nFAIL: ${error.stackTraceToString()}\n")
            finish(0, result)
        }
    }

    private fun sample(compact: Boolean, state: String): RemoteViews = RemoteViews(
        targetContext.packageName,
        if (compact) R.layout.checky_home_widget_compact else R.layout.checky_home_widget,
    ).apply {
        if (state == "parking") setViewVisibility(R.id.widget_schedule_section, View.GONE)
        if (state == "schedule") setViewVisibility(R.id.widget_parking_section, View.GONE)
        if (state == "schedule" || state == "parking") setViewVisibility(R.id.widget_section_divider, View.GONE)
        if (state == "empty") {
            addView(R.id.widget_schedule_list, RemoteViews(targetContext.packageName, R.layout.checky_home_widget_empty))
            addView(R.id.widget_parking_list, RemoteViews(targetContext.packageName, R.layout.checky_home_widget_line).apply {
                setTextViewText(R.id.widget_item_summary, "등록된 주차 위치가 없습니다.")
            })
        } else {
            repeat(if (compact) 2 else 3) {
                addView(R.id.widget_schedule_list, RemoteViews(targetContext.packageName,
                    if (compact) R.layout.checky_home_widget_line else R.layout.checky_home_widget_item_safe).apply {
                    setTextViewText(R.id.widget_item_summary,
                        if (compact) "▌ 09:00 오늘의 긴 일정 제목 ABC123" else "▌ 오늘의 긴 일정 제목 가나다 ABC123\n09:00 - 10:30")
                })
                addView(R.id.widget_parking_list, RemoteViews(targetContext.packageName,
                    if (compact) R.layout.checky_home_widget_line else R.layout.checky_home_widget_item_safe).apply {
                    setTextViewText(R.id.widget_item_summary, if (compact) "우리 차 · 지하 3층 B12" else "우리 차\n지하 3층 B12")
                })
            }
        }
    }
}
