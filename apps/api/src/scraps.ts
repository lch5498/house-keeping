import { requireMembership } from './families';
import { recordGroupActivity } from './group-activity-logs';
import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';

type FamilyRole = 'owner' | 'member';

export type ScrapChannel = {
  id: string;
  family_id: string;
  name: string;
  sort_order: number | null;
  created_by_user_id: string | null;
  created_at: string;
  updated_at: string;
  authorNickname?: string;
  canEdit?: boolean;
  canDelete?: boolean;
  hasRecentPosts?: boolean;
  latestPostCreatedAt?: string | null;
};

export type ScrapPost = {
  id: string;
  family_id: string;
  channel_id: string;
  content: string;
  link_url: string | null;
  link_title: string | null;
  link_description: string | null;
  link_image_url: string | null;
  link_site_name: string | null;
  created_by_user_id: string | null;
  created_at: string;
  updated_at: string;
  authorNickname?: string;
  canEdit?: boolean;
  canDelete?: boolean;
  likeCount?: number;
  isLikedByMe?: boolean;
  comments?: ScrapComment[];
};

export type ScrapComment = {
  id: string;
  family_id: string;
  post_id: string;
  content: string;
  created_by_user_id: string | null;
  created_at: string;
  updated_at: string;
  authorNickname?: string;
  canEdit?: boolean;
  canDelete?: boolean;
  likeCount?: number;
  isLikedByMe?: boolean;
};

export type ScrapRecentActivity = {
  id: string;
  type: 'post' | 'comment';
  post_id: string;
  channel_id: string;
  channel_name: string;
  content: string;
  linkTitle: string | null;
  created_at: string;
  authorNickname: string;
};

type FamilyMemberAuthor = {
  user_id: string | null;
  nickname: string;
};

type ScrapLike = {
  id: string;
  family_id: string;
  post_id: string | null;
  comment_id: string | null;
  user_id: string;
  created_at: string;
};

