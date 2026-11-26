import { createEmbedding } from "../_shared/embedding.ts";

const json = (body: unknown, status: number, origin: string) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Content-Type": "application/json",
      "Vary": "Origin",
    },
  });

Deno.serve(async (request) => {
  const allowedOrigin = Deno.env.get("ALLOWED_ORIGIN") ?? "";
  const origin = request.headers.get("origin") ?? "";
  if (!allowedOrigin || origin !== allowedOrigin) {
    return new Response("Origin not allowed", { status: 403 });
  }
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": allowedOrigin,
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Vary": "Origin",
      },
    });
  }
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);

  try {
    const body = await request.json().catch(() => null);
    if (typeof body?.text !== "string" || !body.text.trim() || body.text.length > 1200) {
      return json({ error: "請提供 1 到 1200 字的搜尋文字" }, 400, origin);
    }
    const embedding = await createEmbedding(body.text.trim());
    return json({ embedding }, 200, origin);
  } catch (error) {
    console.error("Text embedding failed", error);
    return json({
      error: error instanceof Error ? error.message : "文字向量產生失敗，請稍後再試",
    }, 502, origin);
  }
});
