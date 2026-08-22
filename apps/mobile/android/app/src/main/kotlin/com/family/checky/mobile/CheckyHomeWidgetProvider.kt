package com.family.checky.mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
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
                    val itemLayout = if (isCompact) {
                        R.layout.checky_home_widget_item_compact
                    } else {
                        R.layout.checky_home_widget_item
                    }
                    val item = RemoteViews(context.packageName, itemLayout)
                    item.setTextViewText(
                        R.id.widget_item_time,
                        if (isCompact || endsAt.isBlank()) startsAt else "$startsAt - $endsAt",
                    )
                    item.setTextViewText(
                        R.id.widget_item_title,
                        preferences.getString("schedule.item.$index.title", ""),
                    )
                    if (!isCompact) {
                        val memberName = preferences.getString("schedule.item.$index.memberName", "") ?: ""
                        item.setTextViewText(R.id.widget_item_member, memberName)
                        item.setViewVisibility(
                            R.id.widget_item_member,
                            if (memberName.isNotBlank()) View.VISIBLE else View.GONE,
                        )
                    }
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
    }
}
