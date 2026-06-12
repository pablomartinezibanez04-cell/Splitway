import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

/** Storage buckets that store files under `{user_id}/…` */
const USER_BUCKETS = ['avatars', 'vehicle-photos', 'route-thumbnails']

/**
 * Recursively delete every object under `bucket/userId/…`.
 * Uses the admin client (service role) so RLS is bypassed.
 * Silently ignores errors (bucket may not exist, folder may be empty).
 */
async function purgeUserStorage(
  adminClient: ReturnType<typeof createClient>,
  bucket: string,
  userId: string,
): Promise<void> {
  try {
    await purgeFolder(adminClient, bucket, userId)
  } catch {
    // Bucket may not exist or be empty — not a fatal error.
  }
}

/**
 * Lists `bucket/prefix` once, removes the files at this level, then recurses
 * into any sub-folders to arbitrary depth (e.g. vehicle-photos/{uid}/{vid}/…).
 * Supabase Storage returns folder placeholders as entries with a null `id`.
 */
async function purgeFolder(
  adminClient: ReturnType<typeof createClient>,
  bucket: string,
  prefix: string,
): Promise<void> {
  const { data: entries } = await adminClient.storage.from(bucket).list(prefix)
  if (!entries || entries.length === 0) return

  const files: string[] = []
  const folders: string[] = []
  for (const entry of entries) {
    const path = `${prefix}/${entry.name}`
    if (entry.id === null || entry.metadata === null) {
      folders.push(path)
    } else {
      files.push(path)
    }
  }

  if (files.length > 0) {
    await adminClient.storage.from(bucket).remove(files)
  }
  for (const folder of folders) {
    await purgeFolder(adminClient, bucket, folder)
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return new Response('Unauthorized', { status: 401, headers: corsHeaders })
  }

  // Validate the caller's JWT using the anon key client
  const anonClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
  )
  const { data: { user }, error: authError } = await anonClient.auth.getUser(
    authHeader.replace('Bearer ', ''),
  )
  if (authError || !user) {
    return new Response('Unauthorized', { status: 401, headers: corsHeaders })
  }

  // Build privileged client (service role) for admin operations
  const adminClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  )

  // 1. Purge all storage files owned by this user
  await Promise.all(
    USER_BUCKETS.map((bucket) => purgeUserStorage(adminClient, bucket, user.id)),
  )

  // 2. Delete the auth user (CASCADE removes all DB rows)
  const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id)
  if (deleteError) {
    return new Response(deleteError.message, { status: 500, headers: corsHeaders })
  }

  return new Response('OK', { status: 200, headers: corsHeaders })
})
