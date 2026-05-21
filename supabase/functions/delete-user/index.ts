import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/** Storage buckets that store files under `{user_id}/…` */
const USER_BUCKETS = ['avatars', 'vehicle-photos', 'route-thumbnails']

/**
 * List all objects in `bucket` under the folder `userId/` and delete them.
 * Uses the admin client (service role) so RLS is bypassed.
 * Silently ignores errors (bucket may not exist, folder may be empty).
 */
async function purgeUserStorage(
  adminClient: ReturnType<typeof createClient>,
  bucket: string,
  userId: string,
): Promise<void> {
  try {
    const { data: objects } = await adminClient.storage
      .from(bucket)
      .list(userId)

    if (objects && objects.length > 0) {
      const paths = objects.map((o) => `${userId}/${o.name}`)
      await adminClient.storage.from(bucket).remove(paths)
    }

    // Handle nested folders (e.g. vehicle-photos/{uid}/{vehicleId}/…)
    // The first list only returns immediate children; folders appear as
    // items with `metadata: null`.  Iterate one level deeper.
    const { data: nested } = await adminClient.storage
      .from(bucket)
      .list(userId)

    if (nested) {
      for (const item of nested) {
        if (item.metadata === null) {
          // It's a sub-folder — list & delete its contents
          const subPath = `${userId}/${item.name}`
          const { data: subObjects } = await adminClient.storage
            .from(bucket)
            .list(subPath)

          if (subObjects && subObjects.length > 0) {
            const subPaths = subObjects.map((o) => `${subPath}/${o.name}`)
            await adminClient.storage.from(bucket).remove(subPaths)
          }
        }
      }
    }
  } catch {
    // Bucket may not exist or be empty — not a fatal error.
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
