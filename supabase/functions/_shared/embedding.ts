const requiredEnv = (name: string) => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing Edge Function secret: ${name}`);
  return value;
};

export const itemSearchText = (item: {
  name: string;
  category: string;
  color: string;
  other_feature_1: string;
  other_feature_2: string;
  other_feature_3: string;
}) =>
  [
    `標題：${item.name}`,
    item.category && `類別：${item.category}`,
    item.color && `顏色：${item.color}`,
    item.other_feature_1 && `特徵：${item.other_feature_1}`,
    item.other_feature_2 && `特徵：${item.other_feature_2}`,
    item.other_feature_3 && `特徵：${item.other_feature_3}`,
  ].filter(Boolean).join("\n").trim();

export const createEmbedding = async (text: string): Promise<number[]> => {
  const endpoint = (
    Deno.env.get("AZURE_OPENAI_EMBEDDING_ENDPOINT") ??
    requiredEnv("AZURE_OPENAI_ENDPOINT")
  ).replace(/\/+$/, "");
  const key = Deno.env.get("AZURE_OPENAI_EMBEDDING_KEY") ??
    requiredEnv("AZURE_OPENAI_KEY");
  const deployment = requiredEnv("AZURE_OPENAI_EMBEDDING_DEPLOYMENT");
  let base = endpoint;
  if (base.endsWith("/openai/v1/responses")) {
    base = base.slice(0, -"/responses".length);
  } else if (!base.endsWith("/openai/v1")) {
    base = `${base}/openai/v1`;
  }

  const response = await fetch(`${base}/embeddings`, {
    method: "POST",
    headers: {
      "api-key": key,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: deployment,
      input: text,
      encoding_format: "float",
    }),
    signal: AbortSignal.timeout(30000),
  });
  if (!response.ok) {
    console.error("Azure OpenAI embedding request failed", response.status);
    throw new Error(`Azure OpenAI Embedding 失敗（${response.status}）`);
  }

  const result = await response.json();
  const embedding = result?.data?.[0]?.embedding;
  if (
    !Array.isArray(embedding) ||
    embedding.length !== 1536 ||
    !embedding.every((value: unknown) =>
      typeof value === "number" && Number.isFinite(value)
    )
  ) {
    throw new Error("Embedding 模型需回傳 1536 維向量，請確認部署模型與設定");
  }
  return embedding;
};
