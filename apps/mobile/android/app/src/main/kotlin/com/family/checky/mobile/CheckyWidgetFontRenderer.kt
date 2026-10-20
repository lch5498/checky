package com.family.checky.mobile

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Typeface
import android.os.Bundle
import android.util.Log
import android.util.LruCache
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.RemoteViews
import android.widget.TextView
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * RemoteViews cannot safely transport an app-owned Typeface to every launcher.
 * Render the existing layout locally, then send only a bounded bitmap. The
 * default font keeps real TextViews; no custom views/spans cross process boundaries.
 */
internal object CheckyWidgetFontRenderer {
    private val typefaces = LruCache<String, Typeface>(2)

    fun render(context: Context, views: RemoteViews, options: Bundle, font: String): RemoteViews {
        val path = when (font) {
            "gowun-dodum" -> "gowundodum/GowunDodum-Regular.ttf"
            "gowun-batang" -> "gowunbatang/GowunBatang-Regular.ttf"
            "park-dahyun", "ainmom" -> "parkdahyun/Ownglyph-ParkDaHyun.ttf"
            "poor-story" -> "poorstory/PoorStory-Regular.ttf"
            "incheon-himchan" -> "incheonhimchan/ICEHimchan-Regular.ttf"
            else -> return views
        }
        return try {
            val regular = loadTypeface(context, path)
            val bold = if (font == "gowun-batang") {
                loadTypeface(context, "gowunbatang/GowunBatang-Bold.ttf")
            } else regular
            val content = views.apply(context, FrameLayout(context))
            val descriptions = mutableListOf<String>()
            fun applyFont(view: View) {
                if (view.visibility != View.VISIBLE) return
                if (view is TextView) {
                    val style = view.typeface?.style ?: Typeface.NORMAL
                    view.setTypeface(if (style and Typeface.BOLD != 0) bold else regular, style)
                    // Handwriting fonts can have taller ascenders/descenders.
                    view.includeFontPadding = true
                    if (view.text.isNotBlank()) descriptions.add(view.text.toString())
                }
                if (view is ViewGroup) {
                    for (index in 0 until view.childCount) applyFont(view.getChildAt(index))
                }
            }
            applyFont(content)

            val landscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            val widthKey = if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH
            val heightKey = if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT
            val density = context.resources.displayMetrics.density
            val width = (options.getInt(widthKey, 250).coerceIn(100, 800) * density).roundToInt()
            val height = (options.getInt(heightKey, 150).coerceIn(80, 500) * density).roundToInt()
            content.measure(
                View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY),
            )
            content.layout(0, 0, width, height)

            // Keep the whole payload < ~800KB, including on high-density/tablet
            // launchers. Scaling the canvas preserves native text metrics/layout.
            val scale = min(1.0, sqrt(200_000.0 / (width.toDouble() * height)))
            val bitmap = Bitmap.createBitmap(
                (width * scale).toInt().coerceAtLeast(1),
                (height * scale).toInt().coerceAtLeast(1),
                Bitmap.Config.ARGB_8888,
            )
            val canvas = Canvas(bitmap)
            canvas.scale(bitmap.width.toFloat() / width, bitmap.height.toFloat() / height)
            content.draw(canvas)
            RemoteViews(context.packageName, R.layout.checky_home_widget_font).apply {
                setImageViewBitmap(R.id.widget_font_image, bitmap)
                setContentDescription(R.id.widget_font_image, descriptions.joinToString(", "))
            }
        } catch (error: RuntimeException) {
            // A missing asset/launcher incompatibility must not make the widget
            // unaddable. Retain the normal, fully accessible system-font layout.
            Log.w("CheckyHomeWidget", "Custom font render failed; using system font", error)
            views
        }
    }

    private fun loadTypeface(context: Context, path: String): Typeface =
        typefaces.get(path) ?: Typeface.createFromAsset(
            context.assets, "flutter_assets/assets/fonts/$path",
        ).also { typefaces.put(path, it) }
}
