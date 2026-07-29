import { getLocales } from 'expo-localization';
import { I18nManager } from 'react-native';

import { ar } from './ar';
import { es } from './es';
import { fr, type Dictionary } from './fr';
import { it } from './it';
import { ja } from './ja';
import { pt } from './pt';
import { zh } from './zh';

export type { Dictionary };

/** Le français est la référence : toute clé absente ailleurs ne compile pas. */
export const DICTIONARIES = { fr, es, pt, it, ar, zh, ja } satisfies Record<string, Dictionary>;

export type Locale = keyof typeof DICTIONARIES;

export const LOCALES = Object.keys(DICTIONARIES) as Locale[];

/**
 * Endonymes : chaque langue s'écrit dans sa propre langue. On ne traduit pas
 * un nom de langue — quelqu'un qui cherche « 日本語 » ne cherche pas « japonais ».
 */
export const LOCALE_NAMES: Record<Locale, string> = {
  fr: 'Français',
  es: 'Español',
  pt: 'Português',
  it: 'Italiano',
  ar: 'العربية',
  zh: '简体中文',
  ja: '日本語',
};

/** Langues écrites de droite à gauche parmi celles qu'on sert. */
const RTL_LOCALES: Locale[] = ['ar'];

export const FALLBACK_LOCALE: Locale = 'fr';

function isLocale(code: string | null | undefined): code is Locale {
  return Boolean(code) && (LOCALES as string[]).includes(code as string);
}

/**
 * Première langue de l'appareil qu'on sait servir. `getLocales()` rend la liste
 * ordonnée par préférence de l'utilisateur : on la respecte plutôt que de ne
 * regarder que la première.
 */
export function resolveLocale(): Locale {
  try {
    for (const entry of getLocales()) {
      if (isLocale(entry.languageCode)) return entry.languageCode;
    }
  } catch {
    // getLocales peut échouer très tôt au démarrage sur certaines plateformes.
  }
  return FALLBACK_LOCALE;
}

export const locale: Locale = resolveLocale();

export const isRTL = RTL_LOCALES.includes(locale);

/**
 * La direction de mise en page est un réglage de processus dans React Native :
 * elle est lue au démarrage. On la pose ici, au chargement du module, donc
 * avant le premier rendu — mais un utilisateur qui change la langue de son
 * système pendant que l'app est en mémoire ne verra la bascule qu'au
 * redémarrage suivant. C'est le comportement standard, pas un oubli.
 */
I18nManager.allowRTL(true);
if (I18nManager.isRTL !== isRTL) {
  I18nManager.forceRTL(isRTL);
}

export const t: Dictionary = DICTIONARIES[locale];
