// Deletes the caller's account: storage folders, then the auth user (every table cascades from auth.users).
import { admin, caller, HttpError, json, serve } from "../_shared/http.ts";

export default serve(async (req, body) => {
  const { user } = await caller(req);
  if (body.confirm !== "delete") throw new HttpError(400, "Confirmation missing.");
  const svc = admin();
  for (const bucket of ["snapshots", "meal-photos"]) {
    for (;;) {
      const { data: files, error } = await svc.storage.from(bucket).list(user.id, { limit: 1000 });
      if (error) throw error;
      if (!files?.length) break;
      const { error: rmError } = await svc.storage.from(bucket).remove(files.map((f) => `${user.id}/${f.name}`));
      if (rmError) throw rmError;
    }
  }
  const { error } = await svc.auth.admin.deleteUser(user.id);
  if (error) throw error;
  return json({ ok: true });
});
