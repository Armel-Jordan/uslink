import 'react-native-url-polyfill/auto';

import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import { AppState, Platform } from 'react-native';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

/** When false the app runs entirely on the local demo adapter (no backend needed). */
export const isSupabaseConfigured = Boolean(url && anonKey);

export const supabase = isSupabaseConfigured
  ? createClient(url as string, anonKey as string, {
      auth: {
        storage: AsyncStorage,
        persistSession: true,
        autoRefreshToken: true,
        // Deep-link based auth is not used; tokens never arrive via URL.
        detectSessionInUrl: false,
      },
    })
  : null;

// Supabase recommends pausing token refresh while the app is backgrounded.
if (supabase && Platform.OS !== 'web') {
  AppState.addEventListener('change', (state) => {
    if (state === 'active') {
      supabase.auth.startAutoRefresh();
    } else {
      supabase.auth.stopAutoRefresh();
    }
  });
}

export function requireSupabase() {
  if (!supabase) {
    throw new Error('Supabase is not configured (EXPO_PUBLIC_SUPABASE_URL / _ANON_KEY).');
  }
  return supabase;
}