export async function getScrapDashboard(userId: string, familyId: string) {
  const membership = await requireMembership(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('scrap_channels')
    .select('*')
    .eq('family_id', familyId)
    .order('sort_order', { ascending: true, nullsFirst: false })
    .order('created_at', { ascending: false });

  if (error) {
    throw error;
  }

  const recentSince = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const { data: recentPosts, error: recentPostsError } = await supabase
    .from('scrap_posts')
    .select('channel_id, created_at')
    .eq('family_id', familyId)
    .gte('created_at', recentSince);

  if (recentPostsError) {
    throw recentPostsError;
  }

  const recentChannelIds = new Set(
    ((recentPosts ?? []) as Array<{ channel_id: string }>).map((post) =>
      post.channel_id,
    ),
  );
  const latestPostCreatedAtByChannel = new Map<string, string>();

  for (const post of (recentPosts ?? []) as Array<{
    channel_id: string;
    created_at: string;
  }>) {
    const current = latestPostCreatedAtByChannel.get(post.channel_id);

    if (!current || post.created_at > current) {
      latestPostCreatedAtByChannel.set(post.channel_id, post.created_at);
    }
  }

  return {
    channels: (await attachAuthorNicknames(
      familyId,
      (data ?? []) as ScrapChannel[],
    )).map((channel) =>
      withChannelManagePermissions(
        {
          ...channel,
          hasRecentPosts: recentChannelIds.has(channel.id),
          latestPostCreatedAt:
            latestPostCreatedAtByChannel.get(channel.id) ?? null,
        },
        userId,
        membership.role,
      ),
    ),
  };
}

export async function getRecentScrapActivities(
  userId: string,
  familyId: string,
) {
  await requireMembership(userId, familyId);

  const supabase = getSupabaseAdmin();
  const [{ data: posts, error: postsError }, { data: comments, error: commentsError }] =
    await Promise.all([
      supabase
        .from('scrap_posts')
        .select('*')
        .eq('family_id', familyId)
        .order('created_at', { ascending: false })
        .limit(5),
      supabase
        .from('scrap_comments')
        .select('*')
        .eq('family_id', familyId)
        .order('created_at', { ascending: false })
        .limit(5),
    ]);

  if (postsError) {
    throw postsError;
  }
  if (commentsError) {
    throw commentsError;
  }

  const postRows = (posts ?? []) as ScrapPost[];
  const commentRows = (comments ?? []) as ScrapComment[];
  const commentPostIds = commentRows.map((comment) => comment.post_id);
  const knownPosts = new Map(postRows.map((post) => [post.id, post]));
  const missingPostIds = commentPostIds.filter((id) => !knownPosts.has(id));

  if (missingPostIds.length > 0) {
    const { data: parentPosts, error: parentPostsError } = await supabase
      .from('scrap_posts')
      .select('*')
      .eq('family_id', familyId)
      .in('id', missingPostIds);

    if (parentPostsError) {
      throw parentPostsError;
    }

    for (const finalPost of (parentPosts ?? []) as ScrapPost[]) {
      knownPosts.set(finalPost.id, finalPost);
    }
  }

  const channelIds = [
    ...new Set([
      ...postRows.map((post) => post.channel_id),
      ...commentRows
        .map((comment) => knownPosts.get(comment.post_id)?.channel_id)
        .filter((channelId): channelId is string => Boolean(channelId)),
    ]),
  ];
  const channelNameById = new Map<string, string>();

  if (channelIds.length > 0) {
    const { data: channels, error: channelsError } = await supabase
      .from('scrap_channels')
      .select('id, name')
      .eq('family_id', familyId)
      .in('id', channelIds);

    if (channelsError) {
      throw channelsError;
    }

    for (const channel of (channels ?? []) as Array<{ id: string; name: string }>) {
      channelNameById.set(channel.id, channel.name);
    }
  }

  const activitiesWithAuthors = await attachAuthorNicknames(familyId, [
    ...postRows.map((post) => ({ ...post, type: 'post' as const })),
    ...commentRows.map((comment) => ({ ...comment, type: 'comment' as const })),
  ]);

  const recentActivities = activitiesWithAuthors
      .map((activity): ScrapRecentActivity | null => {
        const channelId =
          activity.type === 'post'
            ? activity.channel_id
            : knownPosts.get(activity.post_id)?.channel_id;
        const channelName = channelId ? channelNameById.get(channelId) : null;

        if (!channelId || !channelName) {
          return null;
        }

        return {
          id: activity.id,
          type: activity.type,
          post_id:
            activity.type === 'post' ? activity.id : activity.post_id,
          channel_id: channelId,
          channel_name: channelName,
          content: activity.content,
          linkTitle: null,
          created_at: activity.created_at,
          authorNickname: activity.authorNickname,
        };
      })
      .filter((activity): activity is ScrapRecentActivity => activity !== null)
      .sort((a, b) => b.created_at.localeCompare(a.created_at))
      .slice(0, 5);

  return {
    activities: await Promise.all(
      recentActivities.map(async (activity) => {
        const linkUrl = extractFirstLineHttpUrl(activity.content);

        if (!linkUrl) {
          return activity;
        }

        const savedTitle =
          activity.type === 'post'
            ? knownPosts.get(activity.post_id)?.link_title
            : null;
        const preview = savedTitle ? null : await fetchLinkPreview(linkUrl);

        return {
          ...activity,
          linkTitle:
            savedTitle ?? preview?.title ?? preview?.siteName ?? hostFromUrl(linkUrl),
        };
      }),
    ),
  };
}

export async function createScrapChannel(
  userId: string,
  familyId: string,
  input: { name: string },
) {
  await requireMembership(userId, familyId);

  const supabase = getSupabaseAdmin();
  const sortOrder = await nextChannelSortOrder(familyId);
  const { data, error } = await supabase
    .from('scrap_channels')
    .insert({
      family_id: familyId,
      name: normalizeText(input.name, 60),
      sort_order: sortOrder,
      created_by_user_id: userId,
    })
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  const [channel] = await attachAuthorNicknames(familyId, [data as ScrapChannel]);
  return withChannelManagePermissions(channel, userId, 'owner');
}

export async function updateScrapChannel(
  userId: string,
  familyId: string,
  channelId: string,
  input: { name: string },
) {
  const membership = await requireMembership(userId, familyId);
  const channel = await getChannelOrThrow(familyId, channelId);
  assertCanManageChannel(channel.created_by_user_id, userId, membership.role);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('scrap_channels')
    .update({ name: normalizeText(input.name, 60) })
    .eq('family_id', familyId)
    .eq('id', channelId)
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  const [updatedChannel] = await attachAuthorNicknames(familyId, [
    data as ScrapChannel,
  ]);
  return withChannelManagePermissions(updatedChannel, userId, membership.role);
}

export async function deleteScrapChannel(
  userId: string,
  familyId: string,
  channelId: string,
) {
  const membership = await requireMembership(userId, familyId);
  const channel = await getChannelOrThrow(familyId, channelId);
  assertCanManageChannel(channel.created_by_user_id, userId, membership.role);

  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('scrap_channels')
    .delete()
    .eq('family_id', familyId)
    .eq('id', channelId);

  if (error) {
    throw error;
  }
}

export async function reorderScrapChannels(
  userId: string,
  familyId: string,
  input: { channelIds: string[] },
) {
  await requireMembership(userId, familyId);

  const channelIds = [...new Set(input.channelIds)];

  if (channelIds.length !== input.channelIds.length || channelIds.length === 0) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'channelIds' });
  }

  const supabase = getSupabaseAdmin();
  const { data: channels, error: channelsError } = await supabase
    .from('scrap_channels')
    .select('id')
    .eq('family_id', familyId)
    .in('id', channelIds);

  if (channelsError) {
    throw channelsError;
  }

  if ((channels ?? []).length !== channelIds.length) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'channelIds' });
  }

  const updateResults = await Promise.all(
    channelIds.map((channelId, index) =>
      supabase
        .from('scrap_channels')
        .update({ sort_order: index + 1 })
        .eq('family_id', familyId)
        .eq('id', channelId),
    ),
  );

  const updateError = updateResults.find((result) => result.error)?.error;

  if (updateError) {
    throw updateError;
  }

  return getScrapDashboard(userId, familyId);
}

