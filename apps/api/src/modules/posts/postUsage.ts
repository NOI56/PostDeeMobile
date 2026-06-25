export type PostUsageInput = {
  createdAt: string;
  platforms?: unknown[];
};

export const isCurrentMonthPost = (post: PostUsageInput, now = new Date()) => {
  const createdAt = new Date(post.createdAt);

  return (
    !Number.isNaN(createdAt.valueOf()) &&
    createdAt.getUTCFullYear() === now.getUTCFullYear() &&
    createdAt.getUTCMonth() === now.getUTCMonth()
  );
};

export const countCurrentMonthPosts = (posts: PostUsageInput[], now = new Date()) =>
  posts.filter((post) => isCurrentMonthPost(post, now)).length;

export const countCurrentMonthPostUnits = (posts: PostUsageInput[], now = new Date()) =>
  posts
    .filter((post) => isCurrentMonthPost(post, now))
    .reduce((total, post) => total + Math.max(post.platforms?.length ?? 1, 0), 0);
