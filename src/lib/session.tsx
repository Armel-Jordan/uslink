import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';

import { data } from '@/lib/data';
import type { Link, LinkMode, Profile, Session } from '@/lib/types';

type SessionContextValue = {
  /** True until the stored session (and profile/link) has been resolved. */
  loading: boolean;
  isDemo: boolean;
  session: Session | null;
  profile: Profile | null;
  link: Link | null;
  refresh: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string, displayName: string) => Promise<{ needsConfirmation: boolean }>;
  signOut: () => Promise<void>;
  createLink: (mode: LinkMode) => Promise<Link>;
  joinLink: (code: string) => Promise<Link>;
  regenerateInvite: () => Promise<string>;
  leaveLink: () => Promise<void>;
  updateProfile: (patch: Partial<Pick<Profile, 'displayName' | 'avatarEmoji'>>) => Promise<void>;
};

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const [loading, setLoading] = useState(true);
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [link, setLink] = useState<Link | null>(null);

  const loadForSession = useCallback(async (next: Session | null) => {
    setSession(next);
    if (!next) {
      setProfile(null);
      setLink(null);
      return;
    }
    const [nextProfile, nextLink] = await Promise.all([
      data.getProfile().catch(() => null),
      data.getLink().catch(() => null),
    ]);
    setProfile(nextProfile);
    setLink(nextLink);
  }, []);

  useEffect(() => {
    let active = true;

    (async () => {
      const current = await data.getSession().catch(() => null);
      if (!active) return;
      await loadForSession(current);
      if (active) setLoading(false);
    })();

    const unsubscribe = data.onSessionChange((next) => {
      if (active) void loadForSession(next);
    });

    return () => {
      active = false;
      unsubscribe();
    };
  }, [loadForSession]);

  const refresh = useCallback(async () => {
    const current = await data.getSession().catch(() => null);
    await loadForSession(current);
  }, [loadForSession]);

  const value = useMemo<SessionContextValue>(
    () => ({
      loading,
      isDemo: data.isDemo,
      session,
      profile,
      link,
      refresh,
      signIn: async (email, password) => {
        await data.signIn(email, password);
        await refresh();
      },
      signUp: async (email, password, displayName) => {
        const result = await data.signUp(email, password, displayName);
        await refresh();
        return result;
      },
      signOut: async () => {
        await data.signOut();
        setSession(null);
        setProfile(null);
        setLink(null);
      },
      createLink: async (mode) => {
        const created = await data.createLink(mode);
        setLink(created);
        return created;
      },
      joinLink: async (code) => {
        const joined = await data.joinLink(code);
        setLink(joined);
        return joined;
      },
      regenerateInvite: async () => {
        const code = await data.regenerateInvite();
        setLink((current) => (current ? { ...current, inviteCode: code } : current));
        return code;
      },
      leaveLink: async () => {
        await data.leaveLink();
        setLink(null);
      },
      updateProfile: async (patch) => {
        const updated = await data.updateProfile(patch);
        setProfile(updated);
      },
    }),
    [loading, session, profile, link, refresh],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession() {
  const ctx = useContext(SessionContext);
  if (!ctx) throw new Error('useSession must be used inside <SessionProvider>.');
  return ctx;
}