export async function previewScrapLink(
  userId: string,
  familyId: string,
  input: { content: string },
) {
  await requireMembership(userId, familyId);
  const preview = await fetchLinkPreview(input.content);

  return {
    preview: preview ? serializeLinkPreview(preview) : null,
  };
}

export async function getScrapChannel(
  userId: string,
  familyId: string,
  channelId: string,
) {
  const membership = await requireMembership(userId, familyId);
  const channel = await getChannelOrThrow(familyId, channelId);
  const supabase = getSupabaseAdmin();

  const { data: posts, error: postsError } = await supabase
    .from('scrap_posts')
    .select('*')
    .eq('family_id', familyId)
    .eq('channel_id', channelId)
    .order('created_at', { ascending: false });

  if (postsError) {
    throw postsError;
  }

  const postRows = (posts ?? []) as ScrapPost[];
  const postIds = postRows.map((post) => post.id);
  const commentsByPostId = new Map<string, ScrapComment[]>();
  const commentRows: ScrapComment[] = [];

  if (postIds.length > 0) {
    const { data: comments, error: commentsError } = await supabase
      .from('scrap_comments')
      .select('*')
      .eq('family_id', familyId)
      .in('post_id', postIds)
      .order('created_at', { ascending: true });

    if (commentsError) {
      throw commentsError;
    }

    const commentsWithAuthors = await attachAuthorNicknames(
      familyId,
      (comments ?? []) as ScrapComment[],
    );
    commentRows.push(...commentsWithAuthors);
  }

  const likeSummary = await getScrapLikeSummary(
    familyId,
    userId,
    postIds,
    commentRows.map((comment) => comment.id),
  );

  for (const comment of commentRows) {
    const commentWithPermissions = withLikeSummary(
      withDeletePermission(comment, userId, membership.role),
      likeSummary.comments,
    );
    const bucket = commentsByPostId.get(comment.post_id) ?? [];
    bucket.push(commentWithPermissions);
    commentsByPostId.set(comment.post_id, bucket);
  }

  const postsWithAuthors = await attachAuthorNicknames(familyId, postRows);

  return {
    channel: withChannelManagePermissions(channel, userId, membership.role),
    posts: postsWithAuthors.map((post) =>
      withLikeSummary(
        {
          ...post,
          ...manageFlags(post.created_by_user_id, userId, membership.role),
          comments: commentsByPostId.get(post.id) ?? [],
        },
        likeSummary.posts,
      ),
    ),
  };
}

export async function createScrapPost(
  userId: string,
  familyId: string,
  channelId: string,
  input: { content: string },
) {
  const membership = await requireMembership(userId, familyId);
  await getChannelOrThrow(familyId, channelId);
  const content = normalizeText(input.content, 2000);
  const linkPreview = await fetchLinkPreview(content);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('scrap_posts')
    .insert({
      family_id: familyId,
      channel_id: channelId,
      content,
      link_url: linkPreview?.url ?? null,
      link_title: linkPreview?.title ?? null,
      link_description: linkPreview?.description ?? null,
      link_image_url: linkPreview?.imageUrl ?? null,
      link_site_name: linkPreview?.siteName ?? null,
      created_by_user_id: userId,
    })
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  const [post] = await attachAuthorNicknames(familyId, [data as ScrapPost]);
  const result = {
    ...post,
    ...manageFlags(post.created_by_user_id, userId, membership.role),
    likeCount: 0,
    isLikedByMe: false,
    comments: [],
  };
  await recordGroupActivity({
    familyId,
    actorUserId: userId,
    type: 'scrap',
    title: activityTitle(content, post.link_title),
    detail: '스크랩 글을 등록했어요.',
    target: { type: 'scrap_post', id: post.id, parentId: channelId },
  });
  return result;
}

