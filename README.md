# Lights We Kept · Winter '26

A shared Christmas album: a lit tree by the sea, where every photo is a light.
Friends enter one shared password, then can view, add, rename and delete photos.
New photos fly in on a firework for everyone who has the page open.

## How it works

- **Page:** `index.html` (one file), plus the background music in `music/`.
- **Backend:** Supabase.
  - Photos live in a **private** storage bucket called `photos`. Each photo has a full-size copy, at most 1600 px, and a small thumbnail.
  - The `photos` table holds the captions and who added each photo.
  - Live updates use Supabase Realtime.
- **Password:** checked inside the database by `join_album()`. Only browsers that entered the right password can list, view, upload, rename or delete photos. Because Row Level Security enforces this, the public anon key in the page can't get around it.

## Setup (one time)

1. **Run the database setup.** Run `supabase/migrations/20261119000000_shared_album.sql`.
   - If the Supabase GitHub integration deploys migrations, pushing this repo runs it.
   - Otherwise, paste the file into **SQL Editor → New query → Run**.
2. **Set the album password** in the SQL editor. Don't commit it anywhere:
   ```sql
   select private.set_album_password('your album password');
   ```
   Run the same line again any time to change it. People who already joined keep access. To remove everyone's access, run `delete from public.members;`.
3. **Turn on anonymous sign-ins.** Go to **Authentication → Sign In / Providers** and enable **Allow anonymous sign-ins**. Each visitor's browser gets an invisible account, which becomes a member once they type the password.
4. **Add the Supabase settings as GitHub secrets.** They are kept out of this repo. Go to **Settings → Secrets and variables → Actions → New repository secret** and add two secrets:
   - `SUPABASE_URL`: your Project URL, for example `https://xxxx.supabase.co`.
   - `SUPABASE_PUBLISHABLE_KEY`: the anon / publishable key.

   Never use the `service_role` / secret key.
5. **Host it.** Go to **Settings → Pages** and set **Source** to **GitHub Actions**. Each push to `main` runs `.github/workflows/deploy.yml`, which writes `config.js` from the secrets and publishes the site. To redeploy without a push, open **Actions → Deploy album → Run workflow**. Then share the link and the password.

**Running locally:** copy `config.example.js` to `config.js` and fill in the two values. `config.js` is in `.gitignore`. Without it, the page still runs: you can add, rename and delete photos, but nothing is saved.

**About the publishable key:** keeping it out of git keeps it out of the repo history. The live site still has to send it to every visitor's browser, so anyone can see it in the page's files. That is how Supabase publishable keys are designed to work. The password and Row Level Security protect the photos, not the secrecy of this key.

## Notes

- Storage use: a resized photo is about 300 KB, so 500 photos come to roughly 150 MB. That fits Supabase's free 1 GB.
- Photos are loaded through links that expire after 7 days. Refreshing the page gets fresh links.
- Music: Debussy, *Arabesque No. 1*. Before sharing publicly, make sure you have the right to use this recording.
