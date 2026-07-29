/**
 * Pluriel selon les catégories CLDR de la locale.
 *
 * Le français n'a que deux formes, l'arabe en a six (zéro, un, deux, quelques,
 * beaucoup, autre) et le chinois une seule. Coder « n <= 1 ? singulier :
 * pluriel » marcherait en français et produirait de l'arabe faux, alors on
 * délègue le choix de la forme à `Intl.PluralRules`.
 */
export type PluralForms = Partial<Record<Intl.LDMLPluralRule, string>>;

export function makePlural(locale: string, forms: PluralForms): (n: number) => string {
  let rules: Intl.PluralRules | null = null;
  try {
    rules = new Intl.PluralRules(locale);
  } catch {
    // Hermes sans ICU complet : on retombe sur la règle à deux formes, qui est
    // au moins juste pour les langues européennes de ce dictionnaire.
    rules = null;
  }

  return (n: number) => {
    const category = rules ? rules.select(n) : n === 1 ? 'one' : 'other';
    const template = forms[category] ?? forms.other ?? '';
    return template.replace('{n}', String(n));
  };
}