export async function updateScrapPost(
  userId: string,
  familyId: string,
  channelId: string,
  postId: string,
  input: { content: string },
) {
  const membership = await requireMembership(userId, familyId);
  const post = await getPostOrThrow(familyId, channelId, postId);
  assertCanManage(post.created_by_user_id, userId, membership.role);

  const content = normalizeText(input.content, 2000);
  const linkPreview = await fetchLinkPreview(content);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('scrap_posts')
    .update({
      content,
      link_url: linkPreview?.url ?? null,
      link_title: linkPreview?.title ?? null,
      link_description: linkPreview?.description ?? null,
      link_image_url: linkPreview?.imageUrl ?? null,
      link_site_name: linkPreview?.siteName ?? null,
    })
    .eq('family_id', familyId)
    .eq('channel_id', channelId)
    .eq('id', postId)
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  const [updatedPost] = await attachAuthorNicknames(familyId, [data as ScrapPost]);
  const result = {
    ...updatedPost,
    ...manageFlags(updatedPost.created_by_user_id, userId, membership.role),
    likeCount: 0,
    isLikedByMe: false,
    comments: [],
  };
  await recordGroupActivity({
    familyId,
    actorUserId: userId,
    type: 'scrap',
    title: activityTitle(content, updatedPost.link_title),
    detail: '스크랩 글을 수정했어요.',
    target: { type: 'scrap_post', id: updatedPost.id, parentId: channelId },
  });
  return result;
}

export async function createScrapComment(
  userId: string,
  familyId: string,
  channelId: string,
  postId: string,
  input: { content: string },
) {
  const membership = await requireMembership(userId, familyId);
  await getPostOrThrow(familyId, channelId, postId);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('scrap_comments')
    .insert({
      family_id: familyId,
      post_id: postId,
      content: normalizeText(input.content, 1000),
      created_by_user_id: userId,
    })
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  const [comment] = await attachAuthorNicknames(familyId, [data as ScrapComment]);
  const result = {
    ...withDeletePermission(comment, userId, membership.role),
    likeCount: 0,
    isLikedByMe: false,
  };
  await recordGroupActivity({
    familyId,
    actorUserId: userId,
    type: 'scrap',
    title: activityTitle(result.content),
    detail: '스크랩 글에 댓글을 남겼어요.',
    target: { type: 'scrap_post', id: postId, parentId: channelId },
  });
  return result;
}

export async function updateScrapComment(
  userId: string,
  familyId: string,
  channelId: string,
  postId: string,
  commentId: string,
  input: { content: string },
) {
  const membership = await requireMembership(userId, familyId);
  await getPostOrThrow(familyId, channelId, postId);

  const supabase = getSupabaseAdmin();
  const { data: comment, error: commentError } = await supabase
    .from('scrap_comments')
    .select('*')
    .eq('family_id', familyId)
    .eq('post_id', postId)
    .eq('id', commentId)
    .maybeSingle();

  if (commentError) {
    throw commentError;
  }

  if (!comment) {
    throw new HttpError(404, { error: 'scrap_comment_not_found' });
  }

  assertCanManage(
    (comment as ScrapComment).created_by_user_id,
    userId,
    membership.role,
  );

  const { data, error } = await supabase
    .from('scrap_comments')
    .update({ content: normalizeText(input.content, 1000) })
    .eq('family_id', familyId)
    .eq('post_id', postId)
    .eq('id', commentId)
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  const [updatedComment] = await attachAuthorNicknames(familyId, [
    data as ScrapComment,
  ]);
  const result = {
    ...withDeletePermission(updatedComment, userId, membership.role),
    likeCount: 0,
    isLikedByMe: false,
  };
  await recordGroupActivity({
    familyId,
    actorUserId: userId,
    type: 'scrap',
    title: activityTitle(result.content),
    detail: '스크랩 댓글을 수정했어요.',
    target: { type: 'scrap_post', id: postId, parentId: channelId },
  });
  return result;
}

export async function toggleScrapPostLike(
  userId: string,
  familyId: string,
  channelId: string,
  postId: string,
) {
  await requireMembership(userId, familyId);
  await getPostOrThrow(familyId, channelId, postId);

  return toggleScrapLike(userId, familyId, { postId });
}

export async function toggleScrapCommentLike(
  userId: string,
  familyId: string,
  channelId: string,
  postId: string,
  commentId: string,
) {
  await requireMembership(userId, familyId);
  await getPostOrThrow(familyId, channelId, postId);

  const supabase = getSupabaseAdmin();
  const { data: comment, error } = await supabase
    .from('scrap_comments')
    .select('id')
    .eq('family_id', familyId)
    .eq('post_id', postId)
    .eq('id', commentId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!comment) {
    throw new HttpError(404, { error: 'scrap_comment_not_found' });
  }

  return toggleScrapLike(userId, familyId, { commentId });
}

