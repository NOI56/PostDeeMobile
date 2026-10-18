import { Prisma } from '@prisma/client';
import { AdminError } from './trialAccess.js';
import type { AdminConsoleConfig } from './adminConfig.js';

export type AdminReportScope = 'ALL_ACCOUNTS' | 'LATEST_TRIAL';
export type AdminUsageWindow = { from: string | null; until: string; timezone: 'UTC' };
export type AdminUsageMetrics = {
  captionRequests: number; editMinutes: number; quotaPostUnits: number; postUnits: number;
  livePostUnits: number; draftPostUnits: number; otherDeliveredPostUnits: number;
  failedPostUnits: number; pendingPostUnits: number;
};
export type AdminReportSummary = AdminUsageMetrics & { memberCount: number; estimatedUsd: number | null };
export type AdminUsageReportRow = AdminUsageMetrics & {
  userId: string; email: string; plan: string | null; startsAt: string | null;
  expiresAt: string | null; revokedAt: string | null; usageFrom: string | null;
  usageUntil: string; purchasedPlanNow: string; estimatedUsd: number | null;
};
export type AdminUsageReportPage = {
  rows: AdminUsageReportRow[]; total: number; nextCursor?: string; asOf: string;
  window: AdminUsageWindow; reportScope: AdminReportScope; summary: AdminReportSummary; note: string;
};
type ReportOptions = { query: string; cursor?: string; from?: Date; until?: Date; reportScope?: AdminReportScope };
type RawRow = Omit<AdminUsageReportRow, 'estimatedUsd'>;
type RawReport = { rows: RawRow[]; summary: AdminUsageMetrics & { memberCount: number } };
const estimate = (metrics: AdminUsageMetrics, rates?: AdminConsoleConfig['costRates']) => rates
  ? +(metrics.captionRequests * rates.captionRequestUsd + metrics.editMinutes * rates.editMinuteUsd + metrics.postUnits * rates.postUnitUsd).toFixed(6)
  : null;
// Prisma DateTime columns are UTC timestamp-without-zone. PostgreSQL's JSON
// serialization omits that zone; never reinterpret it using the API host's TZ.
const iso = (value: string | null) => value === null ? null
  : new Date(/(?:Z|[+-]\d{2}:\d{2})$/i.test(value) ? value : `${value}Z`).toISOString();

