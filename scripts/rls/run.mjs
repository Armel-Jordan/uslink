/**
 * Lance supabase/tests/rls.test.sql dans un vrai Postgres, sans Docker ni CLI :
 * PGlite est un Postgres compilé en WebAssembly. `npm run test:rls`.
 *
 * Deux vérifications :
 *   A. `schema.sql` appliqué à neuf passe toutes les assertions.
 *   B. (optionnel, --baseline=<ref git>) l'ancien schéma + les migrations
 *      produisent EXACTEMENT le même état que l'installation neuve, et les
 *      données déjà présentes survivent.
 *
 * B est la vérification qui compte à chaque nouvelle migration : c'est elle qui
 * empêche schema.sql et supabase/migrations/ de diverger en silence.
 *   node scripts/rls/run.mjs --baseline=8dabc20
 */
import { PGlite } from '@electric-sql/pglite';
import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');

const baseline = process.argv.find((a) => a.startsWith('--baseline='))?.slice('--baseline='.length);

// pgcrypto n'est pas empaqueté dans PGlite ; le schéma ne s'en sert que pour
// gen_random_uuid(), dans le cœur de Postgres depuis la 13.
const noPgcrypto = (sql) =>
  sql.replace(/create extension if not exists pgcrypto;/i, '-- (pgcrypto: cœur PG13+)');

const SHIM = read('scripts/rls/supabase-shim.sql');
// Les privilèges par défaut ne valent que pour les tables créées ensuite : on
// rattrape celles que schema.sql vient de créer.
const GRANTS = 'grant select, insert, update, delete on all tables in schema public to anon, authenticated;';

const migrations = readdirSync(resolve(ROOT, 'supabase/migrations'))
  .filter((f) => f.endsWith('.sql'))
  .sort();

let failed = false;
const say = (ok, msg) => {
  if (!ok) failed = true;
  console.log(`  ${ok ? ' ok ' : 'FAIL'}  ${msg}`);
};

async function apply(db, label, sql) {
  try {
    await db.exec(sql);
    say(true, label);
  } catch (e) {
    say(false, `${label}\n        ${e.message}`);
    throw e;
  }
}

/** Tout ce qui doit être identique entre une base neuve et une base migrée. */
async function fingerprint(db) {
  const q = async (sql) => (await db.query(sql)).rows;
  return {
    policies: await q(`select schemaname||'.'||tablename||'.'||policyname as k, cmd, qual, with_check
                       from pg_policies where schemaname = 'public' order by 1`),
    fonctions: await q(`select p.proname, pg_get_function_identity_arguments(p.oid) as args, p.prosecdef
                        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                        where n.nspname = 'public' order by 1, 2`),
    triggers: await q(`select c.relname||'.'||t.tgname as k from pg_trigger t
                       join pg_class c on c.oid = t.tgrelid
                       join pg_namespace n on n.oid = c.relnamespace
                       where n.nspname = 'public' and not t.tgisinternal order by 1`),
    contraintes: await q(`select conrelid::regclass::text||'.'||conname as k, pg_get_constraintdef(oid) as def
                          from pg_constraint where connamespace = 'public'::regnamespace order by 1`),
  };
}

/** Rejoue le fichier de test en lisant le journal assertion par assertion. */
async function runAssertions(db) {
  const file = read('supabase/tests/rls.test.sql');
  const cut = file.indexOf('do $report$');
  const out = await db.exec(
    file.slice(0, cut) + `select ok, name, coalesce(detail, '') as detail from _results order by ord;`,
  );
  const rows = out[out.length - 1].rows;
  await db.exec('rollback');
  for (const r of rows.filter((r) => !r.ok)) console.log(`  FAIL  ${r.name} — ${r.detail}`);
  say(
    rows.every((r) => r.ok),
    `${rows.length} assertions, ${rows.filter((r) => !r.ok).length} en échec`,
  );
  return rows;
}

console.log('== A. installation neuve : schema.sql ==');
const fresh = await PGlite.create();
await apply(fresh, 'shim Supabase', SHIM);
await apply(fresh, 'supabase/schema.sql', noPgcrypto(read('supabase/schema.sql')));
await apply(fresh, 'grants', GRANTS);
await runAssertions(fresh);

if (!baseline) {
  console.log('\n== B. parité migrations : ignorée ==');
  console.log('  Passez --baseline=<ref git> (le commit AVANT les migrations) pour la vérifier.');
} else {
  console.log(`\n== B. ancien schéma (${baseline}) + données + migrations ==`);
  const old = noPgcrypto(
    execFileSync('git', ['show', `${baseline}:supabase/schema.sql`], {
      cwd: ROOT,
      encoding: 'utf8',
      maxBuffer: 1 << 24,
    }),
  );

  const migrated = await PGlite.create();
  await apply(migrated, 'shim Supabase', SHIM);
  await apply(migrated, `schema.sql @${baseline}`, old);
  await apply(migrated, 'grants', GRANTS);
  await apply(migrated, 'données déjà en base', read('scripts/rls/legacy-fixture.sql'));
  for (const m of migrations) await apply(migrated, m, read(`supabase/migrations/${m}`));

  console.log('\n  -- l\'état final est-il identique à une installation neuve ?');
  const a = await fingerprint(fresh);
  const b = await fingerprint(migrated);
  for (const k of Object.keys(a)) {
    const same = JSON.stringify(a[k]) === JSON.stringify(b[k]);
    say(same, `${k} : ${same ? `identiques (${a[k].length})` : `neuf=${a[k].length} migré=${b[k].length}`}`);
    if (!same) {
      const ka = new Set(a[k].map((r) => JSON.stringify(r)));
      const kb = new Set(b[k].map((r) => JSON.stringify(r)));
      for (const x of ka) if (!kb.has(x)) console.log(`        neuf seul  : ${x}`);
      for (const x of kb) if (!ka.has(x)) console.log(`        migré seul : ${x}`);
    }
  }

  console.log('\n  -- les données déjà présentes ont-elles survécu ?');
  for (const [label, sql, expected] of [
    ['réponses', 'select count(*)::int n from public.answers', 2],
    ['questions', 'select count(*)::int n from public.daily_prompts', 1],
    ['réactions', 'select count(*)::int n from public.reactions', 1],
    ['liens', 'select count(*)::int n from public.links', 1],
  ]) {
    const n = (await migrated.query(sql)).rows[0].n;
    say(n === expected, `${label} : ${n} (attendu ${expected})`);
  }

  console.log('\n  -- les assertions passent-elles sur la base migrée ?');
  await runAssertions(migrated);
}

console.log(failed ? '\nÉCHEC' : '\nTout est vert.');
process.exit(failed ? 1 : 0);