export async function deleteScrapPost(
  userId: string,
  familyId: string,
  channelId: string,
  postId: string,
) {
  const membership = await requireMembership(userId, familyId);
  const post = await getPostOrThrow(familyId, channelId, postId);

  assertCanManage(post.created_by_user_id, userId, membership.role);

  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('scrap_posts')
    .delete()
    .eq('family_id', familyId)
    .eq('channel_id', channelId)
    .eq('id', postId);

  if (error) {
    throw error;
  }

  await recordGroupActivity({
    familyId,
    actorUserId: userId,
    type: 'scrap',
    title: activityTitle(post.content, post.link_title),
    detail: '스크랩 글을 삭제했어요.',
  });
}

function activityTitle(value: string, linkTitle?: string | null) {
  const previewTitle = linkTitle?.trim();

  if (previewTitle) {
    return previewTitle;
  }

  return value.trim().split(/\r?\n/, 1)[0]?.trim() || '스크랩';
}

export async function deleteScrapComment(
  userId: string,
  familyId: string,
  channelId: string,
  postId: string,
  commentId: string,
) {
  const membership = await requireMembership(userId, familyId);
  await getPostOrThrow(familyId, channelId, postId);

  const supabase = getSupabaseAdmin();
  const { data: comment, error: commentError } = await supabase
    .from('scrap_comments')
    .select('*')
    .eq('family_id', familyId)
    .eq('post_id', postId)
    .eq('id', commentId)
    .maybeSingle();

  if (commentError) {
    throw commentError;
  }

  if (!comment) {
    throw new HttpError(404, { error: 'scrap_comment_not_found' });
  }

  assertCanManage(
    (comment as ScrapComment).created_by_user_id,
    userId,
    membership.role,
  );

  const { error } = await supabase
    .from('scrap_comments')
    .delete()
    .eq('family_id', familyId)
    .eq('post_id', postId)
    .eq('id', commentId);

  if (error) {
    throw error;
  }

  await recordGroupActivity({
    familyId,
    actorUserId: userId,
    type: 'scrap',
    title: activityTitle((comment as ScrapComment).content),
    detail: '스크랩 댓글을 삭제했어요.',
  });
}

async function getChannelOrThrow(familyId: string, channelId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('scrap_channels')
    .select('*')
    .eq('family_id', familyId)
    .eq('id', channelId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'scrap_channel_not_found' });
  }

  const [channel] = await attachAuthorNicknames(familyId, [data as ScrapChannel]);
  return channel;
}

async function getPostOrThrow(
  familyId: string,
  channelId: string,
  postId: string,
) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('scrap_posts')
    .select('*')
    .eq('family_id', familyId)
    .eq('channel_id', channelId)
    .eq('id', postId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'scrap_post_not_found' });
  }

  return data as ScrapPost;
}

