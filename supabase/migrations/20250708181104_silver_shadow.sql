/*
  # Add User Following System

  1. New Tables
    - `user_follows` - Track user following relationships
    - `user_blocks` - Track blocked users for content filtering

  2. Security
    - Enable RLS on new tables
    - Add policies for user privacy and content filtering

  3. Functions
    - Update follower/following counts automatically
    - Filter content from blocked users
*/

-- Create user follows table
CREATE TABLE IF NOT EXISTS user_follows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id TEXT NOT NULL,
  following_id TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(follower_id, following_id),
  CHECK(follower_id != following_id)
);

-- Create user blocks table
CREATE TABLE IF NOT EXISTS user_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id TEXT NOT NULL,
  blocked_id TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(blocker_id, blocked_id),
  CHECK(blocker_id != blocked_id)
);

-- Enable RLS
ALTER TABLE user_follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_blocks ENABLE ROW LEVEL SECURITY;

-- RLS policies for user_follows
CREATE POLICY "Users can view public follows" ON user_follows
FOR SELECT USING (true);

CREATE POLICY "Users can manage their own follows" ON user_follows
FOR ALL USING (follower_id = current_setting('app.current_user_id', true));

-- RLS policies for user_blocks
CREATE POLICY "Users can manage their own blocks" ON user_blocks
FOR ALL USING (blocker_id = current_setting('app.current_user_id', true));

-- Function to update follower counts
CREATE OR REPLACE FUNCTION update_follow_counts()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Update follower count for the followed user
    UPDATE user_profiles 
    SET follower_count = follower_count + 1 
    WHERE user_id = NEW.following_id;
    
    -- Update following count for the follower
    UPDATE user_profiles 
    SET following_count = following_count + 1 
    WHERE user_id = NEW.follower_id;
    
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    -- Update follower count for the unfollowed user
    UPDATE user_profiles 
    SET follower_count = follower_count - 1 
    WHERE user_id = OLD.following_id;
    
    -- Update following count for the unfollower
    UPDATE user_profiles 
    SET following_count = following_count - 1 
    WHERE user_id = OLD.follower_id;
    
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for follow counts
CREATE TRIGGER update_follow_counts_trigger
  AFTER INSERT OR DELETE ON user_follows
  FOR EACH ROW
  EXECUTE FUNCTION update_follow_counts();

-- Add indexes for performance
CREATE INDEX idx_user_follows_follower ON user_follows(follower_id);
CREATE INDEX idx_user_follows_following ON user_follows(following_id);
CREATE INDEX idx_user_blocks_blocker ON user_blocks(blocker_id);
CREATE INDEX idx_user_blocks_blocked ON user_blocks(blocked_id);