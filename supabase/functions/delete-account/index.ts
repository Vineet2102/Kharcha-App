// delete-account (F-18, §6.9.5, T-M1.7)
//
// Hard-deletes the caller's own account: their transactions, their receipt
// objects, and (if they are the household's only member) the household
// itself. Never operates on an id other than the one derived from the
// caller's own JWT. Requires the service-role key, which is why this must
// run as an Edge Function and never in the client.
//
// Deploy: supabase functions deploy delete-account
// (verify_jwt stays ON — the platform rejects a missing/invalid JWT before
// this code ever runs; we still decode it ourselves to get the user id.)

import { createClient } from "jsr:@supabase/supabase-js@2";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "not_authenticated" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Acts as the caller: SECURITY DEFINER RPCs resolve auth.uid() from this JWT.
  const asUser = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false },
  });
  // Service role: the only client allowed to touch auth.users and every
  // household's storage objects.
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const { data: userRes, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userRes?.user) return json({ error: "not_authenticated" }, 401);
  const uid = userRes.user.id; // never trust a client-supplied id

  const { data: profile, error: profileErr } = await admin
    .from("profiles")
    .select("household_id, role")
    .eq("id", uid)
    .single();
  if (profileErr || !profile) return json({ error: "profile_not_found" }, 404);

  const householdId = profile.household_id as string | null;

  let memberCount = 0;
  let adminCount = 0;
  if (householdId) {
    const { data: members, error: membersErr } = await admin
      .from("profiles")
      .select("id, role")
      .eq("household_id", householdId);
    if (membersErr) return json({ error: "lookup_failed" }, 500);
    memberCount = members.length;
    adminCount = members.filter((m) => m.role === "admin").length;
  }

  const isLastMember = householdId !== null && memberCount === 1;
  const isLastAdminWithOthers = householdId !== null && !isLastMember &&
    profile.role === "admin" && adminCount === 1;

  // Check the admin constraint before touching any data — a deletion that
  // is going to be refused must not leave the account half-deleted.
  if (isLastAdminWithOthers) {
    return json({ error: "promote_someone_first" }, 409);
  }

  // Storage paths must be read before delete_my_records() removes the
  // attachment rows they come from.
  const { data: expenseRows, error: expenseErr } = await admin
    .from("expenses")
    .select("id")
    .eq("user_id", uid);
  if (expenseErr) return json({ error: "lookup_failed" }, 500);
  const expenseIds = (expenseRows ?? []).map((e) => e.id as string);

  let storagePaths: string[] = [];
  if (expenseIds.length > 0) {
    const { data: attachmentRows, error: attachmentErr } = await admin
      .from("attachments")
      .select("storage_path")
      .in("expense_id", expenseIds);
    if (attachmentErr) return json({ error: "lookup_failed" }, 500);
    storagePaths = (attachmentRows ?? []).map((a) => a.storage_path as string);
  }

  const { error: deleteRecordsErr } = await asUser.rpc("delete_my_records");
  if (deleteRecordsErr) {
    return json(
      { error: "delete_records_failed", detail: deleteRecordsErr.message },
      500,
    );
  }

  if (isLastMember) {
    const { error: deleteHouseholdErr } = await asUser.rpc("delete_household");
    if (deleteHouseholdErr) {
      return json(
        { error: "delete_household_failed", detail: deleteHouseholdErr.message },
        500,
      );
    }
  }

  if (storagePaths.length > 0) {
    const { error: storageErr } = await admin.storage
      .from("receipts")
      .remove(storagePaths);
    // Orphaned files are a monitoring item (T-M3.8), not a reason to leave
    // the account undeleted.
    if (storageErr) {
      console.error("delete-account: receipt cleanup failed", storageErr);
    }
  }

  const { error: deleteUserErr } = await admin.auth.admin.deleteUser(uid);
  if (deleteUserErr) {
    return json({ error: "delete_user_failed", detail: deleteUserErr.message }, 500);
  }

  return json({ ok: true });
});
