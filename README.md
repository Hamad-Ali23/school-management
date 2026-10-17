# Smart School - Deploy Guide (Vercel + Supabase)

Folder layout
- `index.html`        the app
- `config.js`         your Supabase URL + anon key (public key, safe) + school name
- `supabase/setup.sql` ONE file: tables + security rules + the admin (no sample data)
- `api/manage-user.js` admin-only function that creates/deletes logins
- `package.json`, `vercel.json`, `.gitignore`

## Step 1 - Database (Supabase, free)
1. supabase.com -> New project (save the database password).
2. SQL Editor -> New query -> paste all of `supabase/setup.sql` -> Run.
3. Authentication -> Users -> Add user -> email `defendercyber759@gmail.com`, choose a strong password, tick **Auto Confirm User**.
4. SQL Editor -> run `supabase/setup.sql` again (this links that user as Admin).
5. Authentication -> Sign In / Providers -> turn **OFF** "Allow new users to sign up".

## Step 2 - Keys
Project Settings -> API:
- Put **Project URL** and **anon public** key in `config.js`.
- Keep the **service_role** key secret. It goes only into Vercel (Step 4).

## Step 3 - GitHub
Create a repo and upload everything in this folder (`.gitignore` is included).

## Step 4 - Vercel
1. vercel.com -> Add New -> Project -> import the repo. Framework: **Other**.
2. Settings -> Environment Variables, add:
   - `SUPABASE_URL` = your Project URL
   - `SUPABASE_SERVICE_ROLE_KEY` = the service_role key
3. Deploy (redeploy after adding variables).

## Step 5 - First use (the system starts completely empty)
- Admin logs in with `defendercyber759@gmail.com` and the password from Step 1.
- Add Students and Teachers in Student/Teacher Management, then assign classes in Class Timetable & Subject Assignment.
- Account Management -> Create Login Account for each teacher/student.
- Teacher/student login ID = their ID (e.g. `TCH-101`, `STD-112`) + the password you set (min 6 characters).

## Rules the database enforces (not just the screen)
- Student sees only own profile, results, attendance and own class subjects.
- Teacher sees only students of assigned/class-teacher classes, can add attendance once, cannot change it later.
- Admin can edit everything.

## Problems?
- "Database not configured": edit `config.js`.
- "No school profile found": run Step 1 point 4 again.
- Account creation error: check the two Vercel variables, then redeploy.

## Changing the admin email/name
Open `supabase/setup.sql`, edit `v_email` / `v_name` in section 4 BEFORE running it, and create the same email in Authentication > Users.

## Old demo data from the earlier version
If you already ran the older SQL, use the commented lines in section 5 of `setup.sql` once, and delete demo users in Authentication > Users.
