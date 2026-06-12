// admin/app/(dashboard)/logs/actions.ts
"use server";

import "server-only";

import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import type { LogLevel } from "@/lib/logs/search-params";

// The shape returned to the client. Keep it explicit (don't reuse the
// generated Database row type) so a column rename in the view becomes
// a compile error here.
export type LogRow = {
  id: string;
  timestamp: string;
  level: LogLevel;
  tag: string;
  message: string;
  error: string | null;
  stack_trace: string | null;
  context: unknown;
  app_version: string;
  platform: string;
  device_model: string;
  user_id: string | null;
  user_nickname: string | null;
};

const filtersSchema = z.object({
  levels: z.array(z.enum(["debug", "info", "warning", "error"])).default([]),
  tag: z.string().max(100).default(""),
  userId: z.string().max(100).default(""),
  appVersion: z.string().max(50).default(""),
  platform: z.string().max(20).default(""),
  search: z.string().max(200).default(""),
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).or(z.literal("")).default(""),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).or(z.literal("")).default(""),
  sinceIso: z.string().datetime(),
  limit: z.number().int().min(1).max(500).default(100),
});

export type FetchNewerInput = z.infer<typeof filtersSchema>;

export async function fetchNewerLogs(
  input: FetchNewerInput,
): Promise<{ ok: true; rows: LogRow[] } | { ok: false; error: string }> {
  await requireAdmin();
  const parsed = filtersSchema.safeParse(input);
  if (!parsed.success) {
    return { ok: false, error: "Filtros inválidos." };
  }
  const f = parsed.data;
  const supabase = adminClient();
  let q = supabase
    .from("admin_app_logs_view")
    .select(
      "id, timestamp, level, tag, message, error, stack_trace, context, app_version, platform, device_model, user_id, user_nickname",
    )
    .gt("timestamp", f.sinceIso)
    .order("timestamp", { ascending: false })
    .limit(f.limit);

  if (f.levels.length > 0) q = q.in("level", f.levels);
  if (f.tag) q = q.ilike("tag", `%${f.tag}%`);
  if (f.userId) q = q.eq("user_id", f.userId);
  if (f.appVersion) q = q.ilike("app_version", `%${f.appVersion}%`);
  if (f.platform) q = q.eq("platform", f.platform);
  if (f.search) q = q.ilike("message", `%${f.search}%`);
  if (f.from) q = q.gte("timestamp", `${f.from}T00:00:00.000Z`);
  if (f.to) {
    const to = new Date(`${f.to}T00:00:00.000Z`);
    to.setUTCDate(to.getUTCDate() + 1);
    q = q.lt("timestamp", to.toISOString());
  }

  const { data, error } = await q;
  if (error) return { ok: false, error: error.message };
  return { ok: true, rows: (data ?? []) as LogRow[] };
}
