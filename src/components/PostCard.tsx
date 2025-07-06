import { useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Heart, MessageCircle, Repeat2, Share, MoreHorizontal, Info } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';

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
  isLiked?: boolean;
  isRetweeted?: boolean;
}

interface PostCardProps {
  post: Post;
}

export const PostCard = ({ post }: PostCardProps) => {
  const { user } = useAuth();
  const [isLiked, setIsLiked] = useState(post.isLiked || false);
  const [isRetweeted, setIsRetweeted] = useState(post.isRetweeted || false);
  const [likeCount, setLikeCount] = useState(post.like_count);
  const [retweetCount, setRetweetCount] = useState(post.retweet_count);
  const [showAnimeInfo, setShowAnimeInfo] = useState(false);

  const handleLike = async () => {
    if (!user) {
      toast({ title: "Error", description: "Please sign in to like posts", variant: "destructive" });
      return;
    }

    try {
      if (isLiked) {
        const { error } = await supabase
          .from('likes')
          .delete()
          .eq('user_id', user.id)
          .eq('post_id', post.id);

        if (error) throw error;
        setIsLiked(false);
        setLikeCount(prev => prev - 1);
      } else {
        const { error } = await supabase
          .from('likes')
          .insert({
            user_id: user.id,
            post_id: post.id
          });

        if (error) throw error;
        setIsLiked(true);
        setLikeCount(prev => prev + 1);
      }
    } catch (error) {
      toast({ title: "Error", description: "Failed to update like", variant: "destructive" });
    }
  };

  const handleRetweet = async () => {
    if (!user) {
      toast({ title: "Error", description: "Please sign in to retweet posts", variant: "destructive" });
      return;
    }

    try {
      if (isRetweeted) {
        const { error } = await supabase
          .from('retweets')
          .delete()
          .eq('user_id', user.id)
          .eq('post_id', post.id);

        if (error) throw error;
        setIsRetweeted(false);
        setRetweetCount(prev => prev - 1);
      } else {
        const { error } = await supabase
          .from('retweets')
          .insert({
            user_id: user.id,
            post_id: post.id
          });

        if (error) throw error;
        setIsRetweeted(true);
        setRetweetCount(prev => prev + 1);
      }
    } catch (error) {
      toast({ title: "Error", description: "Failed to update retweet", variant: "destructive" });
    }
  };

  const extractYouTubeId = (url: string) => {
    const match = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([^&\n?#]+)/);
    return match ? match[1] : null;
  };

  const isYouTubeLink = post.link_url && post.link_url.includes('youtube');
  const youtubeId = isYouTubeLink ? extractYouTubeId(post.link_url!) : null;

  return (
    <Card className="p-4 border-border bg-card hover:bg-accent/5 transition-colors">
      <div className="flex space-x-3">
        <Avatar className="h-12 w-12">
          <AvatarImage src={post.user_avatar} />
          <AvatarFallback className="bg-primary text-primary-foreground">
            {post.username[0]?.toUpperCase()}
          </AvatarFallback>
        </Avatar>

        <div className="flex-1 min-w-0">
          <div className="flex items-center space-x-2 mb-2">
            <span className="font-semibold text-foreground">{post.username}</span>
            <span className="text-muted-foreground text-sm">
              {formatDistanceToNow(new Date(post.created_at), { addSuffix: true })}
            </span>
            {post.anime_title && (
              <Badge 
                variant="secondary" 
                className="bg-gradient-to-r from-purple-500/20 to-pink-500/20 text-purple-300 border-purple-500/30 cursor-pointer"
                onClick={() => setShowAnimeInfo(!showAnimeInfo)}
              >
                {post.anime_title}
                <Info className="ml-1 h-3 w-3" />
              </Badge>
            )}
          </div>

          {/* Anime info */}
          {showAnimeInfo && post.anime_image && (
            <div className="mb-3 p-3 rounded-lg bg-muted/50 border border-purple-500/20">
              <div className="flex space-x-3">
                <img 
                  src={post.anime_image} 
                  alt={post.anime_title}
                  className="w-16 h-20 object-cover rounded"
                />
                <div>
                  <h4 className="font-semibold text-purple-300">{post.anime_title}</h4>
                  <p className="text-sm text-muted-foreground">Related anime</p>
                </div>
              </div>
            </div>
          )}

          <div className="mb-3">
            <p className="text-foreground whitespace-pre-wrap">{post.content}</p>
          </div>

          {/* Media content */}
          {post.media_url && (
            <div className="mb-3 rounded-lg overflow-hidden">
              {post.post_type === 'image' || post.post_type === 'gif' ? (
                <img 
                  src={post.media_url} 
                  alt="Post media"
                  className="w-full max-h-96 object-cover"
                />
              ) : null}
            </div>
          )}

          {/* Link content */}
          {post.link_url && (
            <div className="mb-3">
              {youtubeId ? (
                <div className="rounded-lg overflow-hidden">
                  <iframe
                    width="100%"
                    height="315"
                    src={`https://www.youtube.com/embed/${youtubeId}`}
                    title="YouTube video"
                    frameBorder="0"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                    allowFullScreen
                    className="w-full"
                  />
                </div>
              ) : (
                <a 
                  href={post.link_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="block p-3 border border-border rounded-lg hover:bg-accent/50 transition-colors"
                >
                  <div className="text-primary hover:underline">
                    {post.link_title || post.link_url}
                  </div>
                  <div className="text-sm text-muted-foreground truncate">
                    {post.link_url}
                  </div>
                </a>
              )}
            </div>
          )}

          {/* Action buttons */}
          <div className="flex items-center justify-between max-w-md">
            <Button
              variant="ghost"
              size="sm"
              onClick={handleLike}
              className={`flex items-center space-x-2 hover:bg-red-500/10 hover:text-red-500 ${
                isLiked ? 'text-red-500' : 'text-muted-foreground'
              }`}
            >
              <Heart className={`h-4 w-4 ${isLiked ? 'fill-current' : ''}`} />
              <span>{likeCount}</span>
            </Button>

            <Button
              variant="ghost"
              size="sm"
              className="flex items-center space-x-2 hover:bg-blue-500/10 hover:text-blue-500 text-muted-foreground"
            >
              <MessageCircle className="h-4 w-4" />
              <span>{post.comment_count}</span>
            </Button>

            <Button
              variant="ghost"
              size="sm"
              onClick={handleRetweet}
              className={`flex items-center space-x-2 hover:bg-green-500/10 hover:text-green-500 ${
                isRetweeted ? 'text-green-500' : 'text-muted-foreground'
              }`}
            >
              <Repeat2 className="h-4 w-4" />
              <span>{retweetCount}</span>
            </Button>

            <Button
              variant="ghost"
              size="sm"
              className="hover:bg-blue-500/10 hover:text-blue-500 text-muted-foreground"
            >
              <Share className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>
    </Card>
  );
};