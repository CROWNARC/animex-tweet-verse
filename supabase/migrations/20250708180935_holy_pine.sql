/*
  # Analytics and Insights System

  1. New Tables
    - `post_analytics` - Track post performance metrics
    - `user_engagement_stats` - User engagement analytics
    - `daily_stats` - Daily platform statistics
    - `anime_popularity_stats` - Track anime popularity trends

  2. Functions
    - Calculate engagement rates
    - Generate trending content
    - Track user activity patterns
*/

-- Create post analytics table
CREATE TABLE IF NOT EXISTS post_analytics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  views INTEGER DEFAULT 0,
  unique_views INTEGER DEFAULT 0,
  engagement_rate DECIMAL(5,2) DEFAULT 0.00,
  peak_engagement_time TIMESTAMP WITH TIME ZONE,
  reach INTEGER DEFAULT 0, -- how many unique users saw this
  impressions INTEGER DEFAULT 0, -- total times shown
  click_through_rate DECIMAL(5,2) DEFAULT 0.00,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(post_id)
);

-- Create user engagement stats table
CREATE TABLE IF NOT EXISTS user_engagement_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  date DATE NOT NULL,
  posts_created INTEGER DEFAULT 0,
  comments_made INTEGER DEFAULT 0,
  likes_given INTEGER DEFAULT 0,
  likes_received INTEGER DEFAULT 0,
  shares_given INTEGER DEFAULT 0,
  shares_received INTEGER DEFAULT 0,
  profile_views INTEGER DEFAULT 0,
  followers_gained INTEGER DEFAULT 0,
  followers_lost INTEGER DEFAULT 0,
  engagement_score DECIMAL(8,2) DEFAULT 0.00,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(user_id, date)
);

-- Create daily platform stats table
CREATE TABLE IF NOT EXISTS daily_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date DATE NOT NULL UNIQUE,
  total_users INTEGER DEFAULT 0,
  active_users INTEGER DEFAULT 0,
  new_users INTEGER DEFAULT 0,
  total_posts INTEGER DEFAULT 0,
  total_comments INTEGER DEFAULT 0,
  total_likes INTEGER DEFAULT 0,
  total_shares INTEGER DEFAULT 0,
  top_anime TEXT[],
  top_hashtags TEXT[],
  engagement_rate DECIMAL(5,2) DEFAULT 0.00,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create anime popularity stats table
CREATE TABLE IF NOT EXISTS anime_popularity_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  anime_id TEXT NOT NULL,
  anime_title TEXT NOT NULL,
  date DATE NOT NULL,
  mention_count INTEGER DEFAULT 0,
  post_count INTEGER DEFAULT 0,
  like_count INTEGER DEFAULT 0,
  comment_count INTEGER DEFAULT 0,
  unique_users INTEGER DEFAULT 0,
  popularity_score DECIMAL(8,2) DEFAULT 0.00,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(anime_id, date)
);

-- Enable RLS
ALTER TABLE post_analytics ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_engagement_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_popularity_stats ENABLE ROW LEVEL SECURITY;

-- RLS policies for post analytics
CREATE POLICY "Post owners can view their analytics" ON post_analytics
FOR SELECT USING (
  post_id IN (
    SELECT id FROM posts 
    WHERE user_id = current_setting('app.current_user_id', true)
  )
);

CREATE POLICY "Admins can view all analytics" ON post_analytics
FOR SELECT USING (
  current_setting('app.current_user_id', true) IN (
    SELECT user_id FROM user_profiles WHERE is_admin = true
  )
);

CREATE POLICY "System can update analytics" ON post_analytics
FOR ALL USING (true);

-- RLS policies for user engagement stats
CREATE POLICY "Users can view their own stats" ON user_engagement_stats
FOR SELECT USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Admins can view all user stats" ON user_engagement_stats
FOR SELECT USING (
  current_setting('app.current_user_id', true) IN (
    SELECT user_id FROM user_profiles WHERE is_admin = true
  )
);

CREATE POLICY "System can manage user stats" ON user_engagement_stats
FOR ALL USING (true);

-- RLS policies for daily stats (public read, admin write)
CREATE POLICY "Anyone can view daily stats" ON daily_stats
FOR SELECT USING (true);

CREATE POLICY "Admins can manage daily stats" ON daily_stats
FOR INSERT WITH CHECK (
  current_setting('app.current_user_id', true) IN (
    SELECT user_id FROM user_profiles WHERE is_admin = true
  )
);

-- RLS policies for anime popularity stats (public read, system write)
CREATE POLICY "Anyone can view anime popularity stats" ON anime_popularity_stats
FOR SELECT USING (true);

CREATE POLICY "System can manage anime stats" ON anime_popularity_stats
FOR ALL USING (true);

-- Function to update post analytics
CREATE OR REPLACE FUNCTION update_post_analytics()
RETURNS TRIGGER AS $$
BEGIN
  -- Initialize analytics record if it doesn't exist
  INSERT INTO post_analytics (post_id, views, unique_views)
  VALUES (NEW.id, 0, 0)
  ON CONFLICT (post_id) DO NOTHING;
  
  -- Calculate engagement rate
  UPDATE post_analytics 
  SET 
    engagement_rate = CASE 
      WHEN views > 0 THEN 
        ((SELECT like_count + comment_count + retweet_count FROM posts WHERE id = NEW.id)::decimal / views) * 100
      ELSE 0 
    END,
    updated_at = now()
  WHERE post_id = NEW.id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to update user engagement stats