// One aggregate batch, independent of page size. Cursor filtering happens only
// after the cohort totals, so an empty later page still carries the full summary.
export const readAdminUsageReport = async (tx: Prisma.TransactionClient, options: ReportOptions,
  asOf: Date, rates?: AdminConsoleConfig['costRates']): Promise<AdminUsageReportPage> => {
  // The new console explicitly asks for all accounts; old clients keep trials.
  const reportScope = options.reportScope ?? 'LATEST_TRIAL';
  if (!['ALL_ACCOUNTS', 'LATEST_TRIAL'].includes(reportScope)) throw new AdminError('ADMIN_FILTER_INVALID', 400);
  const from = options.from ?? null;
  const until = new Date(Math.min(options.until?.getTime() ?? Infinity, asOf.getTime()));
  // Raw Prisma Date parameters are timestamptz. Convert explicitly before
  // comparing them to Prisma's UTC timestamp columns, independent of DB TZ.
  const fromTimestamp = Prisma.sql`timezone('UTC', ${from}::timestamptz)`;
  const untilTimestamp = Prisma.sql`timezone('UTC', ${until}::timestamptz)`;
  const asOfTimestamp = Prisma.sql`timezone('UTC', ${asOf}::timestamptz)`;
  const [result] = await tx.$queryRaw<RawReport[]>(Prisma.sql`
    WITH cohort AS MATERIALIZED (
      SELECT u.id AS "userId", u.email, t.plan::text AS plan, t."startsAt", t."expiresAt", t."revokedAt",
        CASE WHEN ${reportScope} = 'LATEST_TRIAL'
          THEN GREATEST(t."startsAt", ${fromTimestamp})
          ELSE ${fromTimestamp} END AS "usageFrom",
        CASE WHEN ${reportScope} = 'LATEST_TRIAL'
          THEN LEAST(${untilTimestamp}, t."expiresAt", t."revokedAt")
          ELSE ${untilTimestamp} END AS "usageUntil",
        CASE WHEN s.status = 'ACTIVE' AND (s."currentPeriodEnd" IS NULL OR s."currentPeriodEnd" > ${asOfTimestamp})
          THEN s.plan::text ELSE 'BASIC' END AS "purchasedPlanNow"
      FROM "User" u
      LEFT JOIN "AdminTrialAccess" t ON t."userId" = u.id
      LEFT JOIN "Subscription" s ON s."userId" = u.id
      WHERE (${options.query} = '' OR strpos(lower(u.email), lower(${options.query})) > 0
        OR strpos(lower(COALESCE(u."displayName", '')), lower(${options.query})) > 0)
        AND (${reportScope} = 'ALL_ACCOUNTS' OR t."userId" IS NOT NULL)
    ), captions AS (
      SELECT c."userId", count(*) AS "captionRequests"
      FROM cohort c JOIN "RealClipCaptionUsage" a ON a."userId" = c."userId"
        AND (c."usageFrom" IS NULL OR a."createdAt" >= c."usageFrom") AND a."createdAt" < c."usageUntil"
      GROUP BY c."userId"
    ), edits AS (
      SELECT c."userId", sum(a.minutes) AS "editMinutes"
      FROM cohort c JOIN "AiEditUsage" a ON a."userId" = c."userId"
        AND (c."usageFrom" IS NULL OR a."createdAt" >= c."usageFrom") AND a."createdAt" < c."usageUntil"
      GROUP BY c."userId"
    ), quota_posts AS (
      SELECT c."userId", sum(cardinality(p."selectedPlatforms")) AS "quotaPostUnits"
      FROM cohort c JOIN "Post" p ON p."userId" = c."userId"
        AND (c."usageFrom" IS NULL OR p."createdAt" >= c."usageFrom") AND p."createdAt" < c."usageUntil"
      GROUP BY c."userId"
    ), deliveries AS (
      SELECT c."userId", count(*) AS "postUnits",
        count(*) FILTER (WHERE d.status = 'PUBLISHED' AND d."deliveryOutcome" = 'LIVE') AS "livePostUnits",
        count(*) FILTER (WHERE d.status = 'PUBLISHED' AND d."deliveryOutcome" = 'DRAFT') AS "draftPostUnits",
        count(*) FILTER (WHERE d.status = 'PUBLISHED' AND (d."deliveryOutcome" IS NULL OR d."deliveryOutcome" NOT IN ('LIVE', 'DRAFT'))) AS "otherDeliveredPostUnits",
        count(*) FILTER (WHERE d.status = 'FAILED') AS "failedPostUnits",
        count(*) FILTER (WHERE d.status IN ('PENDING', 'PUBLISHING')) AS "pendingPostUnits"
      FROM cohort c JOIN "Post" p ON p."userId" = c."userId"
      JOIN "PlatformPublish" d ON d."postId" = p.id
        AND (c."usageFrom" IS NULL OR d."createdAt" >= c."usageFrom") AND d."createdAt" < c."usageUntil"
      GROUP BY c."userId"
    ), metrics AS MATERIALIZED (
      SELECT c.*, COALESCE(a."captionRequests", 0) AS "captionRequests", COALESCE(e."editMinutes", 0) AS "editMinutes",
        COALESCE(q."quotaPostUnits", 0) AS "quotaPostUnits", COALESCE(d."postUnits", 0) AS "postUnits",
        COALESCE(d."livePostUnits", 0) AS "livePostUnits", COALESCE(d."draftPostUnits", 0) AS "draftPostUnits",
        COALESCE(d."otherDeliveredPostUnits", 0) AS "otherDeliveredPostUnits", COALESCE(d."failedPostUnits", 0) AS "failedPostUnits",
        COALESCE(d."pendingPostUnits", 0) AS "pendingPostUnits"
      FROM cohort c LEFT JOIN captions a USING ("userId") LEFT JOIN edits e USING ("userId")
      LEFT JOIN quota_posts q USING ("userId") LEFT JOIN deliveries d USING ("userId")
    ), page AS (
      SELECT * FROM metrics WHERE (${options.cursor ?? null}::text IS NULL OR "userId" > ${options.cursor ?? null}::text)
      ORDER BY "userId" ASC LIMIT 51
    )
    SELECT COALESCE((SELECT jsonb_agg(to_jsonb(page) ORDER BY "userId") FROM page), '[]'::jsonb) AS rows,
      jsonb_build_object('memberCount', count(*),
        'captionRequests', COALESCE(sum("captionRequests"), 0), 'editMinutes', COALESCE(sum("editMinutes"), 0),
        'quotaPostUnits', COALESCE(sum("quotaPostUnits"), 0), 'postUnits', COALESCE(sum("postUnits"), 0),
        'livePostUnits', COALESCE(sum("livePostUnits"), 0), 'draftPostUnits', COALESCE(sum("draftPostUnits"), 0),
        'otherDeliveredPostUnits', COALESCE(sum("otherDeliveredPostUnits"), 0), 'failedPostUnits', COALESCE(sum("failedPostUnits"), 0),
        'pendingPostUnits', COALESCE(sum("pendingPostUnits"), 0)) AS summary
    FROM metrics
  `);
  return {
    rows: result.rows.slice(0, 50).map(row => ({ ...row,
      startsAt: iso(row.startsAt), expiresAt: iso(row.expiresAt), revokedAt: iso(row.revokedAt),
      usageFrom: iso(row.usageFrom), usageUntil: iso(row.usageUntil)!, estimatedUsd: estimate(row, rates) })),
    total: result.summary.memberCount, ...(result.rows.length > 50 ? { nextCursor: result.rows[49].userId } : {}),
    asOf: asOf.toISOString(), window: { from: from?.toISOString() ?? null, until: until.toISOString(), timezone: 'UTC' }, reportScope,
    summary: { ...result.summary, estimatedUsd: estimate(result.summary, rates) },
    note: `${reportScope === 'LATEST_TRIAL' ? 'เฉพาะช่วงทดลองล่าสุดของแต่ละบัญชีที่ซ้อนกับวันที่เลือก ประวัติช่วงเก่าอยู่ที่ประวัติผู้ดูแล' : 'ทุกบัญชีที่ตรงกับการค้นหา รวมบัญชีที่ไม่มีสิทธิ์ทดลอง'} · ช่วงเวลาเริ่มรวม ปลายไม่รวม (UTC) · ยอดรวมครอบคลุมทุกบัญชีที่ตรงตัวกรอง ไม่ใช่เฉพาะหน้านี้ · AI เป็นรายการใช้หรือจองโควตาที่บันทึกไว้ ไม่ใช่จำนวนงานที่ยืนยันสำเร็จ · ผลส่งที่บันทึกรวมร่าง งานรอ และงานล้มเหลว · ต้นทุนเป็นประมาณการ ไม่ใช่ใบแจ้งหนี้`
  };
};