async function attachAuthorNicknames<T extends { created_by_user_id: string | null }>(
  familyId: string,
  rows: T[],
) {
  const userIds = [
    ...new Set(
      rows
        .map((row) => row.created_by_user_id)
        .filter((userId): userId is string => Boolean(userId)),
    ),
  ];

  if (userIds.length === 0) {
    return rows.map((row) => ({ ...row, authorNickname: '알 수 없음' }));
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('family_members')
    .select('user_id, nickname')
    .eq('family_id', familyId)
    .in('user_id', userIds);

  if (error) {
    throw error;
  }

  const nicknameByUserId = new Map(
    ((data ?? []) as FamilyMemberAuthor[])
      .filter((member) => member.user_id)
      .map((member) => [member.user_id as string, member.nickname]),
  );

  return rows.map((row) => ({
    ...row,
    authorNickname:
      (row.created_by_user_id && nicknameByUserId.get(row.created_by_user_id)) ||
      '알 수 없음',
  }));
}

function normalizeText(value: string, maxLength: number) {
  const normalized = value.trim();

  if (!normalized || normalized.length > maxLength) {
    throw new HttpError(400, { error: 'invalid_payload' });
  }

  return normalized;
}

function withDeletePermission<T extends { created_by_user_id: string | null }>(
  row: T,
  userId: string,
  role: FamilyRole,
) {
  return {
    ...row,
    ...manageFlags(row.created_by_user_id, userId, role),
  };
}

function withLikeSummary<T extends { id: string }>(
  row: T,
  summaries: Map<string, { count: number; likedByMe: boolean }>,
) {
  const summary = summaries.get(row.id);

  return {
    ...row,
    likeCount: summary?.count ?? 0,
    isLikedByMe: summary?.likedByMe ?? false,
  };
}

function withManagePermissions<T extends { created_by_user_id: string | null }>(
  row: T,
  userId: string,
  role: FamilyRole,
) {
  return {
    ...row,
    ...manageFlags(row.created_by_user_id, userId, role),
  };
}

function withChannelManagePermissions<
  T extends { created_by_user_id: string | null },
>(row: T, userId: string, role: FamilyRole) {
  const canManage = canManageChannel(row.created_by_user_id, userId, role);

  return {
    ...row,
    canEdit: canManage,
    canDelete: canManage,
  };
}

function manageFlags(
  createdByUserId: string | null,
  userId: string,
  role: FamilyRole,
) {
  const canManage = canManageScrap(createdByUserId, userId, role);

  return {
    canEdit: canManage,
    canDelete: canManage,
  };
}

function canManageScrap(
  createdByUserId: string | null,
  userId: string,
  _role: FamilyRole,
) {
  return createdByUserId === userId;
}

function canManageChannel(
  createdByUserId: string | null,
  userId: string,
  role: FamilyRole,
) {
  return role === 'owner' || createdByUserId === userId;
}

function assertCanManage(
  createdByUserId: string | null,
  userId: string,
  role: FamilyRole,
) {
  if (!canManageScrap(createdByUserId, userId, role)) {
    throw new HttpError(403, { error: 'scrap_manage_forbidden' });
  }
}

function assertCanManageChannel(
  createdByUserId: string | null,
  userId: string,
  role: FamilyRole,
) {
  if (!canManageChannel(createdByUserId, userId, role)) {
    throw new HttpError(403, { error: 'scrap_channel_manage_forbidden' });
  }
}

async function nextChannelSortOrder(familyId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('scrap_channels')
    .select('sort_order')
    .eq('family_id', familyId)
    .order('sort_order', { ascending: false, nullsFirst: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return ((data?.sort_order as number | null) ?? 0) + 1;
}

async function getScrapLikeSummary(
  familyId: string,
  userId: string,
  postIds: string[],
  commentIds: string[],
) {
  const [postLikes, commentLikes] = await Promise.all([
    getLikesForTargets(familyId, 'post_id', postIds),
    getLikesForTargets(familyId, 'comment_id', commentIds),
  ]);

  return {
    posts: summarizeLikes(postLikes, 'post_id', userId),
    comments: summarizeLikes(commentLikes, 'comment_id', userId),
  };
}

async function getLikesForTargets(
  familyId: string,
  targetColumn: 'post_id' | 'comment_id',
  targetIds: string[],
) {
  if (targetIds.length === 0) {
    return [] as ScrapLike[];
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('scrap_likes')
    .select('*')
    .eq('family_id', familyId)
    .in(targetColumn, targetIds);

  if (error) {
    throw error;
  }

  return (data ?? []) as ScrapLike[];
}

function summarizeLikes(
  likes: ScrapLike[],
  targetColumn: 'post_id' | 'comment_id',
  userId: string,
) {
  const summaries = new Map<string, { count: number; likedByMe: boolean }>();

  for (const like of likes) {
    const targetId = like[targetColumn];

    if (!targetId) {
      continue;
    }

    const summary = summaries.get(targetId) ?? { count: 0, likedByMe: false };
    summary.count += 1;
    summary.likedByMe ||= like.user_id === userId;
    summaries.set(targetId, summary);
  }

  return summaries;
}

async function toggleScrapLike(
  userId: string,
  familyId: string,
  target:
    | {
        postId: string;
        commentId?: never;
      }
    | {
        postId?: never;
        commentId: string;
      },
) {
  const supabase = getSupabaseAdmin();
  const targetColumn = target.postId ? 'post_id' : 'comment_id';
  const targetId = target.postId ?? target.commentId;
  const targetFilter =
    targetColumn === 'post_id' ? { post_id: targetId } : { comment_id: targetId };

  const { data: existing, error: existingError } = await supabase
    .from('scrap_likes')
    .select('id')
    .eq('family_id', familyId)
    .eq('user_id', userId)
    .eq(targetColumn, targetId)
    .maybeSingle();

  if (existingError) {
    throw existingError;
  }

  if (existing) {
    const { error } = await supabase
      .from('scrap_likes')
      .delete()
      .eq('id', existing.id);

    if (error) {
      throw error;
    }

    return {
      isLikedByMe: false,
      likeCount: await countScrapLikes(familyId, targetColumn, targetId),
    };
  }

  const { error } = await supabase.from('scrap_likes').insert({
    family_id: familyId,
    user_id: userId,
    ...targetFilter,
  });

  if (error) {
    throw error;
  }

  return {
    isLikedByMe: true,
    likeCount: await countScrapLikes(familyId, targetColumn, targetId),
  };
}

async function countScrapLikes(
  familyId: string,
  targetColumn: 'post_id' | 'comment_id',
  targetId: string,
) {
  const supabase = getSupabaseAdmin();
  const { count, error } = await supabase
    .from('scrap_likes')
    .select('id', { count: 'exact', head: true })
    .eq('family_id', familyId)
    .eq(targetColumn, targetId);

  if (error) {
    throw error;
  }

  return count ?? 0;
}

type LinkPreview = {
  url: string;
  title: string | null;
  description: string | null;
  imageUrl: string | null;
  siteName: string | null;
};

function serializeLinkPreview(preview: LinkPreview) {
  return {
    link_url: preview.url,
    link_title: preview.title,
    link_description: preview.description,
    link_image_url: preview.imageUrl,
    link_site_name: preview.siteName,
  };
}

async function fetchLinkPreview(content: string): Promise<LinkPreview | null> {
  const url = extractFirstHttpUrl(content);

  if (!url) {
    return null;
  }

  const fallback = {
    url,
    title: hostFromUrl(url),
    description: null,
    imageUrl: null,
    siteName: hostFromUrl(url),
  };

  const naverPlaceId = extractNaverPlaceId(url);
  if (naverPlaceId) {
    const naverPreview = await fetchNaverPlacePreview(url, naverPlaceId, fallback);
    if (naverPreview) {
      return naverPreview;
    }
  }

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 3500);
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        accept: 'text/html,application/xhtml+xml',
        'user-agent': 'facebookexternalhit/1.1',
      },
      redirect: 'follow',
    });
    clearTimeout(timeout);

    const contentType = response.headers.get('content-type') ?? '';
    if (!response.ok || !contentType.toLowerCase().includes('text/html')) {
      return fallback;
    }

    const html = (await response.text()).slice(0, 300_000);
    const title = pickMetaContent(html, ['og:title', 'twitter:title']) ?? pickTitle(html);
    const description = pickMetaContent(html, [
      'og:description',
      'twitter:description',
      'description',
    ]);
    const imageUrl = absoluteUrl(
      pickMetaContent(html, ['og:image', 'twitter:image']),
      url,
    );
    const siteName = pickMetaContent(html, ['og:site_name']) ?? hostFromUrl(url);

    return {
      url,
      title: truncateText(title ?? fallback.title, 180),
      description: truncateText(description, 280),
      imageUrl: truncateText(imageUrl, 1000),
      siteName: truncateText(siteName, 120),
    };
  } catch {
    return fallback;
  }
}

