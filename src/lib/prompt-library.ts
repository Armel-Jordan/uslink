import { LIBRARY, type LibraryItem } from '@/lib/i18n/questions';
import { FALLBACK_LOCALE, type Locale } from '@/lib/strings';
import type { ItemKind, LinkMode } from '@/lib/types';

/**
 * Banque de repli. L'Edge Function personnalise les contenus quand elle peut ;
 * cette banque tient le rituel quand elle ne peut pas (pas de clé API, erreur
 * d'API, mode démo). Même forme que la sortie du modèle, pour que l'appelant ne
 * voie la différence que dans `source`.
 *
 * C'est la SEULE banque du produit. L'Edge Function n'en a plus : dupliquée
 * côté serveur, elle servait du français sous une interface arabe.
 */
export type { LibraryItem };

/** L'ordre d'affichage : on débat, on répond, puis on relève le défi du soir. */
export const ITEM_KINDS: ItemKind[] = ['debate', 'question', 'challenge'];

/**
 * Tirage déterministe : le même lien reçoit les mêmes contenus le même jour
 * (donc deux appareils s'accordent sans se coordonner), et deux jours de suite
 * diffèrent. `locale` est celle du LIEN, jamais celle de l'appareil.
 */
export function pickLibraryItem(
  kind: ItemKind,
  mode: LinkMode,
  linkId: string,
  date: string,
  locale: Locale,
): LibraryItem {
  const banks = LIBRARY[locale] ?? LIBRARY[FALLBACK_LOCALE];
  const bank = (mode === 'couple' ? banks.couple : banks.friends)[kind];
  // Le type entre dans la graine : sans lui, les trois contenus du jour
  // tomberaient tous au même index et se répondraient l'un l'autre.
  const seed = hash(`${linkId}:${date}:${kind}`);
  return bank[seed % bank.length];
}

export function pickLibraryDay(
  mode: LinkMode,
  linkId: string,
  date: string,
  locale: Locale,
): { kind: ItemKind; item: LibraryItem }[] {
  return ITEM_KINDS.map((kind) => ({ kind, item: pickLibraryItem(kind, mode, linkId, date, locale) }));
}

function hash(input: string): number {
  let h = 2166136261;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h);
}

/**
 * Longueur minimale d'une réponse écrite. Doit rester alignée sur
 * `has_answered` dans supabase/schema.sql : la base gèle la réponse dès que le
 * partenaire a répondu, donc l'interface doit empêcher d'envoyer trop court
 * plutôt que de laisser quelqu'un rester figé avec « . ».
 */
export const MIN_ANSWER_LENGTH = 15;

export const REACTIONS = ['❤️', '🥲', '😂', '🤯', '🙏'] as const;
