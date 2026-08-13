const postScheduleLimit = Duration(days: 30);

bool isPostScheduleWithinLimit({
  required DateTime scheduledAt,
  required DateTime now,
}) =>
    !scheduledAt.isAfter(now.add(postScheduleLimit));
