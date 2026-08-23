package com.family.checky.mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.view.View
import android.widget.RemoteViews

class CheckyHomeWidgetProvider : AppWidgetProvider() {
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
        private const val preferencesName = "checky.home_widget"

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
            val savedItemCount = preferences.getInt("schedule.itemCount", 0).coerceIn(0, 5)
            val isCompact = appWidgetManager.getAppWidgetOptions(appWidgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250) < 200
            val itemCount = if (isCompact) savedItemCount.coerceAtMost(2) else savedItemCount
            val moreCount = preferences.getInt("schedule.moreCount", 0) + (savedItemCount - itemCount)
            val views = RemoteViews(
                context.packageName,
                if (isCompact) R.layout.checky_home_widget_compact else R.layout.checky_home_widget,
            )

            views.setTextViewText(
                R.id.widget_weekday,
                preferences.getString("schedule.weekday", "오늘"),
            )
            views.setTextViewText(
                R.id.widget_day,
                preferences.getString("schedule.day", ""),
            )
            if (!isCompact) {
                views.setTextViewText(
                    R.id.widget_full_date,
                    preferences.getString("schedule.fullDate", "오늘"),
                )
            }
            views.removeAllViews(R.id.widget_schedule_list)
            if (itemCount == 0) {
                views.addView(
                    R.id.widget_schedule_list,
                    RemoteViews(context.packageName, R.layout.checky_home_widget_empty),
                )
            } else {
                repeat(itemCount) { index ->
                    val startsAt = preferences.getString("schedule.item.$index.startsAt", "") ?: ""
                    val endsAt = preferences.getString("schedule.item.$index.endsAt", "") ?: ""
                    val title = preferences.getString("schedule.item.$index.title", "") ?: ""
                    val memberName = preferences.getString("schedule.item.$index.memberName", "") ?: ""
                    val memberColor = preferences.getString(
                        "schedule.item.$index.memberColor",
                        "gray",
                    ) ?: "gray"
                    val item = RemoteViews(
                        context.packageName,
                        R.layout.checky_home_widget_item_safe,
                    )
                    val timeText = if (isCompact || endsAt.isBlank()) startsAt else "$startsAt - $endsAt"
                    item.setTextViewText(
                        R.id.widget_item_summary,
                        scheduleSummary(
                            timeText = timeText,
                            title = title,
                            memberName = memberName,
                            memberColor = memberColor,
                            isCompact = isCompact,
                        ),
                    )
                    views.addView(R.id.widget_schedule_list, item)
                }
            }
            views.setViewVisibility(R.id.widget_more, if (moreCount > 0) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.widget_more, "더 보기 +${moreCount}개")
            views.setOnClickPendingIntent(
                R.id.widget_content,
                PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun scheduleSummary(
            timeText: String,
            title: String,
            memberName: String,
            memberColor: String,
            isCompact: Boolean,
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
                if (title.isNotBlank()) {
                    append(title)
                } else {
                    append(timeText)
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
