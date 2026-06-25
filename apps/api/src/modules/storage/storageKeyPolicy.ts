export const encodeStorageOwnerId = (userId: string) => {
  const trimmed = userId.trim();

  return encodeURIComponent(trimmed.length > 0 ? trimmed : 'unknown-user');
};

export const isStorageKeyOwnedByUser = ({
  videoS3Key,
  userId
}: {
  videoS3Key: string;
  userId: string;
}) => {
  const parts = videoS3Key.trim().split('/');

  if (parts.length < 4 || parts[0] !== 'uploads') {
    return false;
  }

  if (parts[1] !== encodeStorageOwnerId(userId)) {
    return false;
  }

  return parts.slice(2).every((part) => part.length > 0 && part !== '.' && part !== '..');
};
