import type { LinkMode } from '@/lib/types';

/**
 * Fallback question bank. The AI Edge Function personalises questions when it
 * can; this library keeps the daily ritual alive when it can't (no API key,
 * API error, or demo mode). Same shape as the AI output so callers can't tell
 * the difference beyond `source`.
 */
export type LibraryPrompt = { question: string; category: string };

const couple: LibraryPrompt[] = [
  { question: "Quel petit geste de ma part t'a marqué cette semaine ?", category: 'gratitude' },
  { question: 'À quel moment t’es-tu senti(e) le plus proche de moi récemment ?', category: 'intimité' },
  { question: 'Quelle chose n’ai-je pas encore comprise sur toi ?', category: 'profondeur' },
  { question: 'Si on partait trois jours demain, où irions-nous et pourquoi là ?', category: 'rêves' },
  { question: 'Qu’est-ce qui t’a fait rire tout seul aujourd’hui ?', category: 'légèreté' },
  { question: 'De quoi as-tu besoin de moi cette semaine, concrètement ?', category: 'besoins' },
  { question: 'Quel souvenir de nous te revient le plus souvent ?', category: 'souvenirs' },
  { question: 'Qu’as-tu appris sur toi ce mois-ci ?', category: 'croissance' },
  { question: 'Qu’est-ce que tu redoutes de me dire, en petit ?', category: 'vulnérabilité' },
  { question: 'Quelle habitude aimerais-tu qu’on prenne ensemble ?', category: 'projets' },
  { question: 'Comment aimerais-tu être réconforté(e) quand ça va mal ?', category: 'besoins' },
  { question: 'Quel compliment aurais-tu aimé entendre plus souvent ?', category: 'gratitude' },
  { question: 'Quelle version de nous dans cinq ans te rend heureux(se) ?', category: 'rêves' },
  { question: 'Qu’est-ce qui t’occupe l’esprit en ce moment, même si c’est flou ?', category: 'profondeur' },
  { question: 'Quel moment de ta journée aurais-tu voulu que je voie ?', category: 'quotidien' },
  { question: 'Qu’est-ce qui te rassure chez nous, en ce moment ?', category: 'intimité' },
  { question: 'Y a-t-il quelque chose dont on évite de parler ?', category: 'vulnérabilité' },
  { question: 'Quelle chanson te fait penser à nous, et depuis quand ?', category: 'souvenirs' },
  { question: 'Qu’est-ce que tu aimes chez toi que je ne remarque pas assez ?', category: 'estime' },
  { question: 'Comment était ton énergie aujourd’hui, de 1 à 10 — et pourquoi ?', category: 'quotidien' },
];

const friends: LibraryPrompt[] = [
  { question: 'Quelle décision récente t’a demandé du courage ?', category: 'croissance' },
  { question: 'Qu’est-ce qui t’enthousiasme en ce moment, même si c’est bête ?', category: 'légèreté' },
  { question: 'Quel conseil te donnerais-tu il y a un an ?', category: 'profondeur' },
  { question: 'Qu’est-ce que tu procrastines depuis trop longtemps ?', category: 'honnêteté' },
  { question: 'Quel est le meilleur truc que tu aies découvert ce mois-ci ?', category: 'découverte' },
  { question: 'De quoi es-tu fier(ère) sans jamais le dire ?', category: 'estime' },
  { question: 'Quelle amitié aimerais-tu raviver ?', category: 'liens' },
  { question: 'Qu’est-ce qui te fatigue en ce moment ?', category: 'honnêteté' },
  { question: 'Quel projet reprendrais-tu si le temps n’était pas un problème ?', category: 'rêves' },
  { question: 'Qu’as-tu changé d’avis sur, récemment ?', category: 'profondeur' },
];

const banks: Record<LinkMode, LibraryPrompt[]> = {
  couple,
  friends,
  random: friends,
};

/**
 * Deterministic pick: the same link gets the same question on the same day
 * (so two devices agree without coordinating), and consecutive days differ.
 */
export function pickLibraryPrompt(mode: LinkMode, linkId: string, date: string): LibraryPrompt {
  const bank = banks[mode] ?? couple;
  const seed = hash(`${linkId}:${date}`);
  return bank[seed % bank.length];
}

function hash(input: string): number {
  let h = 2166136261;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h);
}

export const REACTIONS = ['❤️', '🥲', '😂', '🤯', '🙏'] as const;
