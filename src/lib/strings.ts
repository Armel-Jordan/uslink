/**
 * Toute la copie visible vit dans `src/lib/i18n/` : un fichier par langue,
 * tous typés `Dictionary` d'après le français, donc une traduction incomplète
 * ne compile pas.
 *
 * Ce module reste le point d'entrée des écrans — ils importent `t` d'ici et
 * n'ont jamais à savoir quelle langue est active.
 */
export { DICTIONARIES, FALLBACK_LOCALE, isRTL, LOCALE_NAMES, LOCALES, locale, t } from './i18n';
export type { Dictionary, Locale } from './i18n';
