// Vercel serverless function. Only the Administrator can call it.
// Uses the SERVICE ROLE key (kept secret in Vercel Environment Variables).
const { createClient } = require('@supabase/supabase-js');

const authEmail = (id) => `${String(id).toLowerCase()}@school.local`;

const handler = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return res.status(500).json({ error: 'Server is not configured (missing environment variables).' });

  const admin = createClient(url, key, { auth: { persistSession: false } });

  // 1. Who is calling? Must be a logged-in Administrator.
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const { data: caller } = await admin.auth.getUser(token);
  if (!caller || !caller.user) return res.status(401).json({ error: 'Please log in again.' });
  const { data: me } = await admin.from('profiles').select('role').eq('id', caller.user.id).maybeSingle();
  if (!me || me.role !== 'Admin') return res.status(403).json({ error: 'Administrator access only.' });

  const b = req.body || {};
  const role = b.role, recordId = String(b.recordId || '').trim();
  if (!['Student', 'Teacher'].includes(role) || !recordId) return res.status(400).json({ error: 'Invalid request.' });

  if (b.action === 'create') {
    const password = String(b.password || '');
    if (password.length < 6) return res.status(400).json({ error: 'Password must be at least 6 characters.' });
    const table = role === 'Student' ? 'students' : 'teachers';
    const { data: rec } = await admin.from(table).select('id,name').eq('id', recordId).maybeSingle();
    if (!rec) return res.status(404).json({ error: `${role} record ${recordId} does not exist.` });

    const { data: created, error } = await admin.auth.admin.createUser({
      email: authEmail(recordId), password, email_confirm: true,
    });
    if (error) return res.status(400).json({ error: error.message });

    const { error: pErr } = await admin.from('profiles').insert({
      id: created.user.id, role, record_id: recordId, name: rec.name,
    });
    if (pErr) {
      await admin.auth.admin.deleteUser(created.user.id); // undo
      return res.status(400).json({ error: pErr.message });
    }
    return res.status(200).json({ ok: true, loginId: recordId });
  }

  if (b.action === 'delete') {
    const { data: p } = await admin.from('profiles').select('id').eq('role', role).eq('record_id', recordId).maybeSingle();
    if (p) {
      const { error } = await admin.auth.admin.deleteUser(p.id);
      if (error) return res.status(400).json({ error: error.message });
    }
    return res.status(200).json({ ok: true });
  }

  return res.status(400).json({ error: 'Unknown action.' });
};

module.exports = async (req, res) => {
  try { return await handler(req, res); }
  catch (e) { return res.status(500).json({ error: 'Function error: ' + e.message }); }
};
