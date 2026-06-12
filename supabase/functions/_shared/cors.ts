// Shared CORS headers for all Splitway edge functions.
//
// `*` origin is acceptable here because these functions are called by the
// native mobile app (CORS is a browser-only enforcement) and are protected by
// JWT validation, not by origin. If a browser client ever calls them, tighten
// this to an explicit origin allowlist.
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
