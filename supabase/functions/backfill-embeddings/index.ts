import { createEmbedding, itemSearchText } from "../_shared/embedding.ts";

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const expectedSecret = Deno.env.get("BACKFILL_SECRET");
  const suppliedSecret = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!expectedSecret || suppliedSecret !== expectedSecret) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const body = await request.json().catch(() => null);
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json({ error: "請提供 JSON 物件，limit 可設為 1 到 10" }, 400);
    }
    const requestedLimit = body.limit ?? 5;
    if (!Number.isInteger(requestedLimit) || requestedLimit < 1 || requestedLimit > 10) {
      return json({ error: "limit 必須是 1 到 10 的整數" }, 400);
    }
    const limit = requestedLimit;
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      (secretKeys ? JSON.parse(secretKeys).default : undefined);
    if (!supabaseUrl || !serviceKey) {
      throw new Error("Missing Supabase service environment variables");
    }

    const headers = {
      apikey: serviceKey,
      Authorization: ['Bearer', serviceKey].join(' '),
      "Content-Type": "application/json",
    };
    const params = new URLSearchParams({
      select: "id,name,category,color,other_feature_1,other_feature_2,other_feature_3",
      status: "eq.pending",
      embedding: "is.null",
      order: "created_at.asc",
      limit: String(limit),
    });
    const rowsResponse = await fetch(`${supabaseUrl}/rest/v1/lost_items?${params}`, {
      headers,
      signal: AbortSignal.timeout(15000),
    });
    if (!rowsResponse.ok) throw new Error(`Supabase 查詢失敗（${rowsResponse.status}）`);

    const rows = await rowsResponse.json();
    let processed = 0;
    for (const row of rows) {
      const embedding = await createEmbedding(itemSearchText(row));
      const update = await fetch(
        `${supabaseUrl}/rest/v1/lost_items?id=eq.${encodeURIComponent(row.id)}`,
        {
          method: "PATCH",
          headers: { ...headers, Prefer: "return=minimal" },
          body: JSON.stringify({ embedding }),
          signal: AbortSignal.timeout(15000),
        },
      );
      if (!update.ok) throw new Error(`更新物品 ${row.id} 的向量失敗（${update.status}）`);
      processed++;
    }
    return json({ processed, hasMore: rows.length === limit }, 200);
  } catch (error) {
    console.error("Embedding backfill failed", error);
    return json({
      error: error instanceof Error ? error.message : "向量回填失敗",
    }, 500);
  }
});