CREATE OR REPLACE FUNCTION update_user_engagement_stats()
RETURNS TRIGGER AS $$
DECLARE
  target_user_id TEXT;
  today_date DATE := CURRENT_DATE;
BEGIN
  -- Determine the user_id based on the table and operation
  IF TG_TABLE_NAME = 'posts' THEN
    target_user_id := NEW.user_id;
    
    -- Update posts_created count
    INSERT INTO user_engagement_stats (user_id, date, posts_created)
    VALUES (target_user_id, today_date, 1)
    ON CONFLICT (user_id, date) 
    DO UPDATE SET posts_created = user_engagement_stats.posts_created + 1;
    
  ELSIF TG_TABLE_NAME = 'comments' THEN
    target_user_id := NEW.user_id;
    
    -- Update comments_made count
    INSERT INTO user_engagement_stats (user_id, date, comments_made)
    VALUES (target_user_id, today_date, 1)
    ON CONFLICT (user_id, date) 
    DO UPDATE SET comments_made = user_engagement_stats.comments_made + 1;
    
  ELSIF TG_TABLE_NAME = 'likes' THEN
    -- Update likes_given for the user who liked
    INSERT INTO user_engagement_stats (user_id, date, likes_given)
    VALUES (NEW.user_id, today_date, 1)
    ON CONFLICT (user_id, date) 
    DO UPDATE SET likes_given = user_engagement_stats.likes_given + 1;
    
    -- Update likes_received for the post owner
    IF NEW.post_id IS NOT NULL THEN
      SELECT user_id INTO target_user_id FROM posts WHERE id = NEW.post_id;
      INSERT INTO user_engagement_stats (user_id, date, likes_received)
      VALUES (target_user_id, today_date, 1)
      ON CONFLICT (user_id, date) 
      DO UPDATE SET likes_received = user_engagement_stats.likes_received + 1;
    END IF;
  END IF;
  
  -- Calculate engagement score (simple formula)
  UPDATE user_engagement_stats 
  SET engagement_score = (
    posts_created * 3 + 
    comments_made * 2 + 
    likes_given * 1 + 
    likes_received * 2 + 
    shares_given * 2 + 
    shares_received * 3
  )
  WHERE user_id = target_user_id AND date = today_date;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Function to update anime popularity stats
CREATE OR REPLACE FUNCTION update_anime_popularity()
RETURNS TRIGGER AS $$
DECLARE
  today_date DATE := CURRENT_DATE;
BEGIN
  IF NEW.anime_id IS NOT NULL AND NEW.anime_title IS NOT NULL THEN
    -- Update anime popularity stats
    INSERT INTO anime_popularity_stats (
      anime_id, 
      anime_title, 
      date, 
      mention_count, 
      post_count,
      unique_users
    )
    VALUES (
      NEW.anime_id, 
      NEW.anime_title, 
      today_date, 
      1, 
      1,
      1
    )
    ON CONFLICT (anime_id, date) 
    DO UPDATE SET 
      mention_count = anime_popularity_stats.mention_count + 1,
      post_count = anime_popularity_stats.post_count + 1,
      unique_users = (
        SELECT COUNT(DISTINCT user_id) 
        FROM posts 
        WHERE anime_id = NEW.anime_id 
        AND DATE(created_at) = today_date
      );
    
    -- Calculate popularity score
    UPDATE anime_popularity_stats 
    SET popularity_score = (
      mention_count * 1.0 + 
      post_count * 2.0 + 
      like_count * 0.5 + 
      comment_count * 1.5 + 
      unique_users * 3.0
    )
    WHERE anime_id = NEW.anime_id AND date = today_date;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for analytics
CREATE TRIGGER update_post_analytics_trigger
  AFTER INSERT OR UPDATE ON posts
  FOR EACH ROW
  EXECUTE FUNCTION update_post_analytics();

CREATE TRIGGER update_user_engagement_posts_trigger
  AFTER INSERT ON posts
  FOR EACH ROW
  EXECUTE FUNCTION update_user_engagement_stats();

CREATE TRIGGER update_user_engagement_comments_trigger
  AFTER INSERT ON comments
  FOR EACH ROW
  EXECUTE FUNCTION update_user_engagement_stats();

CREATE TRIGGER update_user_engagement_likes_trigger
  AFTER INSERT ON likes
  FOR EACH ROW
  EXECUTE FUNCTION update_user_engagement_stats();

CREATE TRIGGER update_anime_popularity_trigger
  AFTER INSERT ON posts
  FOR EACH ROW
  EXECUTE FUNCTION update_anime_popularity();

-- Add indexes for performance
CREATE INDEX idx_post_analytics_post ON post_analytics(post_id);
CREATE INDEX idx_post_analytics_engagement ON post_analytics(engagement_rate DESC);
CREATE INDEX idx_user_engagement_user_date ON user_engagement_stats(user_id, date);
CREATE INDEX idx_user_engagement_score ON user_engagement_stats(engagement_score DESC);
CREATE INDEX idx_daily_stats_date ON daily_stats(date DESC);
CREATE INDEX idx_anime_popularity_anime_date ON anime_popularity_stats(anime_id, date);
CREATE INDEX idx_anime_popularity_score ON anime_popularity_stats(popularity_score DESC);
CREATE INDEX idx_anime_popularity_date ON anime_popularity_stats(date DESC);