async function fetchNaverPlacePreview(
  url: string,
  placeId: string,
  fallback: LinkPreview,
): Promise<LinkPreview | null> {
  try {
    const mapEntryUrl = `https://map.naver.com/p/entry/place/${placeId}`;
    const [sourceHtml, mapHtml, placeHtml] = await Promise.all([
      fetchPreviewHtml(url, 'facebookexternalhit/1.1', 300_000),
      fetchPreviewHtml(mapEntryUrl, 'facebookexternalhit/1.1', 300_000),
      fetchPreviewHtml(
        `https://m.place.naver.com/place/${placeId}/home`,
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148',
        1_500_000,
      ),
    ]);

    const sourceTitle = pickMetaContent(sourceHtml, ['og:title', 'twitter:title']);
    const sourceDescription = pickMetaContent(sourceHtml, [
      'og:description',
      'twitter:description',
      'description',
    ]);
    const entryDescription = pickMetaContent(mapHtml, [
      'og:description',
      'twitter:description',
      'description',
    ]);
    const placeTitle = normalizeNaverPlaceTitle(
      pickMetaContent(placeHtml, ['og:title', 'twitter:title']) ?? sourceTitle,
    );
    const roadAddress =
      pickJsonString(placeHtml, 'roadAddress') ?? pickNaverRoadAddress(placeHtml);
    const imageUrl =
      absoluteUrl(pickMetaContent(placeHtml, ['og:image', 'twitter:image']), url) ??
      absoluteUrl(pickMetaContent(sourceHtml, ['og:image', 'twitter:image']), url) ??
      absoluteUrl(pickMetaContent(mapHtml, ['og:image', 'twitter:image']), mapEntryUrl);

    return {
      url,
      title: truncateText(
        placeTitle ?? sourceDescription ?? entryDescription ?? fallback.title,
        180,
      ),
      description: truncateText(roadAddress ?? sourceDescription ?? entryDescription, 280),
      imageUrl: truncateText(imageUrl, 1000),
      siteName: '네이버 플레이스',
    };
  } catch {
    return null;
  }
}

