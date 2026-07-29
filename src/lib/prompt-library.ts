import { QUESTIONS, type LibraryPrompt } from '@/lib/i18n/questions';
import { FALLBACK_LOCALE, type Locale } from '@/lib/strings';
import type { LinkMode } from '@/lib/types';

/**
 * Fallback question bank. The AI Edge Function personalises questions when it
 * can; this library keeps the daily ritual alive when it can't (no API key,
 * API error, or demo mode). Same shape as the AI output so callers can't tell
 * the difference beyond `source`.
 *
 * C'est la SEULE banque de repli du produit. L'Edge Function n'en a plus:
 * dupliquée côté serveur, elle servait du français sous une interface arabe.
 */
export type { LibraryPrompt };

/**
 * Deterministic pick: the same link gets the same question on the same day
 * (so two devices agree without coordinating), and consecutive days differ.
 *
 * `locale` est celle du LIEN, pas celle de l'appareil : les deux partenaires
 * doivent lire la même question, même si leurs téléphones sont réglés
 * différemment.
 */
export function pickLibraryPrompt(
  mode: LinkMode,
  linkId: string,
  date: string,
  locale: Locale,
): LibraryPrompt {
  const banks = QUESTIONS[locale] ?? QUESTIONS[FALLBACK_LOCALE];
  const bank = mode === 'couple' ? banks.couple : banks.friends;
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
