/*
  # Advanced Search and Discovery Features

  1. New Tables
    - `search_history` - Track user search queries
    - `content_tags` - Flexible tagging system
    - `saved_searches` - Save search queries for later
    - `content_recommendations` - Store recommendation data

  2. Search Enhancements
    - Full-text search capabilities
    - Tag-based filtering
    - Search analytics
    - Personalized recommendations
*/

-- Create search history table
CREATE TABLE IF NOT EXISTS search_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  query TEXT NOT NULL,
  search_type TEXT DEFAULT 'general', -- 'general', 'anime', 'user', 'hashtag'
  results_count INTEGER DEFAULT 0,
  clicked_result_id TEXT, -- ID of the result user clicked on
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create flexible content tags table
CREATE TABLE IF NOT EXISTS content_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_type TEXT NOT NULL, -- 'post', 'user', 'anime'
  content_id TEXT NOT NULL,
  tag_name TEXT NOT NULL,
  tag_type TEXT DEFAULT 'custom', -- 'custom', 'genre', 'mood', 'category'
  added_by TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(content_type, content_id, tag_name)
);

-- Create saved searches table
CREATE TABLE IF NOT EXISTS saved_searches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  search_name TEXT NOT NULL,
  query TEXT NOT NULL,
  filters JSONB, -- Store complex search filters
  notification_enabled BOOLEAN DEFAULT false,
  last_checked TIMESTAMP WITH TIME ZONE DEFAULT now(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create content recommendations table
CREATE TABLE IF NOT EXISTS content_recommendations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  content_type TEXT NOT NULL,
  content_id TEXT NOT NULL,
  recommendation_type TEXT NOT NULL, -- 'similar_posts', 'trending', 'followed_users', 'anime_based'
  score DECIMAL(5,2) DEFAULT 0.00,
  reason TEXT, -- Why this was recommended
  shown_at TIMESTAMP WITH TIME ZONE,
  clicked_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE search_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_searches ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_recommendations ENABLE ROW LEVEL SECURITY;

-- RLS policies for search history
CREATE POLICY "Users can manage their own search history" ON search_history
FOR ALL USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Admins can view search analytics" ON search_history
FOR SELECT USING (
  current_setting('app.current_user_id', true) IN (
    SELECT user_id FROM user_profiles WHERE is_admin = true
  )
);

-- RLS policies for content tags
CREATE POLICY "Anyone can view content tags" ON content_tags
FOR SELECT USING (true);

CREATE POLICY "Users can add content tags" ON content_tags
FOR INSERT WITH CHECK (added_by = current_setting('app.current_user_id', true));

CREATE POLICY "Users can manage their own tags" ON content_tags
FOR UPDATE USING (added_by = current_setting('app.current_user_id', true));

CREATE POLICY "Users can delete their own tags" ON content_tags
FOR DELETE USING (added_by = current_setting('app.current_user_id', true));

-- RLS policies for saved searches
CREATE POLICY "Users can manage their own saved searches" ON saved_searches
FOR ALL USING (user_id = current_setting('app.current_user_id', true));

-- RLS policies for content recommendations
CREATE POLICY "Users can view their own recommendations" ON content_recommendations
FOR SELECT USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY "System can manage recommendations" ON content_recommendations
FOR ALL USING (true);

-- Add full-text search to posts
ALTER TABLE posts ADD COLUMN IF NOT EXISTS search_vector tsvector;

-- Function to update search vector
CREATE OR REPLACE FUNCTION update_posts_search_vector()
RETURNS TRIGGER AS $$
BEGIN
  NEW.search_vector := 
    setweight(to_tsvector('english', COALESCE(NEW.content, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.anime_title, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(NEW.username, '')), 'C');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for search vector updates
CREATE TRIGGER update_posts_search_vector_trigger
  BEFORE INSERT OR UPDATE ON posts
  FOR EACH ROW
  EXECUTE FUNCTION update_posts_search_vector();

-- Create GIN index for full-text search
CREATE INDEX IF NOT EXISTS idx_posts_search_vector ON posts USING GIN(search_vector);

-- Function to generate content recommendations
CREATE OR REPLACE FUNCTION generate_user_recommendations(target_user_id TEXT)
RETURNS VOID AS $$
DECLARE
  user_interests TEXT[];
  rec_post RECORD;
BEGIN
  -- Clear old recommendations
  DELETE FROM content_recommendations 
  WHERE user_id = target_user_id 
  AND created_at < now() - INTERVAL '24 hours';
  
  -- Get user interests based on their activity
  SELECT ARRAY_AGG(DISTINCT anime_title) INTO user_interests
  FROM posts 
  WHERE user_id = target_user_id 
  AND anime_title IS NOT NULL
  AND created_at > now() - INTERVAL '30 days'
  LIMIT 10;
  
  -- Generate anime-based recommendations
  IF user_interests IS NOT NULL THEN
    FOR rec_post IN
      SELECT DISTINCT p.id, p.anime_title
      FROM posts p
      WHERE p.anime_title = ANY(user_interests)
      AND p.user_id != target_user_id
      AND p.status = 'approved'
      AND p.created_at > now() - INTERVAL '7 days'
      ORDER BY p.like_count DESC, p.created_at DESC
      LIMIT 20
    LOOP
      INSERT INTO content_recommendations (
        user_id,
        content_type,
        content_id,
        recommendation_type,
        score,
        reason
      ) VALUES (
        target_user_id,
        'post',
        rec_post.id::TEXT,
        'anime_based',
        85.0,
        'Based on your interest in ' || rec_post.anime_title
      )
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;
  
  -- Generate trending recommendations
  FOR rec_post IN
    SELECT p.id, p.like_count, p.comment_count
    FROM posts p
    WHERE p.user_id != target_user_id
    AND p.status = 'approved'
    AND p.created_at > now() - INTERVAL '24 hours'
    ORDER BY (p.like_count + p.comment_count * 2) DESC
    LIMIT 10
  LOOP
    INSERT INTO content_recommendations (
      user_id,
      content_type,
      content_id,
      recommendation_type,
      score,
      reason
    ) VALUES (
      target_user_id,
      'post',
      rec_post.id::TEXT,
      'trending',
      75.0,
      'Trending in the community'
    )
    ON CONFLICT DO NOTHING;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function to log search activity
CREATE OR REPLACE FUNCTION log_search_activity()
RETURNS TRIGGER AS $$
BEGIN
  -- This would be called from the application layer
  -- when a search is performed
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add indexes for performance
CREATE INDEX idx_search_history_user ON search_history(user_id);
CREATE INDEX idx_search_history_query ON search_history(query);
CREATE INDEX idx_search_history_created ON search_history(created_at DESC);
CREATE INDEX idx_content_tags_content ON content_tags(content_type, content_id);
CREATE INDEX idx_content_tags_name ON content_tags(tag_name);
CREATE INDEX idx_content_tags_type ON content_tags(tag_type);
CREATE INDEX idx_saved_searches_user ON saved_searches(user_id);
CREATE INDEX idx_content_recommendations_user ON content_recommendations(user_id);
CREATE INDEX idx_content_recommendations_score ON content_recommendations(score DESC);
CREATE INDEX idx_content_recommendations_type ON content_recommendations(recommendation_type);

-- Update existing posts to have search vectors
UPDATE posts SET search_vector = 
  setweight(to_tsvector('english', COALESCE(content, '')), 'A') ||
  setweight(to_tsvector('english', COALESCE(anime_title, '')), 'B') ||
  setweight(to_tsvector('english', COALESCE(username, '')), 'C')
WHERE search_vector IS NULL;