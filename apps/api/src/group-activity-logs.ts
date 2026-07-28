import { requireMembership } from './families';
import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';

const GROUP_ACTIVITY_RETENTION_DAYS = 7;

export type GroupActivityType = 'schedule' | 'parking' | 'scrap' | 'travel';
export type GroupActivityTargetType =
  | 'schedule'
  | 'recurring_schedule'
  | 'parking_vehicle'
  | 'scrap_post'
  | 'travel_trip'
  | 'travel_itinerary';

type GroupActivityRow = {
  id: string;
  actor_user_id: string | null;
  activity_type: GroupActivityType;
  title: string;
  detail: string;
  target_type: GroupActivityTargetType | null;
  target_id: string | null;
  target_parent_id: string | null;
  target_starts_at: string | null;
  created_at: string;
  actor: { nickname: string } | { nickname: string }[] | null;
};

type ScrapPostPreviewRow = {
  id: string;
  content: string;
  link_title: string | null;
};

export type GroupActivityItem = {
  id: string;
  actorUserId: string | null;
  type: GroupActivityType;
  title: string;
  detail: string;
  actorNickname: string | null;
  createdAt: string;
  target: {
    type: GroupActivityTargetType;
    id: string;
    parentId: string | null;
    startsAt: string | null;
  } | null;
};

export async function recordGroupActivity(input: {
  familyId: string;
  actorUserId: string;
  type: GroupActivityType;
  title: string;
  detail: string;
  target?: {
    type: GroupActivityTargetType;
    id: string;
    parentId?: string;
    startsAt?: string;
  };
}) {
  const supabase = getSupabaseAdmin();
  const cutoff = activityCutoff();
  const [{ error: insertError }, { error: cleanupError }] = await Promise.all([
    supabase.from('group_activity_logs').insert({
      family_id: input.familyId,
      actor_user_id: input.actorUserId,
      activity_type: input.type,
      title: input.title,
      detail: input.detail,
      target_type: input.target?.type ?? null,
      target_id: input.target?.id ?? null,
      target_parent_id: input.target?.parentId ?? null,
      target_starts_at: input.target?.startsAt ?? null,
    }),
    supabase
      .from('group_activity_logs')
      .delete()
      .eq('family_id', input.familyId)
      .lt('created_at', cutoff),
  ]);

  if (insertError || cleanupError) {
    // 활동 기록 저장 실패가 이미 완료된 원래 작업을 실패로 만들면 안 된다.
    console.error('Failed to save group activity log', {
      insertError,
      cleanupError,
    });
  }
}

export async function listGroupActivities(
  userId: string,
  familyId: string,
  type?: GroupActivityType,
) {
  await requireMembership(userId, familyId);

  const supabase = getSupabaseAdmin();
  const cutoff = activityCutoff();
  const { error: cleanupError } = await supabase
    .from('group_activity_logs')
    .delete()
    .eq('family_id', familyId)
    .lt('created_at', cutoff);

  if (cleanupError) {
    throw new HttpError(500, { error: 'group_activity_log_cleanup_failed' });
  }

  let query = supabase
    .from('group_activity_logs')
    .select(
      `
        id,
        actor_user_id,
        activity_type,
        title,
        detail,
        target_type,
        target_id,
        target_parent_id,
        target_starts_at,
        created_at,
        actor:users (
          nickname
        )
      `,
    )
    .eq('family_id', familyId)
    .gte('created_at', cutoff)
    .order('created_at', { ascending: false })
    .limit(100);

  if (type) {
    query = query.eq('activity_type', type);
  }

  const { data, error } = await query;
  if (error) {
    throw new HttpError(500, { error: 'group_activity_log_fetch_failed' });
  }

  const rows = (data ?? []) as GroupActivityRow[];
  const scrapPostIds = rows
    .filter(
      (activity) =>
        activity.activity_type === 'scrap' &&
        activity.target_type === 'scrap_post' &&
        activity.target_id !== null &&
        (activity.detail === '스크랩 글을 등록했어요.' ||
          activity.detail === '스크랩 글을 수정했어요.'),
    )
    .map((activity) => activity.target_id as string);
  const scrapTitleByPostId = new Map<string, string>();

  if (scrapPostIds.length > 0) {
    const { data: posts, error: postsError } = await supabase
      .from('scrap_posts')
      .select('id, content, link_title')
      .eq('family_id', familyId)
      .in('id', [...new Set(scrapPostIds)]);

    if (postsError) {
      throw new HttpError(500, { error: 'scrap_activity_title_fetch_failed' });
    }

    for (const post of (posts ?? []) as ScrapPostPreviewRow[]) {
      scrapTitleByPostId.set(
        post.id,
        scrapActivityTitle(post.content, post.link_title),
      );
    }
  }

  return rows.map((row) =>
    toGroupActivityItem(row, scrapTitleByPostId.get(row.target_id ?? '')),
  );
}

function activityCutoff() {
  return new Date(
    Date.now() - GROUP_ACTIVITY_RETENTION_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();
}

function toGroupActivityItem(
  activity: GroupActivityRow,
  titleOverride?: string,
): GroupActivityItem {
  const actor = Array.isArray(activity.actor) ? activity.actor[0] : activity.actor;

  return {
    id: activity.id,
    actorUserId: activity.actor_user_id,
    type: activity.activity_type,
    title: titleOverride ?? activity.title,
    detail: activity.detail,
    actorNickname: actor?.nickname ?? null,
    createdAt: activity.created_at,
    target:
      activity.target_type && activity.target_id
        ? {
            type: activity.target_type,
            id: activity.target_id,
            parentId: activity.target_parent_id,
            startsAt: activity.target_starts_at,
          }
        : null,
  };
}

function scrapActivityTitle(value: string, linkTitle: string | null) {
  const previewTitle = linkTitle?.trim();

  if (previewTitle) {
    return previewTitle;
  }

  return value.trim().split(/\r?\n/, 1)[0]?.trim() || '스크랩';
}
