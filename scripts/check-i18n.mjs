/**
 * Ce que tsc ne peut pas voir : un placeholder perdu en traduction.
 *
 * Le typage garantit que chaque langue a toutes les cles et les bonnes
 * signatures. Il ne garantit pas que la traduction espagnole de
 * `greeting(name)` utilise encore `name` — une fonction qui ignore son
 * parametre compile parfaitement et affiche « Hola » sans prenom.
 *
 * npm run check:i18n
 */
import { readFileSync } from 'node:fs';

import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const CODES = ['fr', 'es', 'pt', 'it', 'ar', 'zh', 'ja'];

// clé -> paramètres qui DOIVENT apparaître dans le corps de la fonction
const FONCTIONS = {
  greeting: ['name'],
  waitingPartner: ['name'],
  frozen: ['name'],
  linkedWith: ['name'],
  timeZoneHint: ['zone', 'hour'],
};

let problemes = 0;
const fail = (m) => {
  problemes++;
  console.log('  ✗ ' + m);
};

for (const code of CODES) {
  const src = readFileSync(`${REPO}/src/lib/i18n/${code}.ts`, 'utf8');
  const lignes = src.split('\n');
  const trouve = [];

  for (const [cle, params] of Object.entries(FONCTIONS)) {
    const i = lignes.findIndex((l) => l.trim().startsWith(cle + ':'));
    if (i < 0) {
      fail(`${code}.${cle} : clé absente`);
      continue;
    }
    // fr.ts est écrit à la main et coupe après la flèche; les fichiers générés
    // tiennent sur une ligne. On recolle les deux formes.
    const ligne = lignes[i] + (lignes[i].trimEnd().endsWith('=>') ? lignes[i + 1] : '');
    const corps = ligne.split('=>')[1] ?? '';
    for (const p of params) {
      if (!new RegExp(`\\b${p}\\b`).test(corps)) fail(`${code}.${cle} : paramètre « ${p} » jamais utilisé`);
    }
    trouve.push(cle);
  }

  const streak = lignes.find((l) => l.trim().startsWith('streak:'));
  if (!streak) fail(`${code}.streak : absent`);
  else {
    const formes = [...streak.matchAll(/["']?(zero|one|two|few|many|other)["']?\s*:/g)].map((m) => m[1]);
    const n = (streak.match(/\{n\}/g) || []).length;
    if (formes.length !== n) fail(`${code}.streak : ${formes.length} forme(s) mais ${n} occurrence(s) de {n}`);
    console.log(`  ${code} : ${trouve.length}/5 fonctions OK, pluriel [${formes.join(', ')}]`);
  }
}

// Aucun texte français ne doit avoir fui dans les autres langues.
const MOTS_FR = /\b(Votre|Vous|votre|Bientôt|Quitter|Enregistrer|Réessayer|Chargement|Annuler|Partager)\b/g;
for (const code of CODES.filter((c) => c !== 'fr')) {
  const corps = readFileSync(`${REPO}/src/lib/i18n/${code}.ts`, 'utf8').split('export const')[1] ?? '';
  const hits = [...new Set(corps.match(MOTS_FR) || [])];
  if (hits.length) fail(`${code} : français résiduel → ${hits.join(', ')}`);
}

// Les banques de questions: 7 langues, 20 + 10 chacune.
const q = readFileSync(`${REPO}/src/lib/i18n/questions.ts`, 'utf8');
for (const code of CODES) {
  const bloc = q.split(new RegExp(`\\n  ${code}: \\{`))[1];
  if (!bloc) {
    fail(`questions.ts : ${code} absent`);
    continue;
  }
  const tronque = bloc.split(/\n  [a-z]{2}: \{/)[0];
  const n = (tronque.match(/\{ question:/g) || []).length;
  if (n !== 30) fail(`questions.ts : ${code} a ${n} questions au lieu de 30`);
}

console.log(problemes ? `\n${problemes} problème(s)` : '\nAucun problème.');
process.exit(problemes ? 1 : 0);
