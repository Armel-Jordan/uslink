/**
 * UsLink design tokens.
 *
 * The palette is warm and intimate rather than "app blue": a paper-cream ground,
 * a terracotta accent for anything the user acts on, and a plum tint for the
 * partner's voice so the two people in a couple are always visually distinct.
 */

import '@/global.css';

import { Platform } from 'react-native';

export const Colors = {
  light: {
    text: '#241B18',
    textSecondary: '#7A6259',
    background: '#FFF8F4',
    backgroundElement: '#FFFFFF',
    backgroundSelected: '#F3E4DA',
    border: '#EADCD2',
    accent: '#D9694C',
    accentText: '#FFFFFF',
    accentSoft: '#FBE8E1',
    mine: '#D9694C',
    theirs: '#7C5A8E',
    success: '#2F7D5B',
    danger: '#B3402C',
  },
  dark: {
    text: '#F6EDE8',
    textSecondary: '#B0988E',
    background: '#14100F',
    backgroundElement: '#1F1917',
    backgroundSelected: '#2C2320',
    border: '#332A26',
    accent: '#E8825F',
    accentText: '#1A1211',
    accentSoft: '#2A1E1A',
    mine: '#E8825F',
    theirs: '#B08FC4',
    success: '#5BB98B',
    danger: '#E2705A',
  },
} as const;

export type ThemeColor = keyof typeof Colors.light & keyof typeof Colors.dark;
export type Theme = (typeof Colors)['light'];

export const Fonts = Platform.select({
  ios: {
    sans: 'system-ui',
    serif: 'ui-serif',
    rounded: 'ui-rounded',
    mono: 'ui-monospace',
  },
  default: {
    sans: 'normal',
    serif: 'serif',
    rounded: 'normal',
    mono: 'monospace',
  },
  web: {
    sans: 'var(--font-display)',
    serif: 'var(--font-serif)',
    rounded: 'var(--font-rounded)',
    mono: 'var(--font-mono)',
  },
});

export const Spacing = {
  half: 2,
  one: 4,
  two: 8,
  three: 16,
  four: 24,
  five: 32,
  six: 64,
} as const;

export const Radius = {
  sm: 8,
  md: 14,
  lg: 22,
  pill: 999,
} as const;

export const BottomTabInset = Platform.select({ ios: 50, android: 80 }) ?? 0;
export const MaxContentWidth = 800;
