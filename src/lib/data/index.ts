import { isSupabaseConfigured } from '@/lib/supabase';

import type { DataAdapter } from './adapter';
import { demoAdapter } from './demo';
import { supabaseAdapter } from './supabase';

/** One adapter for the whole app, chosen once at startup. */
export const data: DataAdapter = isSupabaseConfigured ? supabaseAdapter : demoAdapter;

export { DataError, deviceTimeZone } from './adapter';
export type { DataAdapter, DataErrorCode } from './adapter';
