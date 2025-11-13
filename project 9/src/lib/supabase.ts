import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || '';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || '';

if (!supabaseUrl || !supabaseAnonKey) {
  console.error('Supabase configuration missing:', {
    hasUrl: !!supabaseUrl,
    hasKey: !!supabaseAnonKey,
    env: import.meta.env
  });
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true,
    flowType: 'pkce', // Use PKCE flow for better security
    // Disable the built-in throttling to allow multiple requests
    dangerouslyAllowBrowserRememberMe: true,
  },
  global: {
    headers: {
      'X-Client-Info': 'mediatiger-web',
    },
  },
});

export const isCORSError = (error: any) => {
  return (
    error.message?.includes('CORS') ||
    error.code === 'CORS_ERROR' ||
    (error.name === 'TypeError' && error.message === 'Failed to fetch')
  );
};