async function fetchPreviewHtml(url: string, userAgent: string, maxLength: number) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3500);

  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        accept: 'text/html,application/xhtml+xml',
        'user-agent': userAgent,
      },
      redirect: 'follow',
    });

    const contentType = response.headers.get('content-type') ?? '';
    if (!response.ok || !contentType.toLowerCase().includes('text/html')) {
      return '';
    }

    return (await response.text()).slice(0, maxLength);
  } finally {
    clearTimeout(timeout);
  }
}

function extractFirstHttpUrl(content: string) {
  const match = content.match(/https?:\/\/[^\s<>"']+/i);

  if (!match) {
    return null;
  }

  const rawUrl = match[0].replace(/[)\].,!?]+$/g, '');

  try {
    const url = new URL(rawUrl);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

function extractFirstLineHttpUrl(content: string) {
  const firstLine = content.trim().split(/\r?\n/, 1)[0]?.trim() ?? '';

  if (!firstLine || /\s/.test(firstLine)) {
    return null;
  }

  return extractFirstHttpUrl(firstLine);
}

function extractNaverPlaceId(value: string) {
  try {
    const url = new URL(value);
    const host = url.hostname.replace(/^www\./, '');

    if (
      ![
        'map.naver.com',
        'm.place.naver.com',
        'pcmap.place.naver.com',
      ].includes(host)
    ) {
      return null;
    }

    const match = url.pathname.match(
      /\/(?:p\/entry\/place|place|restaurant|hairshop|hospital|accommodation)\/(\d+)/,
    );
    return match?.[1] ?? null;
  } catch {
    return null;
  }
}

function pickMetaContent(html: string, keys: string[]) {
  const metaRegex = /<meta\s+([^>]*?)>/gi;
  let match: RegExpExecArray | null;

  while ((match = metaRegex.exec(html)) !== null) {
    const attrs = parseHtmlAttributes(match[1]);
    const key = (attrs.property ?? attrs.name ?? '').toLowerCase();

    if (keys.includes(key) && attrs.content) {
      return cleanHtmlText(attrs.content);
    }
  }

  return null;
}

function pickTitle(html: string) {
  const match = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  return match ? cleanHtmlText(match[1]) : null;
}

function pickJsonString(html: string, key: string) {
  const regex = new RegExp(`"${key}"\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"`);
  const match = html.match(regex);

  if (!match) {
    return null;
  }

  try {
    return cleanHtmlText(JSON.parse(`"${match[1]}"`) as string);
  } catch {
    return cleanHtmlText(match[1]);
  }
}

function pickNaverRoadAddress(html: string) {
  const match = html.match(
    /(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)[^<"]{4,90}(대로|로|길)\s*\d+(?:-\d+)?/,
  );
  return match ? cleanHtmlText(match[0]) : null;
}

function normalizeNaverPlaceTitle(value: string | null) {
  if (!value) {
    return null;
  }

  const normalized = cleanHtmlText(value)
    .replace(/\u001c/g, '')
    .replace(/\s*:\s*네이버\s*$/, '')
    .trim();

  if (!normalized || normalized === '네이버지도' || normalized === '네이버 플레이스') {
    return null;
  }

  return normalized;
}

function parseHtmlAttributes(source: string) {
  const attrs: Record<string, string> = {};
  const attrRegex = /([a-zA-Z_:.-]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))/g;
  let match: RegExpExecArray | null;

  while ((match = attrRegex.exec(source)) !== null) {
    attrs[match[1].toLowerCase()] = match[3] ?? match[4] ?? match[5] ?? '';
  }

  return attrs;
}

function cleanHtmlText(value: string) {
  return decodeHtmlEntities(value.replace(/<[^>]+>/g, ' '))
    .replace(/\s+/g, ' ')
    .trim();
}

function decodeHtmlEntities(value: string) {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, (_, code: string) => String.fromCharCode(Number(code)))
    .replace(/&#x([0-9a-f]+);/gi, (_, code: string) =>
      String.fromCharCode(Number.parseInt(code, 16)),
    );
}

function absoluteUrl(value: string | null, baseUrl: string) {
  if (!value) {
    return null;
  }

  try {
    return new URL(value, baseUrl).toString();
  } catch {
    return null;
  }
}

function hostFromUrl(value: string) {
  try {
    return new URL(value).hostname.replace(/^www\./, '');
  } catch {
    return value;
  }
}

function truncateText(value: string | null, maxLength: number) {
  if (!value) {
    return null;
  }

  return value.length > maxLength ? value.slice(0, maxLength) : value;
}
