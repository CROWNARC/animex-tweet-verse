import { supabase } from '@/integrations/supabase/client';
import { User, Session } from '@supabase/supabase-js';

export interface AuthUser extends User {
  profile?: {
    username: string;
    avatar_url?: string;
    bio?: string;
    is_admin?: boolean;
  };
}

export const authService = {
  async signUp(email: string, password: string, username: string) {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: `${window.location.origin}/`,
        data: {
          username,
        }
      }
    });

    if (error) throw error;

    // Create user profile
    if (data.user) {
      const { error: profileError } = await supabase
        .rpc('set_config', { 
          setting_name: 'app.current_user_id', 
          setting_value: data.user.id 
        });

      if (!profileError) {
        await supabase.from('user_profiles').insert({
          user_id: data.user.id,
          username,
          avatar_url: '',
          bio: '',
          is_admin: false
        });
      }
    }

    return { data, error: null };
  },

  async signIn(email: string, password: string) {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    return { data, error };
  },

  async signOut() {
    const { error } = await supabase.auth.signOut();
    return { error };
  },

  async getCurrentUser(): Promise<AuthUser | null> {
    const { data: { user } } = await supabase.auth.getUser();
    
    if (!user) return null;

    // Set the user context
    await supabase.rpc('set_config', { 
      setting_name: 'app.current_user_id', 
      setting_value: user.id 
    });

    // Get user profile
    const { data: profile } = await supabase
      .from('user_profiles')
      .select('*')
      .eq('user_id', user.id)
      .single();

    return {
      ...user,
      profile: profile || undefined
    } as AuthUser;
  },

  onAuthStateChange(callback: (session: Session | null, user: AuthUser | null) => void) {
    return supabase.auth.onAuthStateChange((event, session) => {
      let authUser: AuthUser | null = null;
      
      if (session?.user) {
        authUser = {
          ...session.user,
          profile: undefined
        } as AuthUser;
        
        // Defer async operations to prevent deadlock
        setTimeout(async () => {
          // Set user context
          await supabase.rpc('set_config', { 
            setting_name: 'app.current_user_id', 
            setting_value: session.user.id 
          });

          // Get profile data
          const { data: profile } = await supabase
            .from('user_profiles')
            .select('*')
            .eq('user_id', session.user.id)
            .single();

          // Update the user with profile data
          const updatedUser = {
            ...session.user,
            profile: profile || undefined
          } as AuthUser;
          
          callback(session, updatedUser);
        }, 0);
      }

      callback(session, authUser);
    });
  }
};