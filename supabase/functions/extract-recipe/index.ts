// supabase/functions/extract-recipe/index.ts
//
// recipes-022.2: takes 1+ already-uploaded photo storage paths (a
// screenshot series, a cookbook page, a handwritten card) and asks Claude
// to extract a single clean, ad-free, structured recipe from them -
// title, ingredients, steps, timing/servings when visible. Multiple
// photos are treated as parts of the same recipe (e.g. one photo of
// ingredients, another of steps) and combined into one result.
//
// Returns the extracted recipe as JSON. Does NOT save anything - the
// client prefills the add-recipe form with the result so the user always
// reviews/edits before it's actually saved. Runs under the calling user's
// own JWT (forwarded by the client), same as Houstory's analyze-media.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function err(msg: string, status = 400) {
  return new Response(JSON.stringify({ error: msg }), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

const SYSTEM_PROMPT =
  "You are extracting a clean, structured recipe from one or more photos for Recipes, a personal recipe box app. " +
  "The photos may be a screenshot (or series of screenshots) of a recipe website, blog, or Pinterest pin, a photo of a cookbook page, or a handwritten card. " +
  "Ignore ads, site navigation, comments, related-post sections, and social share buttons - extract only the actual recipe content. " +
  "If multiple photos are given, treat them as parts of the same single recipe (e.g. one photo shows the ingredient list, another shows the numbered steps) and combine them into one coherent result, in the right order. " +
  "Preserve ingredient quantities and units as written rather than converting them. Keep instruction steps as separate, individually actionable items - split a run-on paragraph of steps into individual steps if the source photo presents it that way. " +
  "Only fill in prep time, cook time, servings, or a source name if they are actually visible in the photo(s) - never guess or estimate a value that isn't shown.";

const EXTRACT_TOOL = {
  name: "extract_recipe",
  description: "Record the recipe extracted from the provided photo(s).",
  input_schema: {
    type: "object",
    properties: {
      title: { type: "string", description: "The recipe's name/title." },
      description: { type: "string", description: "A short 1-2 sentence intro/description, only if one is actually present in the source - omit otherwise." },
      prep_minutes: { type: "integer", description: "Prep time in minutes, only if visible in the source." },
      cook_minutes: { type: "integer", description: "Cook time in minutes, only if visible in the source." },
      servings: { type: "string", description: "Servings/yield as written (e.g. '4', '2 dozen cookies'), only if visible." },
      source_name: { type: "string", description: "The site, blog, cookbook, or author name, only if visible in the photo(s)." },
      ingredients: {
        type: "array",
        items: {
          type: "object",
          properties: {
            quantity: { type: "string", description: "e.g. '2', '1/2', '' if none." },
            unit: { type: "string", description: "e.g. 'cups', 'tbsp', '' if none." },
            name: { type: "string", description: "The ingredient itself, e.g. 'flour', 'garlic cloves, minced'." },
          },
          required: ["name"],
        },
      },
      instructions: {
        type: "array",
        items: { type: "string" },
        description: "Ordered list of steps, one instruction per array entry.",
      },
    },
    required: ["title", "ingredients", "instructions"],
  },
};

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { status: 200, headers: corsHeaders });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: corsHeaders });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return err("Missing Authorization header", 401);

  const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return err("Invalid JSON body");
  }

  const storagePaths: string[] = Array.isArray(payload?.storage_paths) ? payload.storage_paths : [];
  if (storagePaths.length === 0) return err("storage_paths is required (array of at least one path)");

  const downloads = await Promise.all(
    storagePaths.map(async (path: string) => {
      const { data: fileBlob, error } = await sb.storage.from("recipe-photos").download(path);
      if (error || !fileBlob) return null;
      const arrayBuffer = await fileBlob.arrayBuffer();
      return { base64: encodeBase64(new Uint8Array(arrayBuffer)), mediaType: fileBlob.type || "image/jpeg" };
    })
  );

  if (downloads.some((d) => d === null)) return err("failed to download one or more photos", 500);

  const content = [
    ...downloads.map((d) => ({ type: "image", source: { type: "base64", media_type: d!.mediaType, data: d!.base64 } })),
    { type: "text", text: "Extract the recipe from the photo(s) above using the extract_recipe tool." },
  ];

  const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-sonnet-5",
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      tools: [EXTRACT_TOOL],
      tool_choice: { type: "tool", name: "extract_recipe" },
      messages: [{ role: "user", content }],
    }),
  });

  if (!anthropicRes.ok) {
    const errText = await anthropicRes.text();
    return err(`Claude API error: ${errText}`, 502);
  }

  const anthropicData = await anthropicRes.json();
  const toolUse = (anthropicData.content ?? []).find((b: any) => b.type === "tool_use" && b.name === "extract_recipe");
  if (!toolUse) return err("Claude did not return a structured recipe", 502);

  return json({ status: "ok", recipe: toolUse.input });
});
