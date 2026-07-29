import { Alert, Platform } from 'react-native';

/**
 * Confirmation d'une action destructrice, sur les trois plateformes.
 *
 * `Alert.alert` n'a pas d'implémentation sur react-native-web : sans cette
 * bascule, la branche web exécute l'action au premier clic. Un seul point de
 * passage pour que ce piège ne se reproduise pas écran par écran.
 */
export function confirmDestructive(
  title: string,
  message: string,
  confirmLabel: string,
  cancelLabel: string,
  onConfirm: () => void,
) {
  if (Platform.OS === 'web') {
    if (typeof window === 'undefined' || window.confirm(`${title}\n\n${message}`)) {
      onConfirm();
    }
    return;
  }

  Alert.alert(title, message, [
    { text: cancelLabel, style: 'cancel' },
    { text: confirmLabel, style: 'destructive', onPress: onConfirm },
  ]);
}
