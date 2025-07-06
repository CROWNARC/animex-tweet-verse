import { useEffect, useState } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { PostCard } from '@/components/PostCard';
import { CreatePost } from '@/components/CreatePost';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Bell, Search, Settings, LogOut, Users } from 'lucide-react';
import { toast } from '@/hooks/use-toast';
import { Link, useNavigate } from 'react-router-dom';

interface Post {
  id: string;
  user_id: string;
  username: string;
  user_avatar?: string;
  content: string;
  post_type: string;
  media_url?: string;
  link_url?: string;
  link_title?: string;
  anime_id?: string;
  anime_title?: string;
  anime_image?: string;
  like_count: number;
  retweet_count: number;
  comment_count: number;
  created_at: string;
  original_post_id?: string;
}

const Index = () => {
  const { user, loading, signOut, isAdmin } = useAuth();
  const [posts, setPosts] = useState<Post[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [filteredPosts, setFilteredPosts] = useState<Post[]>([]);
  const navigate = useNavigate();

  useEffect(() => {
    if (!loading && !user) {
      navigate('/auth');
    }
  }, [user, loading, navigate]);

  useEffect(() => {
    if (user) {
      fetchPosts();
      setupRealtimeSubscription();
    }
  }, [user]);

  useEffect(() => {
    if (searchQuery.trim()) {
      const filtered = posts.filter(post => 
        post.content.toLowerCase().includes(searchQuery.toLowerCase()) ||
        post.anime_title?.toLowerCase().includes(searchQuery.toLowerCase()) ||
        post.username.toLowerCase().includes(searchQuery.toLowerCase())
      );
      setFilteredPosts(filtered);
    } else {
      setFilteredPosts(posts);
    }
  }, [searchQuery, posts]);

  const fetchPosts = async () => {
    try {
      // Fetch approved posts with like/retweet status
      const { data: postsData, error } = await supabase
        .from('posts')
        .select('*')
        .eq('status', 'approved')
        .order('created_at', { ascending: false })
        .limit(50);

      if (error) throw error;

      if (user && postsData) {
        // Check which posts are liked/retweeted by current user
        const postIds = postsData.map(p => p.id);
        
        const [likesData, retweetsData] = await Promise.all([
          supabase.from('likes').select('post_id').eq('user_id', user.id).in('post_id', postIds),
          supabase.from('retweets').select('post_id').eq('user_id', user.id).in('post_id', postIds)
        ]);

        const likedPosts = new Set(likesData.data?.map(l => l.post_id) || []);
        const retweetedPosts = new Set(retweetsData.data?.map(r => r.post_id) || []);

        const enhancedPosts = postsData.map(post => ({
          ...post,
          isLiked: likedPosts.has(post.id),
          isRetweeted: retweetedPosts.has(post.id)
        }));

        setPosts(enhancedPosts);
      }
    } catch (error) {
      console.error('Error fetching posts:', error);
      toast({ title: "Error", description: "Failed to load posts", variant: "destructive" });
    }
  };

  const setupRealtimeSubscription = () => {
    const channel = supabase
      .channel('posts-changes')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'posts', filter: 'status=eq.approved' },
        () => {
          fetchPosts();
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'likes' },
        () => {
          fetchPosts();
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'retweets' },
        () => {
          fetchPosts();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  };

  const handleSignOut = async () => {
    await signOut();
    navigate('/auth');
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary mx-auto mb-4"></div>
          <p className="text-muted-foreground">Loading...</p>
        </div>
      </div>
    );
  }

  if (!user) return null;

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="sticky top-0 z-50 border-b border-border bg-background/80 backdrop-blur-md">
        <div className="max-w-4xl mx-auto px-4 h-16 flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <h1 className="text-2xl font-bold bg-gradient-to-r from-primary to-purple-400 bg-clip-text text-transparent">
              AnimeZ
            </h1>
            {isAdmin && (
              <Badge variant="secondary" className="bg-gradient-to-r from-yellow-500/20 to-orange-500/20 text-yellow-300 border-yellow-500/30">
                <Users className="mr-1 h-3 w-3" />
                Admin
              </Badge>
            )}
          </div>

          <div className="flex-1 max-w-md mx-4">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground h-4 w-4" />
              <Input
                placeholder="Search posts, anime, users..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-10 bg-muted/50"
              />
            </div>
          </div>

          <div className="flex items-center space-x-3">
            <Button variant="ghost" size="sm">
              <Bell className="h-5 w-5" />
            </Button>
            
            {isAdmin && (
              <Button variant="ghost" size="sm" asChild>
                <Link to="/admin">
                  <Settings className="h-5 w-5" />
                </Link>
              </Button>
            )}

            <Avatar className="h-8 w-8 cursor-pointer">
              <AvatarImage src={user.profile?.avatar_url} />
              <AvatarFallback className="bg-primary text-primary-foreground text-sm">
                {user.profile?.username?.[0]?.toUpperCase() || 'U'}
              </AvatarFallback>
            </Avatar>

            <Button variant="ghost" size="sm" onClick={handleSignOut}>
              <LogOut className="h-5 w-5" />
            </Button>
          </div>
        </div>
      </header>

      {/* Main content */}
      <main className="max-w-2xl mx-auto px-4 py-6 space-y-6">
        <CreatePost />
        
        <div className="space-y-4">
          {filteredPosts.length === 0 ? (
            <div className="text-center py-12">
              <p className="text-muted-foreground">
                {searchQuery ? 'No posts found matching your search.' : 'No posts yet. Be the first to post!'}
              </p>
            </div>
          ) : (
            filteredPosts.map((post) => (
              <PostCard key={post.id} post={post} />
            ))
          )}
        </div>
      </main>
    </div>
  );
};

export default Index;
