/*
  # Enhanced Content Features

  1. New Tables
    - `post_bookmarks` - Save posts for later
    - `post_hashtags` - Track hashtags in posts
    - `trending_topics` - Track trending anime/topics
    - `user_activity_log` - Track user engagement for analytics

  2. Enhancements
    - Add hashtag extraction and tracking
    - Bookmark system for saving posts
    - Activity logging for better recommendations
*/

-- Create post bookmarks table
CREATE TABLE IF NOT EXISTS post_bookmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(user_id, post_id)
);

-- Create hashtags table
CREATE TABLE IF NOT EXISTS post_hashtags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  hashtag TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create trending topics table
CREATE TABLE IF NOT EXISTS trending_topics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  topic TEXT NOT NULL,
  topic_type TEXT NOT NULL DEFAULT 'hashtag', -- 'hashtag', 'anime', 'user'
  mention_count INTEGER DEFAULT 1,
  last_mentioned TIMESTAMP WITH TIME ZONE DEFAULT now(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(topic, topic_type)
);

-- Create user activity log
CREATE TABLE IF NOT EXISTS user_activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  activity_type TEXT NOT NULL, -- 'post_view', 'post_like', 'post_share', 'profile_view'
  target_id TEXT, -- post_id, user_id, etc.
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE post_bookmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE trending_topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_activity_log ENABLE ROW LEVEL SECURITY;

-- RLS policies for bookmarks
CREATE POLICY "Users can manage their own bookmarks" ON post_bookmarks
FOR ALL USING (user_id = current_setting('app.current_user_id', true));

-- RLS policies for hashtags
CREATE POLICY "Anyone can view hashtags" ON post_hashtags
FOR SELECT USING (true);

CREATE POLICY "System can manage hashtags" ON post_hashtags
FOR ALL USING (true);

-- RLS policies for trending topics
CREATE POLICY "Anyone can view trending topics" ON trending_topics
FOR SELECT USING (true);

CREATE POLICY "System can manage trending topics" ON trending_topics
FOR ALL USING (true);

-- RLS policies for activity log
CREATE POLICY "Users can view their own activity" ON user_activity_log
FOR SELECT USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY "System can log activity" ON user_activity_log
FOR INSERT WITH CHECK (true);

-- Function to extract and store hashtags
CREATE OR REPLACE FUNCTION extract_hashtags()
RETURNS TRIGGER AS $$
DECLARE
  hashtag_match TEXT;
  hashtag_clean TEXT;
BEGIN
  -- Extract hashtags from post content
  FOR hashtag_match IN 
    SELECT unnest(regexp_split_to_array(NEW.content, '\s+'))
    WHERE unnest(regexp_split_to_array(NEW.content, '\s+')) ~ '^#\w+'
  LOOP
    -- Clean the hashtag (remove # and convert to lowercase)
    hashtag_clean := lower(substring(hashtag_match from 2));
    
    -- Insert hashtag
    INSERT INTO post_hashtags (post_id, hashtag)
    VALUES (NEW.id, hashtag_clean);
    
    -- Update trending topics
    INSERT INTO trending_topics (topic, topic_type, mention_count, last_mentioned)
    VALUES (hashtag_clean, 'hashtag', 1, now())
    ON CONFLICT (topic, topic_type) 
    DO UPDATE SET 
      mention_count = trending_topics.mention_count + 1,
      last_mentioned = now();
  END LOOP;
  
  -- Track anime mentions in trending
  IF NEW.anime_title IS NOT NULL THEN
    INSERT INTO trending_topics (topic, topic_type, mention_count, last_mentioned)
    VALUES (NEW.anime_title, 'anime', 1, now())
    ON CONFLICT (topic, topic_type) 
    DO UPDATE SET 
      mention_count = trending_topics.mention_count + 1,
      last_mentioned = now();
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for hashtag extraction
CREATE TRIGGER extract_hashtags_trigger
  AFTER INSERT ON posts
  FOR EACH ROW
  EXECUTE FUNCTION extract_hashtags();

-- Add indexes for performance
CREATE INDEX idx_post_bookmarks_user ON post_bookmarks(user_id);
CREATE INDEX idx_post_bookmarks_post ON post_bookmarks(post_id);
CREATE INDEX idx_post_hashtags_hashtag ON post_hashtags(hashtag);
CREATE INDEX idx_post_hashtags_post ON post_hashtags(post_id);
CREATE INDEX idx_trending_topics_type ON trending_topics(topic_type);
CREATE INDEX idx_trending_topics_count ON trending_topics(mention_count DESC);
CREATE INDEX idx_user_activity_user ON user_activity_log(user_id);
CREATE INDEX idx_user_activity_type ON user_activity_log(activity_type);
CREATE INDEX idx_user_activity_created ON user_activity_log(created_at DESC);